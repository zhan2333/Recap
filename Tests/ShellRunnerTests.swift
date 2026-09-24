//
//  ShellRunnerTests.swift
//  RecapLibraryTests
//
//  Created by Rio on 9/20/26.
//

import Darwin
import Foundation
import XCTest

@MainActor
final class ShellRunnerTests: XCTestCase {

    func testDetectionUsesInteractiveProfileAndKeepsToolsWhoseVersionFails() async throws {
        let fixture = try DetectionFixture(tools: [
            "claude": "exit 7",
            "codex": "printf 'codex fixture 1.0\\n'",
        ])
        defer { fixture.remove() }
        let exited = expectation(description: "Detection completes")
        var updates: [(String, String)] = []
        var exitStatus: Int32?
        let pid = ShellRunner.detectTools(fixture.directory.path, environment: fixture.environment,
                                          timeout: 2, onTool: { updates.append(($0, $1)) }, onExit: {
            exitStatus = $0
            exited.fulfill()
        })
        defer { ShellRunner.terminate(pid) }
        XCTAssertGreaterThan(pid, 0)

        await fulfillment(of: [exited], timeout: 4)

        XCTAssertEqual(exitStatus, 0)
        XCTAssertEqual(Array(updates.prefix(2)).map(\.0), ["claude", "codex"])
        XCTAssertTrue(updates.prefix(2).allSatisfy { $0.1.isEmpty }, "Installation must be reported before querying versions")
        XCTAssertTrue(updates.contains { $0.0 == "claude" && $0.1.isEmpty })
        XCTAssertTrue(updates.contains { $0.0 == "codex" && $0.1 == "codex fixture 1.0" })
        XCTAssertEqual(Set(updates.map(\.0)), ["claude", "codex"], "Profile output must not become a tool")
    }

    func testHangingVersionDoesNotBlockOtherToolsAndDetectionTimesOut() async throws {
        let fixture = try DetectionFixture(tools: [
            "claude": "exec /bin/sleep 60",
            "codex": "printf 'codex fixture 2.0\\n'",
        ])
        defer { fixture.remove() }
        let versionArrived = expectation(description: "Other tool version arrives while Claude is hung")
        let exited = expectation(description: "Hanging version is terminated")
        exited.assertForOverFulfill = true
        var installed: Set<String> = []
        var exitStatus: Int32?
        let started = Date()
        let pid = ShellRunner.detectTools(fixture.directory.path, environment: fixture.environment,
                                          timeout: 1, onTool: { tool, version in
            installed.insert(tool)
            if tool == "codex", version == "codex fixture 2.0" {
                XCTAssertNil(exitStatus)
                versionArrived.fulfill()
            }
        }, onExit: {
            exitStatus = $0
            exited.fulfill()
        })
        defer { ShellRunner.terminate(pid) }
        XCTAssertGreaterThan(pid, 0)

        await fulfillment(of: [versionArrived, exited], timeout: 3, enforceOrder: true)

        XCTAssertEqual(installed, ["claude", "codex"])
        XCTAssertEqual(exitStatus, 124)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testHangingStartupProfileIsBoundedByDetectionTimeout() async throws {
        let fixture = try DetectionFixture(profile: "exec /bin/sleep 60")
        defer { fixture.remove() }
        let exited = expectation(description: "Startup profile is terminated")
        var exitStatus: Int32?
        let started = Date()
        let pid = ShellRunner.detectTools(fixture.directory.path, environment: fixture.environment,
                                          timeout: 0.3, onTool: { _, _ in
            XCTFail("The detection script cannot run while the startup profile is blocked")
        }, onExit: {
            exitStatus = $0
            exited.fulfill()
        })
        defer { ShellRunner.terminate(pid) }
        XCTAssertGreaterThan(pid, 0)

        await fulfillment(of: [exited], timeout: 2)

        XCTAssertEqual(exitStatus, 124)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testCancellingDetectionReportsExitOnceAndCancelsWatchdog() async throws {
        let fixture = try DetectionFixture(tools: ["claude": "exec /bin/sleep 60"])
        defer { fixture.remove() }
        let discovered = expectation(description: "Claude installation is discovered")
        let exited = expectation(description: "Cancelled detection exits")
        exited.assertForOverFulfill = true
        var exitCount = 0
        var exitStatus: Int32?
        let pid = ShellRunner.detectTools(fixture.directory.path, environment: fixture.environment,
                                          timeout: 1, onTool: { tool, _ in
            if tool == "claude" { discovered.fulfill() }
        }, onExit: {
            exitStatus = $0
            exitCount += 1
            exited.fulfill()
        })
        defer { ShellRunner.terminate(pid) }
        XCTAssertGreaterThan(pid, 0)
        await fulfillment(of: [discovered], timeout: 0.8)

        ShellRunner.terminate(pid)
        ShellRunner.terminate(pid)
        await fulfillment(of: [exited], timeout: 2)
        try await Task.sleep(nanoseconds: 1_100_000_000)

        XCTAssertEqual(exitCount, 1)
        XCTAssertEqual(exitStatus, 130)
    }

    func testDetectionClearsParentSessionMarkersAndPreservesUserConfiguration() async throws {
        let fixture = try DetectionFixture(tools: ["claude": """
        if [[ -n "${CLAUDECODE+x}${CLAUDE_CODE_SESSION_ID+x}${CLAUDE_CODE_CHILD_SESSION+x}${CLAUDE_CODE_SESSION_ATTENDED+x}" ]]; then
            printf 'unexpected-parent-session\\n'
            exit 0
        fi
        printf '%s/%s/%s/%s/%s\\n' "$CLAUDE_CODE_USE_BEDROCK" "$CLAUDE_CODE_CUSTOM_SETTING" "$TERM_PROGRAM" "${TERM_PROGRAM_VERSION-unset}" "${TERM_SESSION_ID-unset}"
        """])
        defer { fixture.remove() }
        var environment = fixture.environment
        for key in ["CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ATTENDED"] {
            environment[key] = "parent-fixture-session"
        }
        environment["CLAUDE_CODE_USE_BEDROCK"] = "1"
        environment["CLAUDE_CODE_CUSTOM_SETTING"] = "keep-fixture-value"
        environment["TERM_PROGRAM"] = "Apple_Terminal"
        environment["TERM_PROGRAM_VERSION"] = "fixture-version"
        environment["TERM_SESSION_ID"] = "parent-terminal-session"
        let exited = expectation(description: "Environment fixture exits")
        var versions: [String] = []
        var exitStatus: Int32?
        let pid = ShellRunner.detectTools(fixture.directory.path, environment: environment,
                                          timeout: 2, onTool: { _, version in
            if !version.isEmpty { versions.append(version) }
        }, onExit: {
            exitStatus = $0
            exited.fulfill()
        })
        defer { ShellRunner.terminate(pid) }
        XCTAssertGreaterThan(pid, 0)

        await fulfillment(of: [exited], timeout: 4)

        XCTAssertEqual(exitStatus, 0)
        XCTAssertEqual(versions, ["1/keep-fixture-value/Recap/unset/unset"])
    }

    func testDetectionParserHandlesSplitUTF8NoiseAndDuplicateDiscoveries() {
        var parser = ToolDetectionParser(marker: "RECAP_FIXTURE")
        let output = """
        profile says claude is installed
        OTHER_MARKER|found|codex
        RECAP_FIXTURE|version|codex|ignored-before-discovery
        RECAP_FIXTURE|found|unknown
        RECAP_FIXTURE|found|claude\r
        RECAP_FIXTURE|found|claude
        RECAP_FIXTURE|found|codex|malformed
        RECAP_FIXTURE|version|claude|\u{1b}[32mClaude 中文版本\u{1b}[0m\t
        RECAP_FIXTURE|ready

        """
        var updates: [(String, String)] = []
        for byte in output.utf8 {
            updates.append(contentsOf: parser.append(Data([byte])))
        }

        XCTAssertTrue(parser.isReady)
        XCTAssertEqual(updates.map(\.0), ["claude", "claude"])
        XCTAssertEqual(updates.map(\.1), ["", "Claude 中文版本"])
        XCTAssertTrue(parser.append(Data(repeating: 120, count: 5000)).isEmpty)
        let recovered = parser.append(Data("RECAP_FIXTURE|found|kimi\n".utf8))
        XCTAssertEqual(recovered.map(\.0), ["kimi"], "Oversized profile noise must not prevent later framed records")
    }

    func testTerminatingInteractiveShellReportsExitAfterTheProcessIsGone() async throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("RecapShellTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let exited = expectation(description: "Interactive shell termination reports onExit")
        exited.assertForOverFulfill = true
        var pid: Int32 = -1
        var exitCount = 0
        var wasGoneAtExit = false
        pid = ShellRunner.startShell(directory.path, cols: 80, rows: 24, onData: { _ in }, onExit: { _ in
            exitCount += 1
            let result = kill(pid, 0)
            wasGoneAtExit = result == -1 && errno == ESRCH
            exited.fulfill()
        })
        defer {
            if pid > 0, kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
                var status: Int32 = 0
                waitpid(pid, &status, 0)
            }
        }
        XCTAssertGreaterThan(pid, 0)
        guard pid > 0 else { return }

        ShellRunner.terminate(pid)
        ShellRunner.terminate(pid)
        await fulfillment(of: [exited], timeout: 2)

        XCTAssertEqual(exitCount, 1)
        XCTAssertTrue(wasGoneAtExit, "The storage lease must remain held until the shell has exited and been reaped")
    }

    private struct DetectionFixture {
        let directory: URL

        var environment: [String: String] {
            ["HOME": directory.path, "ZDOTDIR": directory.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        }

        init(tools: [String: String] = [:], profile: String = "") throws {
            let files = FileManager.default
            directory = files.temporaryDirectory.appendingPathComponent("RecapDetectionTests-\(UUID().uuidString)", isDirectory: true)
            let bin = directory.appendingPathComponent("fixture-bin", isDirectory: true)
            try files.createDirectory(at: bin, withIntermediateDirectories: true)
            do {
                try "unsetopt GLOBAL_RCS\nexport PATH=/usr/bin:/bin\n".write(to: directory.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
                try """
                export PATH="$ZDOTDIR/fixture-bin:$PATH"
                printf 'Fixture profile noise: claude and codex\\n'
                \(profile)

                """.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
                for (name, body) in tools {
                    let executable = bin.appendingPathComponent(name)
                    try "#!/bin/zsh\n\(body)\n".write(to: executable, atomically: true, encoding: .utf8)
                    try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
                }
            } catch {
                try? files.removeItem(at: directory)
                throw error
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

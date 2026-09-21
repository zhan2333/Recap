//
//  UpdateInstallerTests.swift
//  RecapLibraryTests
//
//  Created by Rio on 9/21/26.
//

import Darwin
import Foundation
import XCTest

final class UpdateInstallerTests: XCTestCase {

    @MainActor
    func testDetachedHelperSurvivesTheShellRunnerLauncherExit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 3)
        defer { stop(application) }
        let plan = fixture.plan(processID: application.processIdentifier)
        try fixture.stage(plan)
        try plan.helperScript(waitAttempts: 500, waitInterval: 0.01, relaunch: false)
            .write(to: plan.helperURL, atomically: true, encoding: .utf8)

        let launcherExited = expectation(description: "The PTY launcher acknowledges helper readiness and exits")
        launcherExited.assertForOverFulfill = true
        var launcherStatus: Int32?
        let launcherPID = ShellRunner.run(plan.launchCommand(), onOutput: { _ in }, onExit: { code in
            launcherStatus = code
            launcherExited.fulfill()
        })
        await fulfillment(of: [launcherExited], timeout: 2)

        XCTAssertEqual(launcherStatus, 0)
        XCTAssertGreaterThan(launcherPID, 0)
        XCTAssertEqual(kill(launcherPID, 0), -1)
        XCTAssertTrue(application.isRunning)
        let ready = try String(contentsOf: plan.readyURL, encoding: .utf8)
        let helperPID = try XCTUnwrap(Int32(ready.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertGreaterThan(helperPID, 1)
        defer { if helperPID > 1, kill(helperPID, 0) == 0 { kill(helperPID, SIGTERM) } }
        XCTAssertEqual(kill(helperPID, 0), 0, "The helper must survive the launcher's PTY closing")
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")

        application.waitUntilExit()
        let deadline = Date().addingTimeInterval(3)
        var log = ""
        while Date() < deadline {
            log = (try? String(contentsOf: plan.logURL, encoding: .utf8)) ?? ""
            if log.contains("Update helper finished with status 0.") { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(log.contains("Update helper finished with status 0."), log)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))
    }

    func testRunningApplicationRemainsIntactUntilItsProcessExits() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 2)
        defer { stop(application) }
        let plan = fixture.plan(processID: application.processIdentifier)
        try fixture.stage(plan)
        let helper = try startHelper(plan, attempts: 300)
        defer { stop(helper) }
        try waitForReady(plan, helper: helper)

        XCTAssertTrue(application.isRunning)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")
        XCTAssertEqual(try fixture.version(at: plan.stagedAppURL), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))

        application.waitUntilExit()
        helper.waitUntilExit()

        XCTAssertEqual(helper.terminationStatus, 0)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.stagedAppURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))
    }

    func testMissingStagedApplicationPreservesInstalledApplication() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 0.01)
        application.waitUntilExit()
        let plan = fixture.plan(processID: application.processIdentifier)
        let helper = try startHelper(plan)
        helper.waitUntilExit()

        XCTAssertNotEqual(helper.terminationStatus, 0)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.readyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))
    }

    func testTimeoutPreservesRunningApplicationWithoutTerminatingIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 2)
        defer { stop(application) }
        let plan = fixture.plan(processID: application.processIdentifier)
        try fixture.stage(plan)
        let helper = try startHelper(plan, attempts: 3)
        helper.waitUntilExit()

        XCTAssertNotEqual(helper.terminationStatus, 0)
        XCTAssertTrue(application.isRunning)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))
    }

    func testCancellationAfterReadinessLeavesInstalledApplicationIntact() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 2)
        defer { stop(application) }
        let plan = fixture.plan(processID: application.processIdentifier)
        try fixture.stage(plan)
        let helper = try startHelper(plan, attempts: 300)
        defer { stop(helper) }
        try waitForReady(plan, helper: helper)
        let cleanup = try startShell(command: plan.cleanupCommand())
        cleanup.waitUntilExit()
        helper.waitUntilExit()

        XCTAssertEqual(cleanup.terminationStatus, 0)
        XCTAssertNotEqual(helper.terminationStatus, 0)
        XCTAssertTrue(application.isRunning)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.stagedAppURL.path))
    }

    func testCancellationBeforeReadinessPreservesInstalledApplication() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 2)
        defer { stop(application) }
        let plan = fixture.plan(processID: application.processIdentifier)
        let cleanup = try startShell(command: plan.cleanupCommand())
        cleanup.waitUntilExit()
        try fixture.stage(plan)
        let helper = try startHelper(plan)
        helper.waitUntilExit()

        XCTAssertEqual(cleanup.terminationStatus, 0)
        XCTAssertNotEqual(helper.terminationStatus, 0)
        XCTAssertTrue(application.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.readyURL.path))
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))
    }

    func testCleanupPreservesTheOnlyRemainingBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = fixture.plan(processID: ProcessInfo.processInfo.processIdentifier)
        try FileManager.default.moveItem(at: plan.appURL, to: plan.backupAppURL)
        let cleanup = try startShell(command: plan.cleanupCommand())
        cleanup.waitUntilExit()

        XCTAssertEqual(cleanup.terminationStatus, 0)
        XCTAssertEqual(try fixture.version(at: plan.backupAppURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.appURL.path))
    }

    func testFailedReplacementRestoresPreviousApplication() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let application = try startSleep(seconds: 0.01)
        application.waitUntilExit()
        let plan = fixture.plan(processID: application.processIdentifier)
        try fixture.stage(plan)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: plan.stagedAppURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: plan.stagedAppURL.path) }
        let helper = try startHelper(plan)
        helper.waitUntilExit()

        XCTAssertNotEqual(helper.terminationStatus, 0)
        XCTAssertEqual(try fixture.version(at: plan.appURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupAppURL.path))
    }

    private func startHelper(_ plan: UpdateInstaller.Plan, attempts: Int = 30) throws -> Process {
        try plan.helperScript(waitAttempts: attempts, waitInterval: 0.01, relaunch: false)
            .write(to: plan.helperURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [plan.helperURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func startShell(command: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func startSleep(seconds: Double) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [String(seconds)]
        try process.run()
        return process
    }

    private func waitForReady(_ plan: UpdateInstaller.Plan, helper: Process) throws {
        let deadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: plan.readyURL.path), helper.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.readyURL.path))
    }

    private func stop(_ process: Process) {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    private struct Fixture {
        let directory: URL
        let appURL: URL
        let workingDirectory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RecapUpdateTests-\(UUID().uuidString)", isDirectory: true)
            appURL = directory.appendingPathComponent("Recap's Study.app", isDirectory: true)
            workingDirectory = directory.appendingPathComponent("working", isDirectory: true)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
            try "old".write(to: appURL.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        }

        func plan(processID: Int32) -> UpdateInstaller.Plan {
            UpdateInstaller.Plan(appURL: appURL, workingDirectory: workingDirectory, processID: processID, expectedVersion: "2.5.2")
        }

        func stage(_ plan: UpdateInstaller.Plan) throws {
            try FileManager.default.createDirectory(at: plan.stagedAppURL, withIntermediateDirectories: true)
            try "new".write(to: plan.stagedAppURL.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        }

        func version(at application: URL) throws -> String {
            try String(contentsOf: application.appendingPathComponent("version.txt"), encoding: .utf8)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

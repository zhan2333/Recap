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
}

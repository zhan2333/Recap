//
//  ShellRunner.swift
//  RecapShellPlugin
//
//  Created by Rio on 2026/8/20.
//
//  Compiled as a plain macOS bundle and loaded into the Catalyst process at
//  runtime — the classic glue-bundle workaround for Process being unavailable
//  under Catalyst. Runs a shell command on a PTY so tools like curl render
//  their progress output.

import Foundation
import Darwin

/// Must mirror the host app's protocol byte-for-byte — @objc protocols unify
/// by name at runtime, and the host's `as? ShellRunning.Type` cast checks
/// this conformance.
@objc(RSPShellRunning)
public protocol ShellRunning {
    static func run(
        _ command: String,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    )
}

@objc(RSPShellRunner)
public final class ShellRunner: NSObject, ShellRunning {

    @objc public static func run(
        _ command: String,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            onExit(-1)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { onOutput(text) }
            }
        }

        process.terminationHandler = { finished in
            // Parent's slave handle is released with the Process; drain then stop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                masterHandle.readabilityHandler = nil
                onExit(finished.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            onExit(-1)
        }
    }
}

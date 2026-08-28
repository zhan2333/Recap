//
//  ShellBridge.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import Foundation

// Mirror of the plugin's interface
@objc(RSPShellRunning)
protocol ShellRunning {
    @discardableResult
    static func run(
        _ command: String,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32
    static func terminate(_ pid: Int32)
    @discardableResult
    static func startShell(
        _ workingDirectory: String,
        cols: Int32,
        rows: Int32,
        onData: @escaping (Data) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32
    static func write(_ pid: Int32, data: Data)
    static func resize(_ pid: Int32, cols: Int32, rows: Int32)
}

// Loads the macOS glue bundle that provides subprocess support (Process is unavailable in Catalyst itself).
enum ShellBridge {

    private static let runner: ShellRunning.Type? = {
        let candidates = [Bundle.main.builtInPlugInsURL, Bundle.main.resourceURL]
        for base in candidates {
            guard let url = base?.appendingPathComponent("RecapShellPlugin.bundle"),
                  let bundle = Bundle(url: url), bundle.load(),
                  let cls = bundle.classNamed("RSPShellRunner") else { continue }
            return cls as? ShellRunning.Type
        }
        return nil
    }()

    static var isAvailable: Bool { runner != nil }

    @discardableResult
    static func run(
        _ command: String,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        guard let runner else {
            onExit(-1)
            return -1
        }
        return runner.run(command, onOutput: onOutput, onExit: onExit)
    }

    static func terminate(_ pid: Int32) {
        runner?.terminate(pid)
    }

    @discardableResult
    static func startShell(
        workingDirectory: String,
        cols: Int32,
        rows: Int32,
        onData: @escaping (Data) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        guard let runner else {
            onExit(-1)
            return -1
        }
        return runner.startShell(workingDirectory, cols: cols, rows: rows, onData: onData, onExit: onExit)
    }

    static func write(pid: Int32, data: Data) {
        runner?.write(pid, data: data)
    }

    static func resize(pid: Int32, cols: Int32, rows: Int32) {
        runner?.resize(pid, cols: cols, rows: rows)
    }
}

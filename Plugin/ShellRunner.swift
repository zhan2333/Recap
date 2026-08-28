//
//  ShellRunner.swift
//  RecapShellPlugin
//
//  Created by Rio on 2026/8/20.
//

// macOS glue bundle loaded into the Catalyst process; runs commands on a PTY
import Foundation
import Darwin

// Must mirror the host app's protocol byte-for-byte
@objc(RSPShellRunning)
public protocol ShellRunning {
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

@objc(RSPShellRunner)
public final class ShellRunner: NSObject, ShellRunning {

    // All access happens on the main thread (run, terminate, and the plugin's callbacks)
    private static var sessions: [Int32: (process: Process, master: FileHandle)] = [:]

    @discardableResult
    @objc public static func run(
        _ command: String,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            onExit(-1)
            return -1
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
                sessions[finished.processIdentifier] = nil
                onExit(finished.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            onExit(-1)
            return -1
        }
        let pid = process.processIdentifier
        DispatchQueue.main.async { sessions[pid] = (process, masterHandle) }
        return pid
    }

    // Closing the PTY master hangs up the session (like closing a terminal window); SIGTERM covers the rest
    @objc public static func terminate(_ pid: Int32) {
        DispatchQueue.main.async {
            if let session = sessions[pid] {
                sessions[pid] = nil
                session.master.readabilityHandler = nil
                try? session.master.close()
                session.process.terminate()
                return
            }
            guard let shell = shells[pid] else { return }
            shells[pid] = nil
            shell.exitSource.cancel()
            shell.master.readabilityHandler = nil
            try? shell.master.close()
            kill(pid, SIGHUP)
        }
    }

    // Interactive login shells: forkpty makes the child a session leader owning the PTY,
    // so SIGWINCH and Ctrl-C signals reach it the way a real terminal delivers them
    private static var shells: [Int32: (master: FileHandle, exitSource: DispatchSourceProcess)] = [:]

    @discardableResult
    @objc public static func startShell(
        _ workingDirectory: String,
        cols: Int32,
        rows: Int32,
        onData: @escaping (Data) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"]?.uppercased().contains("UTF-8") != true {
            environment["LANG"] = "en_US.UTF-8"
        }
        // Strip inherited Claude Code session marks so a CLI in here is a clean top-level session
        for key in environment.keys where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") {
            environment.removeValue(forKey: key)
        }
        // Claim our own terminal identity: an inherited Apple_Terminal mark makes zsh run
        // Terminal.app's session save/restore hooks inside this window
        environment["TERM_PROGRAM"] = "Recap"
        environment.removeValue(forKey: "TERM_PROGRAM_VERSION")
        environment.removeValue(forKey: "TERM_SESSION_ID")

        // Every allocation happens before the fork; the child only calls async-signal-safe functions
        let executable = strdup("/bin/zsh")
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("-zsh"), strdup("-il"), nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let directory = strdup(workingDirectory)
        defer {
            free(executable)
            free(directory)
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var master: Int32 = 0
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&master, nil, nil, &size)
        if pid < 0 {
            onExit(-1)
            return -1
        }
        if pid == 0 {
            _ = chdir(directory)
            _ = execve(executable, argv, envp)
            _exit(127)
        }

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { onData(data) }
        }

        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler {
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            exitSource.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                masterHandle.readabilityHandler = nil
                shells[pid] = nil
                let signalNumber = status & 0x7f
                onExit(signalNumber != 0 ? 128 + signalNumber : (status >> 8) & 0xff)
            }
        }
        exitSource.resume()
        DispatchQueue.main.async { shells[pid] = (masterHandle, exitSource) }
        return pid
    }

    @objc public static func write(_ pid: Int32, data: Data) {
        DispatchQueue.main.async {
            guard let shell = shells[pid] else { return }
            try? shell.master.write(contentsOf: data)
        }
    }

    @objc public static func resize(_ pid: Int32, cols: Int32, rows: Int32) {
        DispatchQueue.main.async {
            guard let shell = shells[pid] else { return }
            var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(shell.master.fileDescriptor, TIOCSWINSZ, &size)
        }
    }
}

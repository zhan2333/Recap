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
    @discardableResult
    static func detectTools(
        _ workingDirectory: String,
        onTool: @escaping (String, String) -> Void,
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
    private static var detectionCancellations: [Int32: () -> Void] = [:]

    @discardableResult
    @objc public static func detectTools(
        _ workingDirectory: String,
        onTool: @escaping (String, String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        detectTools(workingDirectory, environment: ProcessInfo.processInfo.environment,
                    timeout: 8, onTool: onTool, onExit: onExit)
    }

    // Keep installation discovery independent of CLI authentication and version-query success.
    @discardableResult
    static func detectTools(
        _ workingDirectory: String,
        environment: [String: String],
        timeout: TimeInterval,
        onTool: @escaping (String, String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        let marker = "RECAP_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let command = """
        builtin unsetopt MONITOR
        typeset -a recap_tools=()
        for recap_tool in claude codex gemini grok kimi; do
            if command -v "$recap_tool" >/dev/null 2>&1; then
                recap_tools+=("$recap_tool")
                builtin printf '\\n\(marker)|found|%s\\n' "$recap_tool"
            fi
        done
        builtin printf '\\n\(marker)|ready\\n'
        for recap_tool in "${recap_tools[@]}"; do
            (
                recap_version=$("$recap_tool" --version </dev/null 2>/dev/null | /usr/bin/head -n 1)
                builtin printf '\\n\(marker)|version|%s|%.200s\\n' "$recap_tool" "$recap_version"
            ) &
        done
        builtin wait
        """
        var parser = ToolDetectionParser(marker: marker)
        var watchdog: DispatchWorkItem?
        var completed = false
        let finish: (Int32) -> Void = { status in
            guard !completed else { return }
            completed = true
            watchdog?.cancel()
            watchdog = nil
            onExit(status)
        }
        var pid: Int32 = -1
        pid = launchShell(workingDirectory, cols: 100, rows: 24,
                          arguments: ["-il", "+m", "-c", command], environment: environment,
                          onData: { data in
            guard !completed else { return }
            for (tool, version) in parser.append(data) { onTool(tool, version) }
        }, onExit: { status in
            detectionCancellations[pid] = nil
            // A profile that exits before our script runs is a detection failure, not "not installed".
            finish(status == 0 && !parser.isReady ? -1 : status)
        })
        guard pid > 0 else { return pid }
        detectionCancellations[pid] = {
            guard !completed else { return }
            stopDetection(pid)
            finish(130)
        }
        let timeoutWork = DispatchWorkItem {
            guard !completed else { return }
            stopDetection(pid)
            // Finish promptly even if the kernel takes longer to reap a killed child.
            finish(124)
        }
        watchdog = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        return pid
    }

    private static func stopDetection(_ pid: Int32) {
        // forkpty owns this process group; job control is disabled for all version probes.
        kill(-pid, SIGKILL)
        kill(pid, SIGKILL)
        if let shell = shells[pid] {
            shell.master.readabilityHandler = nil
            try? shell.master.close()
        }
    }

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
            if let cancel = detectionCancellations[pid] {
                cancel()
                return
            }
            if let session = sessions[pid] {
                sessions[pid] = nil
                session.master.readabilityHandler = nil
                try? session.master.close()
                session.process.terminate()
                return
            }
            guard let shell = shells[pid] else { return }
            guard terminatingShells.insert(pid).inserted else { return }
            // Keep the exit observer alive so owners release their storage lease only after exit.
            shell.master.readabilityHandler = nil
            try? shell.master.close()
            kill(pid, SIGHUP)
        }
    }

    // Interactive login shells: forkpty makes the child a session leader owning the PTY,
    // so SIGWINCH and Ctrl-C signals reach it the way a real terminal delivers them
    private static var shells: [Int32: (master: FileHandle, exitSource: DispatchSourceProcess)] = [:]
    private static var terminatingShells: Set<Int32> = []

    @discardableResult
    @objc public static func startShell(
        _ workingDirectory: String,
        cols: Int32,
        rows: Int32,
        onData: @escaping (Data) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        launchShell(workingDirectory, cols: cols, rows: rows, arguments: ["-il"],
                    environment: ProcessInfo.processInfo.environment, onData: onData, onExit: onExit)
    }

    private static func shellEnvironment(_ inherited: [String: String]) -> [String: String] {
        var environment = inherited
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"]?.uppercased().contains("UTF-8") != true {
            environment["LANG"] = "en_US.UTF-8"
        }
        // Detach from the parent Claude Code session while preserving the user's
        // authentication, provider selection, and other CLAUDE_CODE_* configuration.
        for key in [
            "CLAUDECODE",
            "CLAUDE_CODE_SESSION_ID",
            "CLAUDE_CODE_CHILD_SESSION",
            "CLAUDE_CODE_SESSION_ATTENDED",
        ] {
            environment.removeValue(forKey: key)
        }
        // Claim our own terminal identity: an inherited Apple_Terminal mark makes zsh run
        // Terminal.app's session save/restore hooks inside this window
        environment["TERM_PROGRAM"] = "Recap"
        environment.removeValue(forKey: "TERM_PROGRAM_VERSION")
        environment.removeValue(forKey: "TERM_SESSION_ID")
        return environment
    }

    private static func launchShell(
        _ workingDirectory: String,
        cols: Int32,
        rows: Int32,
        arguments: [String],
        environment: [String: String],
        onData: @escaping (Data) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> Int32 {
        let environment = shellEnvironment(environment)

        // Every allocation happens before the fork; the child only calls async-signal-safe functions
        let executable = strdup("/bin/zsh")
        let argv: [UnsafeMutablePointer<CChar>?] = (["-zsh"] + arguments).map { strdup($0) } + [nil]
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
                terminatingShells.remove(pid)
                let signalNumber = status & 0x7f
                onExit(signalNumber != 0 ? 128 + signalNumber : (status >> 8) & 0xff)
            }
        }
        shells[pid] = (masterHandle, exitSource)
        exitSource.resume()
        return pid
    }

    @objc public static func write(_ pid: Int32, data: Data) {
        DispatchQueue.main.async {
            guard !terminatingShells.contains(pid), let shell = shells[pid] else { return }
            try? shell.master.write(contentsOf: data)
        }
    }

    @objc public static func resize(_ pid: Int32, cols: Int32, rows: Int32) {
        DispatchQueue.main.async {
            guard !terminatingShells.contains(pid), let shell = shells[pid] else { return }
            var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(shell.master.fileDescriptor, TIOCSWINSZ, &size)
        }
    }
}

// PTY reads can split lines and UTF-8 characters. Only framed, allowlisted records enter the menu.
struct ToolDetectionParser {
    let marker: String
    private var pending = Data()
    private var found: Set<String> = []
    private(set) var isReady = false
    private let tools: Set<String> = ["claude", "codex", "gemini", "grok", "kimi"]

    mutating func append(_ data: Data) -> [(String, String)] {
        pending.append(data)
        var updates: [(String, String)] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            pending.removeSubrange(...newline)
            let fields = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.first == Substring(marker) else { continue }
            if fields.count == 2, fields[1] == "ready" {
                isReady = true
                continue
            }
            guard fields.count >= 3, tools.contains(String(fields[2])) else { continue }
            let tool = String(fields[2])
            if fields.count == 3, fields[1] == "found", found.insert(tool).inserted {
                updates.append((tool, ""))
            } else if fields.count == 4, fields[1] == "version", found.contains(tool) {
                let version = String(fields[3])
                    .replacingOccurrences(of: "\u{1b}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
                    .components(separatedBy: .controlCharacters).joined()
                    .trimmingCharacters(in: .whitespaces)
                updates.append((tool, String(version.prefix(200))))
            }
        }
        // Ignore unbounded profile output without retaining it for the lifetime of the window.
        if pending.count > 4096 { pending.removeAll(keepingCapacity: false) }
        return updates
    }
}

//
//  LaTeXCompiler.swift
//  Recap
//
//  Created by Rio on 2026/8/25.
//

import Foundation

// xelatex twice via the shell plugin; surfaces the log tail on failure
enum LaTeXCompiler {

    static func compile(texURL: URL, pdfURL: URL, in directory: URL) async throws {
        let workingDirectory = shellQuote(directory.path)
        let source = shellQuote("./" + texURL.lastPathComponent)
        let jobName = shellQuote("-jobname=" + pdfURL.deletingPathExtension().lastPathComponent)
        let command = """
        cd \(workingDirectory) && XL=$(command -v xelatex || echo /Library/TeX/texbin/xelatex) && "$XL" -interaction=nonstopmode \(jobName) \(source) && "$XL" -interaction=nonstopmode \(jobName) \(source)
        """
        var log = ""
        let code = await withCheckedContinuation { continuation in
            ShellBridge.run(command, onOutput: { log += $0 }, onExit: { continuation.resume(returning: $0) })
        }
        guard code == 0 else {
            let tail = log.split(separator: "\n").suffix(12).joined(separator: "\n")
            throw NSError(domain: "Recap", code: Int(code), userInfo: [
                NSLocalizedDescriptionKey: String(localized: "LaTeX 编译失败（需要本机已安装 BasicTeX/xelatex）：") + "\n" + tail,
            ])
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

//
//  LaTeXCompiler.swift
//  Recap
//
//  Created by Rio on 2026/8/25.
//

import Foundation

// xelatex twice via the shell plugin; surfaces the log tail on failure
enum LaTeXCompiler {

    static func compile(texURL: URL, in directory: URL) async throws {
        let command = """
        cd '\(directory.path)' && XL=$(command -v xelatex || echo /Library/TeX/texbin/xelatex) && "$XL" -interaction=nonstopmode '\(texURL.lastPathComponent)' && "$XL" -interaction=nonstopmode '\(texURL.lastPathComponent)'
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
}

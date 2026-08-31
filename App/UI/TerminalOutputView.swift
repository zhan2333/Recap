//
//  TerminalOutputView.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

// Minimal read-only terminal: monospaced, dark ground, handles \r rewrites (curl progress) and strips ANSI escapes.
final class TerminalOutputView: UIView {

    private let textView = UITextView()
    private var lines: [String] = [""]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
        layer.cornerRadius = RecapTheme.radiusMD
        layer.cornerCurve = .continuous
        clipsToBounds = true

        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = UIColor(red: 0.92, green: 0.90, blue: 0.86, alpha: 1)
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func clear() {
        lines = [""]
        textView.text = ""
    }

    func append(_ chunk: String) {
        var text = chunk
        // Strip ANSI escape sequences (colors, cursor movement)
        while let range = text.range(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", options: .regularExpression) {
            text.removeSubrange(range)
        }
        for ch in text {
            switch ch {
            case "\n":
                lines.append("")
            case "\r":
                lines[lines.count - 1] = ""
            default:
                lines[lines.count - 1].append(ch)
            }
        }
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        textView.text = lines.joined(separator: "\n")
        let end = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.scrollRangeToVisible(end)
    }
}

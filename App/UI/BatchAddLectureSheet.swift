//
//  BatchAddLectureSheet.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit

/// Paste one lecture per line — `name<TAB>url` or a bare URL — and enqueue
/// them all at once. Downloads run in parallel, so grab-then-paste beats the
/// direct-link token expiry. Mirrors the proven urls.txt batch workflow.
final class BatchAddLectureSheet: UIViewController {

    var onSubmit: (([(name: String, urls: [URL])]) -> Void)?

    /// Used to auto-number unnamed lines ("第N讲").
    var existingLectureCount = 0

    private let textView = UITextView()
    private let countLabel = UILabel()
    private let submitButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        title = "添加讲次"

        let hint = UILabel()
        hint.text = "每行一条：讲次名 + 空格/Tab + 直链，或只贴直链（自动编号）。行首加 + 表示上一讲的续段视频（多段视频合成一讲）。"
        hint.font = RecapTheme.body(12)
        hint.textColor = RecapTheme.muted
        hint.numberOfLines = 0

        textView.font = RecapTheme.mono(12, weight: .regular)
        textView.backgroundColor = RecapTheme.surface.withAlphaComponent(0.5)
        textView.layer.cornerRadius = RecapTheme.radiusMD
        textView.layer.cornerCurve = .continuous
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        if let paste = UIPasteboard.general.string, paste.contains("http") {
            textView.text = paste
        }

        countLabel.font = RecapTheme.body(11)
        countLabel.textColor = RecapTheme.quiet

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RecapTheme.ink
        config.baseForegroundColor = RecapTheme.paper
        config.background.cornerRadius = RecapTheme.radiusSM
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        submitButton.configuration = config
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        let footer = UIStackView(arrangedSubviews: [countLabel, UIView(), submitButton])
        footer.axis = .horizontal
        footer.alignment = .center

        let stack = UIStackView(arrangedSubviews: [hint, textView, footer])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        refresh()
    }

    private func submit() {
        let entries = Self.parse(textView.text ?? "", startNumber: existingLectureCount + 1)
        guard !entries.isEmpty else { return }
        dismiss(animated: true) { [onSubmit] in
            onSubmit?(entries)
        }
    }

    private func refresh() {
        let entries = Self.parse(textView.text ?? "", startNumber: existingLectureCount + 1)
        let partCount = entries.reduce(0) { $0 + $1.urls.count }
        countLabel.text = entries.isEmpty
            ? "还没有可入队的直链"
            : partCount > entries.count
                ? "识别到 \(entries.count) 讲（共 \(partCount) 段视频）"
                : "识别到 \(entries.count) 条"
        var title = AttributedString(entries.count > 1 ? "全部入队（\(entries.count) 讲）" : "入队")
        title.font = RecapTheme.body(13, weight: .semibold)
        title.foregroundColor = RecapTheme.paper
        submitButton.configuration?.attributedTitle = title
        submitButton.isEnabled = !entries.isEmpty
    }

    /// `名称<TAB或空格>URL`、当年 urls.txt 的 `name<TAB>date<TAB>url`、或纯 URL 行。
    /// 行首 `+` 表示该视频是上一讲的续段。
    static func parse(_ text: String, startNumber: Int) -> [(name: String, urls: [URL])] {
        var results: [(name: String, urls: [URL])] = []
        var autoNumber = startNumber
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var isContinuation = false
            if line.hasPrefix("+") || line.hasPrefix("＋") {
                isContinuation = true
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard let httpRange = line.range(of: "http") else { continue }
            let urlCandidate = line[httpRange.lowerBound...]
                .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            guard let url = URL(string: urlCandidate), url.host != nil else { continue }

            if isContinuation, !results.isEmpty {
                results[results.count - 1].urls.append(url)
                continue
            }
            var name = String(line[..<httpRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\t", with: " ")
            if name.isEmpty {
                name = "第\(autoNumber)讲"
            }
            autoNumber += 1
            results.append((name, [url]))
        }
        return results
    }
}

extension BatchAddLectureSheet: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        refresh()
    }
}

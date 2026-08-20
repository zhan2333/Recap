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

    var onSubmit: (([(name: String, url: URL)]) -> Void)?

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
        hint.text = "每行一条：讲次名 + 空格/Tab + 直链，或只贴直链（自动编号）。可一次粘贴整门课。"
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
        let count = Self.parse(textView.text ?? "", startNumber: existingLectureCount + 1).count
        countLabel.text = count == 0 ? "还没有可入队的直链" : "识别到 \(count) 条"
        var title = AttributedString(count > 1 ? "全部入队（\(count) 条）" : "入队")
        title.font = RecapTheme.body(13, weight: .semibold)
        title.foregroundColor = RecapTheme.paper
        submitButton.configuration?.attributedTitle = title
        submitButton.isEnabled = count > 0
    }

    /// `名称<TAB或空格>URL`、当年 urls.txt 的 `name<TAB>date<TAB>url`、或纯 URL 行。
    static func parse(_ text: String, startNumber: Int) -> [(name: String, url: URL)] {
        var results: [(String, URL)] = []
        var autoNumber = startNumber
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let httpRange = line.range(of: "http") else { continue }
            let urlCandidate = line[httpRange.lowerBound...]
                .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            guard let url = URL(string: urlCandidate), url.host != nil else { continue }
            var name = String(line[..<httpRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\t", with: " ")
            if name.isEmpty {
                name = "第\(autoNumber)讲"
            }
            autoNumber += 1
            results.append((name, url))
        }
        return results
    }
}

extension BatchAddLectureSheet: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        refresh()
    }
}

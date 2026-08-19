//
//  TranscriptViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import TranscriptionKit
import AnalysisKit

/// Detail column: Evidence Thread review, reading page, or key points.
final class TranscriptViewController: UIViewController {

    private let lecture: Lecture
    private let course: Course

    private var segments: [TranscriptSegment] = []
    private var plainText: String = ""
    private var analysis: LectureAnalysis?
    private var isAnalyzing = false

    private let header = DetailHeaderView()
    private let metaBar = TranscriptMetaBar()
    private let reviewView = EvidenceReviewView()
    private let readingView = ReadingPageView()
    private let signalsView = SignalsPageView()
    private let emptyLabel = UILabel()

    init(lecture: Lecture, course: Course) {
        self.lecture = lecture
        self.course = course
        super.init(nibName: nil, bundle: nil)
        title = lecture.name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        navigationController?.navigationBar.isHidden = true

        header.titleLabel.text = lecture.name
        header.subtitleLabel.text = course.name
        header.modeTabs.onSelect = { [weak self] _ in self?.applyMode() }
        header.analyzeButton.addAction(UIAction { [weak self] _ in self?.primaryAction() }, for: .touchUpInside)

        emptyLabel.textColor = RecapTheme.quiet
        emptyLabel.font = RecapTheme.body(13)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0

        signalsView.onReExtract = { [weak self] in self?.analyze() }

        for subview in [header, metaBar, reviewView, readingView, signalsView, emptyLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safe.topAnchor),
            header.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            metaBar.topAnchor.constraint(equalTo: header.bottomAnchor),
            metaBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            metaBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
        ])
        for pane in [reviewView, readingView, signalsView] as [UIView] {
            NSLayoutConstraint.activate([
                pane.topAnchor.constraint(equalTo: metaBar.bottomAnchor),
                pane.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                pane.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 40),
        ])

        reviewView.onGenerateHandout = { [weak self] in self?.generateHandout() }

        loadContent()
        refreshChrome()
        applyMode()
    }

    // MARK: - Content

    private func loadContent() {
        let store = LibraryStore.shared
        if let data = try? Data(contentsOf: store.productURL(lecture, in: course, ext: "segments.json")),
           let decoded = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
            segments = decoded
        }
        plainText = (try? String(contentsOf: store.productURL(lecture, in: course, ext: "txt"), encoding: .utf8)) ?? ""
        if let data = try? Data(contentsOf: store.productURL(lecture, in: course, ext: "analysis.json")),
           let decoded = try? JSONDecoder().decode(LectureAnalysis.self, from: data) {
            analysis = decoded
        }
        reviewView.update(segments: segments, analysis: analysis)
        readingView.update(title: lecture.name, subtitle: course.name, segments: segments, analysis: analysis)
        signalsView.update(analysis: analysis)
        metaBar.update(segments: segments, characterCount: plainText.count)
    }

    private var handoutURL: URL {
        LibraryStore.shared.productURL(lecture, in: course, ext: "handout.md")
    }

    private var hasHandout: Bool {
        (try? String(contentsOf: handoutURL, encoding: .utf8))?.isEmpty == false
    }

    // MARK: - Chrome

    private func refreshChrome() {
        header.isAnalyzing = isAnalyzing

        var title = "提取重点"
        if analysis != nil { title = hasHandout ? "查看讲义" : "生成讲义" }
        header.analyzeButton.configuration?.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: RecapTheme.body(12, weight: .semibold)]))
        header.analyzeButton.isEnabled = !plainText.isEmpty

        var actions: [UIAction] = []
        if analysis != nil {
            actions.append(UIAction(title: "重新提取重点", image: UIImage(systemName: "text.magnifyingglass")) { [weak self] _ in
                self?.analyze()
            })
            actions.append(UIAction(title: "生成本讲讲义", image: UIImage(systemName: "doc.text")) { [weak self] _ in
                self?.generateHandout()
            })
        }
        if hasHandout {
            actions.append(UIAction(title: "查看本讲讲义", image: UIImage(systemName: "doc.richtext")) { [weak self] _ in
                self?.showHandout()
            })
        }
        header.overflowButton.menu = actions.isEmpty ? nil : UIMenu(children: actions)
        header.overflowButton.isHidden = actions.isEmpty
    }

    private func applyMode() {
        let mode = header.modeTabs.selectedIndex
        reviewView.isHidden = true
        readingView.isHidden = true
        signalsView.isHidden = true
        emptyLabel.isHidden = true

        switch mode {
        case 0 where !segments.isEmpty:
            reviewView.isHidden = false
        case 1 where !plainText.isEmpty:
            readingView.isHidden = false
        case 2 where analysis != nil:
            signalsView.isHidden = false
        default:
            emptyLabel.isHidden = false
            if mode == 2 {
                emptyLabel.text = isAnalyzing
                    ? "正在读取文稿，提取老师强调的重点…"
                    : plainText.isEmpty ? "先完成转写，再提取重点" : "文稿已就绪 · 点右上角提取本讲重点"
            } else {
                emptyLabel.text = lecture.phase == .failed
                    ? "转写失败：\(lecture.errorMessage ?? "未知错误")"
                    : "尚无文稿——转写完成后在这里查看"
            }
        }
    }

    // MARK: - Actions

    private func primaryAction() {
        if analysis == nil {
            analyze()
        } else if hasHandout {
            showHandout()
        } else {
            generateHandout()
        }
    }

    private func analyze() {
        guard !plainText.isEmpty, !isAnalyzing else { return }
        guard let config = Settings.chatConfig else {
            presentConfigureAlert()
            return
        }
        isAnalyzing = true
        refreshChrome()
        header.modeTabs.select(2)

        let transcript = plainText
        Task {
            do {
                let result = try await LectureAnalyzer().extract(transcript: transcript, client: ChatClient(config: config))
                try JSONEncoder().encode(result)
                    .write(to: LibraryStore.shared.productURL(lecture, in: course, ext: "analysis.json"), options: .atomic)
                analysis = result
                loadContent()
            } catch {
                presentInfo(title: "提取失败", message: error.localizedDescription)
            }
            isAnalyzing = false
            refreshChrome()
            applyMode()
        }
    }

    private func generateHandout() {
        guard let analysis, !isAnalyzing else { return }
        guard let config = Settings.chatConfig else {
            presentConfigureAlert()
            return
        }
        isAnalyzing = true
        refreshChrome()

        let transcript = plainText
        let lectureTitle = lecture.name
        Task {
            do {
                let markdown = try await HandoutGenerator().lectureHandout(
                    title: lectureTitle,
                    transcript: transcript,
                    analysis: analysis,
                    client: ChatClient(config: config)
                )
                try markdown.write(to: handoutURL, atomically: true, encoding: .utf8)
                showHandout()
            } catch {
                presentInfo(title: "生成失败", message: error.localizedDescription)
            }
            isAnalyzing = false
            refreshChrome()
        }
    }

    private func showHandout() {
        guard let markdown = try? String(contentsOf: handoutURL, encoding: .utf8) else { return }
        navigationController?.navigationBar.isHidden = false
        navigationController?.pushViewController(
            MarkdownViewController(markdown: markdown, title: "\(lecture.name) 讲义"),
            animated: true
        )
    }

    private func presentConfigureAlert() {
        let alert = UIAlertController(
            title: "先配置 AI 接口",
            message: "在设置里填写 Base URL、API Key 和 Model。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { [weak self] _ in
            self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
        })
        present(alert, animated: true)
    }

    private func presentInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

/// 34pt strip under the header: local state dot, duration/word count, model.
final class TranscriptMetaBar: UIView {

    private let stateLabel = UILabel()
    private let statsLabel = UILabel()
    private let modelLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.metaBar

        let dot = UIView()
        dot.backgroundColor = RecapTheme.complete
        dot.layer.cornerRadius = 3.5

        for label in [stateLabel, statsLabel, modelLabel] {
            label.font = RecapTheme.body(11)
            label.textColor = RecapTheme.quiet
        }
        stateLabel.text = "本地转写完成"

        let bottomLine = UIView()
        bottomLine.backgroundColor = RecapTheme.line

        let stack = UIStackView(arrangedSubviews: [dot, stateLabel, statsLabel, modelLabel, UIView()])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 18
        stack.setCustomSpacing(6, after: dot)
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(bottomLine)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(segments: [TranscriptSegment], characterCount: Int) {
        guard let last = segments.last else {
            statsLabel.text = nil
            modelLabel.text = nil
            stateLabel.text = "等待转写"
            return
        }
        stateLabel.text = "本地转写完成"
        let total = Int(last.end)
        let duration = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
        statsLabel.text = "\(duration) · \(characterCount) 字"
        modelLabel.text = "模型：large-v3-turbo"
    }
}

/// Full-text reading page: serif title, merged paragraphs, quote blocks.
final class ReadingPageView: UIView, UITableViewDataSource {

    fileprivate enum Row {
        case eyebrow(String)
        case title(String)
        case paragraph(String)
        case quote(String)
    }

    private var rows: [Row] = []
    private let tableView = UITableView(frame: .zero, style: .plain)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.paper
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.allowsSelection = false
        tableView.register(ReadingRowCell.self, forCellReuseIdentifier: ReadingRowCell.reuseID)
        tableView.contentInset = UIEdgeInsets(top: 44, left: 0, bottom: 104, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, subtitle: String, segments: [TranscriptSegment], analysis: LectureAnalysis?) {
        var quoteSegmentIndexes = Set<Int>()
        if let analysis {
            let matches = EvidenceMatcher.match(
                signals: analysis.examSignals,
                segments: segments.map { ($0.start, $0.text) }
            )
            quoteSegmentIndexes = Set(matches.map(\.segmentIndex))
        }

        rows = [.eyebrow("\(subtitle) · 完整文稿"), .title(title)]
        var buffer: [String] = []
        func flush() {
            if !buffer.isEmpty {
                rows.append(.paragraph(buffer.joined()))
                buffer = []
            }
        }
        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if quoteSegmentIndexes.contains(index) {
                flush()
                rows.append(.quote(text))
            } else {
                buffer.append(text)
                if buffer.count >= 5 { flush() }
            }
        }
        flush()
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReadingRowCell.reuseID, for: indexPath) as! ReadingRowCell
        cell.configure(with: rows[indexPath.row])
        return cell
    }

    fileprivate final class ReadingRowCell: UITableViewCell {

        static let reuseID = "ReadingRowCell"

        private let label = UILabel()
        private let quoteRule = UIView()
        private var leadingInset: NSLayoutConstraint!

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            selectionStyle = .none
            backgroundColor = .clear
            label.numberOfLines = 0
            quoteRule.backgroundColor = RecapTheme.signal
            quoteRule.isHidden = true

            let content = UIView()
            content.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(content)
            label.translatesAutoresizingMaskIntoConstraints = false
            quoteRule.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(quoteRule)
            content.addSubview(label)

            let width = content.widthAnchor.constraint(lessThanOrEqualToConstant: 680)
            let edge = content.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32)
            leadingInset = label.leadingAnchor.constraint(equalTo: content.leadingAnchor)
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                content.topAnchor.constraint(equalTo: contentView.topAnchor),
                content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                content.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -64).withPriority(.defaultHigh),
                width, edge,
                quoteRule.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                quoteRule.topAnchor.constraint(equalTo: label.topAnchor, constant: 2),
                quoteRule.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: -2),
                quoteRule.widthAnchor.constraint(equalToConstant: 2),
                leadingInset,
                label.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                label.topAnchor.constraint(equalTo: content.topAnchor),
                label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(with row: Row) {
            quoteRule.isHidden = true
            leadingInset.constant = 0
            switch row {
            case .eyebrow(let text):
                label.attributedText = NSAttributedString(string: text, attributes: [
                    .font: RecapTheme.body(11), .foregroundColor: RecapTheme.muted,
                ])
            case .title(let text):
                label.attributedText = NSAttributedString(string: text, attributes: [
                    .font: RecapTheme.display(34, weight: .semibold), .foregroundColor: RecapTheme.ink,
                ])
            case .paragraph(let text):
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.4
                label.attributedText = NSAttributedString(string: text, attributes: [
                    .font: RecapTheme.body(15), .foregroundColor: RecapTheme.ink, .paragraphStyle: style,
                ])
            case .quote(let text):
                quoteRule.isHidden = false
                leadingInset.constant = 24
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.3
                label.attributedText = NSAttributedString(string: text, attributes: [
                    .font: RecapTheme.display(19, weight: .medium), .foregroundColor: RecapTheme.ink, .paragraphStyle: style,
                ])
            }
        }
    }
}

/// Key-points page: serif count header, quote cards, four-cell grid.
final class SignalsPageView: UIView {

    var onReExtract: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.paper
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 42),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -86),
            stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -64)
                .withPriority(.defaultHigh),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(analysis: LectureAnalysis?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let analysis else { return }

        // Header
        let eyebrow = UILabel()
        eyebrow.text = "本讲共提取"
        eyebrow.font = RecapTheme.body(11)
        eyebrow.textColor = RecapTheme.muted
        let count = UILabel()
        count.text = "\(analysis.examSignals.count) 个重点"
        count.font = RecapTheme.display(28, weight: .semibold)
        count.textColor = RecapTheme.ink
        let headerText = UIStackView(arrangedSubviews: [eyebrow, count])
        headerText.axis = .vertical
        headerText.spacing = 5

        let redo = UIButton(type: .system)
        var redoConfig = UIButton.Configuration.plain()
        redoConfig.attributedTitle = AttributedString("重新提取", attributes: AttributeContainer([.font: RecapTheme.body(11)]))
        redoConfig.baseForegroundColor = RecapTheme.muted
        redoConfig.background.strokeColor = RecapTheme.line
        redoConfig.background.strokeWidth = 1
        redoConfig.background.cornerRadius = RecapTheme.radiusSM
        redo.configuration = redoConfig
        redo.addAction(UIAction { [weak self] _ in self?.onReExtract?() }, for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [headerText, UIView(), redo])
        headerRow.axis = .horizontal
        headerRow.alignment = .bottom
        stack.addArrangedSubview(headerRow)
        stack.setCustomSpacing(34, after: headerRow)

        // Quote cards
        if !analysis.examSignals.isEmpty {
            let sectionTitle = UILabel()
            sectionTitle.text = "重点（老师原话）"
            sectionTitle.font = RecapTheme.body(13, weight: .semibold)
            sectionTitle.textColor = RecapTheme.ink
            stack.addArrangedSubview(sectionTitle)
            stack.setCustomSpacing(10, after: sectionTitle)

            for signal in analysis.examSignals {
                stack.addArrangedSubview(SignalCardView(signal: signal))
            }
        }

        // 2×2 grid of list sections
        let gridPairs: [(String, [String])] = [
            ("核心概念", analysis.keyConcepts),
            ("解题方法", analysis.answerApproaches),
            ("易混易错", analysis.confusablePoints),
            ("作业 / 思考题", analysis.assignments),
        ].filter { !$0.1.isEmpty }

        if !gridPairs.isEmpty {
            let grid = UIStackView()
            grid.axis = .vertical
            grid.spacing = 10
            var rowStack: UIStackView?
            for (index, pair) in gridPairs.enumerated() {
                if index % 2 == 0 {
                    let row = UIStackView()
                    row.axis = .horizontal
                    row.spacing = 26
                    row.distribution = .fillEqually
                    row.alignment = .top
                    grid.addArrangedSubview(row)
                    rowStack = row
                }
                rowStack?.addArrangedSubview(GridSectionView(title: pair.0, items: pair.1))
            }
            if gridPairs.count % 2 == 1 { rowStack?.addArrangedSubview(UIView()) }
            stack.setCustomSpacing(32, after: stack.arrangedSubviews.last ?? stack)
            stack.addArrangedSubview(grid)
        }

        if !analysis.mustMemorize.isEmpty {
            stack.setCustomSpacing(24, after: stack.arrangedSubviews.last ?? stack)
            stack.addArrangedSubview(GridSectionView(title: "必背", items: analysis.mustMemorize))
        }
    }

    private final class SignalCardView: UIView {
        init(signal: LectureAnalysis.ExamSignal) {
            super.init(frame: .zero)
            let kind = UILabel()
            var kindText = signal.strength
            if let qtype = signal.qtype, !qtype.isEmpty { kindText += " · \(qtype)" }
            kind.text = kindText
            kind.font = RecapTheme.body(11, weight: .semibold)
            kind.textColor = RecapTheme.signalText

            let quote = UILabel()
            quote.text = "“\(signal.quote)”"
            quote.font = RecapTheme.display(17, weight: .medium)
            quote.textColor = RecapTheme.ink
            quote.numberOfLines = 0

            let topic = UILabel()
            topic.text = signal.topic.map { "知识点：\($0)" }
            topic.font = RecapTheme.body(11)
            topic.textColor = RecapTheme.muted

            let content = UIStackView(arrangedSubviews: [kind, quote, topic])
            content.axis = .vertical
            content.spacing = 11

            let bottomLine = UIView()
            bottomLine.backgroundColor = RecapTheme.line

            content.translatesAutoresizingMaskIntoConstraints = false
            bottomLine.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            addSubview(bottomLine)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor, constant: 20),
                content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
                bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
                bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
                bottomLine.heightAnchor.constraint(equalToConstant: 1),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    private final class GridSectionView: UIView {
        init(title: String, items: [String]) {
            super.init(frame: .zero)
            let topLine = UIView()
            topLine.backgroundColor = RecapTheme.line

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = RecapTheme.body(13, weight: .semibold)
            titleLabel.textColor = RecapTheme.ink

            let body = UILabel()
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.35
            style.paragraphSpacing = 5
            body.attributedText = NSAttributedString(string: items.joined(separator: "\n"), attributes: [
                .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted, .paragraphStyle: style,
            ])
            body.numberOfLines = 0

            let content = UIStackView(arrangedSubviews: [titleLabel, body])
            content.axis = .vertical
            content.spacing = 10

            topLine.translatesAutoresizingMaskIntoConstraints = false
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(topLine)
            addSubview(content)
            NSLayoutConstraint.activate([
                topLine.topAnchor.constraint(equalTo: topAnchor),
                topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
                topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
                topLine.heightAnchor.constraint(equalToConstant: 1),
                content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

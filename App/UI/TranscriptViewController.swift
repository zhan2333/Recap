//
//  TranscriptViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import TranscriptionKit
import AnalysisKit

// Detail column: Evidence Thread review, reading page, or key points.
final class TranscriptViewController: UIViewController {

    private var lecture: Lecture
    private let course: Course

    private var segments: [TranscriptSegment] = []
    private var plainText: String = ""
    private var analysis: LectureAnalysis?
    private var isAnalyzing = false
    private var isLoading = false

    private let header = DetailHeaderView()
    private let metaBar = TranscriptMetaBar()
    private let reviewView = EvidenceReviewView()
    private let readingView = ReadingPageView()
    private let playerPane = PlayerPaneView()
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

        for subview in [header, metaBar, reviewView, readingView, playerPane, signalsView, emptyLabel] as [UIView] {
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
        addChild(playerPane.playerViewController)
        playerPane.playerViewController.didMove(toParent: self)
        playerPane.onRequestRedownload = { [weak self] in
            guard let self else { return }
            LectureQueue.shared.enqueue(self.lecture, in: self.course)
        }
        for pane in [reviewView, readingView, playerPane, signalsView] as [UIView] {
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(queueActivityChanged(_:)),
            name: LectureQueue.activityDidChange, object: nil
        )

        loadContent()
        refreshChrome()
        applyMode()
    }

    // Reload when a pipeline stage for this lecture finishes (e.g. after appending a part)
    @objc private func queueActivityChanged(_ note: Notification) {
        guard note.userInfo?["lectureID"] as? UUID == lecture.id,
              LectureQueue.shared.activity(for: lecture.id) == nil else { return }
        loadContent()
    }

    // MARK: - Content

    // File IO, JSON decoding, row merging and quote matching are heavy for a real 1.5h lecture — all off the main thread
    private func loadContent() {
        isLoading = true
        applyMode()
        let store = LibraryStore.shared
        if let fresh = store.lecture(id: lecture.id, in: course) { lecture = fresh }
        let segmentsURL = store.productURL(lecture, in: course, ext: "segments.json")
        let txtURL = store.productURL(lecture, in: course, ext: "txt")
        let analysisURL = store.productURL(lecture, in: course, ext: "analysis.json")
        let matchCacheURL = store.productURL(lecture, in: course, ext: "matches.json")
        let courseDirectory = store.courseDirectory(course)
        let mediaParts = store.mediaParts(of: lecture, in: course)
            .map { (url: $0.url, duration: $0.part.duration,
                    waveformCacheURL: Optional(courseDirectory.appendingPathComponent("\($0.part.id.uuidString).waveform.json"))) }
        let lectureName = lecture.name
        let courseName = course.name

        Task.detached(priority: .userInitiated) { [weak self] in
            var segments: [TranscriptSegment] = []
            if let data = try? Data(contentsOf: segmentsURL),
               let decoded = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
                segments = decoded
            }
            let plainText = (try? String(contentsOf: txtURL, encoding: .utf8)) ?? ""
            var analysis: LectureAnalysis?
            if let data = try? Data(contentsOf: analysisURL),
               let decoded = try? JSONDecoder().decode(LectureAnalysis.self, from: data) {
                analysis = decoded
            }

            let rows = EvidenceReviewView.mergeRows(segments)
            var evidences: [EvidenceReviewView.Evidence] = []
            if let analysis {
                func modified(_ url: URL) -> Date {
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                }
                let segmentsModified = modified(segmentsURL)
                let analysisModified = modified(analysisURL)
                let matches: [EvidenceMatch]
                if let cached = EvidenceMatcher.cachedMatches(
                    at: matchCacheURL, segmentsModified: segmentsModified, analysisModified: analysisModified) {
                    matches = cached
                } else {
                    matches = EvidenceMatcher.match(
                        signals: analysis.examSignals,
                        segments: rows.map { ($0.start, $0.text) }
                    )
                    EvidenceMatcher.cache(
                        matches, at: matchCacheURL,
                        segmentsModified: segmentsModified, analysisModified: analysisModified)
                }
                let matchBySignal = Dictionary(uniqueKeysWithValues: matches.map { ($0.signalIndex, $0) })
                evidences = analysis.examSignals.enumerated().map { index, signal in
                    EvidenceReviewView.Evidence(
                        signal: signal,
                        rowIndex: matchBySignal[index]?.segmentIndex,
                        start: matchBySignal[index]?.start
                    )
                }
            }
            let quoteRows = Set(evidences.compactMap(\.rowIndex))

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.segments = segments
                self.plainText = plainText
                self.analysis = analysis
                self.reviewView.update(rows: rows, evidences: evidences)
                self.readingView.update(title: lectureName, subtitle: courseName, rows: rows, quoteRows: quoteRows)
                self.playerPane.configure(parts: mediaParts, rows: rows, evidences: evidences)
                self.signalsView.update(analysis: analysis)
                self.metaBar.update(segments: segments, characterCount: plainText.count)
                self.isLoading = false
                self.refreshChrome()
                self.applyMode()
            }
        }
    }

    private var handoutURL: URL {
        LibraryStore.shared.productURL(lecture, in: course, ext: "handout.pdf")
    }

    private var hasHandout: Bool {
        FileManager.default.fileExists(atPath: handoutURL.path)
    }

    // MARK: - Chrome

    private func refreshChrome() {
        header.isAnalyzing = isAnalyzing

        var title = String(localized: "提取重点")
        if analysis != nil { title = hasHandout ? String(localized: "查看讲义") : String(localized: "生成讲义") }
        header.analyzeButton.configuration?.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([
                .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
            ]))
        header.analyzeButton.isEnabled = !plainText.isEmpty

        var actions: [UIAction] = []
        if analysis != nil {
            actions.append(UIAction(title: String(localized: "重新提取重点"), image: UIImage(systemName: "text.magnifyingglass")) { [weak self] _ in
                self?.analyze()
            })
            actions.append(UIAction(title: String(localized: "生成本讲讲义"), image: UIImage(systemName: "doc.text")) { [weak self] _ in
                self?.generateHandout()
            })
        }
        if hasHandout {
            actions.append(UIAction(title: String(localized: "查看本讲讲义"), image: UIImage(systemName: "doc.richtext")) { [weak self] _ in
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
        playerPane.isHidden = true
        signalsView.isHidden = true
        emptyLabel.isHidden = true

        // A background refresh must not flash the loading state over live content
        if isLoading && segments.isEmpty {
            emptyLabel.isHidden = false
            emptyLabel.text = String(localized: "正在载入文稿…")
            return
        }
        switch mode {
        case 0 where !segments.isEmpty:
            reviewView.isHidden = false
        case 1 where !plainText.isEmpty:
            readingView.isHidden = false
        case 2:
            playerPane.isHidden = false
        case 3 where analysis != nil:
            signalsView.isHidden = false
        default:
            emptyLabel.isHidden = false
            if mode == 3 {
                emptyLabel.text = isAnalyzing
                    ? String(localized: "正在读取文稿，提取老师强调的重点…")
                    : plainText.isEmpty ? String(localized: "先完成转写，再提取重点") : String(localized: "文稿已就绪 · 点右上角提取本讲重点")
            } else {
                emptyLabel.text = lecture.phase == .failed
                    ? String(localized: "转写失败：\(lecture.errorMessage ?? String(localized: "未知错误"))")
                    : String(localized: "尚无文稿——转写完成后在这里查看")
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
        header.modeTabs.select(3)

        let transcript = plainText
        Task {
            do {
                let result = try await LectureAnalyzer().extract(transcript: transcript, client: ChatClient(config: config))
                try JSONEncoder().encode(result)
                    .write(to: LibraryStore.shared.productURL(lecture, in: course, ext: "analysis.json"), options: .atomic)
                analysis = result
                loadContent()
            } catch {
                var message = error.localizedDescription
                if let analyzeError = error as? LectureAnalyzer.AnalyzeError {
                    let rawURL = LibraryStore.shared.productURL(lecture, in: course, ext: "analysis-raw.txt")
                    try? analyzeError.rawResponse.write(to: rawURL, atomically: true, encoding: .utf8)
                    message += String(localized: "\n完整响应已保存到课程目录 analysis-raw.txt。")
                }
                presentInfo(title: String(localized: "提取失败"), message: message)
            }
            isAnalyzing = false
            refreshChrome()
            applyMode()
        }
    }

    // Two channels: claude CLI (LaTeX → PDF, per the bundled skill) or the configured API (Markdown)
    private func generateHandout() {
        let alert = UIAlertController(
            title: String(localized: "生成本讲讲义"),
            message: String(localized: "两种方式产出同一份 PDF 讲义：claude 按内置 skill 生成，或用已配置的 API 接口按同一 skill 生成、在本机编译。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "用 CLI agent 生成"), style: .default) { [weak self] _ in
            self?.presentTerminalStudio()
        })
        alert.addAction(UIAlertAction(title: String(localized: "用 API 生成"), style: .default) { [weak self] _ in
            self?.generateHandoutViaAPI()
        })
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        present(alert, animated: true)
    }

    // API channel follows the same bundled skill: LLM writes the .tex, xelatex compiles it locally
    private func generateHandoutViaAPI() {
        guard !plainText.isEmpty, let analysis else { return }
        guard let config = Settings.chatConfig else {
            presentConfigureAlert()
            return
        }
        isAnalyzing = true
        refreshChrome()
        let title = lecture.name
        let transcript = plainText
        let texURL = LibraryStore.shared.productURL(lecture, in: course, ext: "handout.tex")
        let courseDir = LibraryStore.shared.courseDirectory(course)
        Task {
            do {
                guard let skillURL = Bundle.main.url(forResource: "recap-review-skill", withExtension: "md"),
                      let skill = try? String(contentsOf: skillURL, encoding: .utf8) else {
                    throw NSError(domain: "Recap", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "内置 skill 缺失"),
                    ])
                }
                let tex = try await HandoutGenerator().lectureLaTeX(
                    title: title, transcript: transcript, analysis: analysis, skill: skill,
                    client: ChatClient(config: config)
                )
                try tex.write(to: texURL, atomically: true, encoding: .utf8)
                try await Self.compileLaTeX(texURL: texURL, in: courseDir)
                isAnalyzing = false
                refreshChrome()
                showHandout()
            } catch {
                isAnalyzing = false
                refreshChrome()
                presentInfo(title: String(localized: "生成失败"), message: error.localizedDescription)
            }
        }
    }

    private static func compileLaTeX(texURL: URL, in directory: URL) async throws {
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

    private func presentTerminalStudio() {
        let studio = TerminalStudioViewController(lecture: lecture, course: course) { [weak self] in
            self?.showHandout()
        }
        present(studio, animated: true)
    }

    private func showHandout() {
        guard hasHandout else { return }
        navigationController?.navigationBar.isHidden = false
        navigationController?.pushViewController(
            PDFViewController(fileURL: handoutURL, title: String(localized: "\(lecture.name) 讲义")),
            animated: true
        )
    }

    private func presentConfigureAlert() {
        let alert = UIAlertController(
            title: String(localized: "先配置 AI 接口"),
            message: String(localized: "在设置里填写 Base URL、API Key 和 Model。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "去设置"), style: .default) { [weak self] _ in
            self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
        })
        present(alert, animated: true)
    }

    private func presentInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "好"), style: .default))
        present(alert, animated: true)
    }
}

// 34pt strip under the header: local state dot, duration/word count, model.
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
        stateLabel.text = String(localized: "本地转写完成")

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
            stateLabel.text = String(localized: "等待转写")
            return
        }
        stateLabel.text = String(localized: "本地转写完成")
        let total = Int(last.end)
        let duration = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
        statsLabel.text = String(localized: "\(duration) · \(characterCount) 字")
        modelLabel.text = String(localized: "模型：large-v3-turbo")
    }
}

// Full-text reading page: serif title, merged paragraphs, quote blocks.
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

    func update(title: String, subtitle: String, rows displayRows: [EvidenceReviewView.DisplayRow], quoteRows: Set<Int>) {
        rows = [.eyebrow(String(localized: "\(subtitle) · 完整文稿")), .title(title)]
        var buffer = ""
        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                rows.append(.paragraph(trimmed))
            }
            buffer = ""
        }
        for (index, row) in displayRows.enumerated() {
            if quoteRows.contains(index) {
                flush()
                rows.append(.quote(row.text))
            } else {
                buffer += row.text
                let endsSentence = row.text.hasSuffix("。") || row.text.hasSuffix("？") || row.text.hasSuffix("！")
                if buffer.count >= 220 || (endsSentence && buffer.count >= 120) { flush() }
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

// Key-points page: serif count header, quote cards, four-cell grid.
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
            // Hard bounds: content must never escape the visible frame.
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.trailingAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(analysis: LectureAnalysis?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let analysis else { return }

        // Header
        let eyebrow = UILabel()
        eyebrow.text = String(localized: "本讲共提取")
        eyebrow.font = RecapTheme.body(11)
        eyebrow.textColor = RecapTheme.muted
        let count = UILabel()
        count.text = String(localized: "\(analysis.examSignals.count) 个重点")
        count.font = RecapTheme.display(28, weight: .semibold)
        count.textColor = RecapTheme.ink
        let headerText = UIStackView(arrangedSubviews: [eyebrow, count])
        headerText.axis = .vertical
        headerText.spacing = 5

        let redo = UIButton(type: .system)
        var redoConfig = UIButton.Configuration.plain()
        redoConfig.attributedTitle = AttributedString(String(localized: "重新提取"), attributes: AttributeContainer([
            .font: RecapTheme.body(11), .foregroundColor: RecapTheme.muted,
        ]))
        redoConfig.baseForegroundColor = RecapTheme.muted
        redoConfig.background.strokeColor = RecapTheme.line
        redoConfig.background.strokeWidth = 1
        redoConfig.background.cornerRadius = RecapTheme.radiusSM
        redo.configuration = redoConfig
        redo.addAction(UIAction { [weak self] _ in self?.onReExtract?() }, for: .touchUpInside)
        redo.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerRow = UIStackView(arrangedSubviews: [headerText, UIView(), redo])
        headerRow.axis = .horizontal
        headerRow.alignment = .bottom
        stack.addArrangedSubview(headerRow)
        stack.setCustomSpacing(34, after: headerRow)

        // Quote cards
        if !analysis.examSignals.isEmpty {
            let sectionTitle = UILabel()
            sectionTitle.text = String(localized: "重点（老师原话）")
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
            (String(localized: "核心概念"), analysis.keyConcepts),
            (String(localized: "解题方法"), analysis.answerApproaches),
            (String(localized: "易混易错"), analysis.confusablePoints),
            (String(localized: "作业 / 思考题"), analysis.assignments),
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
            stack.addArrangedSubview(GridSectionView(title: String(localized: "必背"), items: analysis.mustMemorize))
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
            topic.text = signal.topic.map { String(localized: "知识点：\($0)") }
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

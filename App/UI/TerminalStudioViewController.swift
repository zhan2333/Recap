//
//  TerminalStudioViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/25.
//

import UIKit
import QuickLook

// Terminal Studio: the user's own CLI runs inside the course context, the artifact lands back in place
final class TerminalStudioViewController: UIViewController {

    private let lecture: Lecture
    private let course: Course
    private let onShowHandout: () -> Void
    private let initialPrompt: String?
    private let onArtifactsChanged: (() -> Void)?

    struct SessionRecord {
        let tool: String
        let prompt: String
        let log: String
        let exitCode: Int32
        let date: Date
    }

    // Survives sheet dismissal for the lifetime of the app
    private static var sessionsByLecture: [UUID: [SessionRecord]] = [:]

    private var detectedTools: [String] = []
    private var toolVersions: [String: String] = [:]
    private var selectedTool: String?
    private var isRunning = false
    private var runningPID: Int32 = -1
    private var pdfModifiedBeforeRun = Date.distantPast
    private var runStartDate = Date.distantPast
    private var currentLog = ""
    private var currentPrompt = ""
    private var isViewingHistory = false
    private var previewItem: URL?

    private let toolButton = UIButton(type: .system)
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let contextStack = UIStackView()
    private let terminal = TerminalOutputView()
    private let promptField = UITextField()
    private let runButton = UIButton(type: .system)
    private let texRow = ArtifactRow()
    private let pdfRow = ArtifactRow()
    private let artifactsStack = UIStackView()
    private let historyStack = UIStackView()
    private let viewHandoutButton = UIButton(type: .system)

    private var courseDir: URL { LibraryStore.shared.courseDirectory(course) }
    private var pdfURL: URL { LibraryStore.shared.productURL(lecture, in: course, ext: "handout.pdf") }
    private var texURL: URL { LibraryStore.shared.productURL(lecture, in: course, ext: "handout.tex") }
    private var analysisURL: URL { LibraryStore.shared.productURL(lecture, in: course, ext: "analysis.json") }

    init(lecture: Lecture, course: Course, initialPrompt: String? = nil,
         onShowHandout: @escaping () -> Void, onArtifactsChanged: (() -> Void)? = nil) {
        self.lecture = lecture
        self.course = course
        self.initialPrompt = initialPrompt
        self.onShowHandout = onShowHandout
        self.onArtifactsChanged = onArtifactsChanged
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        preferredContentSize = CGSize(width: 1080, height: 680)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "Terminal Studio")
        titleLabel.font = RecapTheme.body(14, weight: .semibold)
        titleLabel.textColor = RecapTheme.ink
        let subtitleLabel = UILabel()
        subtitleLabel.text = "\(lecture.name) · \(course.name)"
        subtitleLabel.font = RecapTheme.body(11)
        subtitleLabel.textColor = RecapTheme.quiet
        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 1
        titles.alignment = .leading

        toolButton.preferredBehavioralStyle = .pad
        var toolConfig = UIButton.Configuration.plain()
        toolConfig.attributedTitle = AttributedString(String(localized: "检测中…"), attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        toolConfig.image = UIImage(systemName: "chevron.up.chevron.down",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        toolConfig.imagePlacement = .trailing
        toolConfig.imagePadding = 5
        toolConfig.background.strokeColor = RecapTheme.line
        toolConfig.background.strokeWidth = 1
        toolConfig.background.cornerRadius = RecapTheme.radiusSM
        toolConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
        toolButton.configuration = toolConfig
        toolButton.tintColor = RecapTheme.muted
        toolButton.showsMenuAsPrimaryAction = true

        statusDot.backgroundColor = RecapTheme.quiet
        statusDot.layer.cornerRadius = 3.5
        statusLabel.font = RecapTheme.body(11)
        statusLabel.textColor = RecapTheme.quiet
        statusLabel.text = String(localized: "检测已安装的 CLI…")

        let newSessionButton = UIButton(type: .system)
        newSessionButton.preferredBehavioralStyle = .pad
        var newSessionConfig = UIButton.Configuration.plain()
        newSessionConfig.attributedTitle = AttributedString(String(localized: "新会话"), attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        newSessionConfig.background.strokeColor = RecapTheme.line
        newSessionConfig.background.strokeWidth = 1
        newSessionConfig.background.cornerRadius = RecapTheme.radiusSM
        newSessionConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
        newSessionButton.configuration = newSessionConfig
        newSessionButton.addAction(UIAction { [weak self] _ in self?.startNewSession() }, for: .touchUpInside)

        let doneButton = UIButton(type: .system)
        doneButton.preferredBehavioralStyle = .pad
        var doneConfig = UIButton.Configuration.plain()
        doneConfig.attributedTitle = AttributedString(String(localized: "完成"), attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.ink,
        ]))
        doneButton.configuration = doneConfig
        doneButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titles, UIView(), statusDot, statusLabel, toolButton, newSessionButton, doneButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10
        statusDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 7).isActive = true

        // Left: the context this session carries
        contextStack.axis = .vertical
        contextStack.spacing = 8
        let contextTitle = sectionLabel(String(localized: "本次会话上下文"))
        let readOnlyNote = UILabel()
        readOnlyNote.text = String(localized: "只读上下文 · 产物写入课程目录")
        readOnlyNote.font = RecapTheme.body(10.5)
        readOnlyNote.textColor = RecapTheme.quiet
        readOnlyNote.numberOfLines = 2
        historyStack.axis = .vertical
        historyStack.spacing = 5
        let leftColumn = UIStackView(arrangedSubviews: [contextTitle, contextStack, historyStack, UIView(), readOnlyNote])
        leftColumn.axis = .vertical
        leftColumn.spacing = 10
        leftColumn.widthAnchor.constraint(equalToConstant: 232).isActive = true

        // Center: terminal and prompt
        promptField.font = RecapTheme.mono(12, weight: .regular)
        promptField.textColor = RecapTheme.ink
        promptField.backgroundColor = RecapTheme.surface.withAlphaComponent(0.6)
        promptField.layer.cornerRadius = RecapTheme.radiusSM
        promptField.layer.cornerCurve = .continuous
        promptField.setLeftPadding(10)
        promptField.text = initialPrompt ?? String(localized: "为「\(lecture.name)」生成讲义")
        promptField.autocorrectionType = .no

        runButton.preferredBehavioralStyle = .pad
        var runConfig = UIButton.Configuration.filled()
        runConfig.baseBackgroundColor = RecapTheme.ink
        runConfig.baseForegroundColor = RecapTheme.paper
        runConfig.background.cornerRadius = RecapTheme.radiusSM
        runConfig.attributedTitle = AttributedString(String(localized: "运行"), attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        runConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        runButton.configuration = runConfig
        runButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.isRunning ? self.stop() : self.run()
        }, for: .touchUpInside)
        runButton.isEnabled = false

        let promptRow = UIStackView(arrangedSubviews: [promptField, runButton])
        promptRow.axis = .horizontal
        promptRow.spacing = 8
        promptField.heightAnchor.constraint(equalToConstant: 34).isActive = true

        // Quick tasks fill the prompt; the CLI improvises within the bundled skill
        let chips: [(title: String, prompt: String)] = [
            (String(localized: "生成讲义"), String(localized: "为「\(lecture.name)」生成讲义")),
            (String(localized: "提取重点"), String(localized: "提取「\(lecture.name)」的考试重点")),
            (String(localized: "检查术语"), String(localized: "检查「\(lecture.name)」转写稿中术语的识别错误，输出勘误清单")),
            (String(localized: "补示意图"), String(localized: "为「\(lecture.name)」的讲义补充更多 TikZ 示意图并重新编译 PDF")),
        ]
        let chipsRow = UIStackView(arrangedSubviews: chips.map { chip in
            let button = UIButton(type: .system)
            button.preferredBehavioralStyle = .pad
            var config = UIButton.Configuration.plain()
            config.attributedTitle = AttributedString(chip.title, attributes: AttributeContainer([
                .font: RecapTheme.body(11), .foregroundColor: RecapTheme.muted,
            ]))
            config.background.strokeColor = RecapTheme.line
            config.background.strokeWidth = 1
            config.background.cornerRadius = RecapTheme.radiusSM
            config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
            button.configuration = config
            button.addAction(UIAction { [weak self] _ in self?.promptField.text = chip.prompt }, for: .touchUpInside)
            return button
        } + [UIView()])
        chipsRow.axis = .horizontal
        chipsRow.spacing = 6

        let centerColumn = UIStackView(arrangedSubviews: [terminal, chipsRow, promptRow])
        centerColumn.axis = .vertical
        centerColumn.spacing = 10
        centerColumn.setCustomSpacing(8, after: chipsRow)

        // Right: generated artifact
        texRow.configure(name: "handout.tex")
        pdfRow.configure(name: "handout.pdf")
        viewHandoutButton.preferredBehavioralStyle = .pad
        var viewConfig = UIButton.Configuration.filled()
        viewConfig.baseBackgroundColor = RecapTheme.ink
        viewConfig.baseForegroundColor = RecapTheme.paper
        viewConfig.background.cornerRadius = RecapTheme.radiusSM
        viewConfig.attributedTitle = AttributedString(String(localized: "查看讲义"), attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        viewConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14)
        viewHandoutButton.configuration = viewConfig
        viewHandoutButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true) { self.onShowHandout() }
        }, for: .touchUpInside)

        artifactsStack.axis = .vertical
        artifactsStack.spacing = 5
        let rightColumn = UIStackView(arrangedSubviews: [
            sectionLabel(String(localized: "生成产物")), texRow, pdfRow, artifactsStack, UIView(), viewHandoutButton,
        ])
        rightColumn.axis = .vertical
        rightColumn.spacing = 10
        rightColumn.widthAnchor.constraint(equalToConstant: 224).isActive = true

        let columns = UIStackView(arrangedSubviews: [leftColumn, centerColumn, rightColumn])
        columns.axis = .horizontal
        columns.spacing = 16
        columns.alignment = .fill

        let root = UIStackView(arrangedSubviews: [header, columns])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        buildContextCards()
        refreshArtifacts()
        rebuildHistory()
        detectTools()
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = RecapTheme.body(12, weight: .semibold)
        label.textColor = RecapTheme.ink
        return label
    }

    // MARK: - Context cards

    private func buildContextCards() {
        let store = LibraryStore.shared
        contextStack.addArrangedSubview(ContextCard(
            title: course.name,
            detail: String(localized: "课程文件夹 · …/\(courseDir.lastPathComponent.prefix(8))…")))
        contextStack.addArrangedSubview(ContextCard(
            title: "Recap Review Skill",
            detail: String(localized: "已内置 · claude / codex / gemini 等通用")))
        let txtURL = store.productURL(lecture, in: course, ext: "txt")
        let analysisURL = store.productURL(lecture, in: course, ext: "analysis.json")
        let transcriptCard = ContextCard(title: String(localized: "完整文稿"), detail: String(localized: "读取中…"))
        contextStack.addArrangedSubview(transcriptCard)
        let signalsCard = ContextCard(title: String(localized: "考试重点"), detail: String(localized: "读取中…"))
        contextStack.addArrangedSubview(signalsCard)

        Task.detached {
            let characterCount = (try? String(contentsOf: txtURL, encoding: .utf8))?.count ?? 0
            var signalCount = 0
            if let data = try? Data(contentsOf: analysisURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                signalCount = (json["exam_signals"] as? [Any])?.count ?? 0
            }
            await MainActor.run {
                transcriptCard.update(detail: characterCount > 0
                    ? String(localized: "\(characterCount) 字 · 已转写")
                    : String(localized: "尚未转写"))
                signalsCard.update(detail: signalCount > 0
                    ? String(localized: "\(signalCount) 条 · 已提取")
                    : String(localized: "尚未提取"))
            }
        }
    }

    // MARK: - CLI detection

    private func detectTools() {
        guard ShellBridge.isAvailable else {
            setStatus(String(localized: "内置终端不可用"), ready: false)
            terminal.append(String(localized: "内置终端组件加载失败。可在课程目录自行运行 CLI：\n  claude \"为「\(lecture.name)」生成讲义\"\n"))
            return
        }
        var found = ""
        ShellBridge.run("for t in claude codex gemini grok kimi; do command -v $t >/dev/null 2>&1 && echo \"$t|$($t --version 2>/dev/null | head -1)\"; done") { output in
            found += output
        } onExit: { [weak self] _ in
            guard let self else { return }
            for line in found.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard let tool = parts.first, !tool.isEmpty else { continue }
                self.detectedTools.append(tool)
                if parts.count > 1 { self.toolVersions[tool] = parts[1].trimmingCharacters(in: .whitespaces) }
            }
            self.applyDetection()
        }
    }

    private func applyDetection() {
        guard !detectedTools.isEmpty else {
            setStatus(String(localized: "未检测到 CLI"), ready: false)
            setToolTitle(String(localized: "未安装"))
            terminal.append(String(localized: "没有找到可用的 CLI（claude / codex / gemini / grok / kimi）。安装并登录任意一个后重新打开。\n"))
            return
        }
        selectedTool = detectedTools.first
        rebuildToolMenu()
        setStatus(String(localized: "已检测 · 就绪"), ready: true)
        runButton.isEnabled = true
        terminal.append(String(localized: "❯ 已附加课程上下文（skill · 文稿 · 重点）。输入任务并运行。\n"))
    }

    private func rebuildToolMenu() {
        setToolTitle(selectedTool ?? "")
        toolButton.menu = UIMenu(children: detectedTools.map { tool in
            UIAction(
                title: tool,
                subtitle: toolVersions[tool],
                state: tool == selectedTool ? .on : .off
            ) { [weak self] _ in
                self?.selectedTool = tool
                self?.rebuildToolMenu()
            }
        })
    }

    private func setToolTitle(_ title: String) {
        toolButton.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.mono(12, weight: .semibold), .foregroundColor: RecapTheme.ink,
        ]))
    }

    private func setStatus(_ text: String, ready: Bool) {
        statusLabel.text = text
        statusDot.backgroundColor = ready ? RecapTheme.complete : RecapTheme.quiet
    }

    // MARK: - Run

    // Non-interactive invocations per tool; unknown tools fall back to a bare prompt argument
    private func command(for tool: String, prompt: String) -> String {
        let escaped = prompt.replacingOccurrences(of: "'", with: "'\\''")
        switch tool {
        case "claude": return "claude -p '\(escaped)' --permission-mode acceptEdits"
        case "codex": return "codex exec '\(escaped)'"
        default: return "\(tool) '\(escaped)'"
        }
    }

    private func run() {
        guard !isRunning, let tool = selectedTool,
              let prompt = promptField.text?.trimmingCharacters(in: .whitespaces), !prompt.isEmpty else { return }
        isRunning = true
        isViewingHistory = false
        setRunButton(running: true)
        promptField.isEnabled = false
        pdfModifiedBeforeRun = modified(pdfURL)
        runStartDate = Date()
        currentLog = ""
        currentPrompt = prompt
        setStatus(String(localized: "运行中…"), ready: true)

        let invocation = command(for: tool, prompt: prompt)
        terminal.append("\n❯ \(invocation)\n")
        runningPID = ShellBridge.run("cd '\(courseDir.path)' && \(invocation)") { [weak self] output in
            self?.terminal.append(output)
            self?.currentLog += output
        } onExit: { [weak self] code in
            self?.finishRun(code: code)
        }
    }

    private func stop() {
        guard isRunning, runningPID > 0 else { return }
        terminal.append(String(localized: "\n⏹ 已请求停止…\n"))
        ShellBridge.terminate(runningPID)
    }

    private func startNewSession() {
        guard !isRunning else { return }
        isViewingHistory = false
        terminal.clear()
        promptField.text = initialPrompt ?? String(localized: "为「\(lecture.name)」生成讲义")
        refreshArtifacts()
        clearRunArtifacts()
        if detectedTools.isEmpty {
            detectTools()
        } else {
            setStatus(String(localized: "已检测 · 就绪"), ready: true)
            terminal.append(String(localized: "❯ 已附加课程上下文（skill · 文稿 · 重点）。输入任务并运行。\n"))
        }
    }

    // MARK: - Session history

    private func rebuildHistory() {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let records = Self.sessionsByLecture[lecture.id] ?? []
        guard !records.isEmpty else { return }
        historyStack.addArrangedSubview(sectionLabel(String(localized: "历史会话")))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        for (index, record) in records.enumerated().reversed().prefix(6) {
            let button = UIButton(type: .system)
            button.preferredBehavioralStyle = .pad
            button.contentHorizontalAlignment = .leading
            var config = UIButton.Configuration.plain()
            let mark = record.exitCode == 0 ? "✓" : "✕"
            config.attributedTitle = AttributedString(
                "\(mark) \(formatter.string(from: record.date)) \(record.tool) · \(String(record.prompt.prefix(14)))",
                attributes: AttributeContainer([
                    .font: RecapTheme.mono(10.5, weight: .regular), .foregroundColor: RecapTheme.muted,
                ]))
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
            button.configuration = config
            button.addAction(UIAction { [weak self] _ in self?.showHistory(at: index) }, for: .touchUpInside)
            historyStack.addArrangedSubview(button)
        }
    }

    private func showHistory(at index: Int) {
        guard !isRunning, let record = Self.sessionsByLecture[lecture.id]?[safe: index] else { return }
        isViewingHistory = true
        terminal.clear()
        terminal.append(String(localized: "❯ 历史会话（只读） · \(record.tool)\n\n"))
        terminal.append(record.log)
        setStatus(record.exitCode == 0 ? String(localized: "历史会话 · 成功") : String(localized: "历史会话 · 失败"), ready: record.exitCode == 0)
    }

    // MARK: - Run artifacts

    private func clearRunArtifacts() {
        artifactsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    // Everything the run touched in the course folder, handed back as openable rows
    private func scanRunArtifacts() {
        clearRunArtifacts()
        let fm = FileManager.default
        var found: [URL] = []
        let dirs = [courseDir, courseDir.appendingPathComponent("教材分章", isDirectory: true)]
        for dir in dirs {
            let items = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for url in items {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                guard values?.isDirectory != true,
                      (values?.contentModificationDate ?? .distantPast) > runStartDate else { continue }
                found.append(url)
            }
        }
        guard !found.isEmpty else { return }
        artifactsStack.addArrangedSubview(sectionLabel(String(localized: "本次产物")))
        for url in found.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(8) {
            let button = UIButton(type: .system)
            button.preferredBehavioralStyle = .pad
            button.contentHorizontalAlignment = .leading
            var config = UIButton.Configuration.plain()
            config.attributedTitle = AttributedString(url.lastPathComponent, attributes: AttributeContainer([
                .font: RecapTheme.mono(10.5, weight: .regular), .foregroundColor: RecapTheme.ink,
            ]))
            config.image = UIImage(systemName: "doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9))
            config.imagePadding = 5
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
            button.configuration = config
            button.tintColor = RecapTheme.muted
            button.addAction(UIAction { [weak self] _ in self?.preview(url) }, for: .touchUpInside)
            artifactsStack.addArrangedSubview(button)
        }
    }

    private func preview(_ url: URL) {
        previewItem = url
        let preview = QLPreviewController()
        preview.dataSource = self
        present(preview, animated: true)
    }

    private func setRunButton(running: Bool) {
        runButton.configuration?.baseBackgroundColor = running ? RecapTheme.signal : RecapTheme.ink
        runButton.configuration?.attributedTitle = AttributedString(
            running ? String(localized: "停止") : String(localized: "运行"),
            attributes: AttributeContainer([
                .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
            ]))
    }

    private func finishRun(code: Int32) {
        isRunning = false
        runningPID = -1
        setRunButton(running: false)
        runButton.isEnabled = true
        promptField.isEnabled = true
        refreshArtifacts()
        Self.sessionsByLecture[lecture.id, default: []].append(SessionRecord(
            tool: selectedTool ?? "?", prompt: currentPrompt, log: currentLog, exitCode: code, date: Date()))
        rebuildHistory()
        scanRunArtifacts()
        let analysisUpdated = modified(analysisURL) > runStartDate
        if analysisUpdated { onArtifactsChanged?() }
        let pdfUpdated = modified(pdfURL) > pdfModifiedBeforeRun
        if code == 0 && pdfUpdated {
            setStatus(String(localized: "讲义已生成"), ready: true)
            terminal.append(String(localized: "\n✔ 讲义 PDF 已就绪\n"))
        } else if code == 0 && analysisUpdated {
            setStatus(String(localized: "重点已提取"), ready: true)
            terminal.append(String(localized: "\n✔ 考试重点已更新\n"))
        } else if code == 0 {
            setStatus(String(localized: "已完成"), ready: true)
            terminal.append(String(localized: "\n✔ 完成（本次运行没有更新讲义 PDF）\n"))
        } else {
            setStatus(String(localized: "运行失败"), ready: false)
            terminal.append(String(localized: "\n✘ 退出码 \(code)\n"))
        }
    }

    // MARK: - Artifacts

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func refreshArtifacts() {
        let texExists = FileManager.default.fileExists(atPath: texURL.path)
        let pdfExists = FileManager.default.fileExists(atPath: pdfURL.path)
        texRow.update(state: texExists ? String(localized: "已生成") : String(localized: "未生成"), done: texExists)
        pdfRow.update(state: pdfExists ? String(localized: "已生成") : String(localized: "未生成"), done: pdfExists)
        viewHandoutButton.isEnabled = pdfExists
    }
}

// MARK: - Small views

private final class ContextCard: UIView {

    private let detailLabel = UILabel()

    init(title: String, detail: String) {
        super.init(frame: .zero)
        backgroundColor = RecapTheme.surface.withAlphaComponent(0.7)
        layer.cornerRadius = RecapTheme.radiusSM
        layer.cornerCurve = .continuous

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = RecapTheme.body(12, weight: .semibold)
        titleLabel.textColor = RecapTheme.ink
        titleLabel.numberOfLines = 1
        detailLabel.text = detail
        detailLabel.font = RecapTheme.body(10.5)
        detailLabel.textColor = RecapTheme.muted
        detailLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(detail: String) {
        detailLabel.text = detail
    }
}

private final class ArtifactRow: UIView {

    private let nameLabel = UILabel()
    private let stateLabel = UILabel()
    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.surface.withAlphaComponent(0.7)
        layer.cornerRadius = RecapTheme.radiusSM
        layer.cornerCurve = .continuous

        nameLabel.font = RecapTheme.mono(11, weight: .semibold)
        nameLabel.textColor = RecapTheme.ink
        stateLabel.font = RecapTheme.body(10.5)
        stateLabel.textColor = RecapTheme.muted
        dot.layer.cornerRadius = 3

        let stack = UIStackView(arrangedSubviews: [dot, nameLabel, UIView(), stateLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 7
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String) {
        nameLabel.text = name
    }

    func update(state: String, done: Bool) {
        stateLabel.text = state
        dot.backgroundColor = done ? RecapTheme.complete : RecapTheme.quiet.withAlphaComponent(0.4)
    }
}

private extension UITextField {
    func setLeftPadding(_ inset: CGFloat) {
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: inset, height: 1))
        leftViewMode = .always
    }
}

extension TerminalStudioViewController: QLPreviewControllerDataSource {

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewItem == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewItem ?? URL(fileURLWithPath: "/dev/null")) as NSURL
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

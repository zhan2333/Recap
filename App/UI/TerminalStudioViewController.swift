//
//  TerminalStudioViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/25.
//

import UIKit

// Terminal Studio: the user's own CLI runs inside the course context, the artifact lands back in place
final class TerminalStudioViewController: UIViewController {

    private let lecture: Lecture
    private let course: Course
    private let onShowHandout: () -> Void

    private var detectedTools: [String] = []
    private var selectedTool: String?
    private var isRunning = false
    private var pdfModifiedBeforeRun = Date.distantPast

    private let toolButton = UIButton(type: .system)
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let contextStack = UIStackView()
    private let terminal = TerminalOutputView()
    private let promptField = UITextField()
    private let runButton = UIButton(type: .system)
    private let texRow = ArtifactRow()
    private let pdfRow = ArtifactRow()
    private let viewHandoutButton = UIButton(type: .system)

    private var courseDir: URL { LibraryStore.shared.courseDirectory(course) }
    private var pdfURL: URL { LibraryStore.shared.productURL(lecture, in: course, ext: "handout.pdf") }
    private var texURL: URL { LibraryStore.shared.productURL(lecture, in: course, ext: "handout.tex") }

    init(lecture: Lecture, course: Course, onShowHandout: @escaping () -> Void) {
        self.lecture = lecture
        self.course = course
        self.onShowHandout = onShowHandout
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

        let doneButton = UIButton(type: .system)
        doneButton.preferredBehavioralStyle = .pad
        var doneConfig = UIButton.Configuration.plain()
        doneConfig.attributedTitle = AttributedString(String(localized: "完成"), attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.ink,
        ]))
        doneButton.configuration = doneConfig
        doneButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titles, UIView(), statusDot, statusLabel, toolButton, doneButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10
        statusDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 7).isActive = true

        // Left: the context this session carries
        contextStack.axis = .vertical
        contextStack.spacing = 8
        let contextTitle = sectionLabel(String(localized: "本次会话上下文"))
        let leftColumn = UIStackView(arrangedSubviews: [contextTitle, contextStack, UIView()])
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
        promptField.text = "为「\(lecture.name)」生成讲义"
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
        runButton.addAction(UIAction { [weak self] _ in self?.run() }, for: .touchUpInside)
        runButton.isEnabled = false

        let promptRow = UIStackView(arrangedSubviews: [promptField, runButton])
        promptRow.axis = .horizontal
        promptRow.spacing = 8
        promptField.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let centerColumn = UIStackView(arrangedSubviews: [terminal, promptRow])
        centerColumn.axis = .vertical
        centerColumn.spacing = 10

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

        let rightColumn = UIStackView(arrangedSubviews: [
            sectionLabel(String(localized: "生成产物")), texRow, pdfRow, UIView(), viewHandoutButton,
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
        ShellBridge.run("for t in claude codex gemini grok kimi; do command -v $t >/dev/null 2>&1 && echo $t; done") { output in
            found += output
        } onExit: { [weak self] _ in
            guard let self else { return }
            self.detectedTools = found.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
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
            UIAction(title: tool, state: tool == selectedTool ? .on : .off) { [weak self] _ in
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
        runButton.isEnabled = false
        promptField.isEnabled = false
        pdfModifiedBeforeRun = modified(pdfURL)
        setStatus(String(localized: "运行中…"), ready: true)

        let invocation = command(for: tool, prompt: prompt)
        terminal.append("\n❯ \(invocation)\n")
        ShellBridge.run("cd '\(courseDir.path)' && \(invocation)") { [weak self] output in
            self?.terminal.append(output)
        } onExit: { [weak self] code in
            self?.finishRun(code: code)
        }
    }

    private func finishRun(code: Int32) {
        isRunning = false
        runButton.isEnabled = true
        promptField.isEnabled = true
        refreshArtifacts()
        let pdfUpdated = modified(pdfURL) > pdfModifiedBeforeRun
        if code == 0 && pdfUpdated {
            setStatus(String(localized: "讲义已生成"), ready: true)
            terminal.append(String(localized: "\n✔ 讲义 PDF 已就绪\n"))
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

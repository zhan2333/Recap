//
//  OnboardingViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit
import UniformTypeIdentifiers

/// First-run setup: make sure a whisper model is in place. Two paths —
/// point at an existing ggml file, or copy a curl command to download one.
final class OnboardingViewController: UIViewController {

    var onReady: (() -> Void)?

    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let pathLabel = UILabel()
    private let commandView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let terminal = TerminalOutputView()
    private var autoDownloadButton: UIButton?
    private var isDownloading = false

    private static let downloadCommand = """
    mkdir -p ~/whisper-models && curl -L -o ~/whisper-models/ggml-large-v3-turbo.bin \\
      https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper

        // Brand header
        let mark = UIImageView(image: UIImage(named: "recap-r-mark")?.withRenderingMode(.alwaysTemplate))
        mark.tintColor = RecapTheme.ink
        mark.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = "Recap"
        titleLabel.font = RecapTheme.display(34, weight: .semibold)
        titleLabel.textColor = RecapTheme.ink

        let subtitle = UILabel()
        subtitle.text = "课程回放在本机转写成文稿，重点和讲义都从老师原话出发。转写用 whisper 模型，全程离线。"
        subtitle.font = RecapTheme.body(13)
        subtitle.textColor = RecapTheme.muted
        subtitle.numberOfLines = 0

        // Model status
        statusDot.layer.cornerRadius = 4
        statusLabel.font = RecapTheme.body(13, weight: .semibold)
        pathLabel.font = RecapTheme.mono(11, weight: .regular)
        pathLabel.textColor = RecapTheme.quiet
        pathLabel.numberOfLines = 2
        let statusRow = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 8
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        // Option 1: pick an existing model
        let pickButton = optionButton(
            title: "我已有模型文件…",
            detail: "选择 ggml 格式的 .bin（如 ggml-large-v3-turbo.bin）"
        ) { [weak self] in self?.pickModel() }

        // Option 2: download inside the app (glue-bundle terminal)
        let autoButton = optionButton(
            title: "在 app 内下载（约 1.5GB）",
            detail: "内置终端执行下载，实时显示进度，走 HF 镜像"
        ) { [weak self] in self?.startDownload() }
        autoButton.isHidden = !ShellBridge.isAvailable
        self.autoDownloadButton = autoButton

        terminal.isHidden = true

        // Option 3: copy the command and run it yourself
        let downloadTitle = UILabel()
        downloadTitle.text = ShellBridge.isAvailable ? "或者复制命令自己在终端跑：" : "用命令行下载（约 1.5GB，走 HF 镜像）："
        downloadTitle.font = RecapTheme.body(12)
        downloadTitle.textColor = RecapTheme.muted

        commandView.text = Self.downloadCommand
        commandView.font = RecapTheme.mono(11, weight: .regular)
        commandView.textColor = RecapTheme.ink
        commandView.backgroundColor = RecapTheme.surface.withAlphaComponent(0.6)
        commandView.layer.cornerRadius = RecapTheme.radiusMD
        commandView.isEditable = false
        commandView.isScrollEnabled = false
        commandView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        var copyConfig = UIButton.Configuration.plain()
        copyConfig.attributedTitle = AttributedString("复制命令", attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        copyConfig.image = UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        copyConfig.imagePadding = 5
        copyConfig.baseForegroundColor = RecapTheme.muted
        copyButton.configuration = copyConfig
        copyButton.tintColor = RecapTheme.muted
        copyButton.addAction(UIAction { [weak self] _ in
            UIPasteboard.general.string = Self.downloadCommand.replacingOccurrences(of: " \\\n  ", with: " ")
            self?.copyButton.configuration?.attributedTitle = AttributedString("已复制，下载完成后回到这里", attributes: AttributeContainer([
                .font: RecapTheme.body(12), .foregroundColor: RecapTheme.complete,
            ]))
        }, for: .touchUpInside)

        var startConfig = UIButton.Configuration.filled()
        startConfig.baseBackgroundColor = RecapTheme.ink
        startConfig.baseForegroundColor = RecapTheme.paper
        startConfig.background.cornerRadius = RecapTheme.radiusSM
        startConfig.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 24, bottom: 10, trailing: 24)
        startButton.configuration = startConfig
        startButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { self?.onReady?() }
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            mark, titleLabel, subtitle, statusRow, pathLabel, pickButton,
            autoButton, terminal, downloadTitle, commandView, copyButton, startButton,
        ])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(6, after: mark)
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(4, after: statusRow)
        stack.setCustomSpacing(20, after: pathLabel)
        stack.setCustomSpacing(24, after: pickButton)
        stack.setCustomSpacing(8, after: downloadTitle)
        stack.setCustomSpacing(4, after: commandView)
        stack.setCustomSpacing(28, after: copyButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 40),
            mark.heightAnchor.constraint(equalToConstant: 40),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            commandView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            terminal.widthAnchor.constraint(equalTo: stack.widthAnchor),
            terminal.heightAnchor.constraint(equalToConstant: 170),
            startButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatus),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        refreshStatus()
    }

    private func optionButton(title: String, detail: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        let text = NSMutableAttributedString(
            string: title + "\n",
            attributes: [.font: RecapTheme.body(14, weight: .semibold), .foregroundColor: RecapTheme.ink])
        text.append(NSAttributedString(
            string: detail,
            attributes: [.font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted]))
        config.attributedTitle = AttributedString(text)
        config.background.backgroundColor = RecapTheme.surface.withAlphaComponent(0.6)
        config.background.strokeColor = RecapTheme.line
        config.background.strokeWidth = 1
        config.background.cornerRadius = RecapTheme.radiusMD
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    @objc private func refreshStatus() {
        let exists = Settings.modelExists
        statusDot.backgroundColor = exists ? RecapTheme.complete : RecapTheme.error
        statusLabel.text = exists ? "模型已就绪" : "还没有找到 whisper 模型"
        statusLabel.textColor = exists ? RecapTheme.complete : RecapTheme.error
        pathLabel.text = Settings.modelPath.path
        startButton.isEnabled = exists
        startButton.configuration?.attributedTitle = AttributedString(
            exists ? "开始使用" : "等待模型就绪…",
            attributes: AttributeContainer([
                .font: RecapTheme.body(13, weight: .semibold), .foregroundColor: RecapTheme.paper,
            ]))
    }

    private func pickModel() {
        let types = [UTType(filenameExtension: "bin") ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func startDownload() {
        guard !isDownloading else { return }
        isDownloading = true
        terminal.isHidden = false
        terminal.clear()
        autoDownloadButton?.isEnabled = false
        let command = Self.downloadCommand.replacingOccurrences(of: " \\\n  ", with: " ")
        ShellBridge.run(command) { [weak self] chunk in
            self?.terminal.append(chunk)
        } onExit: { [weak self] code in
            guard let self else { return }
            self.isDownloading = false
            self.autoDownloadButton?.isEnabled = true
            self.terminal.append(code == 0 ? "\n✔ 下载完成\n" : "\n✘ 退出码 \(code)——可复制下方命令自己在终端重试\n")
            self.refreshStatus()
        }
    }
}

/// Minimal read-only terminal: monospaced, dark ground, handles \r rewrites
/// (curl progress) and strips ANSI escapes.
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

extension OnboardingViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Settings.modelPath = url
        refreshStatus()
    }
}

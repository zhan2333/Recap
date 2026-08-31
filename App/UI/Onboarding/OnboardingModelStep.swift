//
//  OnboardingModelStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit
import UniformTypeIdentifiers

// The download keeps its terminal; a quiet progress line carries the same state
final class OnboardingModelStep: OnboardingStepView, UIDocumentPickerDelegate {

    private static let downloadCommand = """
    mkdir -p ~/whisper-models && curl -L -C - --progress-bar -o ~/whisper-models/ggml-large-v3-turbo.bin \
    https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
    """

    private let card = UIView()
    private let cardTitle = UILabel()
    private let cardDetail = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let terminal = TerminalOutputView()
    private let terminalToggle = UIButton(type: .system)
    private var progressWidth: NSLayoutConstraint?
    private var isDownloading = false
    private var pickButton: UIButton?

    override var primaryTitle: String {
        Settings.modelExists ? String(localized: "继续") : String(localized: "下载转写文件")
    }

    override var isPrimaryEnabled: Bool { !isDownloading }

    override func build() {
        card.backgroundColor = RecapTheme.surface.withAlphaComponent(0.55)
        card.layer.cornerRadius = RecapTheme.radiusMD
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = RecapTheme.line.cgColor

        cardTitle.font = RecapTheme.body(12.5, weight: .semibold)
        cardTitle.textColor = RecapTheme.ink
        cardDetail.font = RecapTheme.body(11)
        cardDetail.textColor = RecapTheme.muted
        cardDetail.numberOfLines = 0

        progressTrack.backgroundColor = RecapTheme.line
        progressTrack.layer.cornerRadius = 2
        progressTrack.clipsToBounds = true
        progressTrack.isHidden = true
        progressFill.backgroundColor = RecapTheme.signal
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        let width = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressWidth = width
        NSLayoutConstraint.activate([
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            width,
        ])

        let cardStack = UIStackView(arrangedSubviews: [cardTitle, cardDetail, progressTrack])
        cardStack.axis = .vertical
        cardStack.spacing = 7
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])

        let pick = textAction(String(localized: "选择已有文件…")) { [weak self] in self?.pickModel() }
        pickButton = pick

        terminal.isHidden = true
        terminal.heightAnchor.constraint(equalToConstant: 132).isActive = true
        terminalToggle.preferredBehavioralStyle = .pad
        terminalToggle.contentHorizontalAlignment = .leading
        terminalToggle.isHidden = true
        var toggleConfig = UIButton.Configuration.plain()
        toggleConfig.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
        terminalToggle.configuration = toggleConfig
        terminalToggle.addAction(UIAction { [weak self] _ in self?.toggleTerminal() }, for: .touchUpInside)
        setToggleTitle()

        let advanced = note(String(localized: "默认位置：~/whisper-models/ggml-large-v3-turbo.bin。只有手动管理模型时才需要查看这个路径。"))

        fill(with: stack([card, pick, terminalToggle, terminal, advanced], spacing: 10))
        refresh()
    }

    private func refresh() {
        if Settings.modelExists {
            cardTitle.text = String(localized: "离线转写已准备好")
            cardDetail.text = String(localized: "推荐文件已放在这台 Mac 上，可以继续。")
            pickButton?.isHidden = true
        } else {
            cardTitle.text = String(localized: "高质量离线转写文件")
            cardDetail.text = isDownloading
                ? String(localized: "正在下载 · 中断后可以从断点继续")
                : String(localized: "约 1.5 GB · 中文与英文课程 · 只下载一次")
            pickButton?.isHidden = isDownloading
        }
        onStateChange?()
    }

    private func setToggleTitle() {
        let title = terminal.isHidden ? String(localized: "显示下载日志") : String(localized: "隐藏下载日志")
        terminalToggle.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(11), .foregroundColor: RecapTheme.quiet,
        ]))
    }

    private func toggleTerminal() {
        terminal.isHidden.toggle()
        setToggleTitle()
    }

    override func performPrimary(_ completion: @escaping (PrimaryResult) -> Void) {
        if Settings.modelExists {
            completion(.next)
            return
        }
        startDownload(completion)
    }

    private func startDownload(_ completion: @escaping (PrimaryResult) -> Void) {
        guard !isDownloading, ShellBridge.isAvailable else {
            completion(.stay)
            return
        }
        isDownloading = true
        terminal.clear()
        terminalToggle.isHidden = false
        progressTrack.isHidden = false
        setProgress(0)
        refresh()

        ShellBridge.run(Self.downloadCommand) { [weak self] chunk in
            self?.terminal.append(chunk)
            self?.consumeProgress(chunk)
        } onExit: { [weak self] code in
            guard let self else { return }
            self.isDownloading = false
            if code == 0 && Settings.modelExists {
                self.setProgress(1)
                self.refresh()
                completion(.next)
            } else {
                self.cardTitle.text = String(localized: "下载中断")
                self.cardDetail.text = String(localized: "请检查网络。已经下载的部分会保留，可以重新下载。")
                self.terminal.isHidden = false
                self.setToggleTitle()
                self.onStateChange?()
                completion(.stay)
            }
        }
    }

    // curl's --progress-bar writes a percentage on a carriage-returned line
    private func consumeProgress(_ chunk: String) {
        guard let match = chunk.range(of: "[0-9]+[.,]?[0-9]*%", options: .regularExpression) else { return }
        let text = chunk[match].dropLast().replacingOccurrences(of: ",", with: ".")
        guard let percent = Double(text) else { return }
        setProgress(percent / 100)
    }

    private func setProgress(_ fraction: Double) {
        layoutIfNeeded()
        progressWidth?.constant = progressTrack.bounds.width * min(max(fraction, 0), 1)
        UIView.animate(withDuration: 0.2) { self.layoutIfNeeded() }
    }

    private func pickModel() {
        let types = [UTType(filenameExtension: "bin") ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        host?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Settings.modelPath = url
        refresh()
    }
}

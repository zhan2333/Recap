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
    private let cardSymbol = UILabel()
    private let cardMark = UILabel()
    private let advancedToggle = UIButton(type: .system)
    private let advancedBody = UILabel()
    private let optionMeta = UILabel()

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

        cardSymbol.font = RecapTheme.mono(12, weight: .semibold)
        cardSymbol.textColor = RecapTheme.muted
        cardSymbol.textAlignment = .center
        cardSymbol.widthAnchor.constraint(equalToConstant: 22).isActive = true
        cardMark.font = RecapTheme.body(12, weight: .semibold)
        cardMark.textColor = RecapTheme.complete

        let textStack = UIStackView(arrangedSubviews: [cardTitle, cardDetail, progressTrack])
        textStack.axis = .vertical
        textStack.spacing = 7
        let cardStack = UIStackView(arrangedSubviews: [cardSymbol, textStack, UIView(), cardMark])
        cardStack.axis = .horizontal
        cardStack.alignment = .center
        cardStack.spacing = 11
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

        advancedBody.text = String(localized: "默认位置：~/whisper-models/ggml-large-v3-turbo.bin。只有手动管理模型时才需要查看这个路径。")
        advancedBody.font = RecapTheme.body(10.5)
        advancedBody.textColor = RecapTheme.quiet
        advancedBody.numberOfLines = 0
        advancedBody.isHidden = true
        advancedToggle.preferredBehavioralStyle = .pad
        advancedToggle.contentHorizontalAlignment = .leading
        var advancedConfig = UIButton.Configuration.plain()
        advancedConfig.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
        advancedToggle.configuration = advancedConfig
        advancedToggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.advancedBody.isHidden.toggle()
            self.setAdvancedTitle()
        }, for: .touchUpInside)
        setAdvancedTitle()

        let scene = OnboardingScene(pieces: [
            OnboardingFileCard(glyph: "Aa", size: "1.5 GB"),
            OnboardingThread(distance: 70),
            OnboardingMacFrame(badge: String(localized: "✓ 本机完成")),
        ])
        fill(with: stack([scene, card, pick, terminalToggle, terminal, advancedToggle, advancedBody], spacing: 10))
        refresh()
    }

    private func refresh() {
        if Settings.modelExists {
            cardSymbol.text = "Aa"
            cardTitle.text = String(localized: "离线转写已准备好")
            cardDetail.text = String(localized: "推荐文件已放在这台 Mac 上，可以继续。")
            cardMark.text = "✓"
            card.layer.borderColor = RecapTheme.complete.withAlphaComponent(0.4).cgColor
            pickButton?.isHidden = true
        } else {
            cardSymbol.text = isDownloading ? "↓" : "✓"
            cardSymbol.textColor = isDownloading ? RecapTheme.signalText : RecapTheme.ink
            cardTitle.text = String(localized: "高质量离线转写文件")
            cardDetail.text = isDownloading
                ? String(localized: "正在下载 · 中断后可以从断点继续")
                : String(localized: "约 1.5 GB · 中文与英文课程")
            cardMark.text = isDownloading ? "" : String(localized: "只下载一次")
            cardMark.textColor = RecapTheme.quiet
            card.layer.borderColor = RecapTheme.ink.withAlphaComponent(0.35).cgColor
            card.backgroundColor = RecapTheme.selection
            pickButton?.isHidden = isDownloading
        }
        onStateChange?()
    }

    private func setAdvancedTitle() {
        let marker = advancedBody.isHidden ? "▸" : "▾"
        advancedToggle.configuration?.attributedTitle = AttributedString(
            "\(marker)  " + String(localized: "高级选项"),
            attributes: AttributeContainer([
                .font: RecapTheme.body(11, weight: .semibold), .foregroundColor: RecapTheme.muted,
            ]))
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

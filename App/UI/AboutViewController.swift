//
//  AboutViewController.swift
//  Recap
//
//  Created by Rio on 9/21/26.
//

import UIKit

final class AboutViewController: UIViewController {

    private let version: String
    private let checkForUpdates: @MainActor () async throws -> String?
    private let installUpdate: @MainActor () -> Void
    private var checkTask: Task<Void, Never>?

    private let statusLabel = UILabel()
    private let progressIndicator = UIActivityIndicatorView(style: .medium)
    private let checkButton = UIButton(type: .system)
    private let installButton = UIButton(type: .system)

    init(
        version: String,
        checkForUpdates: @escaping @MainActor () async throws -> String?,
        installUpdate: @escaping @MainActor () -> Void
    ) {
        self.version = version
        self.checkForUpdates = checkForUpdates
        self.installUpdate = installUpdate
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "关于 Recap")
        modalPresentationStyle = .formSheet
        preferredContentSize = CGSize(width: 460, height: 470)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        view.tintColor = RecapTheme.signalText
        buildContent()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        checkTask?.cancel()
        checkTask = nil
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close))]
    }

    // MARK: - Content

    private func buildContent() {
        let closeButton = UIButton(type: .close)
        closeButton.accessibilityLabel = String(localized: "关闭")
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        let mark = UIImageView(image: UIImage(named: "recap-r-mark")?.withRenderingMode(.alwaysTemplate))
        mark.tintColor = RecapTheme.ink
        mark.contentMode = .scaleAspectFit
        mark.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 54),
            mark.heightAnchor.constraint(equalToConstant: 58),
        ])

        let name = label("Recap", font: RecapTheme.display(34), color: RecapTheme.ink)
        name.accessibilityTraits.insert(.header)
        let versionLabel = label(String(localized: "版本 \(version)"), font: RecapTheme.body(13), color: RecapTheme.quiet)
        let identity = UIStackView(arrangedSubviews: [mark, name, versionLabel])
        identity.axis = .vertical
        identity.alignment = .center
        identity.spacing = 6
        identity.setCustomSpacing(16, after: mark)

        let description = label(
            String(localized: "把课堂记录，整理成自己的复习讲义。"),
            font: RecapTheme.body(15),
            color: RecapTheme.muted
        )
        description.textAlignment = .center

        statusLabel.text = String(localized: "随时检查，获取 Recap 的最新版本。")
        statusLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: RecapTheme.body(13))
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = RecapTheme.quiet
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        progressIndicator.color = RecapTheme.quiet
        progressIndicator.hidesWhenStopped = true
        progressIndicator.isHidden = true
        let status = UIStackView(arrangedSubviews: [progressIndicator, statusLabel])
        status.axis = .vertical
        status.alignment = .center
        status.spacing = 8
        statusLabel.widthAnchor.constraint(equalTo: status.widthAnchor).isActive = true

        checkButton.configuration = buttonConfiguration(title: String(localized: "检查更新"), prominent: false)
        checkButton.addAction(UIAction { [weak self] _ in self?.check() }, for: .touchUpInside)
        installButton.configuration = buttonConfiguration(title: String(localized: "下载并更新"), prominent: true)
        installButton.isHidden = true
        installButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let installUpdate = self.installUpdate
            self.dismiss(animated: true) { installUpdate() }
        }, for: .touchUpInside)

        let updates = UIStackView(arrangedSubviews: [status, installButton, checkButton])
        updates.axis = .vertical
        updates.spacing = 12
        updates.isLayoutMarginsRelativeArrangement = true
        updates.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        updates.backgroundColor = RecapTheme.surface
        updates.layer.cornerRadius = 16
        updates.layer.cornerCurve = .continuous

        let content = UIStackView(arrangedSubviews: [identity, description, updates])
        content.axis = .vertical
        content.spacing = 24
        content.setCustomSpacing(18, after: identity)
        content.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),
        ])
    }

    private func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFontMetrics.default.scaledFont(for: font)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func buttonConfiguration(title: String, prominent: Bool) -> UIButton.Configuration {
        var configuration = prominent ? UIButton.Configuration.filled() : .plain()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = RecapTheme.signalText
        configuration.baseForegroundColor = prominent ? RecapTheme.paper : RecapTheme.signalText
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        return configuration
    }

    // MARK: - Updates

    private func check() {
        guard checkTask == nil else { return }
        installButton.isHidden = true
        checkButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimating()
        statusLabel.textColor = RecapTheme.quiet
        statusLabel.text = String(localized: "正在检查更新…")

        let checkForUpdates = self.checkForUpdates
        checkTask = Task { [weak self] in
            do {
                let availableVersion = try await checkForUpdates()
                guard !Task.isCancelled, let self, self.viewIfLoaded?.window != nil else { return }
                self.finishChecking()
                if let availableVersion {
                    self.statusLabel.text = String(localized: "新版本 \(availableVersion) 已可用。")
                    self.statusLabel.textColor = RecapTheme.signalText
                    self.installButton.isHidden = false
                    self.checkButton.configuration?.title = String(localized: "重新检查")
                } else {
                    self.statusLabel.text = String(localized: "Recap 已是最新版本。")
                    self.statusLabel.textColor = RecapTheme.complete
                    self.checkButton.configuration?.title = String(localized: "检查更新")
                }
                UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
            } catch {
                guard !Task.isCancelled, let self, self.viewIfLoaded?.window != nil else { return }
                self.finishChecking()
                self.statusLabel.text = String(localized: "暂时无法检查更新，请稍后重试。")
                self.statusLabel.textColor = RecapTheme.error
                self.checkButton.configuration?.title = String(localized: "重试")
                UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
            }
        }
    }

    private func finishChecking() {
        checkTask = nil
        progressIndicator.stopAnimating()
        progressIndicator.isHidden = true
        checkButton.isEnabled = true
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

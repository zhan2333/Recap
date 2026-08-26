//
//  UpdateChecker.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit

// Once-a-day check against the GitHub latest release; a persistent pill installs the update in place
enum UpdateChecker {

    private static let repo = "zhan2333/Recap"
    private static let mountPoint = "/tmp/recap-update-mount"

    static func checkIfDue(presenting window: UIWindow?) {
        showPillFromCache(in: window)

        let lastCheck = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - lastCheck > 86_400 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")

        Task {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String
            else { return }

            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmgURL = assets
                .compactMap { $0["browser_download_url"] as? String }
                .first { $0.hasSuffix(".dmg") }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            UserDefaults.standard.set(latest, forKey: "latestKnownVersion")
            UserDefaults.standard.set(htmlURL, forKey: "latestKnownURL")
            UserDefaults.standard.set(dmgURL, forKey: "latestKnownDMG")
            await MainActor.run { showPillFromCache(in: window) }
        }
    }

    // The pill persists every launch until the user updates — no dismiss, no skip
    private static func showPillFromCache(in window: UIWindow?) {
        guard let window,
              let latest = UserDefaults.standard.string(forKey: "latestKnownVersion"),
              let urlString = UserDefaults.standard.string(forKey: "latestKnownURL"),
              let pageURL = URL(string: urlString) else { return }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard latest.compare(current, options: .numeric) == .orderedDescending else {
            window.viewWithTag(UpdatePillView.viewTag)?.removeFromSuperview()
            return
        }
        guard window.viewWithTag(UpdatePillView.viewTag) == nil else { return }

        let dmgURL = UserDefaults.standard.string(forKey: "latestKnownDMG").flatMap(URL.init(string:))
        let pill = UpdatePillView()
        pill.onTap = { [weak pill] in
            guard let pill else { return }
            switch pill.phase {
            case .idle where dmgURL != nil:
                performUpdate(dmgURL: dmgURL!, pageURL: pageURL, pill: pill)
            case .idle, .failed:
                UIApplication.shared.open(pageURL)
            case .downloading, .installing:
                break
            }
        }
        window.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -18),
        ])
        pill.animateIn()
    }

    // MARK: - In-place install

    private static func performUpdate(dmgURL: URL, pageURL: URL, pill: UpdatePillView) {
        pill.phase = .downloading
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: dmgURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1_000_000 else {
                    throw URLError(.badServerResponse)
                }
                let tmpDMG = FileManager.default.temporaryDirectory.appendingPathComponent("Recap-update.dmg")
                try data.write(to: tmpDMG, options: .atomic)
                pill.phase = .installing
                try await install(dmg: tmpDMG)
                relaunch()
            } catch {
                pill.phase = .failed
            }
        }
    }

    private static func install(dmg: URL) async throws {
        guard ShellBridge.isAvailable else { throw URLError(.unknown) }
        let script = """
        hdiutil detach -quiet '\(mountPoint)' >/dev/null 2>&1; hdiutil attach -nobrowse -quiet '\(dmg.path)' -mountpoint '\(mountPoint)' && rm -rf '/Applications/Recap.app' && cp -R '\(mountPoint)/Recap.app' /Applications/ && hdiutil detach -quiet '\(mountPoint)'
        """
        let code = await withCheckedContinuation { continuation in
            ShellBridge.run(script, onOutput: { _ in }, onExit: { continuation.resume(returning: $0) })
        }
        guard code == 0 else { throw URLError(.cannotWriteToFile) }
    }

    // The relauncher must outlive this process: nohup + detach, then hard-exit
    private static func relaunch() {
        ShellBridge.run(
            "nohup zsh -c 'sleep 1; open /Applications/Recap.app' >/dev/null 2>&1 &",
            onOutput: { _ in }, onExit: { _ in }
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
    }
}

// MARK: - Update pill

final class UpdatePillView: UIButton {

    static let viewTag = 0xECAB

    enum Phase {
        case idle, downloading, installing, failed
    }

    var onTap: (() -> Void)?
    var phase: Phase = .idle {
        didSet { applyPhase() }
    }

    init() {
        super.init(frame: .zero)
        tag = Self.viewTag
        translatesAutoresizingMaskIntoConstraints = false
        preferredBehavioralStyle = .pad

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RecapTheme.ink
        config.baseForegroundColor = RecapTheme.paper
        config.imagePadding = 7
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        config.background.cornerRadius = 20
        configuration = config
        tintColor = RecapTheme.paper

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 5)

        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        applyPhase()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyPhase() {
        let title: String
        let symbol: String
        switch phase {
        case .idle:
            title = String(localized: "更新 Recap")
            symbol = "arrow.up.circle.fill"
        case .downloading:
            title = String(localized: "正在下载更新…")
            symbol = "arrow.down.circle"
        case .installing:
            title = String(localized: "正在安装…")
            symbol = "gearshape.circle"
        case .failed:
            title = String(localized: "更新失败 · 打开下载页")
            symbol = "exclamationmark.circle"
        }
        configuration?.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(13, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
    }

    func animateIn() {
        transform = CGAffineTransform(translationX: 0, y: 72)
        alpha = 0
        UIView.animate(withDuration: 0.55, delay: 0.15, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}

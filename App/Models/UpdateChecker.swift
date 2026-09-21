//
//  UpdateChecker.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit

// Network continuations and every update control stay on the UI actor.
@MainActor
enum UpdateChecker {

    private struct Release {
        let version: String
        let pageURL: URL
        let dmgURL: URL?
    }

    private static let repo = "zhan2333/Recap"
    private static let minimumInterval: TimeInterval = 600
    private static let pollInterval: TimeInterval = 1_800
    private static var pollTimer: Timer?
    private static var checkTask: Task<Release, Error>?
    private static var installationTask: Task<Void, Never>?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func start() {
        refreshPill()
        check()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { _ in
            Task { @MainActor in check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in check() } }
    }

    static func check(force: Bool = false) {
        let lastCheck = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard checkTask == nil,
              force || Date().timeIntervalSince1970 - lastCheck > minimumInterval else { return }
        Task { _ = try? await fetchRelease(force: force) }
    }

    // An explicit check bypasses the automatic polling interval and reports failures to About.
    static func checkManually() async throws -> String? {
        let release = try await fetchRelease(force: true)
        return isNewer(release) ? release.version : nil
    }

    private static func fetchRelease(force: Bool) async throws -> Release {
        if let checkTask { return try await checkTask.value }
        // Throttle failed automatic attempts too; an explicit check still bypasses this interval.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        let task = Task { @MainActor () throws -> Release in
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if !force, let etag = UserDefaults.standard.string(forKey: "latestReleaseETag") {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let release: Release
            if http.statusCode == 304, let cached = cachedRelease {
                release = cached
            } else {
                guard http.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let page = json["html_url"] as? String,
                      let pageURL = secureURL(page) else { throw URLError(.badServerResponse) }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard !version.isEmpty, version.first?.isNumber == true,
                      version.allSatisfy({ $0.isNumber || $0 == "." }) else { throw URLError(.badServerResponse) }
                let assets = json["assets"] as? [[String: Any]] ?? []
                let dmgURL = assets.compactMap { $0["browser_download_url"] as? String }
                    .compactMap(secureURL).first { $0.pathExtension.lowercased() == "dmg" }
                release = Release(version: version, pageURL: pageURL, dmgURL: dmgURL)
                UserDefaults.standard.set(version, forKey: "latestKnownVersion")
                UserDefaults.standard.set(pageURL.absoluteString, forKey: "latestKnownURL")
                UserDefaults.standard.set(dmgURL?.absoluteString, forKey: "latestKnownDMG")
                UserDefaults.standard.set(http.value(forHTTPHeaderField: "ETag"), forKey: "latestReleaseETag")
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            refreshPill()
            return release
        }
        checkTask = task
        defer { checkTask = nil }
        return try await task.value
    }

    private static func secureURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private static var cachedRelease: Release? {
        guard let version = UserDefaults.standard.string(forKey: "latestKnownVersion"),
              let page = UserDefaults.standard.string(forKey: "latestKnownURL"),
              let pageURL = secureURL(page) else { return nil }
        return Release(version: version, pageURL: pageURL,
            dmgURL: UserDefaults.standard.string(forKey: "latestKnownDMG").flatMap(secureURL))
    }

    private static func isNewer(_ release: Release) -> Bool {
        release.version.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    // The library window owns the pill; studio windows are working surfaces.
    private static var libraryWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.rootViewController is MainSplitViewController }
    }

    private static func refreshPill() {
        guard let window = libraryWindow, let release = cachedRelease else { return }
        guard isNewer(release) else {
            if installationTask == nil { window.viewWithTag(UpdatePillView.viewTag)?.removeFromSuperview() }
            return
        }
        if let shown = window.viewWithTag(UpdatePillView.viewTag) as? UpdatePillView {
            guard shown.version != release.version, shown.phase == .idle else { return }
            shown.removeFromSuperview()
        }
        let pill = UpdatePillView()
        pill.version = release.version
        pill.onTap = { [weak pill] in
            guard let pill else { return }
            switch pill.phase {
            case .idle: installAvailableUpdate()
            case .failed: UIApplication.shared.open(release.pageURL)
            case .downloading, .installing: break
            }
        }
        window.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -18),
        ])
        pill.animateIn()
    }

    // MARK: - Install after a normal quit

    private static var hasActiveWork: Bool {
        LibraryStore.shared.hasActiveStorageUsers || !LectureQueue.shared.activities.isEmpty
    }

    static func installAvailableUpdate() {
        guard installationTask == nil, let release = cachedRelease, isNewer(release) else { return }
        guard let dmgURL = release.dmgURL, ShellBridge.isAvailable, StatusItemBridge.isAvailable else {
            UIApplication.shared.open(release.pageURL)
            return
        }
        guard !hasActiveWork else { showBusyAlert(); return }
        refreshPill()
        let pill = libraryWindow?.viewWithTag(UpdatePillView.viewTag) as? UpdatePillView
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("Recap-update-\(UUID().uuidString)", isDirectory: true)
        let plan = UpdateInstaller.Plan(appURL: Bundle.main.bundleURL, workingDirectory: work,
            processID: ProcessInfo.processInfo.processIdentifier, expectedVersion: release.version)
        pill?.phase = .downloading
        installationTask = Task {
            defer { installationTask = nil }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let (download, response) = try await URLSession.shared.download(from: dmgURL)
                defer { try? FileManager.default.removeItem(at: download) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let dmg = work.appendingPathComponent("Recap.dmg")
                try FileManager.default.moveItem(at: download, to: dmg)
                defer { try? FileManager.default.removeItem(at: dmg) }
                pill?.phase = .installing
                guard await run(plan.preparationCommand(dmgURL: dmg)) == 0 else {
                    throw URLError(.cannotWriteToFile)
                }
                try FileManager.default.removeItem(at: dmg)
                guard !hasActiveWork else {
                    _ = await run(plan.cleanupCommand())
                    pill?.phase = .idle
                    showBusyAlert()
                    return
                }
                try plan.helperScript().write(to: plan.helperURL, atomically: true, encoding: .utf8)
                guard await run(plan.launchCommand()) == 0 else { throw URLError(.cannotWriteToFile) }
                // No suspension between the final activity check, Metal cleanup, and ordinary quit.
                guard !hasActiveWork, LectureQueue.shared.releaseIdleEngine() else {
                    _ = await run(plan.cleanupCommand())
                    pill?.phase = .idle
                    showBusyAlert()
                    return
                }
                StatusItemBridge.terminate()
                // If termination is cancelled, the helper times out without touching this bundle.
                try await Task.sleep(for: .seconds(65))
                _ = await run(plan.cleanupCommand())
                pill?.phase = .failed
            } catch {
                _ = await run(plan.cleanupCommand())
                pill?.phase = .failed
            }
        }
    }

    private static func run(_ command: String) async -> Int32 {
        await withCheckedContinuation { continuation in
            ShellBridge.run(command, onOutput: { _ in }, onExit: { continuation.resume(returning: $0) })
        }
    }

    private static func showBusyAlert() {
        let activeWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        guard var presenter = (activeWindow ?? libraryWindow)?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIAlertController) else { return }
        let alert = UIAlertController(title: String(localized: "请在任务结束后更新"),
            message: String(localized: "正在处理课程文件或运行终端会话。请等待任务结束或关闭终端后再更新。"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "好"), style: .default))
        presenter.present(alert, animated: true)
    }
}

// MARK: - Update pill

final class UpdatePillView: UIButton {

    static let viewTag = 0xECAB

    enum Phase {
        case idle, downloading, installing, failed
    }

    var onTap: (() -> Void)?
    var version: String?
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

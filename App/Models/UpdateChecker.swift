//
//  UpdateChecker.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit

// Once-a-day check against the GitHub latest release
enum UpdateChecker {

    private static let repo = "floonetio/Recap"

    static func checkIfDue(presenting window: UIWindow?) {
        let lastCheck = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - lastCheck > 86_400 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")

        Task {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))
            else { return }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            guard latest.compare(current, options: .numeric) == .orderedDescending,
                  UserDefaults.standard.string(forKey: "skippedVersion") != latest else { return }

            await MainActor.run {
                guard let root = window?.rootViewController else { return }
                let alert = UIAlertController(
                    title: String(localized: "新版本 \(tag) 可用"),
                    message: String(localized: "当前版本 \(current)。前往 GitHub 下载最新的 dmg。"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "前往下载"), style: .default) { _ in
                    UIApplication.shared.open(htmlURL)
                })
                alert.addAction(UIAlertAction(title: String(localized: "跳过此版本"), style: .default) { _ in
                    UserDefaults.standard.set(latest, forKey: "skippedVersion")
                })
                alert.addAction(UIAlertAction(title: String(localized: "稍后"), style: .cancel))
                var presenter = root
                while let presented = presenter.presentedViewController { presenter = presented }
                presenter.present(alert, animated: true)
            }
        }
    }
}

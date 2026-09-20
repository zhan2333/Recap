//
//  AppDelegate.swift
//  RecapPDFTestHost
//
//  Created by Rio on 9/20/26.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let files = ProcessInfo.processInfo.arguments.dropFirst().filter {
            $0.lowercased().hasSuffix(".pdf") && FileManager.default.fileExists(atPath: $0)
        }.map { URL(fileURLWithPath: $0) }
        if let first = files.first {
            let samples = PDFSamplesViewController(files: files)
            let navigation = UINavigationController(rootViewController: samples)
            navigation.viewControllers = [samples, PDFViewController(fileURL: first, title: first.deletingPathExtension().lastPathComponent)]
            window.rootViewController = navigation
            scene.title = "Recap PDF"
            scene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 640)
        } else {
            window.rootViewController = UIViewController()
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class PDFSamplesViewController: UITableViewController {
    private let files: [URL]

    init(files: [URL]) {
        self.files = files
        super.init(style: .plain)
        title = "PDF"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = RecapTheme.paper
        tableView.separatorColor = RecapTheme.line
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PDFSample")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { files.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let file = files[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "PDFSample", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = file.deletingPathExtension().lastPathComponent
        content.secondaryText = file.deletingLastPathComponent().lastPathComponent
        content.textProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.backgroundColor = RecapTheme.paper
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let file = files[indexPath.row]
        navigationController?.pushViewController(
            PDFViewController(fileURL: file, title: file.deletingPathExtension().lastPathComponent), animated: true
        )
    }
}

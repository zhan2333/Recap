//
//  SceneDelegate.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        #if targetEnvironment(macCatalyst)
        windowScene.titlebar?.titleVisibility = .visible
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1180, height: 720)
        #endif

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MainSplitViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

//
//  SceneDelegate.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
#if targetEnvironment(macCatalyst)
import AppKit
#endif

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    #if targetEnvironment(macCatalyst)
    private let toolbarDelegate = BrandToolbarDelegate()
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        #if targetEnvironment(macCatalyst)
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        windowScene.titlebar?.toolbar = toolbar
        windowScene.titlebar?.toolbarStyle = .unified
        windowScene.titlebar?.titleVisibility = .visible
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1180, height: 720)
        #endif

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MainSplitViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

#if targetEnvironment(macCatalyst)
/// Puts the italic brand R (design-site mark, template-rendered so it follows
/// light/dark) ahead of the window title in the unified titlebar.
final class BrandToolbarDelegate: NSObject, NSToolbarDelegate {

    static let brandID = NSToolbarItem.Identifier("recapBrandMark")

    private static var brandImage: UIImage? = {
        guard let image = UIImage(named: "recap-r-mark") else { return nil }
        let height: CGFloat = 19
        let size = CGSize(width: height * image.size.width / image.size.height, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysTemplate)
    }()

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, Self.brandID, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.brandID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = Self.brandImage
        item.label = "Recap"
        item.isNavigational = true
        item.isBordered = false
        item.autovalidates = false
        return item
    }
}
#endif

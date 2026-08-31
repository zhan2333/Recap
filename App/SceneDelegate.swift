//
//  SceneDelegate.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import UserNotifications
#if targetEnvironment(macCatalyst)
import AppKit
#endif

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    private static let studioSessionKey = "recapStudioLecture"
    private static var mainSessionID: String?

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

        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == TerminalStudioViewController.activityType }) {
            connectStudioWindow(windowScene, activity: activity)
            return
        }
        // A restored studio session comes back without its activity, and the app has no
        // second main window: drop such sessions instead of opening another library
        if session.userInfo?[Self.studioSessionKey] != nil || Self.mainSessionID != nil {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
            return
        }
        Self.mainSessionID = session.persistentIdentifier

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

        UNUserNotificationCenter.current().delegate = self

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MainSplitViewController()
        window.makeKeyAndVisible()
        self.window = window

        // One-shot: installs that predate first-run setup skip it, later resets still show it
        if !UserDefaults.standard.bool(forKey: "onboardingMigrated") {
            UserDefaults.standard.set(true, forKey: "onboardingMigrated")
            if Settings.modelExists || !LibraryStore.shared.courses.isEmpty {
                Settings.onboardingCompleted = true
            }
        }

        if !Settings.onboardingCompleted {
            let onboarding = OnboardingViewController()
            onboarding.modalPresentationStyle = .pageSheet
            onboarding.isModalInPresentation = true
            onboarding.onFinish = { outcome in
                guard let split = window.rootViewController as? MainSplitViewController,
                      let course = outcome.course else { return }
                split.show(course: course)
                if let lecture = outcome.lecture {
                    split.show(lecture: lecture, in: course)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                window.rootViewController?.present(onboarding, animated: true)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                UpdateChecker.start()
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if Self.mainSessionID == scene.session.persistentIdentifier {
            Self.mainSessionID = nil
        }
    }

    // MARK: - Terminal Studio window

    private func connectStudioWindow(_ windowScene: UIWindowScene, activity: NSUserActivity) {
        guard let idString = activity.userInfo?["lectureID"] as? String,
              let id = UUID(uuidString: idString),
              let found = LibraryStore.shared.locate(lectureID: id) else { return }
        let prompt = (activity.userInfo?["prompt"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        windowScene.session.userInfo = [Self.studioSessionKey: idString]

        #if targetEnvironment(macCatalyst)
        windowScene.title = "Terminal Studio · \(found.course.name)"
        windowScene.titlebar?.titleVisibility = .visible
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 880, height: 540)
        #endif

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = TerminalStudioViewController(
            lecture: found.lecture, course: found.course, initialPrompt: prompt)
        window.makeKeyAndVisible()
        self.window = window
    }
}

#if targetEnvironment(macCatalyst)
// Puts the italic brand R (design-site mark, template-rendered so it follows light/dark) ahead of the window title in the unified titlebar.
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

extension SceneDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let idString = response.notification.request.content.userInfo["lectureID"] as? String,
              let id = UUID(uuidString: idString),
              let found = LibraryStore.shared.locate(lectureID: id),
              let split = window?.rootViewController as? MainSplitViewController else { return }
        split.show(course: found.course)
        split.show(lecture: found.lecture, in: found.course)
    }
}

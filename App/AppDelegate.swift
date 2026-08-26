//
//  AppDelegate.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }

    // MARK: - Main menu

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        builder.remove(menu: .newScene)
        builder.insertChild(UIMenu(options: .displayInline, children: [
            UIKeyCommand(title: String(localized: "新建课程"), action: #selector(MainSplitViewController.menuNewCourse), input: "n", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "添加讲次"), action: #selector(MainSplitViewController.menuAddLecture), input: "n", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: String(localized: "导入文件…"), action: #selector(MainSplitViewController.menuImportFiles), input: "o", modifierFlags: .command),
        ]), atStartOfMenu: .file)

        builder.insertChild(UIMenu(options: .displayInline, children: [
            UIKeyCommand(title: String(localized: "分段"), action: #selector(MainSplitViewController.menuShowSegments), input: "1", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "全文"), action: #selector(MainSplitViewController.menuShowFullText), input: "2", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "播放"), action: #selector(MainSplitViewController.menuShowPlayer), input: "3", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "重点"), action: #selector(MainSplitViewController.menuShowKeyPoints), input: "4", modifierFlags: .command),
        ]), atStartOfMenu: .view)

        builder.insertSibling(UIMenu(title: String(localized: "讲次"), children: [
            UIKeyCommand(title: String(localized: "提取重点"), action: #selector(MainSplitViewController.menuExtractKeyPoints), input: "e", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "生成讲义"), action: #selector(MainSplitViewController.menuGenerateHandout), input: "g", modifierFlags: .command),
            UIKeyCommand(title: "Terminal Studio", action: #selector(MainSplitViewController.menuOpenTerminalStudio), input: "t", modifierFlags: [.command, .shift]),
            UIMenu(options: .displayInline, children: [
                UIKeyCommand(title: String(localized: "上一重点"), action: #selector(MainSplitViewController.menuPreviousKeyPoint), input: "[", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "下一重点"), action: #selector(MainSplitViewController.menuNextKeyPoint), input: "]", modifierFlags: .command),
            ]),
        ]), afterMenu: .view)

        builder.insertSibling(UIMenu(identifier: .preferences, options: .displayInline, children: [
            UIKeyCommand(title: String(localized: "设置…"), action: #selector(MainSplitViewController.menuShowSettings), input: ",", modifierFlags: .command),
        ]), afterMenu: .about)
    }
}

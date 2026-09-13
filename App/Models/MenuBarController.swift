//
//  MenuBarController.swift
//  Recap
//
//  Created by Rio on 2026/9/13.
//

import UIKit

// Keeps Recap reachable while its window is closed: the brand mark sits in the menu bar,
// left click opens the library, right click drops a menu built from what the queue is doing
@MainActor
enum MenuBarController {

    private static var observer: NSObjectProtocol?

    static func install() {
        guard StatusItemBridge.isAvailable, observer == nil else { return }
        guard let image = UIImage(named: "recap-r-mark"),
              let data = image.pngData() else { return }

        StatusItemBridge.install(image: data, tooltip: "Recap") { command in
            DispatchQueue.main.async { handle(command) }
        } onPrimaryClick: {
            DispatchQueue.main.async { openLibrary() }
        }
        refresh()

        observer = NotificationCenter.default.addObserver(
            forName: LectureQueue.activityDidChange, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { refresh() } }
    }

    private static func refresh() {
        refreshMenu()
        let (fraction, active) = progress()
        StatusItemBridge.setProgress(fraction, active: active, tooltip: statusLine())
    }

    // The bar under the mark: a share for staged work, an unknown length for the rest
    private static func progress() -> (fraction: Double, active: Bool) {
        let activities = LectureQueue.shared.activities.values
        guard !activities.isEmpty else { return (0, false) }
        let staged = activities.compactMap { activity -> Double? in
            switch activity {
            case .downloading(let value), .transcribing(let value): return value
            default: return nil
            }
        }
        guard let furthest = staged.max() else { return (0, true) }
        return (furthest, true)
    }

    // MARK: - Menu

    private static func refreshMenu() {
        var items: [[String: String]] = [
            ["kind": "header", "title": statusLine()],
            ["kind": "separator"],
            ["kind": "item", "id": "open", "title": String(localized: "打开 Recap")],
        ]

        let working = workingLectures()
        if !working.isEmpty {
            items.append(["kind": "separator"])
            items.append(["kind": "header", "title": String(localized: "进行中")])
            for entry in working {
                items.append([
                    "kind": "item",
                    "id": "lecture:\(entry.lecture.id.uuidString)",
                    "title": "\(entry.lecture.name) · \(entry.course.name)",
                ])
            }
        }

        items.append(contentsOf: [
            ["kind": "separator"],
            ["kind": "item", "id": "settings", "title": String(localized: "设置…")],
            ["kind": "item", "id": "quit", "title": String(localized: "退出 Recap"), "key": "q"],
        ])
        StatusItemBridge.setMenu(items)
    }

    // What the queue is doing right now, in one line
    private static func statusLine() -> String {
        let activities = LectureQueue.shared.activities
        guard !activities.isEmpty else { return String(localized: "空闲") }

        let running = activities.first { lectureID, activity in
            switch activity {
            case .waitingToTranscribe: return false
            default: return LibraryStore.shared.locate(lectureID: lectureID) != nil
            }
        }
        guard let running, let found = LibraryStore.shared.locate(lectureID: running.key) else {
            return String(localized: "队列中 \(activities.count) 个讲次")
        }

        let name = found.lecture.name
        switch running.value {
        case .downloading(let progress):
            return String(localized: "正在下载 \(Int(progress * 100))% · \(name)")
        case .transcribing(let progress):
            return String(localized: "正在转写 \(Int(progress * 100))% · \(name)")
        case .analyzing:
            return String(localized: "正在提取重点 · \(name)")
        case .waitingToTranscribe:
            return String(localized: "等待转写 · \(name)")
        }
    }

    // Whatever the queue is carrying, so a closed window still has a way back to it
    private static func workingLectures() -> [(course: Course, lecture: Lecture)] {
        LectureQueue.shared.activities.keys
            .compactMap { LibraryStore.shared.locate(lectureID: $0) }
            .sorted { $0.lecture.name < $1.lecture.name }
            .prefix(5)
            .map { (course: $0.course, lecture: $0.lecture) }
    }

    // MARK: - Commands

    private static func handle(_ command: String) {
        switch command {
        case "open":
            openLibrary()
        case "settings":
            openLibrary()
            split()?.menuShowSettings()
        case "quit":
            StatusItemBridge.terminate()
        default:
            guard command.hasPrefix("lecture:"),
                  let id = UUID(uuidString: String(command.dropFirst("lecture:".count))),
                  let found = LibraryStore.shared.locate(lectureID: id) else { return }
            openLibrary()
            // The window may still be coming back, so land on the lecture once it is up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard let split = split() else { return }
                split.select(course: found.course)
                split.show(lecture: found.lecture, in: found.course)
            }
        }
    }

    // Brings the library window back, opening one if every window was closed
    private static func openLibrary() {
        if let scene = libraryScene() {
            UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil)
            return
        }
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
    }

    private static func libraryScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in
                scene.windows.contains { $0.rootViewController is MainSplitViewController }
            }
    }

    private static func split() -> MainSplitViewController? {
        libraryScene()?.windows
            .compactMap { $0.rootViewController as? MainSplitViewController }
            .first
    }
}

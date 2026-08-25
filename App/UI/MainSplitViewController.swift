//
//  MainSplitViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

// Three columns: courses | lectures | transcript.
final class MainSplitViewController: UISplitViewController {

    private let courseList = CourseListViewController()

    init() {
        super.init(style: .tripleColumn)
        preferredDisplayMode = .twoBesideSecondary
        preferredSplitBehavior = .tile
        minimumPrimaryColumnWidth = 200
        maximumPrimaryColumnWidth = 240
        preferredPrimaryColumnWidth = 210
        minimumSupplementaryColumnWidth = 280
        maximumSupplementaryColumnWidth = 340
        preferredSupplementaryColumnWidth = 300

        setViewController(UINavigationController(rootViewController: courseList), for: .primary)
        setViewController(UINavigationController(rootViewController: PlaceholderViewController(text: String(localized: "这里还没有内容，但第一步很轻。\n先新建一门课程。"))), for: .supplementary)
        setViewController(UINavigationController(rootViewController: PlaceholderViewController(text: String(localized: "选择一个讲次查看文稿"))), for: .secondary)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(course: Course) {
        let lectures = LectureListViewController(course: course)
        setViewController(UINavigationController(rootViewController: lectures), for: .supplementary)
        setViewController(UINavigationController(rootViewController: PlaceholderViewController(text: String(localized: "选择一个讲次查看文稿"))), for: .secondary)
    }

    func show(lecture: Lecture, in course: Course) {
        let transcript = TranscriptViewController(lecture: lecture, course: course)
        setViewController(UINavigationController(rootViewController: transcript), for: .secondary)
    }

    func show(markdown: String, title: String) {
        let viewer = MarkdownViewController(markdown: markdown, title: title)
        setViewController(UINavigationController(rootViewController: viewer), for: .secondary)
    }

    func show(pdfAt url: URL, title: String) {
        let viewer = PDFViewController(fileURL: url, title: title)
        setViewController(UINavigationController(rootViewController: viewer), for: .secondary)
    }
}

// Neutral empty-state column.
final class PlaceholderViewController: UIViewController {

    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        navigationController?.navigationBar.isHidden = true

        let label = UILabel()
        label.text = text
        label.font = RecapTheme.body(13)
        label.textColor = RecapTheme.quiet
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -24),
        ])
    }
}

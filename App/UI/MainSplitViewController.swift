//
//  MainSplitViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

/// Three columns: courses | lectures | transcript.
final class MainSplitViewController: UISplitViewController {

    private let courseList = CourseListViewController()

    init() {
        super.init(style: .tripleColumn)
        primaryBackgroundStyle = .sidebar
        preferredDisplayMode = .twoBesideSecondary
        preferredSplitBehavior = .tile
        minimumPrimaryColumnWidth = 200
        maximumPrimaryColumnWidth = 300
        minimumSupplementaryColumnWidth = 280
        maximumSupplementaryColumnWidth = 400

        setViewController(UINavigationController(rootViewController: courseList), for: .primary)
        setViewController(UINavigationController(rootViewController: PlaceholderViewController(text: "选择或创建一门课程")), for: .supplementary)
        setViewController(UINavigationController(rootViewController: PlaceholderViewController(text: "选择一个讲次查看文稿")), for: .secondary)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(course: Course) {
        let lectures = LectureListViewController(course: course)
        setViewController(UINavigationController(rootViewController: lectures), for: .supplementary)
        setViewController(UINavigationController(rootViewController: PlaceholderViewController(text: "选择一个讲次查看文稿")), for: .secondary)
    }

    func show(lecture: Lecture, in course: Course) {
        let transcript = TranscriptViewController(lecture: lecture, course: course)
        setViewController(UINavigationController(rootViewController: transcript), for: .secondary)
    }
}

/// Neutral empty-state column.
final class PlaceholderViewController: UIViewController {

    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

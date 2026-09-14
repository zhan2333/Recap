//
//  MergeLecturesSheet.swift
//  Recap
//
//  Created by Rio on 2026/9/14.
//

import UIKit

// Picks the lectures that belong to one class so they become parts of a single lecture,
// which is what makes one transcript and one handout out of them
final class MergeLecturesSheet: UIViewController {

    private let course: Course
    private var lectures: [Lecture] = []
    private var selected: Set<UUID> = []
    private let rows = UIStackView()
    private let countLabel = UILabel()
    private let mergeButton = UIButton(type: .system)

    var onMerge: (([UUID]) -> Void)?

    init(course: Course) {
        self.course = course
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "合并为一个讲次")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        lectures = LibraryStore.shared.lectures(in: course)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "取消"), primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            })

        let hint = UILabel()
        hint.text = String(localized: "选中的讲次会按顺序合成一讲，媒体文件不会重新下载。合成后需要重新转写，之后就能生成一份讲义。")
        hint.font = RecapTheme.body(12)
        hint.textColor = RecapTheme.muted
        hint.numberOfLines = 0

        rows.axis = .vertical
        rows.spacing = 2
        for lecture in lectures {
            rows.addArrangedSubview(row(for: lecture))
        }
        let scroller = UIScrollView()
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            rows.widthAnchor.constraint(equalTo: scroller.frameLayoutGuide.widthAnchor),
        ])

        countLabel.font = RecapTheme.body(12)
        countLabel.textColor = RecapTheme.quiet
        mergeButton.preferredBehavioralStyle = .pad
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RecapTheme.ink
        config.background.cornerRadius = RecapTheme.radiusSM
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        mergeButton.configuration = config
        mergeButton.addAction(UIAction { [weak self] _ in self?.merge() }, for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [countLabel, UIView(), mergeButton])
        footer.axis = .horizontal
        footer.alignment = .center

        let stack = UIStackView(arrangedSubviews: [hint, scroller, footer])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        refresh()
    }

    private func row(for lecture: Lecture) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        button.contentHorizontalAlignment = .leading
        button.tag = abs(lecture.id.hashValue % 1_000_000)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.selected.contains(lecture.id) {
                self.selected.remove(lecture.id)
            } else {
                self.selected.insert(lecture.id)
            }
            self.refresh()
        }, for: .touchUpInside)
        return button
    }

    private func refresh() {
        for (index, view) in rows.arrangedSubviews.enumerated() {
            guard let button = view as? UIButton, lectures.indices.contains(index) else { continue }
            let lecture = lectures[index]
            let isOn = selected.contains(lecture.id)
            let busy = LectureQueue.shared.activity(for: lecture.id) != nil
            var config = UIButton.Configuration.plain()
            let mark = isOn ? "☑︎" : "☐"
            let suffix = busy ? String(localized: "（正在处理，先等它完成）") : ""
            config.attributedTitle = AttributedString("\(mark)  \(lecture.name)\(suffix)", attributes: AttributeContainer([
                .font: RecapTheme.body(12.5, weight: isOn ? .semibold : .regular),
                .foregroundColor: busy ? RecapTheme.quiet : RecapTheme.ink,
            ]))
            config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6)
            config.background.cornerRadius = RecapTheme.radiusSM
            config.background.backgroundColor = isOn ? RecapTheme.selection : .clear
            button.configuration = config
            button.isEnabled = !busy
        }

        let busySelected = selected.contains { LectureQueue.shared.activity(for: $0) != nil }
        countLabel.text = selected.count < 2
            ? String(localized: "至少选择两讲")
            : String(localized: "已选 \(selected.count) 讲")
        var title = AttributedString(String(localized: "合并"))
        title.font = RecapTheme.body(13, weight: .semibold)
        title.foregroundColor = RecapTheme.paper
        mergeButton.configuration?.attributedTitle = title
        mergeButton.isEnabled = selected.count > 1 && !busySelected
    }

    private func merge() {
        let ordered = lectures.map(\.id).filter { selected.contains($0) }
        guard ordered.count > 1 else { return }
        dismiss(animated: true) { [onMerge] in onMerge?(ordered) }
    }
}

//
//  OnboardingDoneStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

// Two endings: the first lecture is already transcribing, or the app is simply ready
final class OnboardingDoneStep: OnboardingStepView {

    override var primaryTitle: String {
        host?.recordedCourse == nil ? String(localized: "打开 Recap") : String(localized: "打开课程")
    }

    override func build() {
        let hasLecture = host?.recordedLecture != nil
        let course = host?.recordedCourse

        let badge = UILabel()
        badge.text = hasLecture ? "✓" : "R"
        badge.font = RecapTheme.display(22, weight: .semibold)
        badge.textColor = RecapTheme.paper
        badge.textAlignment = .center
        badge.backgroundColor = hasLecture ? RecapTheme.complete : RecapTheme.ink
        badge.layer.cornerRadius = 22
        badge.layer.masksToBounds = true
        badge.widthAnchor.constraint(equalToConstant: 44).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let badgeRow = UIStackView(arrangedSubviews: [badge, UIView()])
        badgeRow.axis = .horizontal

        // A miniature of the workspace this hands over to
        let row = UIView()
        row.backgroundColor = RecapTheme.surface.withAlphaComponent(0.7)
        row.layer.cornerRadius = RecapTheme.radiusMD
        row.layer.cornerCurve = .continuous

        let icon = UILabel()
        icon.text = hasLecture ? "▶" : "+"
        icon.font = RecapTheme.mono(12, weight: .semibold)
        icon.textColor = RecapTheme.muted
        let title = UILabel()
        title.text = host?.recordedLecture?.name ?? course?.name ?? String(localized: "尚未创建课程")
        title.font = RecapTheme.body(12.5, weight: .semibold)
        title.textColor = RecapTheme.ink
        title.numberOfLines = 1
        let detail = UILabel()
        detail.text = hasLecture ? (course?.name ?? "") : String(localized: "尚未添加资料")
        detail.font = RecapTheme.body(11)
        detail.textColor = RecapTheme.quiet
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2
        let state = UILabel()
        state.text = hasLecture ? String(localized: "正在开始…") : "—"
        state.font = RecapTheme.body(11)
        state.textColor = hasLecture ? RecapTheme.signalText : RecapTheme.quiet

        let rowStack = UIStackView(arrangedSubviews: [icon, text, UIView(), state])
        rowStack.axis = .horizontal
        rowStack.spacing = 10
        rowStack.alignment = .center
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -13),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
        ])

        let back = textAction(hasLecture ? String(localized: "再添加一讲") : String(localized: "返回添加资料")) { [weak self] in
            self?.host?.returnToLectureStep()
        }

        fill(with: stack([badgeRow, row, back], spacing: 14))
    }

    override func performPrimary(_ completion: @escaping (PrimaryResult) -> Void) {
        completion(.finish)
    }
}

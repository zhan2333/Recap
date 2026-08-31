//
//  OnboardingCourseStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

final class OnboardingCourseStep: OnboardingStepView {

    private var name = Settings.onboardingCourseName
    private weak var folder: OnboardingFolder?
    private let error = UILabel()

    override var primaryTitle: String { String(localized: "创建课程") }

    override func build() {
        error.font = RecapTheme.body(11, weight: .semibold)
        error.textColor = RecapTheme.error
        error.numberOfLines = 0
        error.isHidden = true
        error.alpha = 0

        let input = field(
            label: String(localized: "课程名称"),
            placeholder: String(localized: "例如：深度学习基础"),
            value: name
        ) { [weak self] value in
            guard let self else { return }
            self.name = value
            Settings.onboardingCourseName = value
            self.folder?.retitle(value.isEmpty ? String(localized: "深度学习基础") : value)
            if !self.error.isHidden {
                self.animateContentChange {
                    self.error.isHidden = true
                    self.error.alpha = 0
                }
            }
        }

        let skip = textAction(String(localized: "稍后创建")) { [weak self] in
            Settings.onboardingCourseName = ""
            self?.requestAdvance?()
        }

        let folder = OnboardingFolder(
            title: name.isEmpty ? String(localized: "深度学习基础") : name,
            detail: String(localized: "本机保存"))
        self.folder = folder
        let scene = OnboardingScene(pieces: [OnboardingPaperStack(), folder], spacing: 28, minHeight: 160)
        fill(with: stack([
            scene,
            input,
            note(String(localized: "名称只保存在本机，也可以随时修改。")),
            error,
            skip,
        ], spacing: 10))
    }

    override func performPrimary(_ completion: @escaping (PrimaryResult) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error.text = String(localized: "请输入课程名称，或选择「稍后创建」。")
            animateContentChange {
                error.isHidden = false
                error.alpha = 1
            }
            completion(.stay)
            return
        }
        let course = LibraryStore.shared.addCourse(named: trimmed)
        host?.record(course: course)
        Settings.onboardingCourseName = ""
        completion(.next)
    }
}

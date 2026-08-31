//
//  OnboardingViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

// First-run setup: five short steps from the model file to the first lecture
final class OnboardingViewController: UIViewController {

    enum Step: Int, CaseIterable {
        case welcome, model, ai, course, lecture
    }

    struct Outcome {
        var course: Course?
        var lecture: Lecture?
    }

    var onFinish: ((Outcome) -> Void)?

    private(set) var step: Step = .welcome
    private(set) var maxReachable = 0
    private var outcome = Outcome()

    private let brandTitle = UILabel()
    private let progressCount = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let stepList = UIStackView()
    private let stageEyebrow = UILabel()
    private let stageTitle = UILabel()
    private let stageDescription = UILabel()
    private let stageContent = UIView()
    private let guideIndex = UILabel()
    private let guideTitle = UILabel()
    private let guideDetail = UILabel()
    private let footerStatus = UILabel()
    private let backButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)

    private var stepViews: [Step: OnboardingStepView] = [:]
    private var progressFillWidth: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        buildChrome()
        step = Step(rawValue: min(Settings.onboardingStep, Step.allCases.count - 1)) ?? .welcome
        maxReachable = step.rawValue
        show(step, animated: false)
    }

    // MARK: - Chrome

    private func buildChrome() {
        let mark = UIImageView(image: UIImage(named: "recap-r-mark")?.withRenderingMode(.alwaysTemplate))
        mark.tintColor = RecapTheme.ink
        mark.contentMode = .scaleAspectFit
        mark.widthAnchor.constraint(equalToConstant: 20).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 22).isActive = true

        brandTitle.text = "Recap"
        brandTitle.font = RecapTheme.display(15, weight: .semibold)
        brandTitle.textColor = RecapTheme.ink
        let brandDetail = UILabel()
        brandDetail.text = String(localized: "初次设置")
        brandDetail.font = RecapTheme.body(11)
        brandDetail.textColor = RecapTheme.quiet
        let brandText = UIStackView(arrangedSubviews: [brandTitle, brandDetail])
        brandText.axis = .vertical
        brandText.spacing = 1
        brandText.alignment = .leading
        let brand = UIStackView(arrangedSubviews: [mark, brandText])
        brand.axis = .horizontal
        brand.spacing = 9
        brand.alignment = .center

        let helpButton = quietButton(title: "?", accessibility: String(localized: "解释课程、讲次和转写")) { [weak self] in
            self?.presentGlossary()
        }
        helpButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        let exitButton = quietButton(title: String(localized: "暂时退出"), accessibility: nil) { [weak self] in
            self?.presentExitConfirmation()
        }

        let header = UIStackView(arrangedSubviews: [brand, UIView(), helpButton, exitButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        // Sidebar: progress and the five steps
        let progressLabel = UILabel()
        progressLabel.text = String(localized: "设置 Recap")
        progressLabel.font = RecapTheme.body(11, weight: .semibold)
        progressLabel.textColor = RecapTheme.muted
        progressCount.font = RecapTheme.mono(11, weight: .semibold)
        progressCount.textColor = RecapTheme.ink
        let progressRow = UIStackView(arrangedSubviews: [progressLabel, UIView(), progressCount])
        progressRow.axis = .horizontal

        progressTrack.backgroundColor = RecapTheme.line
        progressTrack.layer.cornerRadius = 1.5
        progressTrack.clipsToBounds = true
        progressFill.backgroundColor = RecapTheme.ink
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidth = fillWidth
        NSLayoutConstraint.activate([
            progressTrack.heightAnchor.constraint(equalToConstant: 3),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidth,
        ])

        stepList.axis = .vertical
        stepList.spacing = 2
        for item in Step.allCases {
            stepList.addArrangedSubview(stepRow(item))
        }

        let sidebar = UIStackView(arrangedSubviews: [progressRow, progressTrack, stepList, UIView()])
        sidebar.axis = .vertical
        sidebar.spacing = 10
        sidebar.setCustomSpacing(18, after: progressTrack)
        sidebar.widthAnchor.constraint(equalToConstant: 214).isActive = true

        // Stage
        stageEyebrow.font = RecapTheme.body(11, weight: .semibold)
        stageEyebrow.textColor = RecapTheme.signalText
        stageTitle.font = RecapTheme.display(26, weight: .semibold)
        stageTitle.textColor = RecapTheme.ink
        stageTitle.numberOfLines = 0
        stageDescription.font = RecapTheme.body(13)
        stageDescription.textColor = RecapTheme.muted
        stageDescription.numberOfLines = 0
        let stageCopy = UIStackView(arrangedSubviews: [stageEyebrow, stageTitle, stageDescription])
        stageCopy.axis = .vertical
        stageCopy.spacing = 6

        guideIndex.font = RecapTheme.mono(10, weight: .semibold)
        guideIndex.textColor = RecapTheme.quiet
        guideTitle.font = RecapTheme.body(12, weight: .semibold)
        guideTitle.textColor = RecapTheme.ink
        guideDetail.font = RecapTheme.body(11)
        guideDetail.textColor = RecapTheme.muted
        guideDetail.numberOfLines = 0
        let guideText = UIStackView(arrangedSubviews: [guideTitle, guideDetail])
        guideText.axis = .vertical
        guideText.spacing = 2
        let guide = UIStackView(arrangedSubviews: [guideIndex, guideText])
        guide.axis = .horizontal
        guide.spacing = 10
        guide.alignment = .top
        guide.isLayoutMarginsRelativeArrangement = true
        guide.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13)
        let guideBackground = UIView()
        guideBackground.backgroundColor = RecapTheme.surface.withAlphaComponent(0.6)
        guideBackground.layer.cornerRadius = RecapTheme.radiusMD
        guideBackground.layer.cornerCurve = .continuous
        guide.translatesAutoresizingMaskIntoConstraints = false
        guideBackground.addSubview(guide)
        NSLayoutConstraint.activate([
            guide.topAnchor.constraint(equalTo: guideBackground.topAnchor),
            guide.bottomAnchor.constraint(equalTo: guideBackground.bottomAnchor),
            guide.leadingAnchor.constraint(equalTo: guideBackground.leadingAnchor),
            guide.trailingAnchor.constraint(equalTo: guideBackground.trailingAnchor),
        ])

        let stage = UIStackView(arrangedSubviews: [stageCopy, stageContent, UIView(), guideBackground])
        stage.axis = .vertical
        stage.spacing = 20

        // Footer
        footerStatus.font = RecapTheme.body(11)
        footerStatus.textColor = RecapTheme.quiet
        backButton.preferredBehavioralStyle = .pad
        var backConfig = UIButton.Configuration.plain()
        backConfig.attributedTitle = AttributedString(String(localized: "返回"), attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        backConfig.background.strokeColor = RecapTheme.line
        backConfig.background.strokeWidth = 1
        backConfig.background.cornerRadius = RecapTheme.radiusSM
        backConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        backButton.configuration = backConfig
        backButton.addAction(UIAction { [weak self] _ in self?.goBack() }, for: .touchUpInside)

        primaryButton.preferredBehavioralStyle = .pad
        var primaryConfig = UIButton.Configuration.filled()
        primaryConfig.baseBackgroundColor = RecapTheme.ink
        primaryConfig.baseForegroundColor = RecapTheme.paper
        primaryConfig.background.cornerRadius = RecapTheme.radiusSM
        primaryConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 20)
        primaryButton.configuration = primaryConfig
        primaryButton.addAction(UIAction { [weak self] _ in self?.advance() }, for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [footerStatus, UIView(), backButton, primaryButton])
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 10

        let main = UIStackView(arrangedSubviews: [stage, footer])
        main.axis = .vertical
        main.spacing = 18

        let columns = UIStackView(arrangedSubviews: [sidebar, main])
        columns.axis = .horizontal
        columns.spacing = 30
        columns.alignment = .fill

        let separator = UIView()
        separator.backgroundColor = RecapTheme.line
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let root = UIStackView(arrangedSubviews: [header, separator, columns])
        root.axis = .vertical
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    private func quietButton(title: String, accessibility: String?, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        config.background.strokeColor = RecapTheme.line
        config.background.strokeWidth = 1
        config.background.cornerRadius = RecapTheme.radiusSM
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        button.configuration = config
        button.accessibilityLabel = accessibility
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Step list

    private func stepRow(_ item: Step) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        button.contentHorizontalAlignment = .leading
        button.tag = item.rawValue + 1
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9)
        config.background.cornerRadius = RecapTheme.radiusSM
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in
            guard let self, item.rawValue <= self.maxReachable else { return }
            self.show(item, animated: true)
        }, for: .touchUpInside)
        return button
    }

    private func refreshStepList() {
        for item in Step.allCases {
            guard let button = stepList.arrangedSubviews.compactMap({ $0 as? UIButton })
                .first(where: { $0.tag == item.rawValue + 1 }) else { continue }
            let isCurrent = item == step
            let reachable = item.rawValue <= maxReachable
            let color = isCurrent ? RecapTheme.ink : (reachable ? RecapTheme.muted : RecapTheme.quiet.withAlphaComponent(0.6))
            var title = AttributedString("\(item.rawValue + 1)  \(item.navTitle)")
            title.font = RecapTheme.body(12, weight: isCurrent ? .semibold : .regular)
            title.foregroundColor = color
            var subtitle = AttributedString(item.navDetail)
            subtitle.font = RecapTheme.body(10.5)
            subtitle.foregroundColor = RecapTheme.quiet
            button.configuration?.attributedTitle = title
            button.configuration?.attributedSubtitle = subtitle
            button.configuration?.background.backgroundColor = isCurrent ? RecapTheme.selection : .clear
            button.isEnabled = reachable
        }
        let total = CGFloat(Step.allCases.count)
        progressCount.text = "\(step.rawValue + 1) / \(Int(total))"
        footerStatus.text = String(localized: "第 \(step.rawValue + 1) 步，共 \(Int(total)) 步")
        view.layoutIfNeeded()
        progressFillWidth?.constant = progressTrack.bounds.width * CGFloat(step.rawValue + 1) / total
        UIView.animate(withDuration: 0.28) { self.view.layoutIfNeeded() }
    }

    // MARK: - Navigation

    private func show(_ target: Step, animated: Bool) {
        step = target
        maxReachable = max(maxReachable, target.rawValue)
        Settings.onboardingStep = target.rawValue

        stageEyebrow.text = target.eyebrow
        stageTitle.text = target.title
        stageDescription.text = target.detail
        guideIndex.text = String(format: "%02d", target.rawValue + 1)
        guideTitle.text = target.guideTitle
        guideDetail.text = target.guideDetail

        let stepView = stepViews[target] ?? makeStepView(for: target)
        stepViews[target] = stepView
        stageContent.subviews.forEach { $0.removeFromSuperview() }
        stepView.translatesAutoresizingMaskIntoConstraints = false
        stageContent.addSubview(stepView)
        NSLayoutConstraint.activate([
            stepView.topAnchor.constraint(equalTo: stageContent.topAnchor),
            stepView.bottomAnchor.constraint(equalTo: stageContent.bottomAnchor),
            stepView.leadingAnchor.constraint(equalTo: stageContent.leadingAnchor),
            stepView.trailingAnchor.constraint(equalTo: stageContent.trailingAnchor),
        ])
        stepView.onStateChange = { [weak self] in self?.refreshPrimary() }

        backButton.isHidden = target == .welcome
        refreshStepList()
        refreshPrimary()

        if animated {
            stepView.alpha = 0
            stepView.transform = CGAffineTransform(translationX: 0, y: 8)
            UIView.animate(withDuration: 0.3) {
                stepView.alpha = 1
                stepView.transform = .identity
            }
        }
    }

    private func makeStepView(for target: Step) -> OnboardingStepView {
        let view: OnboardingStepView
        switch target {
        case .welcome: view = OnboardingWelcomeStep(host: self)
        case .model: view = OnboardingModelStep(host: self)
        case .ai: view = OnboardingAIStep(host: self)
        case .course: view = OnboardingCourseStep(host: self)
        case .lecture: view = OnboardingLectureStep(host: self)
        }
        view.requestAdvance = { [weak self] in self?.skipCurrentStep() }
        return view
    }

    private func skipCurrentStep() {
        if let next = Step(rawValue: step.rawValue + 1) {
            show(next, animated: true)
        } else {
            finish()
        }
    }

    private func refreshPrimary() {
        let stepView = stepViews[step]
        let title = stepView?.primaryTitle ?? String(localized: "继续")
        primaryButton.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        primaryButton.isEnabled = stepView?.isPrimaryEnabled ?? true
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        show(previous, animated: true)
    }

    private func advance() {
        guard let stepView = stepViews[step] else { return }
        stepView.performPrimary { [weak self] result in
            guard let self else { return }
            switch result {
            case .stay:
                self.refreshPrimary()
            case .next:
                if let next = Step(rawValue: self.step.rawValue + 1) {
                    self.show(next, animated: true)
                } else {
                    self.finish()
                }
            case .finish:
                self.finish()
            }
        }
    }

    // MARK: - Completion

    var recordedCourse: Course? { outcome.course }

    func record(course: Course) {
        outcome.course = course
    }

    func record(lecture: Lecture) {
        outcome.lecture = lecture
    }

    private func finish() {
        Settings.onboardingCompleted = true
        Settings.onboardingStep = 0
        let result = outcome
        dismiss(animated: true) { [weak self] in self?.onFinish?(result) }
    }

    // MARK: - Dialogs

    private func presentGlossary() {
        let message = [
            String(localized: "课程：一个学习主题，例如「深度学习基础」。"),
            String(localized: "讲次：课程里的一次课，例如「第 8 讲」。"),
            String(localized: "转写：把音频里的讲话变成可以搜索的文字。"),
        ].joined(separator: "\n\n")
        let alert = UIAlertController(title: String(localized: "这些词是什么意思？"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "知道了"), style: .default))
        present(alert, animated: true)
    }

    private func presentExitConfirmation() {
        let alert = UIAlertController(
            title: String(localized: "可以放心退出"),
            message: String(localized: "已经填写的内容和当前步骤保存在这台 Mac。下次打开 Recap，会从这里继续。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "继续设置"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "退出 Recap"), style: .destructive) { _ in
            exit(0)
        })
        present(alert, animated: true)
    }

    // MARK: - Keyboard

    override var keyCommands: [UIKeyCommand]? {
        let back = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .command, action: #selector(commandBack))
        back.wantsPriorityOverSystemBehavior = true
        let forward = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(commandForward))
        forward.wantsPriorityOverSystemBehavior = true
        return [back, forward]
    }

    @objc private func commandBack() { goBack() }

    @objc private func commandForward() {
        guard primaryButton.isEnabled else { return }
        advance()
    }
}

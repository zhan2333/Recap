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
        case welcome, model, ai, course, lecture, done

        static var setupSteps: [Step] { [.welcome, .model, .ai, .course, .lecture] }
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
    private var stageCopy = UIStackView()
    private let guideIndex = UILabel()
    private let guideTitle = UILabel()
    private let guideDetail = UILabel()
    private let guideBackground = UIView()
    private let guideNow = UILabel()
    private let guideArrow = OnboardingGuideArrow()
    private let footerStatus = UILabel()
    private let savedNote = UILabel()
    private let backButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)

    private var stepViews: [Step: OnboardingStepView] = [:]
    private var progressFillWidth: NSLayoutConstraint?
    private var dotWidths: [Step: NSLayoutConstraint] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        preferredContentSize = CGSize(width: 980, height: 780)
        buildChrome()
        step = Step(rawValue: min(Settings.onboardingStep, Step.setupSteps.count - 1)) ?? .welcome
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
        let brand = UIStackView(arrangedSubviews: [mark, brandText, UIView()])
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
        let actions = UIStackView(arrangedSubviews: [UIView(), helpButton, exitButton])
        actions.axis = .horizontal
        actions.spacing = 8
        actions.alignment = .center

        // Centered progress: five dots riding a track, count label above them
        let progressLabel = UILabel()
        progressLabel.text = String(localized: "设置 Recap")
        progressLabel.font = RecapTheme.body(10, weight: .semibold)
        progressLabel.textColor = RecapTheme.quiet
        progressCount.font = RecapTheme.mono(10, weight: .semibold)
        progressCount.textColor = RecapTheme.muted
        let labelRow = UIStackView(arrangedSubviews: [progressLabel, progressCount])
        labelRow.axis = .horizontal
        labelRow.spacing = 6

        progressTrack.backgroundColor = RecapTheme.line
        progressTrack.layer.cornerRadius = 1
        progressTrack.clipsToBounds = true
        progressFill.backgroundColor = RecapTheme.signal
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidth = fillWidth

        stepList.axis = .horizontal
        stepList.distribution = .fillEqually
        stepList.alignment = .center
        for item in Step.setupSteps {
            stepList.addArrangedSubview(stepDot(item))
        }

        let dots = UIView()
        for piece in [progressTrack, stepList] as [UIView] {
            piece.translatesAutoresizingMaskIntoConstraints = false
            dots.addSubview(piece)
        }
        NSLayoutConstraint.activate([
            dots.widthAnchor.constraint(equalToConstant: 246),
            dots.heightAnchor.constraint(equalToConstant: 30),
            progressTrack.heightAnchor.constraint(equalToConstant: 2),
            progressTrack.centerYAnchor.constraint(equalTo: dots.centerYAnchor),
            progressTrack.leadingAnchor.constraint(equalTo: dots.leadingAnchor, constant: 24),
            progressTrack.trailingAnchor.constraint(equalTo: dots.trailingAnchor, constant: -24),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidth,
            stepList.topAnchor.constraint(equalTo: dots.topAnchor),
            stepList.bottomAnchor.constraint(equalTo: dots.bottomAnchor),
            stepList.leadingAnchor.constraint(equalTo: dots.leadingAnchor),
            stepList.trailingAnchor.constraint(equalTo: dots.trailingAnchor),
        ])

        let progress = UIStackView(arrangedSubviews: [labelRow, dots])
        progress.axis = .vertical
        progress.spacing = 4
        progress.alignment = .trailing

        let header = UIStackView(arrangedSubviews: [brand, progress, actions])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 20
        header.heightAnchor.constraint(equalToConstant: 66).isActive = true
        brand.widthAnchor.constraint(equalTo: actions.widthAnchor).isActive = true

        // Stage: copy on the left, the step's own content on the right
        stageEyebrow.font = RecapTheme.body(11, weight: .semibold)
        stageEyebrow.textColor = RecapTheme.signalText
        stageTitle.font = RecapTheme.display(34, weight: .medium)
        stageTitle.textColor = RecapTheme.ink
        stageTitle.numberOfLines = 0
        stageDescription.font = RecapTheme.body(13)
        stageDescription.textColor = RecapTheme.muted
        stageDescription.numberOfLines = 0
        stageCopy = UIStackView(arrangedSubviews: [stageEyebrow, stageTitle, stageDescription])
        stageCopy.axis = .vertical
        stageCopy.spacing = 10
        stageCopy.setCustomSpacing(14, after: stageEyebrow)
        let copyColumn = UIView()
        stageCopy.translatesAutoresizingMaskIntoConstraints = false
        copyColumn.addSubview(stageCopy)
        NSLayoutConstraint.activate([
            copyColumn.widthAnchor.constraint(equalToConstant: 320),
            stageCopy.leadingAnchor.constraint(equalTo: copyColumn.leadingAnchor),
            stageCopy.trailingAnchor.constraint(equalTo: copyColumn.trailingAnchor),
            stageCopy.centerYAnchor.constraint(equalTo: copyColumn.centerYAnchor),
            stageCopy.topAnchor.constraint(greaterThanOrEqualTo: copyColumn.topAnchor),
        ])

        guideIndex.font = RecapTheme.mono(9, weight: .bold)
        guideIndex.textColor = RecapTheme.signalText
        guideIndex.textAlignment = .center
        guideIndex.backgroundColor = RecapTheme.paper
        guideIndex.layer.cornerRadius = 10
        guideIndex.layer.cornerCurve = .continuous
        guideIndex.layer.masksToBounds = true
        guideIndex.widthAnchor.constraint(equalToConstant: 30).isActive = true
        guideIndex.heightAnchor.constraint(equalToConstant: 30).isActive = true
        guideNow.text = String(localized: "现在")
        guideNow.font = RecapTheme.body(9, weight: .semibold)
        guideNow.textColor = RecapTheme.quiet
        guideTitle.font = RecapTheme.body(12, weight: .semibold)
        guideTitle.textColor = RecapTheme.ink
        guideDetail.font = RecapTheme.body(11)
        guideDetail.textColor = RecapTheme.muted
        guideDetail.numberOfLines = 0
        let guideText = UIStackView(arrangedSubviews: [guideNow, guideTitle, guideDetail])
        guideText.axis = .vertical
        guideText.spacing = 2
        let guide = UIStackView(arrangedSubviews: [guideIndex, guideText])
        guide.axis = .horizontal
        guide.spacing = 10
        guide.alignment = .center
        guide.isLayoutMarginsRelativeArrangement = true
        guide.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 14)
        guideBackground.layer.cornerRadius = RecapTheme.radiusMD
        guideBackground.layer.cornerCurve = .continuous
        guideBackground.layer.borderWidth = 1
        guideBackground.layer.borderColor = RecapTheme.signal.withAlphaComponent(0.35).cgColor
        guideBackground.backgroundColor = RecapTheme.signalSoft.withAlphaComponent(0.5)
        guide.translatesAutoresizingMaskIntoConstraints = false
        guideBackground.addSubview(guide)
        NSLayoutConstraint.activate([
            guide.topAnchor.constraint(equalTo: guideBackground.topAnchor),
            guide.bottomAnchor.constraint(equalTo: guideBackground.bottomAnchor),
            guide.leadingAnchor.constraint(equalTo: guideBackground.leadingAnchor),
            guide.trailingAnchor.constraint(equalTo: guideBackground.trailingAnchor),
        ])
        guideArrow.translatesAutoresizingMaskIntoConstraints = false
        let guideColumn = UIView()
        guideBackground.translatesAutoresizingMaskIntoConstraints = false
        guideColumn.addSubview(guideBackground)
        guideColumn.addSubview(guideArrow)
        NSLayoutConstraint.activate([
            guideBackground.topAnchor.constraint(equalTo: guideColumn.topAnchor),
            guideBackground.leadingAnchor.constraint(equalTo: guideColumn.leadingAnchor),
            guideBackground.trailingAnchor.constraint(equalTo: guideColumn.trailingAnchor),
            guideArrow.topAnchor.constraint(equalTo: guideBackground.bottomAnchor, constant: 6),
            guideArrow.widthAnchor.constraint(equalToConstant: 10),
            guideArrow.heightAnchor.constraint(equalToConstant: 22),
            guideArrow.bottomAnchor.constraint(equalTo: guideColumn.bottomAnchor),
        ])
        let guideRow = UIStackView(arrangedSubviews: [UIView(), guideColumn])
        guideRow.axis = .horizontal

        guideBackground.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        guideBackground.setContentCompressionResistancePriority(.required, for: .vertical)

        let contentColumn = UIStackView(arrangedSubviews: [stageContent, guideRow])
        contentColumn.axis = .vertical
        contentColumn.spacing = 16

        // Steps with forms can outgrow the stage, especially in English; let them scroll
        let scroller = UIScrollView()
        scroller.showsVerticalScrollIndicator = false
        let centeringHost = UIView()
        centeringHost.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.translatesAutoresizingMaskIntoConstraints = false
        centeringHost.addSubview(contentColumn)
        scroller.addSubview(centeringHost)
        NSLayoutConstraint.activate([
            centeringHost.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            centeringHost.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            centeringHost.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            centeringHost.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            centeringHost.widthAnchor.constraint(equalTo: scroller.frameLayoutGuide.widthAnchor),
            // Short steps sit centred like the design; tall ones grow and scroll
            centeringHost.heightAnchor.constraint(greaterThanOrEqualTo: scroller.frameLayoutGuide.heightAnchor),
            contentColumn.leadingAnchor.constraint(equalTo: centeringHost.leadingAnchor, constant: 20),
            contentColumn.trailingAnchor.constraint(equalTo: centeringHost.trailingAnchor, constant: -20),
            contentColumn.centerYAnchor.constraint(equalTo: centeringHost.centerYAnchor),
            contentColumn.topAnchor.constraint(greaterThanOrEqualTo: centeringHost.topAnchor),
        ])

        let stage = UIStackView(arrangedSubviews: [copyColumn, scroller])
        // Step content always draws above the copy column
        stage.bringSubviewToFront(scroller)
        stage.axis = .horizontal
        stage.spacing = 32
        stage.alignment = .fill

        // Footer: status left, actions right
        footerStatus.font = RecapTheme.body(10, weight: .semibold)
        footerStatus.textColor = RecapTheme.quiet
        savedNote.text = String(localized: "✓ 进度保存在这台 Mac")
        savedNote.font = RecapTheme.body(10)
        savedNote.textColor = RecapTheme.quiet
        savedNote.textAlignment = .center

        backButton.preferredBehavioralStyle = .pad
        var backConfig = UIButton.Configuration.plain()
        backConfig.attributedTitle = AttributedString(String(localized: "返回"), attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        backConfig.image = UIImage(systemName: "arrow.left",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        backConfig.imagePlacement = .leading
        backConfig.imagePadding = 8
        backConfig.background.strokeColor = RecapTheme.line
        backConfig.background.strokeWidth = 1
        backConfig.background.cornerRadius = 17
        backConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16)
        backButton.configuration = backConfig
        backButton.tintColor = RecapTheme.muted
        backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
        backButton.addAction(UIAction { [weak self] _ in self?.goBack() }, for: .touchUpInside)

        primaryButton.preferredBehavioralStyle = .pad
        var primaryConfig = UIButton.Configuration.filled()
        primaryConfig.baseBackgroundColor = RecapTheme.ink
        primaryConfig.baseForegroundColor = RecapTheme.paper
        primaryConfig.background.cornerRadius = 15
        primaryConfig.image = UIImage(systemName: "arrow.right",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        primaryConfig.imagePlacement = .trailing
        primaryConfig.imagePadding = 14
        primaryConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 18, bottom: 9, trailing: 18)
        primaryButton.configuration = primaryConfig
        primaryButton.tintColor = RecapTheme.paper
        primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 126).isActive = true
        primaryButton.layer.shadowColor = RecapTheme.ink.cgColor
        primaryButton.layer.shadowOpacity = 0.15
        primaryButton.layer.shadowRadius = 11
        primaryButton.layer.shadowOffset = CGSize(width: 0, height: 8)
        primaryButton.addAction(UIAction { [weak self] _ in self?.advance() }, for: .touchUpInside)

        let statusSide = UIStackView(arrangedSubviews: [footerStatus, UIView()])
        statusSide.axis = .horizontal
        let actionSide = UIStackView(arrangedSubviews: [UIView(), backButton, primaryButton])
        actionSide.axis = .horizontal
        actionSide.spacing = 10
        actionSide.alignment = .center

        let footer = UIStackView(arrangedSubviews: [statusSide, savedNote, actionSide])
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 16
        footer.heightAnchor.constraint(equalToConstant: 62).isActive = true
        statusSide.widthAnchor.constraint(equalTo: actionSide.widthAnchor).isActive = true

        let topRule = UIView()
        topRule.backgroundColor = RecapTheme.line
        topRule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let bottomRule = UIView()
        bottomRule.backgroundColor = RecapTheme.line
        bottomRule.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let root = UIStackView(arrangedSubviews: [header, topRule, stage, bottomRule, footer])
        root.axis = .vertical
        root.spacing = 18
        root.setCustomSpacing(0, after: header)
        root.setCustomSpacing(0, after: stage)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            // Aimed at the action it is pointing to, now that both share an ancestor
            guideArrow.centerXAnchor.constraint(equalTo: primaryButton.centerXAnchor),
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

    private func stepDot(_ item: Step) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        button.tag = item.rawValue + 1
        button.accessibilityLabel = item.navTitle
        var config = UIButton.Configuration.plain()
        config.contentInsets = .zero
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in
            guard let self, item.rawValue <= self.maxReachable else { return }
            self.show(item, animated: true)
        }, for: .touchUpInside)

        let dot = UIView()
        dot.tag = 99
        dot.layer.cornerRadius = 5
        dot.layer.borderWidth = 1
        dot.isUserInteractionEnabled = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(dot)
        let dotWidth = dot.widthAnchor.constraint(equalToConstant: 10)
        dotWidths[item] = dotWidth
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
            dotWidth,
            dot.heightAnchor.constraint(equalToConstant: 10),
            dot.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        return button
    }

    private func refreshStepList() {
        for item in Step.setupSteps {
            guard let button = stepList.arrangedSubviews.compactMap({ $0 as? UIButton })
                .first(where: { $0.tag == item.rawValue + 1 }),
                  let dot = button.viewWithTag(99) else { continue }
            let passed = item.rawValue < step.rawValue
            let isCurrent = item == step
            dot.backgroundColor = passed || isCurrent ? RecapTheme.signal : RecapTheme.paper
            dot.layer.borderColor = (passed || isCurrent ? RecapTheme.signal : RecapTheme.line).cgColor
            UIView.animate(withDuration: 0.28) {
                self.dotWidths[item]?.constant = isCurrent ? 26 : 10
                self.view.layoutIfNeeded()
            }
            button.isEnabled = item.rawValue <= maxReachable
        }
        let total = Step.setupSteps.count
        let shown = min(step.rawValue + 1, total)
        progressCount.text = "\(shown) / \(total)"
        footerStatus.text = step == .done
            ? String(localized: "设置完成")
            : String(localized: "第 \(shown) 步，共 \(total) 步")
        view.layoutIfNeeded()
        let ratio = CGFloat(step.rawValue) / CGFloat(total - 1)
        progressFillWidth?.constant = progressTrack.bounds.width * min(ratio, 1)
        UIView.animate(withDuration: 0.28) { self.view.layoutIfNeeded() }
    }

    // MARK: - Navigation

    private func show(_ target: Step, animated: Bool) {
        step = target
        maxReachable = max(maxReachable, target.rawValue)
        Settings.onboardingStep = target.rawValue

        let hasLecture = outcome.lecture != nil
        stageEyebrow.text = target.eyebrow
        stageTitle.text = target == .done
            ? (hasLecture ? String(localized: "第一讲开始转写了。") : String(localized: "Recap 准备好了。"))
            : target.title
        stageDescription.text = target == .done
            ? (hasLecture
                ? String(localized: "完成后，文稿和重点会出现在课程里。")
                : String(localized: "有资料时，再从课程里添加音频或视频。"))
            : target.detail
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

        backButton.isEnabled = target != .welcome && target != .done
        backButton.alpha = backButton.isEnabled ? 1 : 0.38
        guideBackground.isHidden = target == .done
        guideArrow.isHidden = target == .done
        refreshStepList()
        refreshPrimary()

        if animated {
            // stage-enter: the design lifts each step in from 14px below
            for piece in [stageCopy, stepView] as [UIView] {
                piece.alpha = 0
                piece.transform = CGAffineTransform(translationX: 0, y: 14)
                UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut]) {
                    piece.alpha = 1
                    piece.transform = .identity
                }
            }
            breathe(primaryButton, delay: 0.9)
            breathe(guideBackground, delay: 0.5)
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
        case .done: view = OnboardingDoneStep(host: self)
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

    // action-breathe / guide-breathe: two soft lifts pointing at what to do next
    private func breathe(_ view: UIView, delay: TimeInterval) {
        let lift = CABasicAnimation(keyPath: "transform.translation.y")
        lift.fromValue = 0
        lift.toValue = -2
        lift.duration = 0.6
        lift.beginTime = CACurrentMediaTime() + delay
        lift.autoreverses = true
        lift.repeatCount = 2
        lift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(lift, forKey: "breathe")
    }

    private func refreshPrimary() {
        let stepView = stepViews[step]
        let title = stepView?.primaryTitle ?? String(localized: "继续")
        let attributed = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        if primaryButton.configuration?.attributedTitle != attributed {
            UIView.transition(with: primaryButton, duration: 0.22, options: [.transitionCrossDissolve]) {
                self.primaryButton.configuration?.attributedTitle = attributed
            }
        }
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
                self.show(.done, animated: true)
            }
        }
    }

    // MARK: - Completion

    var recordedCourse: Course? { outcome.course }
    var recordedLecture: Lecture? { outcome.lecture }

    // The finished stage can send the user back for one more lecture
    func returnToLectureStep() {
        stepViews[.done] = nil
        show(.lecture, animated: true)
    }

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

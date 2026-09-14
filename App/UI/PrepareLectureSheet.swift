//
//  PrepareLectureSheet.swift
//  Recap
//
//  Created by Rio on 2026/9/15.
//

import UIKit

// Key points and lecture notes are the same question asked twice — what to make, and
// which path makes it — so they are chosen once here. Notes need key points first, and
// this keeps that order instead of leaving it to the user.
final class PrepareLectureSheet: UIViewController {

    enum Channel {
        case cli, api
    }

    struct Plan {
        var extractKeyPoints: Bool
        var generateHandout: Bool
        var channel: Channel
    }

    private let hasKeyPoints: Bool
    private let hasHandout: Bool
    private var plan: Plan
    private let optionsStack = UIStackView()
    private var startButton = UIButton(type: .system)

    var onStart: ((Plan) -> Void)?

    init(hasKeyPoints: Bool, hasHandout: Bool, preferred: Channel) {
        self.hasKeyPoints = hasKeyPoints
        self.hasHandout = hasHandout
        // Whatever is missing is what this lecture still needs
        plan = Plan(extractKeyPoints: !hasKeyPoints, generateHandout: !hasHandout, channel: preferred)
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "整理这一讲")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "取消"), primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            })

        optionsStack.axis = .vertical
        optionsStack.spacing = 8

        startButton.preferredBehavioralStyle = .pad
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RecapTheme.ink
        config.background.cornerRadius = RecapTheme.radiusSM
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 18, bottom: 9, trailing: 18)
        startButton.configuration = config
        startButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let plan = self.plan
            self.dismiss(animated: true) { self.onStart?(plan) }
        }, for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [UIView(), startButton])
        footer.axis = .horizontal

        let stack = UIStackView(arrangedSubviews: [optionsStack, footer])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        rebuild()
    }

    private func rebuild() {
        optionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        optionsStack.addArrangedSubview(sectionLabel(String(localized: "做什么")))
        optionsStack.addArrangedSubview(checkRow(
            title: String(localized: "提取考试重点"),
            detail: hasKeyPoints ? String(localized: "已有重点，重新提取会覆盖") : String(localized: "从转写稿里找出老师强调的内容"),
            isOn: plan.extractKeyPoints
        ) { [weak self] in
            self?.plan.extractKeyPoints.toggle()
            self?.rebuild()
        })
        optionsStack.addArrangedSubview(checkRow(
            title: String(localized: "生成讲义 PDF"),
            detail: hasHandout ? String(localized: "已有讲义，重新生成会覆盖") : String(localized: "按内置 skill 排版成 LaTeX 讲义"),
            isOn: plan.generateHandout
        ) { [weak self] in
            self?.plan.generateHandout.toggle()
            self?.rebuild()
        })

        optionsStack.addArrangedSubview(sectionLabel(String(localized: "用哪条路")))
        optionsStack.addArrangedSubview(checkRow(
            title: String(localized: "CLI agent"),
            detail: String(localized: "在课程目录里跑你已装的 claude / codex，用它们自己的订阅"),
            isOn: plan.channel == .cli, isRadio: true
        ) { [weak self] in
            self?.plan.channel = .cli
            self?.rebuild()
        })
        optionsStack.addArrangedSubview(checkRow(
            title: String(localized: "API 接口"),
            detail: String(localized: "用设置里配置的 OpenAI-compatible 接口"),
            isOn: plan.channel == .api, isRadio: true
        ) { [weak self] in
            self?.plan.channel = .api
            self?.rebuild()
        })

        var title = AttributedString(String(localized: "开始"))
        title.font = RecapTheme.body(13, weight: .semibold)
        title.foregroundColor = RecapTheme.paper
        startButton.configuration?.attributedTitle = title
        startButton.isEnabled = plan.extractKeyPoints || plan.generateHandout
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = RecapTheme.body(11, weight: .semibold)
        label.textColor = RecapTheme.quiet
        return label
    }

    private func checkRow(title: String, detail: String, isOn: Bool,
                          isRadio: Bool = false, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        button.contentHorizontalAlignment = .leading
        var config = UIButton.Configuration.plain()
        let mark = isRadio ? (isOn ? "◉" : "○") : (isOn ? "☑︎" : "☐")
        config.attributedTitle = AttributedString("\(mark)  \(title)", attributes: AttributeContainer([
            .font: RecapTheme.body(12.5, weight: isOn ? .semibold : .regular),
            .foregroundColor: RecapTheme.ink,
        ]))
        config.attributedSubtitle = AttributedString(detail, attributes: AttributeContainer([
            .font: RecapTheme.body(10.5), .foregroundColor: RecapTheme.muted,
        ]))
        config.titleAlignment = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11)
        config.background.cornerRadius = RecapTheme.radiusMD
        config.background.backgroundColor = isOn ? RecapTheme.selection : .clear
        button.configuration = config
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

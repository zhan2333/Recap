//
//  OnboardingStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

extension OnboardingViewController.Step {

    var navTitle: String {
        switch self {
        case .welcome: String(localized: "认识 Recap")
        case .model: String(localized: "本地转写")
        case .ai: String(localized: "自动重点")
        case .course: String(localized: "课程")
        case .lecture: String(localized: "第一讲")
        case .done: String(localized: "完成")
        }
    }

    var navDetail: String {
        switch self {
        case .welcome: String(localized: "从结果开始")
        case .model: String(localized: "准备一次")
        case .ai: String(localized: "可选")
        case .course: String(localized: "起个名字")
        case .lecture: String(localized: "音频或视频")
        case .done: ""
        }
    }

    var eyebrow: String {
        switch self {
        case .welcome: String(localized: "欢迎使用 Recap")
        case .model: String(localized: "第 2 步 · 约 1.5 GB")
        case .ai: String(localized: "第 3 步 · 可选")
        case .course: String(localized: "第 4 步")
        case .lecture: String(localized: "第 5 步")
        case .done: String(localized: "设置完成")
        }
    }

    var title: String {
        switch self {
        case .welcome: String(localized: "一节课，变成一条复习路径。")
        case .model: String(localized: "下载一次，以后都在本机转写。")
        case .ai: String(localized: "要自动整理重点吗？")
        case .course: String(localized: "这门课叫什么？")
        case .lecture: String(localized: "添加第一讲。")
        case .done: ""
        }
    }

    var detail: String {
        switch self {
        case .welcome: String(localized: "音视频变成文稿；每条重点都能回到老师原话。")
        case .model: String(localized: "课程音视频不会在这一步被上传。")
        case .ai: String(localized: "可以先只用文稿，之后再连接 AI 服务。")
        case .course: String(localized: "相关讲次会自动收进同一个课程。")
        case .lecture: String(localized: "选择这台 Mac 上的一段课程音频或视频。")
        case .done: ""
        }
    }

    var guideTitle: String {
        switch self {
        case .welcome: String(localized: "沿着这条线看")
        case .model: String(localized: "下载转写文件")
        case .ai: String(localized: "选择一条路径")
        case .course: String(localized: "输入课程名")
        case .lecture: String(localized: "选择一个文件")
        case .done: ""
        }
    }

    var guideDetail: String {
        switch self {
        case .welcome: String(localized: "不需要选择，也不用记住术语。")
        case .model: String(localized: "以后无需重复下载。")
        case .ai: String(localized: "默认只在本机生成文稿。")
        case .course: String(localized: "名称只保存在本机，也可以稍后修改。")
        case .lecture: String(localized: "也可以切换到回放直链。")
        case .done: ""
        }
    }
}

// MARK: - Step view

class OnboardingStepView: UIView {

    enum PrimaryResult {
        case stay, next, finish
    }

    weak var host: OnboardingViewController?
    var onStateChange: (() -> Void)?
    // Skipping leaves the step without running its primary action
    var requestAdvance: (() -> Void)?

    var primaryTitle: String { String(localized: "继续") }
    var isPrimaryEnabled: Bool { true }

    init(host: OnboardingViewController?) {
        self.host = host
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func build() {}

    func performPrimary(_ completion: @escaping (PrimaryResult) -> Void) {
        completion(.next)
    }

    // MARK: - Shared building blocks

    func stack(_ views: [UIView], spacing: CGFloat = 12) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }

    func fill(with content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // Choice cards keep their identity so selection restyles instead of rebuilding
    func optionCard(title: String, detail: String, meta: String? = nil, selected: Bool,
                    action: @escaping () -> Void) -> OnboardingChoiceCard {
        let card = OnboardingChoiceCard(title: title, detail: detail, meta: meta)
        card.isChosen = selected
        card.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return card
    }

    // Layout changes ripple through a centred scroll area, so animate them
    func animateContentChange(_ changes: () -> Void) {
        changes()
        guard let root = host?.view else { return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            root.layoutIfNeeded()
        }
    }

    func secondaryAction(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(11, weight: .semibold), .foregroundColor: RecapTheme.muted,
        ]))
        config.background.strokeColor = RecapTheme.line
        config.background.strokeWidth = 1
        config.background.cornerRadius = 13
        config.background.backgroundColor = RecapTheme.paper
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        button.configuration = config
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    func textAction(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.preferredBehavioralStyle = .pad
        button.contentHorizontalAlignment = .leading
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(11.5), .foregroundColor: RecapTheme.signalText,
        ]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
        button.configuration = config
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    func field(label: String, placeholder: String, secure: Bool = false, value: String = "",
               onChange: @escaping (String) -> Void) -> UIView {
        let caption = UILabel()
        caption.text = label
        caption.font = RecapTheme.body(11, weight: .semibold)
        caption.textColor = RecapTheme.muted

        let input = UITextField()
        input.text = value
        input.placeholder = placeholder
        input.font = RecapTheme.body(12.5)
        input.textColor = RecapTheme.ink
        input.isSecureTextEntry = secure
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.backgroundColor = RecapTheme.surface.withAlphaComponent(0.6)
        input.layer.cornerRadius = RecapTheme.radiusSM
        input.layer.cornerCurve = .continuous
        input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        input.leftViewMode = .always
        input.heightAnchor.constraint(equalToConstant: 32).isActive = true
        input.addAction(UIAction { _ in onChange(input.text ?? "") }, for: .editingChanged)

        let row = UIStackView(arrangedSubviews: [caption, input])
        row.axis = .vertical
        row.spacing = 5
        return row
    }

    func note(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = RecapTheme.body(10.5)
        label.textColor = RecapTheme.quiet
        label.numberOfLines = 0
        return label
    }

    func errorLabel() -> UILabel {
        let label = UILabel()
        label.font = RecapTheme.body(11, weight: .semibold)
        label.textColor = RecapTheme.error
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }
}

// MARK: - Choice card

final class OnboardingChoiceCard: UIControl {

    private let indicator = UILabel()

    var isChosen = false {
        didSet { applySelection(animated: true) }
    }

    init(title: String, detail: String, meta: String?) {
        super.init(frame: .zero)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        indicator.font = RecapTheme.body(10, weight: .bold)
        indicator.textAlignment = .center
        indicator.layer.cornerRadius = 10
        indicator.layer.masksToBounds = true
        indicator.layer.borderWidth = 1

        let name = UILabel()
        name.text = title
        name.font = RecapTheme.body(12, weight: .semibold)
        name.textColor = RecapTheme.ink
        let caption = UILabel()
        caption.text = detail
        caption.font = RecapTheme.body(10)
        caption.textColor = RecapTheme.muted
        caption.numberOfLines = 2
        let text = UIStackView(arrangedSubviews: [name, caption])
        text.axis = .vertical
        text.spacing = 3

        var pieces: [UIView] = [indicator, text]
        if let meta {
            let metaLabel = UILabel()
            metaLabel.text = meta
            metaLabel.font = RecapTheme.body(9, weight: .semibold)
            metaLabel.textColor = RecapTheme.signalText
            pieces.append(UIView())
            pieces.append(metaLabel)
        }
        let row = UIStackView(arrangedSubviews: pieces)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 11
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            indicator.widthAnchor.constraint(equalToConstant: 20),
            indicator.heightAnchor.constraint(equalToConstant: 20),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        applySelection(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applySelection(animated: Bool) {
        let apply = {
            self.backgroundColor = self.isChosen ? RecapTheme.signalSoft : RecapTheme.paper
            self.layer.borderColor = (self.isChosen ? RecapTheme.signal.withAlphaComponent(0.32) : RecapTheme.line).cgColor
            self.indicator.backgroundColor = self.isChosen ? RecapTheme.ink : .clear
            self.indicator.layer.borderColor = (self.isChosen ? RecapTheme.ink : RecapTheme.line).cgColor
            self.indicator.textColor = RecapTheme.paper
        }
        guard animated else {
            apply()
            indicator.text = isChosen ? "✓" : ""
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: apply)
        UIView.transition(with: indicator, duration: 0.22, options: [.transitionCrossDissolve]) {
            self.indicator.text = self.isChosen ? "✓" : ""
        }
        // The chosen card gives a small settle, like the design's selection feedback
        if isChosen {
            UIView.animate(withDuration: 0.16, animations: { self.transform = CGAffineTransform(scaleX: 1.012, y: 1.012) }) { _ in
                UIView.animate(withDuration: 0.2) { self.transform = .identity }
            }
        }
    }
}


extension UIView {
    convenience init(width: CGFloat) {
        self.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }
}

//
//  OnboardingScene.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

// The framed panel every journey diagram sits in
final class OnboardingScene: UIView {

    init(pieces: [UIView], spacing: CGFloat = 0, minHeight: CGFloat = 176) {
        super.init(frame: .zero)
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = RecapTheme.line.cgColor
        backgroundColor = RecapTheme.surface.withAlphaComponent(0.4)

        let row = UIStackView(arrangedSubviews: pieces)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}


// Scaling from the left edge without touching anchorPoint, which Auto Layout would fight
private func leftEdgeScale(_ view: UIView, _ scale: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: -view.bounds.width * (1 - scale) / 2, y: 0).scaledBy(x: scale, y: 1)
}

// MARK: - Thread

// A signal line that draws itself, with a node travelling along it
final class OnboardingThread: UIView {

    private let line = UIView()
    private let node = UIView()
    private let distance: CGFloat

    init(distance: CGFloat = 70) {
        self.distance = distance
        super.init(frame: .zero)
        line.backgroundColor = RecapTheme.signal
        node.backgroundColor = RecapTheme.signal
        node.layer.cornerRadius = 3.5
        for piece in [line, node] {
            piece.translatesAutoresizingMaskIntoConstraints = false
            addSubview(piece)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: distance),
            heightAnchor.constraint(equalToConstant: 14),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 2),
            node.widthAnchor.constraint(equalToConstant: 7),
            node.heightAnchor.constraint(equalToConstant: 7),
            node.centerYAnchor.constraint(equalTo: centerYAnchor),
            node.centerXAnchor.constraint(equalTo: leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        layoutIfNeeded()
        line.transform = leftEdgeScale(line, 0.001)
        line.alpha = 0.35
        node.alpha = 0
        UIView.animate(withDuration: 0.52, delay: 0.26, options: [.curveEaseInOut]) {
            self.line.transform = .identity
            self.line.alpha = 1
        }
        UIView.animate(withDuration: 0.52, delay: 0.32, options: [.curveEaseInOut]) {
            self.node.alpha = 1
            self.node.transform = CGAffineTransform(translationX: self.distance, y: 0)
        }
    }
}

// MARK: - Step 2 pieces

// The downloadable model, drawn as a file card that hovers twice
final class OnboardingFileCard: UIView {

    init(glyph: String, size: String) {
        super.init(frame: .zero)
        backgroundColor = RecapTheme.paper
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
        layer.borderWidth = 1
        layer.borderColor = RecapTheme.line.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let mark = UILabel()
        mark.text = glyph
        mark.font = RecapTheme.display(28, weight: .medium)
        mark.textColor = RecapTheme.ink
        let caption = UILabel()
        caption.text = size
        caption.font = RecapTheme.body(8, weight: .bold)
        caption.textColor = RecapTheme.signalText

        let rules = UIStackView(arrangedSubviews: (0..<3).map { _ in Self.rule() })
        rules.axis = .vertical
        rules.spacing = 4

        for piece in [mark, caption, rules] as [UIView] {
            piece.translatesAutoresizingMaskIntoConstraints = false
            addSubview(piece)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 94),
            heightAnchor.constraint(equalToConstant: 112),
            caption.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            mark.centerXAnchor.constraint(equalTo: centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            rules.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            rules.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            rules.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func rule() -> UIView {
        let rule = UIView()
        rule.backgroundColor = RecapTheme.line
        rule.heightAnchor.constraint(equalToConstant: 2).isActive = true
        return rule
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, layer.animation(forKey: "hover") == nil else { return }
        let hover = CAKeyframeAnimation(keyPath: "transform")
        hover.values = [
            CATransform3DMakeRotation(-0.017, 0, 0, 1),
            CATransform3DConcat(CATransform3DMakeTranslation(0, -7, 0), CATransform3DMakeRotation(0.017, 0, 0, 1)),
            CATransform3DMakeRotation(-0.017, 0, 0, 1),
        ]
        hover.keyTimes = [0, 0.5, 1]
        hover.duration = 1.1
        hover.repeatCount = 2
        hover.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(hover, forKey: "hover")
    }
}

// This Mac: a bordered screen on a foot, with text lines revealing inside
final class OnboardingMacFrame: UIView {

    private let lines: [UIView]

    init(badge: String) {
        lines = (0..<3).map { _ in UIView() }
        super.init(frame: .zero)

        let screen = UIView()
        screen.backgroundColor = RecapTheme.paper
        screen.layer.cornerRadius = 18
        screen.layer.cornerCurve = .continuous
        screen.layer.borderWidth = 2
        screen.layer.borderColor = RecapTheme.ink.cgColor

        for (index, line) in lines.enumerated() {
            line.backgroundColor = index == 2 ? RecapTheme.signal.withAlphaComponent(0.55) : RecapTheme.line
            line.layer.cornerRadius = 2.5
        }
        let stack = UIStackView(arrangedSubviews: lines)
        stack.axis = .vertical
        stack.spacing = 8
        stack.distribution = .fillEqually

        let foot = UIView()
        foot.backgroundColor = RecapTheme.ink
        foot.layer.cornerRadius = 2

        let pill = UILabel()
        pill.text = badge
        pill.font = RecapTheme.body(9, weight: .bold)
        pill.textColor = RecapTheme.complete
        pill.textAlignment = .center
        pill.backgroundColor = RecapTheme.completeSoft
        pill.layer.cornerRadius = 9
        pill.layer.masksToBounds = true

        for piece in [screen, foot, stack, pill] as [UIView] {
            piece.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(screen)
        addSubview(foot)
        screen.addSubview(stack)
        screen.addSubview(pill)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 138),
            heightAnchor.constraint(equalToConstant: 108),
            screen.topAnchor.constraint(equalTo: topAnchor),
            screen.leadingAnchor.constraint(equalTo: leadingAnchor),
            screen.trailingAnchor.constraint(equalTo: trailingAnchor),
            screen.heightAnchor.constraint(equalToConstant: 98),
            foot.topAnchor.constraint(equalTo: screen.bottomAnchor, constant: -1),
            foot.centerXAnchor.constraint(equalTo: centerXAnchor),
            foot.widthAnchor.constraint(equalToConstant: 54),
            foot.heightAnchor.constraint(equalToConstant: 8),
            stack.topAnchor.constraint(equalTo: screen.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: screen.leadingAnchor, constant: 14),
            stack.widthAnchor.constraint(equalTo: screen.widthAnchor, multiplier: 0.7),
            stack.heightAnchor.constraint(equalToConstant: 26),
            pill.trailingAnchor.constraint(equalTo: screen.trailingAnchor, constant: -12),
            pill.bottomAnchor.constraint(equalTo: screen.bottomAnchor, constant: -10),
            pill.heightAnchor.constraint(equalToConstant: 18),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 66),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        layoutIfNeeded()
        for line in lines {
            line.transform = leftEdgeScale(line, 0.2)
            line.alpha = 0
        }
        UIView.animate(withDuration: 0.62, delay: 0.6, options: [.curveEaseOut]) {
            self.lines.forEach {
                $0.transform = .identity
                $0.alpha = 1
            }
        }
    }
}

// MARK: - Step 3 pieces

// A transcript page, drawn as ruled lines on a card
final class OnboardingDocumentCard: UIView {

    init(width: CGFloat = 112, height: CGFloat = 132, ruleCount: Int = 4) {
        super.init(frame: .zero)
        backgroundColor = RecapTheme.paper
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
        layer.borderWidth = 1
        layer.borderColor = RecapTheme.line.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let rules = UIStackView(arrangedSubviews: (0..<ruleCount).map { _ in
            let rule = UIView()
            rule.backgroundColor = RecapTheme.line
            rule.layer.cornerRadius = 2.5
            rule.heightAnchor.constraint(equalToConstant: 5).isActive = true
            return rule
        })
        rules.axis = .vertical
        rules.spacing = 13
        rules.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rules)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
            rules.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            rules.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            rules.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// The line that splits in two, drawn as the design's rounded fork
final class OnboardingBranchThread: UIView {

    private let shape = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        shape.strokeColor = RecapTheme.signal.cgColor
        shape.lineWidth = 2
        shape.fillColor = nil
        layer.addSublayer(shape)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 84),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        let middle = height / 2
        let radius: CGFloat = 16
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: middle))
        path.addLine(to: CGPoint(x: width / 2, y: middle))
        path.move(to: CGPoint(x: width / 2, y: middle))
        path.addArc(withCenter: CGPoint(x: width / 2, y: middle - radius), radius: radius,
                    startAngle: .pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: width / 2 + radius, y: 1))
        path.move(to: CGPoint(x: width / 2, y: middle))
        path.addArc(withCenter: CGPoint(x: width / 2, y: middle + radius), radius: radius,
                    startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: width / 2 + radius, y: height - 1))
        shape.path = path.cgPath
        shape.frame = bounds
        guard shape.animation(forKey: "draw") == nil, window != nil else { return }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.52
        draw.beginTime = CACurrentMediaTime() + 0.26
        draw.fillMode = .backwards
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shape.add(draw, forKey: "draw")
    }
}

// The two outcomes of step 3, revealed one after the other
final class OnboardingBranchResults: UIView {

    private var cards: [UIView] = []

    init(first: String, second: String) {
        super.init(frame: .zero)
        cards = [Self.card(first, tinted: false), Self.card(second, tinted: true)]
        let stack = UIStackView(arrangedSubviews: cards)
        stack.axis = .vertical
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 200),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func card(_ text: String, tinted: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = RecapTheme.paper
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = (tinted ? RecapTheme.signal.withAlphaComponent(0.35) : RecapTheme.line).cgColor

        let label = UILabel()
        label.text = text
        label.font = RecapTheme.body(12, weight: .semibold)
        label.textColor = tinted ? RecapTheme.signalText : RecapTheme.muted
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        return container
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        for (index, card) in cards.enumerated() {
            card.alpha = 0
            UIView.animate(withDuration: 0.36, delay: 0.5 + Double(index) * 0.22) {
                card.alpha = 1
            }
        }
    }
}

// MARK: - Step 4 and 5 pieces

// Loose lectures settling into a pile
final class OnboardingPaperStack: UIView {

    private let papers: [UIView]

    override init(frame: CGRect) {
        papers = (0..<3).map { _ in UIView() }
        super.init(frame: frame)
        let offsets: [(x: CGFloat, y: CGFloat, angle: CGFloat)] = [(2, 4, -8), (20, 15, 5), (10, 24, -1)]
        for (paper, offset) in zip(papers, offsets) {
            paper.backgroundColor = RecapTheme.paper
            paper.layer.cornerRadius = 13
            paper.layer.cornerCurve = .continuous
            paper.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
            paper.layer.borderWidth = 1
            paper.layer.borderColor = RecapTheme.line.cgColor
            paper.layer.shadowColor = UIColor.black.cgColor
            paper.layer.shadowOpacity = 0.06
            paper.layer.shadowRadius = 9
            paper.layer.shadowOffset = CGSize(width: 0, height: 4)
            paper.frame = CGRect(x: offset.x, y: offset.y, width: 82, height: 58)
            paper.transform = CGAffineTransform(rotationAngle: offset.angle * .pi / 180)
            addSubview(paper)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 118),
            heightAnchor.constraint(equalToConstant: 86),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        for (index, paper) in papers.enumerated() {
            let settled = paper.transform
            paper.alpha = 0
            paper.transform = settled.concatenating(CGAffineTransform(translationX: 0, y: -18))
            UIView.animate(withDuration: 0.46, delay: Double(index) * 0.09,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0.2) {
                paper.alpha = 1
                paper.transform = settled
            }
        }
    }
}

// Where lectures land: a folder with a tab, in signal tint
final class OnboardingFolder: UIView {

    init(title: String, detail: String) {
        super.init(frame: .zero)
        let surface = RecapTheme.signalSoft
        let border = RecapTheme.signal.withAlphaComponent(0.38)

        let tab = UIView()
        tab.backgroundColor = surface
        tab.layer.cornerRadius = 10
        tab.layer.cornerCurve = .continuous
        tab.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tab.layer.borderWidth = 1
        tab.layer.borderColor = border.cgColor

        let body = UIView()
        body.backgroundColor = surface
        body.layer.cornerRadius = 22
        body.layer.cornerCurve = .continuous
        body.layer.borderWidth = 1
        body.layer.borderColor = border.cgColor

        let name = UILabel()
        name.text = title
        name.font = RecapTheme.display(16, weight: .semibold)
        name.textColor = RecapTheme.ink
        name.numberOfLines = 2
        let caption = UILabel()
        caption.text = detail
        caption.font = RecapTheme.body(10)
        caption.textColor = RecapTheme.muted
        let text = UIStackView(arrangedSubviews: [name, caption])
        text.axis = .vertical
        text.spacing = 8

        for piece in [tab, body, text] as [UIView] {
            piece.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(tab)
        addSubview(body)
        body.addSubview(text)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 232),
            tab.topAnchor.constraint(equalTo: topAnchor),
            tab.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tab.widthAnchor.constraint(equalToConstant: 64),
            tab.heightAnchor.constraint(equalToConstant: 12),
            body.topAnchor.constraint(equalTo: tab.bottomAnchor, constant: -1),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 114),
            text.topAnchor.constraint(greaterThanOrEqualTo: body.topAnchor, constant: 20),
            text.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 18),
            text.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -18),
            text.centerYAnchor.constraint(equalTo: body.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// The media file being dropped in
final class OnboardingMediaChip: UIView {

    init(label: String) {
        super.init(frame: .zero)
        backgroundColor = RecapTheme.ink
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let play = UILabel()
        play.text = "▶"
        play.font = RecapTheme.body(8)
        play.textColor = RecapTheme.paper
        play.textAlignment = .center
        play.layer.borderWidth = 1
        play.layer.borderColor = UIColor.white.withAlphaComponent(0.36).cgColor
        play.layer.cornerRadius = 16

        let caption = UILabel()
        caption.text = label
        caption.font = RecapTheme.body(8, weight: .semibold)
        caption.textColor = RecapTheme.paper.withAlphaComponent(0.7)

        let stack = UIStackView(arrangedSubviews: [play, caption])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 84),
            heightAnchor.constraint(equalToConstant: 104),
            play.widthAnchor.constraint(equalToConstant: 32),
            play.heightAnchor.constraint(equalToConstant: 32),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        alpha = 0
        transform = CGAffineTransform(translationX: 64, y: -22).rotated(by: 5 * .pi / 180)
        UIView.animate(withDuration: 0.76, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3) {
            self.alpha = 1
            self.transform = .identity
        }
    }
}

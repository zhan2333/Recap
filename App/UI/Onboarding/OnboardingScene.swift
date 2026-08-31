//
//  OnboardingScene.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

// The design's journey diagrams: something enters on the left, a thread draws, a result lands
final class OnboardingScene: UIView {

    private let thread = CAShapeLayer()
    private let travelling = CALayer()
    private let leading: UIView
    private let trailing: UIView
    private let threadHost = UIView()

    init(leading: UIView, trailing: UIView) {
        self.leading = leading
        self.trailing = trailing
        super.init(frame: .zero)

        thread.strokeColor = RecapTheme.signal.withAlphaComponent(0.75).cgColor
        thread.lineWidth = 1.5
        thread.lineCap = .round
        thread.fillColor = nil
        threadHost.layer.addSublayer(thread)
        travelling.backgroundColor = RecapTheme.signal.cgColor
        travelling.cornerRadius = 2.5
        travelling.frame = CGRect(x: 0, y: 0, width: 5, height: 5)
        threadHost.layer.addSublayer(travelling)

        // The design frames every diagram in a rounded panel
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = RecapTheme.line.cgColor
        backgroundColor = RecapTheme.surface.withAlphaComponent(0.4)
        clipsToBounds = true

        let row = UIStackView(arrangedSubviews: [leading, threadHost, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 0
        threadHost.widthAnchor.constraint(equalToConstant: 64).isActive = true
        threadHost.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 22),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard threadHost.bounds.width > 0 else { return }
        let middle = threadHost.bounds.midY
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: middle))
        path.addLine(to: CGPoint(x: threadHost.bounds.width, y: middle))
        thread.path = path.cgPath
        thread.frame = threadHost.bounds
        travelling.position = CGPoint(x: 0, y: middle)
        guard thread.animation(forKey: "draw") == nil else { return }
        animateThread(along: path, middle: middle)
    }

    private func animateThread(along path: UIBezierPath, middle: CGFloat) {
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.6
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        thread.add(draw, forKey: "draw")

        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.path = path.cgPath
        travel.duration = 1.6
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        travelling.add(travel, forKey: "travel")
    }

    // MARK: - Pieces

    static func chip(_ title: String, detail: String? = nil, tinted: Bool = false) -> UIView {
        let container = UIView()
        container.backgroundColor = tinted ? RecapTheme.signalSoft : RecapTheme.surface.withAlphaComponent(0.75)
        container.layer.cornerRadius = RecapTheme.radiusSM
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = (tinted ? RecapTheme.signal.withAlphaComponent(0.3) : RecapTheme.line).cgColor

        let label = UILabel()
        label.text = title
        label.font = RecapTheme.body(11.5, weight: .semibold)
        label.textColor = RecapTheme.ink
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.spacing = 1
        if let detail {
            let sub = UILabel()
            sub.text = detail
            sub.font = RecapTheme.body(9.5)
            sub.textColor = RecapTheme.quiet
            sub.textAlignment = .center
            stack.addArrangedSubview(sub)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
        return container
    }

    // A stand-in for this Mac, so "stays on this device" is visible rather than stated
    static func macFrame(badge: String) -> UIView {
        let frame = UIView()
        frame.layer.cornerRadius = RecapTheme.radiusMD
        frame.layer.cornerCurve = .continuous
        frame.layer.borderWidth = 1.5
        frame.layer.borderColor = RecapTheme.line.cgColor
        frame.backgroundColor = RecapTheme.surface.withAlphaComponent(0.4)

        let label = UILabel()
        label.text = badge
        label.font = RecapTheme.body(10, weight: .semibold)
        label.textColor = RecapTheme.complete
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        frame.addSubview(label)
        NSLayoutConstraint.activate([
            frame.widthAnchor.constraint(equalToConstant: 96),
            frame.heightAnchor.constraint(equalToConstant: 62),
            label.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: frame.centerYAnchor),
        ])
        return frame
    }
}

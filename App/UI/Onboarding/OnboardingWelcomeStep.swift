//
//  OnboardingWelcomeStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit

// The product's own metaphor, drawn with the same parts the workspace uses
final class OnboardingWelcomeStep: OnboardingStepView {

    private let thread = CAShapeLayer()

    override func build() {
        let quoteCard = UIView()
        quoteCard.backgroundColor = RecapTheme.surface.withAlphaComponent(0.7)
        quoteCard.layer.cornerRadius = RecapTheme.radiusMD
        quoteCard.layer.cornerCurve = .continuous

        let source = UILabel()
        source.text = String(localized: "老师原话 · 00:43:06")
        source.font = RecapTheme.mono(10.5, weight: .semibold)
        source.textColor = RecapTheme.time
        let quote = UILabel()
        quote.text = String(localized: "「这一讲最重要的是反向传播：先沿计算图把梯度传回来，再更新参数，这两个步骤不要混。」")
        quote.font = RecapTheme.body(12.5)
        quote.textColor = RecapTheme.ink
        quote.numberOfLines = 0
        let quoteStack = UIStackView(arrangedSubviews: [source, quote])
        quoteStack.axis = .vertical
        quoteStack.spacing = 6
        quoteStack.translatesAutoresizingMaskIntoConstraints = false
        quoteCard.addSubview(quoteStack)
        NSLayoutConstraint.activate([
            quoteStack.topAnchor.constraint(equalTo: quoteCard.topAnchor, constant: 13),
            quoteStack.bottomAnchor.constraint(equalTo: quoteCard.bottomAnchor, constant: -13),
            quoteStack.leadingAnchor.constraint(equalTo: quoteCard.leadingAnchor, constant: 14),
            quoteStack.trailingAnchor.constraint(equalTo: quoteCard.trailingAnchor, constant: -14),
        ])

        let threadHost = UIView()
        threadHost.heightAnchor.constraint(equalToConstant: 30).isActive = true
        thread.strokeColor = RecapTheme.signal.cgColor
        thread.lineWidth = 1.5
        thread.lineCap = .round
        thread.fillColor = nil
        threadHost.layer.addSublayer(thread)

        let pointCard = UIView()
        pointCard.backgroundColor = RecapTheme.signalSoft
        pointCard.layer.cornerRadius = RecapTheme.radiusMD
        pointCard.layer.cornerCurve = .continuous
        let pointLabel = UILabel()
        pointLabel.text = String(localized: "重点")
        pointLabel.font = RecapTheme.body(10.5, weight: .semibold)
        pointLabel.textColor = RecapTheme.signalText
        let pointTitle = UILabel()
        pointTitle.text = String(localized: "反向传播")
        pointTitle.font = RecapTheme.body(13, weight: .semibold)
        pointTitle.textColor = RecapTheme.ink
        let takeaway = UILabel()
        takeaway.text = String(localized: "先求梯度，再更新参数")
        takeaway.font = RecapTheme.body(12)
        takeaway.textColor = RecapTheme.muted
        let pointStack = UIStackView(arrangedSubviews: [pointLabel, pointTitle, takeaway])
        pointStack.axis = .vertical
        pointStack.spacing = 3
        pointStack.translatesAutoresizingMaskIntoConstraints = false
        pointCard.addSubview(pointStack)
        NSLayoutConstraint.activate([
            pointStack.topAnchor.constraint(equalTo: pointCard.topAnchor, constant: 12),
            pointStack.bottomAnchor.constraint(equalTo: pointCard.bottomAnchor, constant: -12),
            pointStack.leadingAnchor.constraint(equalTo: pointCard.leadingAnchor, constant: 14),
            pointStack.trailingAnchor.constraint(equalTo: pointCard.trailingAnchor, constant: -14),
        ])

        fill(with: stack([quoteCard, threadHost, pointCard], spacing: 0))
        self.threadHost = threadHost
    }

    private weak var threadHost: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let threadHost, threadHost.bounds.width > 0 else { return }
        let path = UIBezierPath()
        let x = 26.0
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: threadHost.bounds.height))
        thread.path = path.cgPath
        thread.frame = threadHost.bounds
        guard thread.animation(forKey: "draw") == nil else { return }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.7
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        thread.add(draw, forKey: "draw")
    }
}

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
        quote.textColor = RecapTheme.muted
        quote.numberOfLines = 0
        let quoteStack = UIStackView(arrangedSubviews: [source, quote])
        quoteStack.axis = .vertical
        quoteStack.spacing = 6
        quoteStack.translatesAutoresizingMaskIntoConstraints = false
        quoteCard.addSubview(quoteStack)
        NSLayoutConstraint.activate([
            quoteStack.topAnchor.constraint(equalTo: quoteCard.topAnchor, constant: 18),
            quoteStack.bottomAnchor.constraint(equalTo: quoteCard.bottomAnchor, constant: -18),
            quoteStack.leadingAnchor.constraint(equalTo: quoteCard.leadingAnchor, constant: 18),
            quoteStack.trailingAnchor.constraint(equalTo: quoteCard.trailingAnchor, constant: -18),
        ])

        let threadHost = UIView()
        threadHost.widthAnchor.constraint(equalToConstant: 64).isActive = true
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
        pointLabel.font = RecapTheme.body(9.5, weight: .bold)
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
            pointStack.topAnchor.constraint(equalTo: pointCard.topAnchor, constant: 21),
            pointStack.bottomAnchor.constraint(equalTo: pointCard.bottomAnchor, constant: -21),
            pointStack.leadingAnchor.constraint(equalTo: pointCard.leadingAnchor, constant: 21),
            pointStack.trailingAnchor.constraint(equalTo: pointCard.trailingAnchor, constant: -21),
        ])

        quoteCard.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
        quoteCard.layer.cornerRadius = 18
        pointCard.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        pointCard.layer.cornerRadius = 18
        pointCard.layer.borderWidth = 1
        pointCard.layer.borderColor = RecapTheme.signal.withAlphaComponent(0.32).cgColor
        quoteCard.layer.borderWidth = 1
        quoteCard.layer.borderColor = RecapTheme.line.cgColor
        quoteCard.backgroundColor = RecapTheme.paper
        for card in [quoteCard, pointCard] {
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = 0.08
            card.layer.shadowRadius = 18
            card.layer.shadowOffset = CGSize(width: 0, height: 7)
        }
        // The corner facing the thread stays small, as in the design
        quoteCard.layer.cornerRadius = 22
        pointCard.layer.cornerRadius = 22

        let row = UIStackView(arrangedSubviews: [quoteCard, threadHost, pointCard])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 0
        quoteCard.widthAnchor.constraint(equalTo: pointCard.widthAnchor, multiplier: 1.15 / 0.85).isActive = true
        fill(with: row)
        self.threadHost = threadHost
    }

    private weak var threadHost: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let threadHost, threadHost.bounds.width > 0 else { return }
        let path = UIBezierPath()
        let y = threadHost.bounds.midY
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: threadHost.bounds.width, y: y))
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

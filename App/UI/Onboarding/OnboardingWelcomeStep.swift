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
        let preview = OnboardingSourcePreview(time: "00:43:06")
        let quoteStack = UIStackView(arrangedSubviews: [preview, source, quote])
        quoteStack.axis = .vertical
        quoteStack.spacing = 6
        quoteStack.setCustomSpacing(15, after: preview)
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

        self.pointCard = pointCard
        let row = UIStackView(arrangedSubviews: [quoteCard, threadHost, pointCard])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 0
        quoteCard.widthAnchor.constraint(equalTo: pointCard.widthAnchor, multiplier: 1.15 / 0.85).isActive = true
        fill(with: row)
        self.threadHost = threadHost
    }

    private weak var threadHost: UIView?
    private weak var pointCard: UIView?

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

        guard let pointCard else { return }
        pointCard.alpha = 0
        pointCard.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.42, delay: 0.52, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.2) {
            pointCard.alpha = 1
            pointCard.transform = .identity
        }
    }
}

// The clip this quote came from: a dark strip with a waveform and its timecode
final class OnboardingSourcePreview: UIView {

    private let waveform = WaveformView()

    init(time: String) {
        super.init(frame: .zero)
        backgroundColor = RecapTheme.ink
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let play = UILabel()
        play.text = "▶"
        play.font = RecapTheme.body(8)
        play.textColor = RecapTheme.paper
        play.textAlignment = .center
        play.layer.borderWidth = 1
        play.layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
        play.layer.cornerRadius = 14

        let stamp = UILabel()
        stamp.text = time
        stamp.font = RecapTheme.mono(9, weight: .semibold)
        stamp.textColor = UIColor.white.withAlphaComponent(0.72)

        let row = UIStackView(arrangedSubviews: [play, waveform, stamp])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 66),
            play.widthAnchor.constraint(equalToConstant: 28),
            play.heightAnchor.constraint(equalToConstant: 28),
            waveform.heightAnchor.constraint(equalToConstant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// The speaking waveform under the play control
final class WaveformView: UIView {

    private let bars: [UIView]

    override init(frame: CGRect) {
        bars = (0..<22).map { _ in UIView() }
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: bars)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 2
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.82)
            bar.layer.cornerRadius = 0.5
            let heights: [CGFloat] = [5, 11, 7, 14, 6, 16, 9, 12, 4, 15, 8, 13, 6, 10, 16, 7, 12, 5, 14, 9, 11, 6]
            bar.heightAnchor.constraint(equalToConstant: heights[index % heights.count]).isActive = true
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        for (index, bar) in bars.enumerated() {
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 0.55
            pulse.toValue = 1
            pulse.duration = 0.7
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.02
            pulse.autoreverses = true
            pulse.repeatCount = 3
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.layer.add(pulse, forKey: "speak")
        }
    }
}

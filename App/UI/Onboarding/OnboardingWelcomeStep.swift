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
    private let startRing = UIView()
    private let endRing = UIView()
    private let node = UIView()

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
        threadHost.heightAnchor.constraint(equalToConstant: 14).isActive = true
        for end in [startRing, endRing] {
            end.backgroundColor = RecapTheme.paper
            end.layer.borderWidth = 2
            end.layer.borderColor = RecapTheme.signal.cgColor
            end.layer.cornerRadius = 5
            end.translatesAutoresizingMaskIntoConstraints = false
            threadHost.addSubview(end)
            NSLayoutConstraint.activate([
                end.widthAnchor.constraint(equalToConstant: 10),
                end.heightAnchor.constraint(equalToConstant: 10),
                end.centerYAnchor.constraint(equalTo: threadHost.centerYAnchor),
            ])
        }
        startRing.centerXAnchor.constraint(equalTo: threadHost.leadingAnchor).isActive = true
        endRing.centerXAnchor.constraint(equalTo: threadHost.trailingAnchor).isActive = true
        node.backgroundColor = RecapTheme.signal
        node.layer.cornerRadius = 3.5
        node.translatesAutoresizingMaskIntoConstraints = false
        threadHost.addSubview(node)
        NSLayoutConstraint.activate([
            node.widthAnchor.constraint(equalToConstant: 7),
            node.heightAnchor.constraint(equalToConstant: 7),
            node.centerYAnchor.constraint(equalTo: threadHost.centerYAnchor),
            node.centerXAnchor.constraint(equalTo: threadHost.leadingAnchor),
        ])
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

        node.alpha = 0
        node.transform = .identity
        UIView.animate(withDuration: 0.62, delay: 0.26, options: [.curveEaseInOut]) {
            self.node.alpha = 1
            self.node.transform = CGAffineTransform(translationX: threadHost.bounds.width, y: 0)
        }

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
        backgroundColor = UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let play = UILabel()
        play.text = "▶"
        play.font = RecapTheme.body(8)
        play.textColor = .white
        play.textAlignment = .center
        play.layer.borderWidth = 1
        play.layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
        play.layer.cornerRadius = 14

        let rule = UIView()
        rule.backgroundColor = UIColor.white.withAlphaComponent(0.22)

        let stamp = UILabel()
        stamp.text = time
        stamp.font = RecapTheme.mono(9, weight: .semibold)
        stamp.textColor = UIColor.white.withAlphaComponent(0.72)

        for piece in [play, waveform, rule, stamp] as [UIView] {
            piece.translatesAutoresizingMaskIntoConstraints = false
            addSubview(piece)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 66),
            play.widthAnchor.constraint(equalToConstant: 28),
            play.heightAnchor.constraint(equalToConstant: 28),
            play.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            play.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            // The strip sits on its baseline: play, waveform and stamp all align to the bottom
            waveform.leadingAnchor.constraint(equalTo: play.trailingAnchor, constant: 12),
            waveform.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.46),
            waveform.heightAnchor.constraint(equalToConstant: 18),
            waveform.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            rule.leadingAnchor.constraint(equalTo: waveform.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: waveform.trailingAnchor),
            rule.topAnchor.constraint(equalTo: waveform.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            stamp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            stamp.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// One continuous silhouette, the shape the design clips out of a filled block
final class WaveformView: UIView {

    private let shape = CAShapeLayer()
    // x, y as fractions of the box, from the design's clip-path
    private static let peaks: [(CGFloat, CGFloat)] = [
        (0, 0.55), (0.07, 0.22), (0.14, 0.66), (0.22, 0.35), (0.30, 0.75), (0.38, 0.17),
        (0.46, 0.56), (0.54, 0.28), (0.62, 0.68), (0.70, 0.40), (0.78, 0.76), (0.86, 0.24),
        (0.94, 0.52), (1, 0.43),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        shape.fillColor = UIColor.white.withAlphaComponent(0.82).cgColor
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: bounds.height * Self.peaks[0].1))
        for peak in Self.peaks.dropFirst() {
            path.addLine(to: CGPoint(x: bounds.width * peak.0, y: bounds.height * peak.1))
        }
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
        path.addLine(to: CGPoint(x: 0, y: bounds.height))
        path.close()
        shape.path = path.cgPath
        shape.frame = bounds
        shape.anchorPoint = CGPoint(x: 0.5, y: 1)
        shape.position = CGPoint(x: bounds.midX, y: bounds.maxY)
        guard shape.animation(forKey: "speak") == nil, window != nil else { return }
        let speak = CAKeyframeAnimation(keyPath: "transform.scale.y")
        speak.values = [0.55, 1, 0.55]
        speak.keyTimes = [0, 0.5, 1]
        speak.duration = 0.7
        speak.repeatCount = 3
        speak.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shape.add(speak, forKey: "speak")
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.55, 1, 0.55]
        fade.keyTimes = [0, 0.5, 1]
        fade.duration = 0.7
        fade.repeatCount = 3
        shape.add(fade, forKey: "fade")
    }
}

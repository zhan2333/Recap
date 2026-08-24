//
//  PlayerPaneView.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit
import AVKit
import AnalysisKit

/// The player mode: system AVPlayerViewController on top (untouched AVKit
/// semantics), Recap's Focus Rail below — waveform, key-point ranges, a
/// playhead — and the phrase lens with "play from 3s before the quote".
final class PlayerPaneView: UIView {

    struct KeyPoint {
        let index: Int
        let signal: LectureAnalysis.ExamSignal
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Host must add this as a child view controller.
    let playerViewController = AVPlayerViewController()

    var onRequestRedownload: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var keyPoints: [KeyPoint] = []
    private var selectedIndex: Int?
    private var duration: TimeInterval = 0

    private let rail = FocusRailView()
    private let railTitle = UILabel()
    private let railDetail = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let lensIndex = UILabel()
    private let lensTime = UILabel()
    private let lensQuote = UILabel()
    private let playLeadInButton = UIButton(type: .system)
    private let emptyState = UIStackView()

    private var content: UIStackView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.paper

        playerViewController.view.layer.cornerRadius = RecapTheme.radiusRow
        playerViewController.view.layer.cornerCurve = .continuous
        playerViewController.view.clipsToBounds = true

        railTitle.text = "Focus Rail · 重点轨道"
        railTitle.font = RecapTheme.body(13, weight: .semibold)
        railTitle.textColor = RecapTheme.ink
        railDetail.text = "波形来自课堂音频，色块表示老师原话所在区间。"
        railDetail.font = RecapTheme.body(11)
        railDetail.textColor = RecapTheme.quiet

        configureStep(previousButton, title: "上一重点", icon: "chevron.left", iconLeading: true) { [weak self] in
            self?.step(-1)
        }
        configureStep(nextButton, title: "下一重点", icon: "chevron.right", iconLeading: false) { [weak self] in
            self?.step(1)
        }

        rail.onSelectRange = { [weak self] index in
            self?.select(index, seek: true, play: false)
        }

        lensIndex.font = RecapTheme.mono(11, weight: .semibold)
        lensIndex.textColor = RecapTheme.signalText
        lensTime.font = RecapTheme.mono(11, weight: .regular)
        lensTime.textColor = RecapTheme.time
        lensQuote.font = RecapTheme.display(16, weight: .medium)
        lensQuote.textColor = RecapTheme.ink
        lensQuote.numberOfLines = 3

        var playConfig = UIButton.Configuration.filled()
        playConfig.baseBackgroundColor = RecapTheme.ink
        playConfig.baseForegroundColor = RecapTheme.paper
        playConfig.background.cornerRadius = RecapTheme.radiusSM
        playConfig.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        playConfig.imagePadding = 7
        playConfig.attributedTitle = AttributedString("从原话前 3 秒播放", attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        playConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        playLeadInButton.configuration = playConfig
        playLeadInButton.tintColor = RecapTheme.paper
        playLeadInButton.addAction(UIAction { [weak self] _ in self?.playFromLeadIn() }, for: .touchUpInside)

        previousButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nextButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        railTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        railDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let railHeader = UIStackView(arrangedSubviews: [
            vstack([railTitle, railDetail], spacing: 2), UIView(), previousButton, nextButton,
        ])
        railHeader.axis = .horizontal
        railHeader.alignment = .center
        railHeader.spacing = 8

        let lensHead = UIStackView(arrangedSubviews: [lensIndex, lensTime, UIView()])
        lensHead.axis = .horizontal
        lensHead.spacing = 10

        let lens = vstack([lensHead, lensQuote, playLeadInButton], spacing: 9)
        lens.setCustomSpacing(12, after: lensQuote)
        lens.alignment = .leading

        content = UIStackView(arrangedSubviews: [playerViewController.view, railHeader, rail, lens])
        content.axis = .vertical
        content.spacing = 14
        content.setCustomSpacing(20, after: playerViewController.view)
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 16, left: 24, bottom: 20, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        // Empty state: media missing → explain + re-download path.
        let emptyIcon = UIImageView(image: UIImage(systemName: "film.stack"))
        emptyIcon.tintColor = RecapTheme.quiet
        emptyIcon.contentMode = .scaleAspectFit
        let emptyTitle = UILabel()
        emptyTitle.text = "视频文件不在本机"
        emptyTitle.font = RecapTheme.body(14, weight: .semibold)
        emptyTitle.textColor = RecapTheme.ink
        let emptyDetail = UILabel()
        emptyDetail.text = "直链 token 有时效——若下载失败，重新从云课堂抓取直链后在讲次右键「更新直链」再试。"
        emptyDetail.font = RecapTheme.body(12)
        emptyDetail.textColor = RecapTheme.muted
        emptyDetail.numberOfLines = 0
        emptyDetail.textAlignment = .center
        var redownloadConfig = UIButton.Configuration.filled()
        redownloadConfig.baseBackgroundColor = RecapTheme.ink
        redownloadConfig.baseForegroundColor = RecapTheme.paper
        redownloadConfig.background.cornerRadius = RecapTheme.radiusSM
        redownloadConfig.attributedTitle = AttributedString("重新下载视频", attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        redownloadConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let redownloadButton = UIButton(configuration: redownloadConfig)
        redownloadButton.addAction(UIAction { [weak self] _ in self?.onRequestRedownload?() }, for: .touchUpInside)

        for view in [emptyIcon, emptyTitle, emptyDetail, redownloadButton] {
            emptyState.addArrangedSubview(view)
        }
        emptyState.axis = .vertical
        emptyState.alignment = .center
        emptyState.spacing = 10
        emptyState.isHidden = true
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyState)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            playerViewController.view.heightAnchor.constraint(
                equalTo: content.widthAnchor, multiplier: 9.0 / 16.0, constant: -27),
            rail.heightAnchor.constraint(equalToConstant: 64),
            emptyIcon.heightAnchor.constraint(equalToConstant: 36),
            emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 48),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -48),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
    }

    // MARK: - Configuration

    func configure(mediaURL: URL?, waveformCacheURL: URL?, rows: [EvidenceReviewView.DisplayRow], evidences: [EvidenceReviewView.Evidence]) {
        // LLM signal order is arbitrary — the rail must be chronological.
        keyPoints = evidences.enumerated().compactMap { index, evidence -> KeyPoint? in
            guard let rowIndex = evidence.rowIndex, rowIndex < rows.count else { return nil }
            let row = rows[rowIndex]
            return KeyPoint(index: index, signal: evidence.signal, start: row.start, end: max(row.end, row.start + 1))
        }
        .sorted { $0.start < $1.start }

        guard let mediaURL, FileManager.default.fileExists(atPath: mediaURL.path) else {
            content.isHidden = true
            emptyState.isHidden = false
            teardownPlayer()
            return
        }
        content.isHidden = false
        emptyState.isHidden = true

        if player == nil {
            let player = AVPlayer(url: mediaURL)
            self.player = player
            playerViewController.player = player
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 10), queue: .main
            ) { [weak self] time in
                self?.tick(time.seconds)
            }
            // Rail needs a duration before playback starts: seed from the
            // transcript's end, then correct with the asset's real duration.
            Task { [weak self] in
                if let seconds = try? await player.currentItem?.asset.load(.duration).seconds,
                   seconds.isFinite, seconds > 0 {
                    self?.duration = seconds
                    self?.rail.duration = seconds
                }
            }
        }
        if duration == 0, let transcriptEnd = rows.last?.end, transcriptEnd > 0 {
            duration = transcriptEnd
            rail.duration = transcriptEnd
        }

        rail.ranges = keyPoints.map { ($0.start, $0.end) }
        select(keyPoints.isEmpty ? nil : 0, seek: false, play: false)

        if let cacheURL = waveformCacheURL {
            let sourceURL = mediaURL
            Task { [weak self] in
                if let buckets = try? await WaveformGenerator.waveform(for: sourceURL, cacheURL: cacheURL) {
                    self?.rail.waveform = buckets
                }
            }
        }
    }

    private func teardownPlayer() {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        timeObserver = nil
        playerViewController.player = nil
        player = nil
    }

    func pause() {
        player?.pause()
    }

    // MARK: - Playback linkage

    private func tick(_ seconds: TimeInterval) {
        if duration == 0, let total = player?.currentItem?.duration.seconds, total.isFinite, total > 0 {
            duration = total
            rail.duration = total
        }
        rail.playheadTime = seconds
        // Highlight the range the playhead is inside.
        if let inside = keyPoints.firstIndex(where: { seconds >= $0.start && seconds <= $0.end }),
           inside != selectedIndex {
            select(inside, seek: false, play: false)
        }
    }

    private func select(_ index: Int?, seek: Bool, play: Bool) {
        selectedIndex = index
        rail.selectedIndex = index
        guard let index, index < keyPoints.count else {
            lensIndex.text = keyPoints.isEmpty ? "—" : nil
            lensTime.text = keyPoints.isEmpty ? "提取重点后，重点区间会出现在轨道上" : nil
            lensQuote.text = nil
            playLeadInButton.isHidden = true
            return
        }
        let point = keyPoints[index]
        lensIndex.text = String(format: "%02d", index + 1)
        lensTime.text = "\(Self.timestamp(point.start))—\(Self.timestamp(point.end))"
        lensQuote.text = "“\(point.signal.quote)”"
        playLeadInButton.isHidden = false
        if seek {
            player?.seek(to: CMTime(seconds: max(0, point.start - 3), preferredTimescale: 600))
        }
        if play {
            player?.play()
        }
    }

    private func step(_ delta: Int) {
        guard !keyPoints.isEmpty else { return }
        let next = ((selectedIndex ?? -1) + delta + keyPoints.count) % keyPoints.count
        select(next, seek: true, play: false)
    }

    private func playFromLeadIn() {
        guard let index = selectedIndex else { return }
        select(index, seek: true, play: true)
    }

    // MARK: - Helpers

    private func configureStep(_ button: UIButton, title: String, icon: String, iconLeading: Bool, action: @escaping () -> Void) {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(11), .foregroundColor: RecapTheme.muted,
        ]))
        config.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        config.imagePlacement = iconLeading ? .leading : .trailing
        config.imagePadding = 4
        config.baseForegroundColor = RecapTheme.muted
        config.background.strokeColor = RecapTheme.line
        config.background.strokeWidth = 1
        config.background.cornerRadius = RecapTheme.radiusSM
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        button.configuration = config
        button.tintColor = RecapTheme.muted
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func vstack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }

    static func timestamp(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

/// Waveform + key-point ranges + playhead, all proportional to duration.
final class FocusRailView: UIView {

    var waveform: [Float] = [] {
        didSet { setNeedsDisplay() }
    }
    var ranges: [(start: TimeInterval, end: TimeInterval)] = [] {
        didSet { rebuildRangeButtons() }
    }
    var duration: TimeInterval = 0 {
        didSet { setNeedsLayout(); setNeedsDisplay() }
    }
    var playheadTime: TimeInterval = 0 {
        didSet { setNeedsLayout() }
    }
    var selectedIndex: Int? {
        didSet { styleRangeButtons() }
    }
    var onSelectRange: ((Int) -> Void)?

    private var rangeButtons: [UIButton] = []
    private let playhead = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.surface.withAlphaComponent(0.5)
        layer.cornerRadius = RecapTheme.radiusMD
        layer.cornerCurve = .continuous
        clipsToBounds = true
        contentMode = .redraw
        playhead.backgroundColor = RecapTheme.ink
        addSubview(playhead)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard !waveform.isEmpty else { return }
        let color = RecapTheme.time.withAlphaComponent(0.35)
        color.setFill()
        let barWidth = bounds.width / CGFloat(waveform.count)
        let midY = bounds.midY
        for (index, value) in waveform.enumerated() {
            let height = max(1.5, CGFloat(value) * (bounds.height - 14))
            let bar = CGRect(
                x: CGFloat(index) * barWidth,
                y: midY - height / 2,
                width: max(0.8, barWidth * 0.6),
                height: height
            )
            UIBezierPath(rect: bar).fill()
        }
    }

    private func rebuildRangeButtons() {
        rangeButtons.forEach { $0.removeFromSuperview() }
        rangeButtons = ranges.enumerated().map { index, _ in
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle("\(index + 1)", for: .normal)
            button.titleLabel?.font = RecapTheme.mono(10, weight: .semibold)
            button.layer.cornerRadius = 4
            button.layer.cornerCurve = .continuous
            button.addAction(UIAction { [weak self] action in
                guard let btn = action.sender as? UIButton else { return }
                self?.onSelectRange?(btn.tag)
            }, for: .touchUpInside)
            addSubview(button)
            return button
        }
        styleRangeButtons()
        setNeedsLayout()
    }

    private func styleRangeButtons() {
        for (index, button) in rangeButtons.enumerated() {
            let selected = index == selectedIndex
            button.backgroundColor = selected
                ? RecapTheme.signal
                : RecapTheme.signal.withAlphaComponent(0.35)
            button.setTitleColor(selected ? RecapTheme.paper : RecapTheme.signalText, for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard duration > 0 else {
            playhead.frame = .zero
            rangeButtons.forEach { $0.frame = .zero }
            return
        }
        for (index, button) in rangeButtons.enumerated() {
            let range = ranges[index]
            let left = bounds.width * CGFloat(range.start / duration)
            let width = max(18, bounds.width * CGFloat((range.end - range.start) / duration))
            button.frame = CGRect(x: left, y: 6, width: width, height: bounds.height - 12)
        }
        let x = bounds.width * CGFloat(min(1, playheadTime / duration))
        playhead.frame = CGRect(x: x - 0.75, y: 0, width: 1.5, height: bounds.height)
        bringSubviewToFront(playhead)
    }
}

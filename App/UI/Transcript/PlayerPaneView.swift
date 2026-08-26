//
//  PlayerPaneView.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit
import AVKit
import AnalysisKit

// The player mode: system AVPlayerViewController on top (untouched AVKit semantics), Recap's Focus Rail below
final class PlayerPaneView: UIView {

    struct KeyPoint {
        let index: Int
        let signal: LectureAnalysis.ExamSignal
        let start: TimeInterval
        let end: TimeInterval
    }

    // One video file on the lecture's global timeline.
    struct PlayablePart {
        let url: URL
        let globalStart: TimeInterval
        let duration: TimeInterval
        let waveformCacheURL: URL?
    }

    // Host must add this as a child view controller.
    let playerViewController = AVPlayerViewController()

    var onRequestRedownload: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var keyPoints: [KeyPoint] = []
    private var selectedIndex: Int?
    private var duration: TimeInterval = 0
    private var playableParts: [PlayablePart] = []
    private var currentPartIndex = 0
    private var partKeyPointIndices: [Int] = []
    private var captionRows: [(start: TimeInterval, end: TimeInterval, text: String)] = []
    private let captionLabel = PaddedCaptionLabel()

    private let rail = FocusRailView()
    private let partPicker = UIStackView()
    private var partPickerRow: UIStackView!
    private let railTitle = UILabel()
    private let railDetail = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let showAllButton = UIButton(type: .system)
    private let lensIndex = UILabel()
    private let lensTime = UILabel()
    private let lensQuote = UILabel()
    private let lensNote = UILabel()
    private let frameStrip = FrameStripView()
    private let inspector = KeyPointInspectorView()
    private let playLeadInButton = UIButton(type: .system)
    private var frameGenerators: [AVAssetImageGenerator] = []
    private let emptyState = UIStackView()

    private var content: UIStackView!
    private var columns: UIStackView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.paper

        playerViewController.view.layer.cornerRadius = RecapTheme.radiusRow
        playerViewController.view.layer.cornerCurve = .continuous
        playerViewController.view.clipsToBounds = true
        if let overlay = playerViewController.contentOverlayView {
            captionLabel.translatesAutoresizingMaskIntoConstraints = false
            captionLabel.isHidden = true
            overlay.addSubview(captionLabel)
            NSLayoutConstraint.activate([
                captionLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                captionLabel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -56),
                captionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 48),
                captionLabel.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -48),
            ])
        }

        railTitle.text = String(localized: "Focus Rail · 重点轨道")
        railTitle.font = RecapTheme.body(13, weight: .semibold)
        railTitle.textColor = RecapTheme.ink
        railDetail.text = String(localized: "波形来自课堂音频，色块表示老师原话所在区间。")
        railDetail.font = RecapTheme.body(11)
        railDetail.textColor = RecapTheme.quiet

        configureStep(previousButton, title: String(localized: "上一重点"), icon: "backward.end", iconLeading: true) { [weak self] in
            self?.step(-1)
        }
        configureStep(showAllButton, title: String(localized: "显示全部"), icon: "rectangle.grid.1x2", iconLeading: true) { [weak self] in
            self?.select(nil, seek: false, play: false)
        }
        configureStep(nextButton, title: String(localized: "下一重点"), icon: "forward.end", iconLeading: false) { [weak self] in
            self?.step(1)
        }

        rail.onSelectRange = { [weak self] index in
            guard let self, self.partKeyPointIndices.indices.contains(index) else { return }
            self.select(self.partKeyPointIndices[index], seek: true, play: false)
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
        playConfig.attributedTitle = AttributedString(String(localized: "从原话前 3 秒播放"), attributes: AttributeContainer([
            .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
        ]))
        playConfig.attributedSubtitle = AttributedString(String(localized: "保留老师铺垫，不承诺逐帧对齐"), attributes: AttributeContainer([
            .font: RecapTheme.body(9.5), .foregroundColor: RecapTheme.paper.withAlphaComponent(0.75),
        ]))
        playConfig.titleAlignment = .leading
        playConfig.titlePadding = 2
        playConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        playLeadInButton.configuration = playConfig
        playLeadInButton.tintColor = RecapTheme.paper
        playLeadInButton.addAction(UIAction { [weak self] _ in self?.playFromLeadIn() }, for: .touchUpInside)

        previousButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nextButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        showAllButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        railTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        railDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let railHeader = UIStackView(arrangedSubviews: [
            vstack([railTitle, railDetail], spacing: 2), UIView(), previousButton, showAllButton, nextButton,
        ])
        railHeader.axis = .horizontal
        railHeader.alignment = .center
        railHeader.spacing = 8

        let lensHead = UIStackView(arrangedSubviews: [lensIndex, lensTime, UIView()])
        lensHead.axis = .horizontal
        lensHead.spacing = 10

        lensNote.font = RecapTheme.body(11)
        lensNote.textColor = RecapTheme.muted
        lensNote.numberOfLines = 1
        let lensLeft = vstack([lensHead, lensQuote, lensNote], spacing: 8)
        lensLeft.alignment = .leading
        let lensRight = vstack([frameStrip, playLeadInButton], spacing: 10)
        lensRight.alignment = .leading
        let lens = UIStackView(arrangedSubviews: [lensLeft, UIView(), lensRight])
        lens.axis = .horizontal
        lens.alignment = .top
        lens.spacing = 18
        frameStrip.onSelectTime = { [weak self] time in self?.seekGlobal(time, thenPlay: false) }
        inspector.onSelect = { [weak self] index in self?.select(index, seek: true, play: false) }

        partPicker.axis = .horizontal
        partPicker.spacing = 8
        partPickerRow = UIStackView(arrangedSubviews: [partPicker, UIView()])
        partPickerRow.axis = .horizontal

        content = UIStackView(arrangedSubviews: [playerViewController.view, partPickerRow, railHeader, rail, lens])
        // CHCR must sit on leaf views — a UIStackView row has no intrinsic size to defend
        for view in [railTitle, railDetail, previousButton, nextButton, showAllButton,
                     lensIndex, lensTime, lensQuote, lensNote, playLeadInButton] as [UIView] {
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        content.axis = .vertical
        content.spacing = 14
        content.setCustomSpacing(18, after: playerViewController.view)
        content.setCustomSpacing(12, after: partPickerRow)
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 16, left: 24, bottom: 20, right: 24)

        let columns = UIStackView(arrangedSubviews: [content, inspector])
        columns.axis = .horizontal
        columns.alignment = .fill
        inspector.widthAnchor.constraint(equalToConstant: 236).isActive = true
        columns.translatesAutoresizingMaskIntoConstraints = false
        addSubview(columns)
        self.columns = columns

        // Empty state: media missing → explain + re-download path.
        let emptyIcon = UIImageView(image: UIImage(systemName: "film.stack"))
        emptyIcon.tintColor = RecapTheme.quiet
        emptyIcon.contentMode = .scaleAspectFit
        let emptyTitle = UILabel()
        emptyTitle.text = String(localized: "视频文件不在本机")
        emptyTitle.font = RecapTheme.body(14, weight: .semibold)
        emptyTitle.textColor = RecapTheme.ink
        let emptyDetail = UILabel()
        emptyDetail.text = String(localized: "直链 token 有时效——若下载失败，重新从云课堂抓取直链后在讲次右键「更新直链」再试。")
        emptyDetail.font = RecapTheme.body(12)
        emptyDetail.textColor = RecapTheme.muted
        emptyDetail.numberOfLines = 0
        emptyDetail.textAlignment = .center
        var redownloadConfig = UIButton.Configuration.filled()
        redownloadConfig.baseBackgroundColor = RecapTheme.ink
        redownloadConfig.baseForegroundColor = RecapTheme.paper
        redownloadConfig.background.cornerRadius = RecapTheme.radiusSM
        redownloadConfig.attributedTitle = AttributedString(String(localized: "重新下载视频"), attributes: AttributeContainer([
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

        let playerAspect = playerViewController.view.heightAnchor.constraint(
            equalTo: content.widthAnchor, multiplier: 9.0 / 16.0, constant: -27)
        // 749: below every default CHCR so scarce height always squeezes the video first
        playerAspect.priority = UILayoutPriority(749)
        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo: topAnchor),
            columns.leadingAnchor.constraint(equalTo: leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: trailingAnchor),
            columns.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            playerAspect,
            playerViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            rail.heightAnchor.constraint(equalToConstant: 92),
            emptyIcon.heightAnchor.constraint(equalToConstant: 36),
            emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 48),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -48),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        inspector.isHidden = bounds.width < 1000
    }

    deinit {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - Configuration

    func configure(
        parts: [(url: URL, duration: TimeInterval?, waveformCacheURL: URL?)],
        rows: [EvidenceReviewView.DisplayRow],
        evidences: [EvidenceReviewView.Evidence]
    ) {
        captionRows = rows.map { ($0.start, $0.end, $0.text) }
        // LLM signal order is arbitrary — the rail must be chronological.
        keyPoints = evidences.enumerated().compactMap { index, evidence -> KeyPoint? in
            guard let rowIndex = evidence.rowIndex, rowIndex < rows.count else { return nil }
            let row = rows[rowIndex]
            return KeyPoint(index: index, signal: evidence.signal, start: row.start, end: max(row.end, row.start + 1))
        }
        .sorted { $0.start < $1.start }

        let existing = parts.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !existing.isEmpty else {
            columns.isHidden = true
            emptyState.isHidden = false
            teardownPlayer()
            return
        }
        columns.isHidden = false
        emptyState.isHidden = true

        // Build the global timeline; transcript end covers a missing tail duration.
        var offset: TimeInterval = 0
        playableParts = existing.enumerated().map { index, entry in
            let fallback = (index == existing.count - 1)
                ? max(60, (rows.last?.end ?? 60) - offset)
                : 60
            let partDuration = entry.duration ?? fallback
            let part = PlayablePart(
                url: entry.url, globalStart: offset, duration: partDuration,
                waveformCacheURL: entry.waveformCacheURL
            )
            offset += partDuration
            return part
        }
        duration = max(offset, rows.last?.end ?? 0)

        if player == nil {
            let player = AVPlayer(playerItem: AVPlayerItem(url: playableParts[0].url))
            self.player = player
            currentPartIndex = 0
            playerViewController.player = player
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 10), queue: .main
            ) { [weak self] time in
                self?.tick(time.seconds)
            }
            observePartEnd()
        } else if currentPartIndex >= playableParts.count
            || (player?.currentItem?.asset as? AVURLAsset)?.url != playableParts[currentPartIndex].url {
            // Reconfigured with a different part list — restart from the first part
            currentPartIndex = 0
            player?.replaceCurrentItem(with: AVPlayerItem(url: playableParts[0].url))
            observePartEnd()
        }

        frameGenerators = playableParts.map { part in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: part.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 136)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 10)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 10)
            return generator
        }
        inspector.update(keyPoints: keyPoints)
        rebuildPartPicker()
        applyPart()
        select(keyPoints.isEmpty ? nil : 0, seek: false, play: false)
    }

    // Maps a global timeline instant onto its part and local offset
    private func partAndLocalTime(for global: TimeInterval) -> (index: Int, local: TimeInterval)? {
        guard !playableParts.isEmpty else { return nil }
        let index = playableParts.lastIndex { global >= $0.globalStart } ?? 0
        return (index, global - playableParts[index].globalStart)
    }

    private func updateFrameStrip(for point: KeyPoint?) {
        frameGenerators.forEach { $0.cancelAllCGImageGeneration() }
        guard let point else {
            frameStrip.isHidden = true
            return
        }
        frameStrip.isHidden = false
        let times = [max(0, point.start - 3), point.start, min(max(point.start, duration - 1), point.start + 14)]
        frameStrip.beginLoading(times: times)
        for (slot, global) in times.enumerated() {
            guard let target = partAndLocalTime(for: global),
                  frameGenerators.indices.contains(target.index) else { continue }
            let time = CMTime(seconds: target.local, preferredTimescale: 600)
            frameGenerators[target.index].generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, image, _, _, _ in
                guard let image else { return }
                let frame = UIImage(cgImage: image)
                DispatchQueue.main.async { self?.frameStrip.setImage(frame, at: slot) }
            }
        }
    }

    // MARK: - Part presentation

    // The rail covers only the current part, in part-local coordinates
    private func applyPart() {
        guard playableParts.indices.contains(currentPartIndex) else { return }
        let part = playableParts[currentPartIndex]
        let partEnd = part.globalStart + part.duration
        partKeyPointIndices = keyPoints.indices.filter {
            keyPoints[$0].start >= part.globalStart && keyPoints[$0].start < partEnd
        }
        rail.rangeTitles = partKeyPointIndices.map { "\($0 + 1)" }
        rail.ranges = partKeyPointIndices.map {
            (keyPoints[$0].start - part.globalStart, min(keyPoints[$0].end, partEnd) - part.globalStart)
        }
        rail.duration = part.duration
        rail.selectedIndex = selectedIndex.flatMap { partKeyPointIndices.firstIndex(of: $0) }
        stylePartPicker()

        rail.waveform = []
        guard let cacheURL = part.waveformCacheURL else { return }
        let url = part.url
        let index = currentPartIndex
        Task { [weak self] in
            if let buckets = try? await WaveformGenerator.waveform(for: url, cacheURL: cacheURL),
               self?.currentPartIndex == index {
                self?.rail.waveform = buckets
            }
        }
    }

    private func rebuildPartPicker() {
        partPicker.arrangedSubviews.forEach { $0.removeFromSuperview() }
        partPickerRow.isHidden = playableParts.count <= 1
        guard playableParts.count > 1 else { return }
        for index in playableParts.indices {
            let button = UIButton(type: .system)
            // NSButton bridging cannot restyle plain→filled at runtime; force UIKit rendering
            button.preferredBehavioralStyle = .pad
            button.tag = index
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.playableParts.indices.contains(index) else { return }
                self.seekGlobal(self.playableParts[index].globalStart, thenPlay: false)
            }, for: .touchUpInside)
            partPicker.addArrangedSubview(button)
        }
        stylePartPicker()
    }

    private func stylePartPicker() {
        for (index, view) in partPicker.arrangedSubviews.enumerated() {
            guard let button = view as? UIButton, playableParts.indices.contains(index) else { continue }
            let selected = index == currentPartIndex
            // .plain() never renders background/stroke on Catalyst — selected must be .filled()
            var config = selected ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
            config.attributedTitle = AttributedString(
                String(localized: "第 \(index + 1) 段 · \(Self.timestamp(playableParts[index].duration))"),
                attributes: AttributeContainer([
                    .font: RecapTheme.mono(11, weight: selected ? .semibold : .regular),
                    .foregroundColor: selected ? RecapTheme.paper : RecapTheme.muted,
                ]))
            if selected {
                config.baseBackgroundColor = RecapTheme.ink
            }
            config.background.cornerRadius = RecapTheme.radiusSM
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
            button.configuration = config
            button.tintColor = selected ? RecapTheme.paper : RecapTheme.muted
        }
    }

    // Seeks on the global timeline, switching video parts as needed.
    private func seekGlobal(_ time: TimeInterval, thenPlay: Bool) {
        guard let player, !playableParts.isEmpty else { return }
        let clamped = max(0, min(time, duration - 0.5))
        let index = playableParts.lastIndex { clamped >= $0.globalStart } ?? 0
        if index != currentPartIndex {
            currentPartIndex = index
            player.replaceCurrentItem(with: AVPlayerItem(url: playableParts[index].url))
            observePartEnd()
            applyPart()
        }
        let local = clamped - playableParts[index].globalStart
        player.seek(to: CMTime(seconds: local, preferredTimescale: 600))
        if thenPlay { player.play() }
    }

    // Advances to the next part when the current one finishes.
    private func observePartEnd() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player?.currentItem, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let next = self.currentPartIndex + 1
            guard next < self.playableParts.count else { return }
            self.seekGlobal(self.playableParts[next].globalStart, thenPlay: true)
        }
    }

    private func teardownPlayer() {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        playerViewController.player = nil
        player = nil
    }

    func pause() {
        player?.pause()
    }

    func togglePlayback() {
        guard let player else { return }
        player.rate == 0 ? player.play() : player.pause()
    }

    // MARK: - Playback linkage

    private func tick(_ seconds: TimeInterval) {
        let globalTime = (playableParts.indices.contains(currentPartIndex)
            ? playableParts[currentPartIndex].globalStart : 0) + seconds
        rail.playheadTime = seconds
        updateCaption(at: globalTime)
        // Highlight the range the playhead is inside.
        if let inside = keyPoints.firstIndex(where: { globalTime >= $0.start && globalTime <= $0.end }),
           inside != selectedIndex {
            select(inside, seek: false, play: false)
        }
    }

    // The current transcript row rides the video as a caption
    private func updateCaption(at globalTime: TimeInterval) {
        let row = captionRows.last { $0.start <= globalTime && globalTime <= $0.end + 1.5 }
        captionLabel.text = row?.text
        captionLabel.isHidden = row == nil
    }

    private func select(_ index: Int?, seek: Bool, play: Bool) {
        selectedIndex = index
        rail.selectedIndex = index.flatMap { partKeyPointIndices.firstIndex(of: $0) }
        inspector.select(index: index)
        updateFrameStrip(for: index.flatMap { $0 < keyPoints.count ? keyPoints[$0] : nil })
        guard let index, index < keyPoints.count else {
            lensIndex.text = keyPoints.isEmpty ? "—" : nil
            lensTime.text = keyPoints.isEmpty ? String(localized: "提取重点后，重点区间会出现在轨道上") : nil
            lensQuote.text = nil
            playLeadInButton.isHidden = true
            return
        }
        let point = keyPoints[index]
        lensIndex.text = String(format: "%02d", index + 1)
        lensTime.text = "\(Self.timestamp(point.start))—\(Self.timestamp(point.end))"
        lensQuote.text = "“\(point.signal.quote)”"
        var noteParts = [point.signal.strength]
        if let qtype = point.signal.qtype, !qtype.isEmpty { noteParts.append(qtype) }
        if let topic = point.signal.topic, !topic.isEmpty { noteParts.append(topic) }
        lensNote.text = noteParts.joined(separator: " · ")
        playLeadInButton.isHidden = false
        if seek {
            seekGlobal(max(0, point.start - 3), thenPlay: play)
        } else if play {
            player?.play()
        }
    }

    func step(_ delta: Int) {
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
        button.preferredBehavioralStyle = .pad
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

// Dense waveform with numbered key-point tags, a playhead, and a time scale, per the M4 board
final class FocusRailView: UIView {

    private let badgeBand: CGFloat = 20
    private let scaleBand: CGFloat = 16

    var waveform: [Float] = [] {
        didSet { setNeedsDisplay() }
    }
    var ranges: [(start: TimeInterval, end: TimeInterval)] = [] {
        didSet { rebuildRangeButtons() }
    }
    // Button labels; falls back to 1-based position when unset
    var rangeTitles: [String] = [] {
        didSet { rebuildRangeButtons() }
    }
    var duration: TimeInterval = 0 {
        didSet { setNeedsLayout(); setNeedsDisplay(); rebuildScale() }
    }
    var playheadTime: TimeInterval = 0 {
        didSet { setNeedsLayout() }
    }
    var selectedIndex: Int? {
        didSet { styleRangeButtons() }
    }
    var onSelectRange: ((Int) -> Void)?

    private var rangeButtons: [UIButton] = []
    private var tagLines: [UIView] = []
    private var scaleLabels: [UILabel] = []
    private let playhead = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        playhead.backgroundColor = RecapTheme.ink
        addSubview(playhead)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var waveBand: CGRect {
        CGRect(x: 0, y: badgeBand, width: bounds.width, height: bounds.height - badgeBand - scaleBand)
    }

    override func draw(_ rect: CGRect) {
        guard !waveform.isEmpty else { return }
        RecapTheme.time.withAlphaComponent(0.4).setFill()
        let band = waveBand
        let barWidth = band.width / CGFloat(waveform.count)
        for (index, value) in waveform.enumerated() {
            let height = max(2, CGFloat(value) * (band.height - 4))
            UIBezierPath(rect: CGRect(
                x: CGFloat(index) * barWidth,
                y: band.midY - height / 2,
                width: max(0.7, barWidth * 0.5),
                height: height
            )).fill()
        }
    }

    private func rebuildRangeButtons() {
        rangeButtons.forEach { $0.removeFromSuperview() }
        tagLines.forEach { $0.removeFromSuperview() }
        tagLines = ranges.map { _ in
            let line = UIView()
            addSubview(line)
            return line
        }
        rangeButtons = ranges.enumerated().map { index, _ in
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(index < rangeTitles.count ? rangeTitles[index] : "\(index + 1)", for: .normal)
            button.titleLabel?.font = RecapTheme.mono(9, weight: .semibold)
            button.layer.cornerRadius = 4.5
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
            button.backgroundColor = selected ? RecapTheme.signal : RecapTheme.signal.withAlphaComponent(0.3)
            button.setTitleColor(selected ? RecapTheme.paper : RecapTheme.signalText, for: .normal)
            if tagLines.indices.contains(index) {
                tagLines[index].backgroundColor = selected
                    ? RecapTheme.signal
                    : RecapTheme.signal.withAlphaComponent(0.45)
            }
        }
    }

    private func rebuildScale() {
        scaleLabels.forEach { $0.removeFromSuperview() }
        scaleLabels = []
        guard duration > 0 else { return }
        for step in 0...4 {
            let label = UILabel()
            label.text = PlayerPaneView.timestamp(duration * Double(step) / 4)
            label.font = RecapTheme.mono(8.5, weight: .regular)
            label.textColor = RecapTheme.quiet
            addSubview(label)
            scaleLabels.append(label)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard duration > 0 else {
            playhead.frame = .zero
            rangeButtons.forEach { $0.frame = .zero }
            tagLines.forEach { $0.frame = .zero }
            return
        }
        let band = waveBand
        for (index, button) in rangeButtons.enumerated() {
            let range = ranges[index]
            let center = bounds.width * CGFloat(range.start / duration)
            button.frame = CGRect(x: center - 9, y: 0, width: 18, height: 18)
            let width = max(3, bounds.width * CGFloat((range.end - range.start) / duration))
            tagLines[index].frame = CGRect(x: center - 1.5, y: badgeBand, width: min(width, 26), height: band.height)
        }
        for (step, label) in scaleLabels.enumerated() {
            label.sizeToFit()
            let x = bounds.width * CGFloat(step) / 4
            let clamped = min(max(0, x - label.bounds.width / 2), bounds.width - label.bounds.width)
            label.frame.origin = CGPoint(x: clamped, y: band.maxY + 3)
        }
        let x = bounds.width * CGFloat(min(1, playheadTime / duration))
        playhead.frame = CGRect(x: x - 0.75, y: badgeBand - 3, width: 1.5, height: band.height + 6)
        bringSubviewToFront(playhead)
    }
}

// MARK: - Frame strip

// Three thumbnails around the quote: 3s before, the quote itself, 14s after
final class FrameStripView: UIView {

    var onSelectTime: ((TimeInterval) -> Void)?

    private var slots: [UIButton] = []
    private var times: [TimeInterval] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        let labels = [String(localized: "前 3 秒"), String(localized: "原话"), String(localized: "后 14 秒")]
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        for (index, text) in labels.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.backgroundColor = RecapTheme.surface
            button.layer.cornerRadius = 6
            button.layer.cornerCurve = .continuous
            button.clipsToBounds = true
            button.imageView?.contentMode = .scaleAspectFill
            button.widthAnchor.constraint(equalToConstant: 96).isActive = true
            button.heightAnchor.constraint(equalToConstant: 54).isActive = true
            if index == 1 {
                button.layer.borderWidth = 2
                button.layer.borderColor = RecapTheme.signal.cgColor
            }
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.times.indices.contains(index) else { return }
                self.onSelectTime?(self.times[index])
            }, for: .touchUpInside)

            let caption = UILabel()
            caption.text = text
            caption.font = RecapTheme.body(9.5)
            caption.textColor = RecapTheme.quiet
            caption.textAlignment = .center

            let cell = UIStackView(arrangedSubviews: [button, caption])
            cell.axis = .vertical
            cell.spacing = 3
            cell.alignment = .center
            slots.append(button)
            stack.addArrangedSubview(cell)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginLoading(times: [TimeInterval]) {
        self.times = times
        slots.forEach { $0.setImage(nil, for: .normal) }
    }

    func setImage(_ image: UIImage, at slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot].setImage(image, for: .normal)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        slots[1].layer.borderColor = RecapTheme.signal.cgColor
    }
}

// MARK: - Key point inspector

// Right column: every key point of the lecture, selection synced with the rail
final class KeyPointInspectorView: UIView {

    var onSelect: ((Int) -> Void)?

    private let countLabel = UILabel()
    private let stack = UIStackView()
    private var rows: [InspectorRow] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.notesPane

        let title = UILabel()
        title.text = String(localized: "本讲重点")
        title.font = RecapTheme.body(13, weight: .semibold)
        title.textColor = RecapTheme.ink
        countLabel.font = RecapTheme.body(11)
        countLabel.textColor = RecapTheme.quiet
        let header = UIStackView(arrangedSubviews: [title, UIView(), countLabel])
        header.axis = .horizontal
        header.alignment = .firstBaseline

        let intro = UILabel()
        intro.text = String(localized: "选择一条重点，播放器会跳到老师原话附近，并保留前后讲解。")
        intro.font = RecapTheme.body(10.5)
        intro.textColor = RecapTheme.muted
        intro.numberOfLines = 0

        stack.axis = .vertical
        stack.spacing = 5

        let footnoteTitle = UILabel()
        footnoteTitle.text = String(localized: "● 音频定位已匹配")
        footnoteTitle.font = RecapTheme.body(10.5, weight: .semibold)
        footnoteTitle.textColor = RecapTheme.complete
        let footnoteDetail = UILabel()
        footnoteDetail.text = String(localized: "跳到重点附近 · 建议提前 3 秒")
        footnoteDetail.font = RecapTheme.body(10)
        footnoteDetail.textColor = RecapTheme.quiet
        let footnote = UIStackView(arrangedSubviews: [footnoteTitle, footnoteDetail])
        footnote.axis = .vertical
        footnote.spacing = 2

        let scroll = UIScrollView()
        let contentStack = UIStackView(arrangedSubviews: [header, intro, stack, footnote])
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.setCustomSpacing(8, after: header)
        contentStack.setCustomSpacing(16, after: stack)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 14, left: 13, bottom: 20, right: 13)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(contentStack)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(keyPoints: [PlayerPaneView.KeyPoint]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = keyPoints.enumerated().map { index, point in
            let row = InspectorRow(number: index + 1, point: point)
            row.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            stack.addArrangedSubview(row)
            return row
        }
        countLabel.text = String(localized: "\(keyPoints.count) 个")
    }

    func select(index: Int?) {
        for (rowIndex, row) in rows.enumerated() {
            row.isActive = rowIndex == index
        }
    }

    private final class InspectorRow: UIControl {

        var isActive = false {
            didSet { backgroundColor = isActive ? RecapTheme.signalSoft : .clear }
        }

        init(number: Int, point: PlayerPaneView.KeyPoint) {
            super.init(frame: .zero)
            layer.cornerRadius = RecapTheme.radiusSM
            layer.cornerCurve = .continuous

            let numberLabel = UILabel()
            numberLabel.text = String(format: "%02d", number)
            numberLabel.font = RecapTheme.mono(10, weight: .semibold)
            numberLabel.textColor = RecapTheme.signalText

            let timeLabel = UILabel()
            timeLabel.text = PlayerPaneView.timestamp(point.start)
            timeLabel.font = RecapTheme.mono(10, weight: .regular)
            timeLabel.textColor = RecapTheme.time

            let head = UIStackView(arrangedSubviews: [numberLabel, timeLabel, UIView()])
            head.axis = .horizontal
            head.spacing = 7

            let text = UILabel()
            text.text = point.signal.topic ?? point.signal.quote
            text.font = RecapTheme.body(11.5)
            text.textColor = RecapTheme.ink
            text.numberOfLines = 2

            let column = UIStackView(arrangedSubviews: [head, text])
            column.axis = .vertical
            column.spacing = 4
            column.isUserInteractionEnabled = false
            column.translatesAutoresizingMaskIntoConstraints = false
            addSubview(column)
            NSLayoutConstraint.activate([
                column.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
                column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
                column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

// MARK: - Caption

final class PaddedCaptionLabel: UILabel {

    private let insets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = RecapTheme.body(12.5, weight: .medium)
        textColor = .white
        numberOfLines = 2
        textAlignment = .center
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

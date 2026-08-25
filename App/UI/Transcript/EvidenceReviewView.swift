//
//  EvidenceReviewView.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import TranscriptionKit
import AnalysisKit

// The segments mode: transcript rows | time rail with pins | review notes
final class EvidenceReviewView: UIView, UITableViewDataSource, UITableViewDelegate {

    struct Evidence {
        let signal: LectureAnalysis.ExamSignal
        let rowIndex: Int?         // nil when the quote couldn't be matched
        let start: TimeInterval?
    }

    // Reading-friendly row merged from whisper's fragmented segments.
    struct DisplayRow {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let segmentRange: Range<Int>   // original segment indices
    }

    private(set) var evidences: [Evidence] = []
    private var displayRows: [DisplayRow] = []
    private var selectedEvidenceIndex: Int?

    var onGenerateHandout: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let rail = UIView()
    private let railStem = UIView()
    private let branchLayer = CAShapeLayer()
    private var pinButtons: [UIButton] = []

    private let notesScroll = UIScrollView()
    private let notesStack = UIStackView()
    private let notesCountLabel = UILabel()
    private let selectionStatusLabel = UILabel()
    private var noteCards: [NoteCardButton] = []
    private var notesWidthConstraint: NSLayoutConstraint!
    private let resizeHandle = UIView()
    private let resizeLine = UIView()

    private var preferredNotesWidth: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: "notesPaneWidth")
            return stored > 0 ? stored : RecapTheme.notesWidth
        }
        set { UserDefaults.standard.set(newValue, forKey: "notesPaneWidth") }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.paper

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TranscriptRowCell.self, forCellReuseIdentifier: TranscriptRowCell.reuseID)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 96, right: 0)

        rail.clipsToBounds = false
        railStem.backgroundColor = RecapTheme.time.withAlphaComponent(0.42)
        branchLayer.strokeColor = RecapTheme.signal.cgColor
        branchLayer.lineWidth = 1
        branchLayer.isHidden = true
        rail.layer.addSublayer(branchLayer)

        let notesPane = UIView()
        notesPane.backgroundColor = RecapTheme.notesPane

        let heading = UILabel()
        heading.text = String(localized: "证据线索")
        heading.font = RecapTheme.body(13, weight: .semibold)
        heading.textColor = RecapTheme.ink
        notesCountLabel.font = RecapTheme.body(11)
        notesCountLabel.textColor = RecapTheme.quiet
        let headingRow = UIStackView(arrangedSubviews: [heading, UIView(), notesCountLabel])
        headingRow.axis = .horizontal
        headingRow.alignment = .firstBaseline

        selectionStatusLabel.font = RecapTheme.body(11)
        selectionStatusLabel.textColor = RecapTheme.time
        selectionStatusLabel.numberOfLines = 2

        notesStack.axis = .vertical
        notesStack.spacing = 5

        let notesContent = UIStackView(arrangedSubviews: [headingRow, selectionStatusLabel, notesStack])
        notesContent.axis = .vertical
        notesContent.spacing = 8
        notesContent.setCustomSpacing(12, after: selectionStatusLabel)
        notesContent.isLayoutMarginsRelativeArrangement = true
        notesContent.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 24, right: 14)

        notesContent.translatesAutoresizingMaskIntoConstraints = false
        notesScroll.addSubview(notesContent)
        notesPane.addSubview(notesScroll)
        notesScroll.translatesAutoresizingMaskIntoConstraints = false

        for subview in [tableView, rail, notesPane] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        railStem.translatesAutoresizingMaskIntoConstraints = false
        rail.addSubview(railStem)

        resizeLine.backgroundColor = RecapTheme.line
        resizeHandle.addSubview(resizeLine)
        resizeLine.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeHandle)
        resizeHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleResize(_:))))
        resizeHandle.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:))))

        notesWidthConstraint = notesPane.widthAnchor.constraint(equalToConstant: RecapTheme.notesWidth)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.leadingAnchor.constraint(equalTo: tableView.trailingAnchor),
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: RecapTheme.railWidth),
            notesPane.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            notesPane.topAnchor.constraint(equalTo: topAnchor),
            notesPane.bottomAnchor.constraint(equalTo: bottomAnchor),
            notesPane.trailingAnchor.constraint(equalTo: trailingAnchor),
            notesWidthConstraint,
            railStem.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            railStem.topAnchor.constraint(equalTo: rail.topAnchor, constant: 42),
            railStem.bottomAnchor.constraint(equalTo: rail.bottomAnchor, constant: -36),
            railStem.widthAnchor.constraint(equalToConstant: 1),
            notesScroll.topAnchor.constraint(equalTo: notesPane.topAnchor),
            notesScroll.bottomAnchor.constraint(equalTo: notesPane.bottomAnchor),
            notesScroll.leadingAnchor.constraint(equalTo: notesPane.leadingAnchor),
            notesScroll.trailingAnchor.constraint(equalTo: notesPane.trailingAnchor),
            notesContent.topAnchor.constraint(equalTo: notesScroll.contentLayoutGuide.topAnchor),
            notesContent.bottomAnchor.constraint(equalTo: notesScroll.contentLayoutGuide.bottomAnchor),
            notesContent.leadingAnchor.constraint(equalTo: notesScroll.contentLayoutGuide.leadingAnchor),
            notesContent.trailingAnchor.constraint(equalTo: notesScroll.contentLayoutGuide.trailingAnchor),
            notesContent.widthAnchor.constraint(equalTo: notesScroll.frameLayoutGuide.widthAnchor),
            resizeHandle.centerXAnchor.constraint(equalTo: notesPane.leadingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 9),
            resizeLine.centerXAnchor.constraint(equalTo: resizeHandle.centerXAnchor),
            resizeLine.topAnchor.constraint(equalTo: resizeHandle.topAnchor),
            resizeLine.bottomAnchor.constraint(equalTo: resizeHandle.bottomAnchor),
            resizeLine.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - Notes pane resizing

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        let dx = gesture.translation(in: self).x
        gesture.setTranslation(.zero, in: self)
        let upperBound = min(420, bounds.width * 0.45)
        let width = min(upperBound, max(200, notesWidthConstraint.constant - dx))
        notesWidthConstraint.constant = width
        preferredNotesWidth = width
        if gesture.state == .began || gesture.state == .changed {
            resizeLine.backgroundColor = RecapTheme.quiet
        } else {
            resizeLine.backgroundColor = RecapTheme.line
        }
        layoutIfNeeded()
        layoutPins()
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            resizeLine.backgroundColor = RecapTheme.quiet
        default:
            resizeLine.backgroundColor = RecapTheme.line
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Content

    // Merges fragments into rows: break on long pauses (semantic gaps), sentence-ending punctuation past a minimum, or a length cap.
    static func mergeRows(_ segments: [TranscriptSegment]) -> [DisplayRow] {
        var rows: [DisplayRow] = []
        var buffer = ""
        var bufferStart: TimeInterval = 0
        var rangeStart = 0
        var lastEnd: TimeInterval = 0

        func flush(upTo endIndex: Int) {
            let trimmed = buffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                rows.append(DisplayRow(start: bufferStart, end: lastEnd, text: trimmed, segmentRange: rangeStart..<endIndex))
            }
            buffer = ""
            rangeStart = endIndex
        }

        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if buffer.isEmpty {
                bufferStart = segment.start
                rangeStart = index
            } else if segment.start - lastEnd > 2.0 {
                flush(upTo: index)
                bufferStart = segment.start
                rangeStart = index
            }
            buffer += text
            lastEnd = segment.end
            let endsSentence = text.hasSuffix("。") || text.hasSuffix("？") || text.hasSuffix("！")
            if buffer.count >= 64 || (endsSentence && buffer.count >= 24) {
                flush(upTo: index + 1)
            }
        }
        flush(upTo: segments.count)
        return rows
    }

    private func evidenceIndex(forRow row: Int) -> Int? {
        evidences.firstIndex { $0.rowIndex == row }
    }

    // Rows and matches are prepared off the main thread by the controller.
    func update(rows: [DisplayRow], evidences: [Evidence]) {
        self.displayRows = rows
        self.evidences = evidences
        selectedEvidenceIndex = nil
        tableView.reloadData()
        rebuildPins()
        rebuildNotes()
        updateSelectionStatus()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Hide the notes pane when the detail column gets narrow.
        let narrow = bounds.width < 620
        notesWidthConstraint.constant = narrow ? 0 : min(preferredNotesWidth, bounds.width * 0.45)
        resizeHandle.isHidden = narrow
        layoutPins()
    }

    // MARK: - Pins

    private func rebuildPins() {
        pinButtons.forEach { $0.removeFromSuperview() }
        pinButtons = []
        for (index, evidence) in evidences.enumerated() where evidence.rowIndex != nil {
            let pin = UIButton(type: .custom)
            pin.tag = index
            pin.accessibilityLabel = String(localized: "选择 \(Self.timestamp(evidence.start ?? 0)) 重点线索")
            pin.addAction(UIAction { [weak self] action in
                guard let button = action.sender as? UIButton else { return }
                self?.select(evidenceIndex: button.tag, scrollToRow: true)
            }, for: .touchUpInside)
            let dot = UIView()
            dot.isUserInteractionEnabled = false
            dot.backgroundColor = RecapTheme.signal
            dot.layer.cornerRadius = 5
            dot.layer.borderWidth = 2
            dot.layer.borderColor = RecapTheme.paper.cgColor
            dot.layer.shadowColor = RecapTheme.signal.cgColor
            dot.layer.shadowOpacity = 1
            dot.layer.shadowRadius = 0
            dot.layer.shadowOffset = .zero
            dot.tag = 100
            dot.translatesAutoresizingMaskIntoConstraints = false
            pin.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.centerXAnchor.constraint(equalTo: pin.centerXAnchor),
                dot.centerYAnchor.constraint(equalTo: pin.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10),
            ])
            rail.addSubview(pin)
            pinButtons.append(pin)
        }
        layoutPins()
    }

    private func layoutPins() {
        for pin in pinButtons {
            let evidence = evidences[pin.tag]
            guard let row = evidence.rowIndex else {
                pin.isHidden = true
                continue
            }
            let rowRect = tableView.rectForRow(at: IndexPath(row: row, section: 0))
            let inRail = tableView.convert(rowRect, to: rail)
            pin.frame = CGRect(x: (RecapTheme.railWidth - 44) / 2, y: inRail.midY - 22, width: 44, height: 44)
            pin.isHidden = inRail.midY < -10 || inRail.midY > rail.bounds.height + 10
        }
        layoutBranch()
    }

    // The active branch: one horizontal rule crossing the rail from the selected row to its note card (two-segment look from the design).
    private func layoutBranch() {
        guard let selected = selectedEvidenceIndex,
              let pin = pinButtons.first(where: { $0.tag == selected }),
              !pin.isHidden, notesWidthConstraint.constant > 0 else {
            branchLayer.isHidden = true
            return
        }
        let y = pin.frame.midY
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -44, y: y))
        path.addLine(to: CGPoint(x: RecapTheme.railWidth + 46, y: y))
        branchLayer.path = path.cgPath
        branchLayer.isHidden = false
    }

    // MARK: - Notes

    private func rebuildNotes() {
        noteCards.forEach { $0.removeFromSuperview() }
        notesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        noteCards = []

        notesCountLabel.text = evidences.isEmpty ? "" : String(localized: "\(evidences.count) 条线索")

        if evidences.isEmpty {
            let empty = UILabel()
            empty.text = displayRows.isEmpty ? "" : String(localized: "提取重点后，证据线索会出现在这里。")
            empty.font = RecapTheme.body(11)
            empty.textColor = RecapTheme.quiet
            empty.numberOfLines = 0
            notesStack.addArrangedSubview(empty)
            return
        }

        for (index, evidence) in evidences.enumerated() {
            let card = NoteCardButton(evidence: evidence)
            card.tag = index
            card.addAction(UIAction { [weak self] action in
                guard let button = action.sender as? UIButton else { return }
                self?.select(evidenceIndex: button.tag, scrollToRow: true)
            }, for: .touchUpInside)
            noteCards.append(card)
            notesStack.addArrangedSubview(card)
        }

        let generate = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            String(localized: "生成本讲讲义 →"), attributes: AttributeContainer([
                .font: RecapTheme.body(11, weight: .semibold), .foregroundColor: RecapTheme.ink,
            ]))
        config.baseForegroundColor = RecapTheme.ink
        config.background.backgroundColor = RecapTheme.paper
        config.background.strokeColor = RecapTheme.line
        config.background.strokeWidth = 1
        config.background.cornerRadius = 7
        generate.configuration = config
        generate.heightAnchor.constraint(equalToConstant: 34).isActive = true
        generate.addAction(UIAction { [weak self] _ in self?.onGenerateHandout?() }, for: .touchUpInside)
        notesStack.setCustomSpacing(18, after: notesStack.arrangedSubviews.last ?? notesStack)
        notesStack.addArrangedSubview(generate)
    }

    private func updateSelectionStatus() {
        guard let index = selectedEvidenceIndex else {
            selectionStatusLabel.text = evidences.isEmpty ? " " : String(localized: "选择一条证据")
            return
        }
        let evidence = evidences[index]
        var parts: [String] = []
        if let start = evidence.start { parts.append(Self.timestamp(start)) }
        parts.append(evidence.signal.strength)
        if let topic = evidence.signal.topic, !topic.isEmpty { parts.append(topic) }
        selectionStatusLabel.text = String(localized: "当前证据：") + parts.joined(separator: " · ")
    }

    // MARK: - Selection

    func select(evidenceIndex: Int, scrollToRow: Bool) {
        selectedEvidenceIndex = evidenceIndex
        for (index, card) in noteCards.enumerated() {
            card.isActive = index == evidenceIndex
        }
        for pin in pinButtons {
            let active = pin.tag == evidenceIndex
            if let dot = pin.viewWithTag(100) {
                dot.layer.shadowOpacity = 1
                dot.layer.shadowRadius = active ? 5 : 0
                dot.layer.shadowColor = (active ? RecapTheme.signalSoft : RecapTheme.signal).cgColor
            }
        }
        updateSelectionStatus()
        if scrollToRow, let row = evidences[evidenceIndex].rowIndex {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: true)
        }
        tableView.reloadData()
        setNeedsLayout()
    }

    // MARK: - UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TranscriptRowCell.reuseID, for: indexPath) as! TranscriptRowCell
        let row = displayRows[indexPath.row]
        let evidenceIndex = evidenceIndex(forRow: indexPath.row)
        cell.configure(
            start: row.start,
            text: row.text,
            evidence: evidenceIndex.map { evidences[$0] },
            isFocused: evidenceIndex != nil && evidenceIndex == selectedEvidenceIndex
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if let evidenceIndex = evidenceIndex(forRow: indexPath.row) {
            select(evidenceIndex: evidenceIndex, scrollToRow: false)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutPins()
    }

    static func timestamp(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

// Transcript row: mono timecode column + body
final class TranscriptRowCell: UITableViewCell {

    static let reuseID = "TranscriptRowCell"

    private let container = UIView()
    private let timeLabel = UILabel()
    private let bodyLabel = UILabel()
    private let annotationLabel = UILabel()
    private let markRule = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        container.layer.cornerRadius = RecapTheme.radiusRow
        container.layer.cornerCurve = .continuous

        timeLabel.font = RecapTheme.mono(11, weight: .semibold)
        timeLabel.textColor = RecapTheme.time

        bodyLabel.numberOfLines = 0
        annotationLabel.numberOfLines = 0

        markRule.layer.cornerRadius = 1

        for subview in [container, markRule] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        for subview in [timeLabel, bodyLabel, annotationLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            markRule.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            markRule.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            markRule.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            markRule.widthAnchor.constraint(equalToConstant: 2),
            timeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            timeLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 17),
            timeLabel.widthAnchor.constraint(equalToConstant: RecapTheme.timeColumnWidth),
            bodyLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 18),
            bodyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            bodyLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            annotationLabel.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),
            annotationLabel.trailingAnchor.constraint(equalTo: bodyLabel.trailingAnchor),
            annotationLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 8),
            annotationLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
        ])
        let bodyBottom = bodyLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        bodyBottom.priority = .defaultHigh
        bodyBottom.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(start: TimeInterval, text rowText: String, evidence: EvidenceReviewView.Evidence?, isFocused: Bool) {
        timeLabel.text = EvidenceReviewView.timestamp(start)
        let text = rowText

        if let evidence {
            bodyLabel.font = RecapTheme.display(16, weight: .medium)
            bodyLabel.textColor = RecapTheme.ink
            bodyLabel.attributedText = NSAttributedString(string: text, attributes: [
                .font: RecapTheme.display(16, weight: .medium),
                .paragraphStyle: Self.paragraph(lineHeightMultiple: 1.35),
                .foregroundColor: RecapTheme.ink,
            ])
            let annotation = NSMutableAttributedString(
                string: evidence.signal.strength + "  ",
                attributes: [.font: RecapTheme.body(11, weight: .semibold), .foregroundColor: RecapTheme.signalText])
            var detail = String(localized: "老师原话已保留")
            if let qtype = evidence.signal.qtype, !qtype.isEmpty { detail += " · \(qtype)" }
            annotation.append(NSAttributedString(
                string: detail,
                attributes: [.font: RecapTheme.body(11), .foregroundColor: RecapTheme.muted]))
            annotationLabel.attributedText = annotation
            annotationLabel.isHidden = false
            markRule.isHidden = false
            markRule.backgroundColor = RecapTheme.signal
            container.backgroundColor = isFocused ? RecapTheme.markedRowFocused : RecapTheme.markedRow
            container.layer.borderWidth = isFocused ? 1 : 0
            container.layer.borderColor = RecapTheme.signal.withAlphaComponent(0.34).cgColor
        } else {
            bodyLabel.attributedText = NSAttributedString(string: text, attributes: [
                .font: RecapTheme.body(15),
                .paragraphStyle: Self.paragraph(lineHeightMultiple: 1.3),
                .foregroundColor: RecapTheme.ink,
            ])
            annotationLabel.isHidden = true
            annotationLabel.attributedText = nil
            markRule.isHidden = true
            container.backgroundColor = .clear
            container.layer.borderWidth = 0
        }
    }

    private static func paragraph(lineHeightMultiple: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }
}

// Evidence note card in the review margin.
final class NoteCardButton: UIButton {

    var isActive = false {
        didSet { backgroundColor = isActive ? RecapTheme.paper.withAlphaComponent(0.72) : .clear }
    }

    init(evidence: EvidenceReviewView.Evidence) {
        super.init(frame: .zero)
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous

        let kind = UILabel()
        var kindText = evidence.signal.strength
        if let qtype = evidence.signal.qtype, !qtype.isEmpty { kindText += " · \(qtype)" }
        kind.text = kindText
        kind.font = RecapTheme.body(11, weight: .semibold)
        kind.textColor = RecapTheme.signalText

        let topic = UILabel()
        topic.text = evidence.signal.topic?.isEmpty == false
            ? evidence.signal.topic
            : String(evidence.signal.quote.prefix(12))
        topic.font = RecapTheme.display(17, weight: .semibold)
        topic.textColor = RecapTheme.ink
        topic.numberOfLines = 2

        let quote = UILabel()
        quote.text = evidence.signal.quote
        quote.font = RecapTheme.body(11)
        quote.textColor = RecapTheme.muted
        quote.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [kind, topic, quote])
        stack.axis = .vertical
        stack.spacing = 7
        stack.isUserInteractionEnabled = false

        if let start = evidence.start {
            let back = UILabel()
            back.text = String(localized: "回到 \(EvidenceReviewView.timestamp(start))")
            back.font = RecapTheme.body(11, weight: .medium)
            back.textColor = RecapTheme.time
            stack.addArrangedSubview(back)
            stack.setCustomSpacing(11, after: quote)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

//
//  TranscriptViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import TranscriptionKit

/// Detail column: segments with timestamps, or plain text.
final class TranscriptViewController: UIViewController, UITableViewDataSource {

    private let lecture: Lecture
    private let course: Course

    private var segments: [TranscriptSegment] = []
    private var plainText: String = ""

    private let modePicker = UISegmentedControl(items: ["分段", "全文"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let textView = UITextView()
    private let emptyLabel = UILabel()

    init(lecture: Lecture, course: Course) {
        self.lecture = lecture
        self.course = course
        super.init(nibName: nil, bundle: nil)
        title = lecture.name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        modePicker.selectedSegmentIndex = 0
        modePicker.addAction(UIAction { [weak self] _ in self?.applyMode() }, for: .valueChanged)
        navigationItem.titleView = modePicker

        tableView.dataSource = self
        tableView.register(SegmentCell.self, forCellReuseIdentifier: SegmentCell.reuseID)
        tableView.separatorStyle = .none
        tableView.allowsSelection = false

        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center

        for subview in [tableView, textView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }

        loadContent()
        applyMode()
    }

    private func loadContent() {
        let store = LibraryStore.shared
        if let data = try? Data(contentsOf: store.productURL(lecture, in: course, ext: "segments.json")),
           let decoded = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
            segments = decoded
        }
        plainText = (try? String(contentsOf: store.productURL(lecture, in: course, ext: "txt"), encoding: .utf8)) ?? ""
    }

    private func applyMode() {
        let hasContent = !segments.isEmpty || !plainText.isEmpty
        emptyLabel.isHidden = hasContent
        if !hasContent {
            emptyLabel.text = lecture.phase == .failed
                ? "转写失败：\(lecture.errorMessage ?? "未知错误")"
                : "尚无文稿——转写完成后在这里查看"
            tableView.isHidden = true
            textView.isHidden = true
            return
        }
        let showSegments = modePicker.selectedSegmentIndex == 0
        tableView.isHidden = !showSegments
        textView.isHidden = showSegments
        if showSegments {
            tableView.reloadData()
        } else {
            textView.text = plainText
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        segments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SegmentCell.reuseID, for: indexPath) as! SegmentCell
        cell.configure(with: segments[indexPath.row])
        return cell
    }
}

/// Timestamp + text row. The timestamp is a future seek target for the player.
final class SegmentCell: UITableViewCell {

    static let reuseID = "SegmentCell"

    private let timeLabel = UILabel()
    private let bodyLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .tintColor
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [timeLabel, bodyLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with segment: TranscriptSegment) {
        let total = Int(segment.start)
        timeLabel.text = String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        bodyLabel.text = segment.text.trimmingCharacters(in: .whitespaces)
    }
}

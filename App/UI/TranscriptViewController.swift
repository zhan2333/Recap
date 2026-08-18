//
//  TranscriptViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import TranscriptionKit
import AnalysisKit

/// Detail column: segments with timestamps, plain text, or exam-signal analysis.
final class TranscriptViewController: UIViewController, UITableViewDataSource {

    private let lecture: Lecture
    private let course: Course

    private var segments: [TranscriptSegment] = []
    private var plainText: String = ""
    private var analysis: LectureAnalysis?
    private var isAnalyzing = false

    private let modePicker = UISegmentedControl(items: ["分段", "全文", "考点"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let textView = UITextView()
    private let analysisTable = UITableView(frame: .zero, style: .insetGrouped)
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
        updateAnalyzeButton()

        tableView.dataSource = self
        tableView.register(SegmentCell.self, forCellReuseIdentifier: SegmentCell.reuseID)
        tableView.separatorStyle = .none
        tableView.allowsSelection = false

        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        analysisTable.dataSource = self
        analysisTable.register(UITableViewCell.self, forCellReuseIdentifier: "AnalysisCell")
        analysisTable.allowsSelection = false

        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0

        for subview in [tableView, textView, analysisTable, emptyLabel] {
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
        if let data = try? Data(contentsOf: store.productURL(lecture, in: course, ext: "analysis.json")),
           let decoded = try? JSONDecoder().decode(LectureAnalysis.self, from: data) {
            analysis = decoded
        }
    }

    private func applyMode() {
        let mode = modePicker.selectedSegmentIndex
        tableView.isHidden = true
        textView.isHidden = true
        analysisTable.isHidden = true
        emptyLabel.isHidden = true

        switch mode {
        case 0 where !segments.isEmpty:
            tableView.isHidden = false
            tableView.reloadData()
        case 1 where !plainText.isEmpty:
            textView.isHidden = false
            textView.text = plainText
        case 2 where analysis != nil:
            analysisTable.isHidden = false
            analysisTable.reloadData()
        default:
            emptyLabel.isHidden = false
            if mode == 2 {
                emptyLabel.text = isAnalyzing
                    ? "正在提取考点…"
                    : plainText.isEmpty ? "先完成转写，再提取考点" : "点右上角 ✨ 提取本讲考点"
            } else {
                emptyLabel.text = lecture.phase == .failed
                    ? "转写失败：\(lecture.errorMessage ?? "未知错误")"
                    : "尚无文稿——转写完成后在这里查看"
            }
        }
    }

    // MARK: - Analysis

    private func updateAnalyzeButton() {
        if isAnalyzing {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "sparkles"),
                primaryAction: UIAction { [weak self] _ in self?.analyze() }
            )
            navigationItem.rightBarButtonItem?.isEnabled = !plainText.isEmpty
        }
    }

    private func analyze() {
        guard !plainText.isEmpty else { return }
        guard let config = Settings.chatConfig else {
            let alert = UIAlertController(
                title: "先配置 AI 接口",
                message: "在设置里填写 Base URL、API Key 和 Model。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "去设置", style: .default) { [weak self] _ in
                self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
            })
            present(alert, animated: true)
            return
        }

        isAnalyzing = true
        updateAnalyzeButton()
        modePicker.selectedSegmentIndex = 2
        applyMode()

        let transcript = plainText
        Task {
            do {
                let result = try await LectureAnalyzer().extract(transcript: transcript, client: ChatClient(config: config))
                let store = LibraryStore.shared
                try JSONEncoder().encode(result)
                    .write(to: store.productURL(lecture, in: course, ext: "analysis.json"), options: .atomic)
                analysis = result
            } catch {
                let alert = UIAlertController(title: "提取失败", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                present(alert, animated: true)
            }
            isAnalyzing = false
            updateAnalyzeButton()
            applyMode()
        }
    }

    // MARK: - Analysis sections

    private var analysisSections: [(title: String, rows: [String])] {
        guard let analysis else { return [] }
        var sections: [(String, [String])] = []
        if !analysis.examSignals.isEmpty {
            let rows = analysis.examSignals.map { signal in
                var line = "【\(signal.strength)】\(signal.quote)"
                if let topic = signal.topic, !topic.isEmpty { line += "\n知识点：\(topic)" }
                if let qtype = signal.qtype, !qtype.isEmpty { line += "　题型：\(qtype)" }
                return line
            }
            sections.append(("考试信号（老师原话）", rows))
        }
        if !analysis.mustMemorize.isEmpty { sections.append(("必背", analysis.mustMemorize)) }
        if !analysis.answerApproaches.isEmpty { sections.append(("答题套路", analysis.answerApproaches)) }
        if !analysis.confusablePoints.isEmpty { sections.append(("易混易错", analysis.confusablePoints)) }
        if !analysis.keyConcepts.isEmpty { sections.append(("核心概念", analysis.keyConcepts)) }
        if !analysis.assignments.isEmpty { sections.append(("作业 / 思考题", analysis.assignments)) }
        return sections
    }

    // MARK: - UITableViewDataSource (segments table + analysis table)

    func numberOfSections(in tableView: UITableView) -> Int {
        tableView === analysisTable ? max(analysisSections.count, 1) : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard tableView === analysisTable, section < analysisSections.count else { return nil }
        return analysisSections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === analysisTable {
            return section < analysisSections.count ? analysisSections[section].rows.count : 0
        }
        return segments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === analysisTable {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AnalysisCell", for: indexPath)
            var content = UIListContentConfiguration.cell()
            content.text = analysisSections[indexPath.section].rows[indexPath.row]
            content.textProperties.numberOfLines = 0
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            cell.contentConfiguration = content
            return cell
        }
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

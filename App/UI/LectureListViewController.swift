//
//  LectureListViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import AnalysisKit

/// Middle column: lectures of one course, with live queue state.
final class LectureListViewController: UIViewController, UICollectionViewDelegate {

    private enum Section { case main }

    private let course: Course
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!
    private var selectedLectureID: UUID?
    private var searchText = ""

    private let headerBar = LectureHeaderBar()
    private let searchField = UISearchTextField()

    init(course: Course) {
        self.course = course
        super.init(nibName: nil, bundle: nil)
        title = course.name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.surface
        navigationController?.navigationBar.isHidden = true

        headerBar.courseLabel.text = course.name
        headerBar.addButton.showsMenuAsPrimaryAction = true

        searchField.placeholder = "搜索讲次"
        searchField.font = RecapTheme.body(12)
        searchField.backgroundColor = RecapTheme.paper.withAlphaComponent(0.72)
        searchField.addAction(UIAction { [weak self] _ in
            self?.searchText = self?.searchField.text ?? ""
            self?.reload()
        }, for: .editingChanged)

        var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfig.showsSeparators = false
        listConfig.backgroundColor = .clear
        listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath)
        }
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            section.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self

        let footer = UIStackView()
        footer.axis = .horizontal
        footer.spacing = 6
        footer.distribution = .fillEqually
        footer.addArrangedSubview(footerButton(title: "粘贴直链") { [weak self] in self?.promptNewLecture() })
        footer.addArrangedSubview(footerButton(title: "导入文件…") { [weak self] in self?.pickLocalFile() })

        for subview in [headerBar, searchField, collectionView, footer] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: safe.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 46),
            searchField.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 7),
            searchField.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 32),
            collectionView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 3),
            collectionView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            footer.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),
            footer.heightAnchor.constraint(equalToConstant: 30),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])

        let cellRegistration = UICollectionView.CellRegistration<LectureCell, UUID> { [weak self] cell, _, lectureID in
            guard let self,
                  let lecture = LibraryStore.shared.lecture(id: lectureID, in: self.course) else { return }
            let index = LibraryStore.shared.lectures(in: self.course).firstIndex { $0.id == lectureID } ?? 0
            cell.configure(
                lecture: lecture,
                number: index + 1,
                activity: LectureQueue.shared.activity(for: lectureID),
                keyPointCount: self.keyPointCount(of: lecture),
                isActive: lectureID == self.selectedLectureID
            )
        }
        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
            collectionView, indexPath, lectureID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: lectureID)
        }

        LectureQueue.shared.onActivity = { [weak self] lectureID in
            self?.reconfigure(lectureID)
        }
        refreshToolsMenu()
        reload()
    }

    /// Cell configuration path — cache so scrolling never touches disk.
    private var keyPointCounts: [UUID: Int?] = [:]

    private func keyPointCount(of lecture: Lecture) -> Int? {
        if let cached = keyPointCounts[lecture.id] { return cached }
        var count: Int?
        if let data = try? Data(contentsOf: LibraryStore.shared.productURL(lecture, in: course, ext: "analysis.json")),
           let analysis = try? JSONDecoder().decode(LectureAnalysis.self, from: data) {
            count = analysis.examSignals.count
        }
        keyPointCounts[lecture.id] = count
        return count
    }

    private func footerButton(title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: RecapTheme.body(11), .foregroundColor: RecapTheme.muted,
        ]))
        config.baseForegroundColor = RecapTheme.muted
        config.background.backgroundColor = RecapTheme.paper
        config.background.strokeColor = RecapTheme.ink.withAlphaComponent(0.16)
        config.background.strokeWidth = 1
        config.background.cornerRadius = RecapTheme.radiusSM
        let button = UIButton(configuration: config)
        button.tintColor = RecapTheme.muted
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Data

    private var visibleLectures: [Lecture] {
        let all = LibraryStore.shared.lectures(in: course)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func reload() {
        keyPointCounts.removeAll()
        let lectures = visibleLectures
        headerBar.countLabel.text = lectures.isEmpty && searchText.isEmpty
            ? "还没有讲次"
            : "\(lectures.count) 个讲次"
        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(lectures.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
        var reconfigure = dataSource.snapshot()
        reconfigure.reconfigureItems(reconfigure.itemIdentifiers)
        dataSource.apply(reconfigure, animatingDifferences: false)
    }

    private func reconfigure(_ lectureID: UUID) {
        keyPointCounts.removeValue(forKey: lectureID)
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(lectureID) else { return reload() }
        snapshot.reconfigureItems([lectureID])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Add lecture

    private func promptNewLecture() {
        let sheet = BatchAddLectureSheet()
        sheet.existingLectureCount = LibraryStore.shared.lectures(in: course).count
        sheet.onSubmit = { [weak self] entries in
            guard let self else { return }
            for entry in entries {
                let lecture = LibraryStore.shared.addLecture(named: entry.name, url: entry.url, to: self.course)
                LectureQueue.shared.enqueue(lecture, in: self.course)
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func pickLocalFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .audio], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Course tools (textbook + exam digest)

    private var isWorking = false

    private func refreshToolsMenu() {
        let addActions = [
            UIAction(title: "粘贴直链入队", image: UIImage(systemName: "link")) { [weak self] _ in
                self?.promptNewLecture()
            },
            UIAction(title: "导入本地文件", image: UIImage(systemName: "folder")) { [weak self] _ in
                self?.pickLocalFile()
            },
        ]
        let revealAction = UIAction(title: "在访达中显示课程目录", image: UIImage(systemName: "folder.badge.gearshape")) { [weak self] _ in
            guard let self else { return }
            let dir = LibraryStore.shared.courseDirectory(self.course)
            UIApplication.shared.open(URL(fileURLWithPath: dir.path, isDirectory: true))
        }
        headerBar.addButton.menu = UIMenu(children: [
            UIMenu(options: .displayInline, children: addActions),
            UIMenu(options: .displayInline, children: courseToolActions),
            UIMenu(options: .displayInline, children: [revealAction]),
        ])
        headerBar.isWorking = isWorking
    }

    private var courseToolActions: [UIAction] {
        let store = LibraryStore.shared
        var actions: [UIAction] = [
            UIAction(title: "导入教材 PDF", image: UIImage(systemName: "doc.badge.plus")) { [weak self] _ in
                self?.pickTextbook()
            },
        ]
        if let text = try? String(contentsOf: store.courseFileURL(course, name: "textbook.txt"), encoding: .utf8),
           !text.isEmpty {
            actions.append(UIAction(title: "查看教材全文", image: UIImage(systemName: "text.book.closed")) { [weak self] _ in
                guard let self else { return }
                (self.splitViewController as? MainSplitViewController)?
                    .show(markdown: text, title: "\(self.course.name) 教材")
            })
        }
        actions.append(UIAction(title: "生成考试重点", image: UIImage(systemName: "star.circle")) { [weak self] _ in
            self?.generateDigest()
        })
        if let digest = try? String(contentsOf: store.courseFileURL(course, name: "review.md"), encoding: .utf8),
           !digest.isEmpty {
            actions.append(UIAction(title: "查看考试重点", image: UIImage(systemName: "star.fill")) { [weak self] _ in
                guard let self else { return }
                (self.splitViewController as? MainSplitViewController)?
                    .show(markdown: digest, title: "\(self.course.name)考试重点")
            })
        }
        return actions
    }

    private func pickTextbook() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func importTextbook(from url: URL) {
        guard !isWorking else { return }
        isWorking = true
        refreshToolsMenu()
        Task {
            do {
                let text = try await TextbookImporter.extractText(from: url)
                try text.write(
                    to: LibraryStore.shared.courseFileURL(course, name: "textbook.txt"),
                    atomically: true, encoding: .utf8
                )
                let pages = text.components(separatedBy: "【第").count - 1
                presentInfo(title: "教材导入完成", message: "共提取 \(pages) 页文本。")
            } catch {
                presentInfo(title: "导入失败", message: error.localizedDescription)
            }
            isWorking = false
            refreshToolsMenu()
        }
    }

    private func generateDigest() {
        guard !isWorking else { return }
        guard let config = Settings.chatConfig else {
            presentInfo(title: "先配置 AI 接口", message: "在设置里填写 Base URL、API Key 和 Model。")
            return
        }
        let store = LibraryStore.shared
        let inputs: [(title: String, analysis: LectureAnalysis)] = store.lectures(in: course).compactMap { lecture in
            guard let data = try? Data(contentsOf: store.productURL(lecture, in: course, ext: "analysis.json")),
                  let analysis = try? JSONDecoder().decode(LectureAnalysis.self, from: data)
            else { return nil }
            return (lecture.name, analysis)
        }
        guard !inputs.isEmpty else {
            presentInfo(title: "没有可汇总的讲次", message: "先对讲次逐个「提取重点」，再生成考试重点。")
            return
        }

        isWorking = true
        refreshToolsMenu()
        let courseName = course.name
        Task {
            do {
                let markdown = try await HandoutGenerator().courseDigest(
                    courseName: courseName,
                    lectures: inputs,
                    client: ChatClient(config: config)
                )
                try markdown.write(
                    to: store.courseFileURL(course, name: "review.md"),
                    atomically: true, encoding: .utf8
                )
                (splitViewController as? MainSplitViewController)?
                    .show(markdown: markdown, title: "\(courseName)考试重点")
            } catch {
                presentInfo(title: "生成失败", message: error.localizedDescription)
            }
            isWorking = false
            refreshToolsMenu()
        }
    }

    private func presentInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let lectureID = dataSource.itemIdentifier(for: indexPath),
              let lecture = LibraryStore.shared.lecture(id: lectureID, in: course) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { return done(false) }
            LibraryStore.shared.deleteLecture(lecture, in: self.course)
            self.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let lectureID = dataSource.itemIdentifier(for: indexPath),
              let lecture = LibraryStore.shared.lecture(id: lectureID, in: course) else { return }
        selectedLectureID = lectureID
        reload()
        (splitViewController as? MainSplitViewController)?.show(lecture: lecture, in: course)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let lectureID = dataSource.itemIdentifier(for: indexPath),
              let lecture = LibraryStore.shared.lecture(id: lectureID, in: course) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            self?.contextMenu(for: lecture)
        })
    }

    private func contextMenu(for lecture: Lecture) -> UIMenu {
        let store = LibraryStore.shared
        let isBusy = LectureQueue.shared.activity(for: lecture.id) != nil
        let mediaExists = FileManager.default.fileExists(atPath: store.mediaURL(lecture, in: course).path)

        var workActions: [UIAction] = []
        if !isBusy {
            if mediaExists {
                let title: String
                switch lecture.phase {
                case .transcribed: title = "重新转写"
                case .failed: title = "重试转写"
                default: title = "开始转写"
                }
                workActions.append(UIAction(title: title, image: UIImage(systemName: "waveform")) { [weak self] _ in
                    guard let self else { return }
                    LectureQueue.shared.retranscribe(lecture, in: self.course)
                })
            }
            if lecture.sourceURL != nil {
                workActions.append(UIAction(
                    title: mediaExists ? "重新下载并转写" : "下载并转写",
                    image: UIImage(systemName: "arrow.down.circle")
                ) { [weak self] _ in
                    guard let self else { return }
                    LectureQueue.shared.enqueue(lecture, in: self.course)
                })
            }
        }

        let rename = UIAction(title: "重命名…", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.promptRename(lecture)
        }
        let reveal = UIAction(title: "在访达中显示", image: UIImage(systemName: "folder")) { [weak self] _ in
            guard let self else { return }
            let dir = store.courseDirectory(self.course)
            UIApplication.shared.open(URL(fileURLWithPath: dir.path, isDirectory: true))
        }
        let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            LibraryStore.shared.deleteLecture(lecture, in: self.course)
            self.reload()
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: workActions),
            UIMenu(options: .displayInline, children: [rename, reveal]),
            UIMenu(options: .displayInline, children: [delete]),
        ])
    }

    private func promptRename(_ lecture: Lecture) {
        let alert = UIAlertController(title: "重命名讲次", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = lecture.name }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            var renamed = lecture
            renamed.name = name
            LibraryStore.shared.updateLecture(renamed, in: self.course)
        })
        present(alert, animated: true)
    }
}

extension LectureListViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let first = urls.first, first.pathExtension.lowercased() == "pdf" {
            importTextbook(from: first)
            return
        }
        let store = LibraryStore.shared
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            var lecture = store.addLecture(named: name, url: nil, to: course)
            do {
                try FileManager.default.copyItem(at: url, to: store.mediaURL(lecture, in: course))
                lecture.phase = .downloaded
                store.updateLecture(lecture, in: course)
                LectureQueue.shared.retranscribe(lecture, in: course)
            } catch {
                lecture.phase = .failed
                lecture.errorMessage = error.localizedDescription
                store.updateLecture(lecture, in: course)
            }
        }
        reload()
    }
}

/// Two-line header: course name over lecture count, one quiet add button
/// trailing (its menu carries both lecture sources and course tools).
final class LectureHeaderBar: UIView {

    let courseLabel = UILabel()
    let countLabel = UILabel()
    let addButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    var isWorking = false {
        didSet {
            addButton.isHidden = isWorking
            spinner.isHidden = !isWorking
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        courseLabel.font = RecapTheme.body(11)
        courseLabel.textColor = RecapTheme.quiet
        countLabel.font = RecapTheme.body(13, weight: .semibold)
        countLabel.textColor = RecapTheme.ink

        let titles = UIStackView(arrangedSubviews: [courseLabel, countLabel])
        titles.axis = .vertical
        titles.spacing = 1

        var addConfig = UIButton.Configuration.plain()
        addConfig.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        addConfig.attributedTitle = AttributedString("添加讲次", attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        addConfig.imagePadding = 4
        addConfig.baseForegroundColor = RecapTheme.muted
        addConfig.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        addConfig.indicator = .none
        addButton.configuration = addConfig
        addButton.tintColor = RecapTheme.muted

        spinner.hidesWhenStopped = false
        spinner.isHidden = true
        spinner.startAnimating()

        let bottomLine = UIView()
        bottomLine.backgroundColor = RecapTheme.ink.withAlphaComponent(0.08)

        for subview in [titles, addButton, spinner, bottomLine] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titles.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titles.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.leadingAnchor.constraint(greaterThanOrEqualTo: titles.trailingAnchor, constant: 8),
            spinner.centerXAnchor.constraint(equalTo: addButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Lecture row: number column, title/status, trailing state glyph,
/// inline progress while transcribing, active left rule.
final class LectureCell: UICollectionViewCell {

    private let numberLabel = UILabel()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let stateLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let activeRule = UIView()
    private var progressWidth: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        contentView.layer.cornerRadius = 7
        contentView.layer.cornerCurve = .continuous

        numberLabel.font = RecapTheme.mono(11, weight: .semibold)
        numberLabel.textColor = RecapTheme.quiet
        titleLabel.font = RecapTheme.body(13, weight: .semibold)
        titleLabel.textColor = RecapTheme.ink
        statusLabel.font = RecapTheme.body(11)
        statusLabel.textColor = RecapTheme.muted
        stateLabel.font = RecapTheme.body(11, weight: .semibold)
        stateLabel.textAlignment = .center

        progressTrack.backgroundColor = RecapTheme.time.withAlphaComponent(0.16)
        progressTrack.layer.cornerRadius = 1.5
        progressTrack.isHidden = true
        progressFill.backgroundColor = RecapTheme.time
        progressFill.layer.cornerRadius = 1.5

        activeRule.backgroundColor = RecapTheme.time
        activeRule.layer.cornerRadius = 1
        activeRule.isHidden = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, progressTrack])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.setCustomSpacing(6, after: statusLabel)

        progressTrack.addSubview(progressFill)
        for subview in [numberLabel, textStack, stateLabel, activeRule] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressWidth = progressFill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: 0)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
            numberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            numberLabel.widthAnchor.constraint(equalToConstant: 28),
            numberLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 8),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            stateLabel.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 8),
            stateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stateLabel.widthAnchor.constraint(equalToConstant: 24),
            stateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressWidth,
            activeRule.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            activeRule.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            activeRule.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            activeRule.widthAnchor.constraint(equalToConstant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        lecture: Lecture,
        number: Int,
        activity: LectureQueue.Activity?,
        keyPointCount: Int?,
        isActive: Bool
    ) {
        numberLabel.text = String(format: "%02d", number)
        titleLabel.text = lecture.name
        activeRule.isHidden = !isActive
        contentView.backgroundColor = isActive ? RecapTheme.selection : .clear

        var progress: Double?
        if let activity {
            switch activity {
            case .downloading(let value):
                statusLabel.text = "下载中 \(Int(value * 100))%"
                progress = value
                stateLabel.text = "\(Int(value * 100))"
                stateLabel.textColor = RecapTheme.quiet
            case .waitingToTranscribe:
                statusLabel.text = "排队等待转写"
                stateLabel.text = "·"
                stateLabel.textColor = RecapTheme.quiet
            case .transcribing(let value):
                statusLabel.text = "转写中 \(Int(value * 100))%"
                progress = value
                stateLabel.text = "\(Int(value * 100))"
                stateLabel.textColor = RecapTheme.quiet
            case .analyzing:
                statusLabel.text = "正在提取重点…"
                stateLabel.text = "✦"
                stateLabel.textColor = RecapTheme.signalText
            }
        } else {
            switch lecture.phase {
            case .pending:
                statusLabel.text = "等待处理"
                stateLabel.text = "·"
                stateLabel.textColor = RecapTheme.quiet
            case .downloaded:
                statusLabel.text = "文稿未转写"
                stateLabel.text = "·"
                stateLabel.textColor = RecapTheme.quiet
            case .transcribed:
                if let keyPointCount, keyPointCount > 0 {
                    statusLabel.text = "已完成 · \(keyPointCount) 个重点"
                } else {
                    statusLabel.text = "文稿已就绪 · 等待提取重点"
                }
                stateLabel.text = keyPointCount == nil ? "◆" : "✓"
                stateLabel.textColor = keyPointCount == nil ? RecapTheme.time : RecapTheme.complete
            case .failed:
                statusLabel.text = "失败：\(lecture.errorMessage ?? "未知错误")"
                stateLabel.text = "!"
                stateLabel.textColor = RecapTheme.error
            }
        }

        if let progress {
            progressTrack.isHidden = false
            progressWidth.isActive = false
            progressWidth = progressFill.widthAnchor.constraint(
                equalTo: progressTrack.widthAnchor, multiplier: max(0.01, progress))
            progressWidth.isActive = true
        } else {
            progressTrack.isHidden = true
        }
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        if state.isHighlighted && contentView.backgroundColor == .clear {
            contentView.backgroundColor = RecapTheme.hover
        }
    }
}

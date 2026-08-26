//
//  LectureListViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import UniformTypeIdentifiers
import AnalysisKit

// Middle column: lectures of one course, with live queue state.
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

        searchField.placeholder = String(localized: "搜索讲次")
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
        footer.addArrangedSubview(footerButton(title: String(localized: "粘贴直链")) { [weak self] in self?.promptNewLecture() })
        footer.addArrangedSubview(footerButton(title: String(localized: "导入文件…")) { [weak self] in self?.pickLocalFile() })

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
        view.addInteraction(UIDropInteraction(delegate: self))
        refreshToolsMenu()
        reload()
    }

    // Cell configuration path
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
        button.preferredBehavioralStyle = .pad
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
            ? String(localized: "还没有讲次")
            : String(localized: "\(lectures.count) 个讲次")
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

    // Queueing without a model would just fail at transcription
    private func ensureModelReady() -> Bool {
        guard !Settings.modelExists else { return true }
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .pageSheet
        present(onboarding, animated: true)
        return false
    }

    func promptNewLecture() {
        guard ensureModelReady() else { return }
        let sheet = BatchAddLectureSheet()
        sheet.existingLectureCount = LibraryStore.shared.lectures(in: course).count
        sheet.onSubmit = { [weak self] entries in
            guard let self else { return }
            for entry in entries {
                let lecture: Lecture
                if entry.urls.count > 1 {
                    let parts = entry.urls.map { MediaPart(id: UUID(), sourceURL: $0, duration: nil) }
                    lecture = LibraryStore.shared.addLecture(named: entry.name, url: nil, parts: parts, to: self.course)
                } else {
                    lecture = LibraryStore.shared.addLecture(named: entry.name, url: entry.urls[0], to: self.course)
                }
                LectureQueue.shared.enqueue(lecture, in: self.course)
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    func pickLocalFile() {
        guard ensureModelReady() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .audio], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Course tools (textbook + exam digest)

    private var isWorking = false

    private func refreshToolsMenu() {
        let addActions = [
            UIAction(title: String(localized: "粘贴直链入队"), image: UIImage(systemName: "link")) { [weak self] _ in
                self?.promptNewLecture()
            },
            UIAction(title: String(localized: "导入本地文件"), image: UIImage(systemName: "folder")) { [weak self] _ in
                self?.pickLocalFile()
            },
        ]
        let revealAction = UIAction(title: String(localized: "在访达中显示课程目录"), image: UIImage(systemName: "folder.badge.gearshape")) { [weak self] _ in
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
            UIAction(title: String(localized: "导入教材 PDF"), image: UIImage(systemName: "doc.badge.plus")) { [weak self] _ in
                self?.pickTextbook()
            },
        ]
        if let text = try? String(contentsOf: store.courseFileURL(course, name: "textbook.txt"), encoding: .utf8),
           !text.isEmpty {
            actions.append(UIAction(title: String(localized: "查看教材全文"), image: UIImage(systemName: "text.book.closed")) { [weak self] _ in
                guard let self else { return }
                (self.splitViewController as? MainSplitViewController)?
                    .show(markdown: text, title: String(localized: "\(self.course.name) 教材"))
            })
        }
        actions.append(UIAction(title: String(localized: "生成考试重点"), image: UIImage(systemName: "star.circle")) { [weak self] _ in
            self?.generateDigest()
        })
        let reviewPDF = store.courseFileURL(course, name: "review.pdf")
        if FileManager.default.fileExists(atPath: reviewPDF.path) {
            actions.append(UIAction(title: String(localized: "查看考试重点"), image: UIImage(systemName: "star.fill")) { [weak self] _ in
                guard let self else { return }
                (self.splitViewController as? MainSplitViewController)?
                    .show(pdfAt: reviewPDF, title: String(localized: "\(self.course.name)考试重点"))
            })
        } else if let digest = try? String(contentsOf: store.courseFileURL(course, name: "review.md"), encoding: .utf8),
                  !digest.isEmpty {
            actions.append(UIAction(title: String(localized: "查看考试重点"), image: UIImage(systemName: "star.fill")) { [weak self] _ in
                guard let self else { return }
                (self.splitViewController as? MainSplitViewController)?
                    .show(markdown: digest, title: String(localized: "\(self.course.name)考试重点"))
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
                presentInfo(title: String(localized: "教材导入完成"), message: String(localized: "共提取 \(pages) 页文本。"))
            } catch {
                presentInfo(title: String(localized: "导入失败"), message: error.localizedDescription)
            }
            isWorking = false
            refreshToolsMenu()
        }
    }

    private func generateDigest() {
        guard !isWorking else { return }
        guard let config = Settings.chatConfig else {
            presentInfo(title: String(localized: "先配置 AI 接口"), message: String(localized: "在设置里填写 Base URL、API Key 和 Model。"))
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
            presentInfo(title: String(localized: "没有可汇总的讲次"), message: String(localized: "先对讲次逐个「提取重点」，再生成考试重点。"))
            return
        }

        isWorking = true
        refreshToolsMenu()
        let courseName = course.name
        let courseDir = store.courseDirectory(course)
        let texURL = store.courseFileURL(course, name: "review.tex")
        let pdfURL = store.courseFileURL(course, name: "review.pdf")
        Task {
            do {
                guard let skillURL = Bundle.main.url(forResource: "recap-review-skill", withExtension: "md"),
                      let skill = try? String(contentsOf: skillURL, encoding: .utf8) else {
                    throw NSError(domain: "Recap", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "内置 skill 缺失"),
                    ])
                }
                let tex = try await HandoutGenerator().courseLaTeX(
                    courseName: courseName,
                    lectures: inputs,
                    skill: skill,
                    client: ChatClient(config: config)
                )
                try tex.write(to: texURL, atomically: true, encoding: .utf8)
                try await LaTeXCompiler.compile(texURL: texURL, in: courseDir)
                (splitViewController as? MainSplitViewController)?
                    .show(pdfAt: pdfURL, title: String(localized: "\(courseName)考试重点"))
            } catch {
                presentInfo(title: String(localized: "生成失败"), message: error.localizedDescription)
            }
            isWorking = false
            refreshToolsMenu()
        }
    }

    private func presentInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "好"), style: .default))
        present(alert, animated: true)
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let lectureID = dataSource.itemIdentifier(for: indexPath),
              let lecture = LibraryStore.shared.lecture(id: lectureID, in: course) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: String(localized: "删除")) { [weak self] _, _, done in
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
                case .transcribed: title = String(localized: "重新转写")
                case .failed: title = String(localized: "重试转写")
                default: title = String(localized: "开始转写")
                }
                workActions.append(UIAction(title: title, image: UIImage(systemName: "waveform")) { [weak self] _ in
                    guard let self else { return }
                    LectureQueue.shared.retranscribe(lecture, in: self.course)
                })
            }
            if lecture.sourceURL != nil {
                workActions.append(UIAction(
                    title: mediaExists ? String(localized: "重新下载并转写") : String(localized: "下载并转写"),
                    image: UIImage(systemName: "arrow.down.circle")
                ) { [weak self] _ in
                    guard let self else { return }
                    LectureQueue.shared.enqueue(lecture, in: self.course)
                })
            }
        }

        var appendActions: [UIAction] = []
        if !isBusy {
            appendActions = [
                UIAction(title: String(localized: "追加视频直链…"), image: UIImage(systemName: "text.append")) { [weak self] _ in
                    self?.promptAppendLink(lecture)
                },
                UIAction(title: String(localized: "追加视频文件…"), image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                    self?.pickAppendFiles(lecture)
                },
            ]
        }

        let rename = UIAction(title: String(localized: "重命名…"), image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.promptRename(lecture)
        }
        let updateLink = UIAction(title: String(localized: "更新直链…"), image: UIImage(systemName: "link.badge.plus")) { [weak self] _ in
            self?.promptUpdateLink(lecture)
        }
        let reveal = UIAction(title: String(localized: "在访达中显示"), image: UIImage(systemName: "folder")) { [weak self] _ in
            guard let self else { return }
            let dir = store.courseDirectory(self.course)
            UIApplication.shared.open(URL(fileURLWithPath: dir.path, isDirectory: true))
        }
        let delete = UIAction(title: String(localized: "删除"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            LibraryStore.shared.deleteLecture(lecture, in: self.course)
            self.reload()
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: workActions),
            UIMenu(options: .displayInline, children: appendActions),
            UIMenu(options: .displayInline, children: [rename, updateLink, reveal]),
            UIMenu(options: .displayInline, children: [delete]),
        ])
    }

    // MARK: - Appending parts to an existing lecture

    // Legacy single-media lectures migrate to explicit parts
    private func migratedToParts(_ lecture: Lecture) -> Lecture {
        guard lecture.parts == nil else { return lecture }
        var updated = lecture
        updated.parts = [MediaPart(id: lecture.id, sourceURL: lecture.sourceURL, duration: nil)]
        return updated
    }

    private func promptAppendLink(_ lecture: Lecture) {
        let alert = UIAlertController(
            title: String(localized: "追加视频直链"),
            message: String(localized: "新视频会接在本讲末尾，转写完成后文稿自动拼接。"),
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "https://look.tongji.edu.cn/...mp4?...."
            if let paste = UIPasteboard.general.string, paste.hasPrefix("http") {
                $0.text = paste
            }
        }
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "追加并转写"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let urlString = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  let url = URL(string: urlString), url.host != nil else { return }
            var updated = self.migratedToParts(lecture)
            updated.parts?.append(MediaPart(id: UUID(), sourceURL: url, duration: nil))
            LibraryStore.shared.updateLecture(updated, in: self.course)
            LectureQueue.shared.enqueue(updated, in: self.course)
        })
        present(alert, animated: true)
    }

    private var pendingAppendLecture: Lecture?

    private func pickAppendFiles(_ lecture: Lecture) {
        pendingAppendLecture = lecture
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .audio], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    private func appendFiles(_ urls: [URL], to lecture: Lecture) {
        let store = LibraryStore.shared
        var updated = migratedToParts(lecture)
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        do {
            for source in sorted {
                let part = MediaPart(id: UUID(), sourceURL: nil, duration: nil)
                try FileManager.default.copyItem(at: source, to: store.partMediaURL(part, in: course))
                updated.parts?.append(part)
            }
            store.updateLecture(updated, in: course)
            LectureQueue.shared.retranscribe(updated, in: course)
        } catch {
            updated.errorMessage = error.localizedDescription
            store.updateLecture(updated, in: course)
        }
        reload()
    }

    private func promptUpdateLink(_ lecture: Lecture) {
        let alert = UIAlertController(
            title: String(localized: "更新直链"),
            message: String(localized: "直链 token 过期后，从云课堂重新抓取并粘贴到这里。"),
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = lecture.sourceURL?.absoluteString
            $0.placeholder = "https://look.tongji.edu.cn/...mp4?...."
        }
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "保存"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let urlString = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  let url = URL(string: urlString), url.host != nil else { return }
            var updated = lecture
            updated.sourceURL = url
            LibraryStore.shared.updateLecture(updated, in: self.course)
        })
        present(alert, animated: true)
    }

    private func promptRename(_ lecture: Lecture) {
        let alert = UIAlertController(title: String(localized: "重命名讲次"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = lecture.name }
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "确定"), style: .default) { [weak self, weak alert] _ in
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
        if let target = pendingAppendLecture {
            pendingAppendLecture = nil
            appendFiles(urls, to: target)
            return
        }
        if let first = urls.first, first.pathExtension.lowercased() == "pdf" {
            importTextbook(from: first)
            return
        }
        handleIncomingFiles(urls)
    }

    func handleIncomingFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard urls.count > 1 else {
            urls.forEach { importAsSeparateLecture($0) }
            reload()
            return
        }
        let alert = UIAlertController(
            title: String(localized: "导入 \(urls.count) 个文件"),
            message: String(localized: "多段视频合并为一讲时，转写会拼成一份文稿，重点和讲义共用。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "合并为一个讲次"), style: .default) { [weak self] _ in
            self?.importAsSingleLecture(urls)
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: String(localized: "分别创建 \(urls.count) 个讲次"), style: .default) { [weak self] _ in
            urls.forEach { self?.importAsSeparateLecture($0) }
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        present(alert, animated: true)
    }

    private func importAsSeparateLecture(_ url: URL) {
        let store = LibraryStore.shared
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

    private func importAsSingleLecture(_ urls: [URL]) {
        let store = LibraryStore.shared
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let parts = sorted.map { _ in MediaPart(id: UUID(), sourceURL: nil, duration: nil) }
        let name = sorted[0].deletingPathExtension().lastPathComponent
        var lecture = store.addLecture(named: name, url: nil, parts: parts, to: course)
        do {
            for (index, source) in sorted.enumerated() {
                try FileManager.default.copyItem(at: source, to: store.partMediaURL(parts[index], in: course))
            }
            lecture.phase = .downloaded
            store.updateLecture(lecture, in: course)
            LectureQueue.shared.retranscribe(lecture, in: course)
        } catch {
            lecture.phase = .failed
            lecture.errorMessage = error.localizedDescription
            store.updateLecture(lecture, in: course)
        }
    }
}

// Two-line header: course name over lecture count, one quiet add button trailing (its menu carries both lecture sources and course tools).
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
        addConfig.attributedTitle = AttributedString(String(localized: "添加讲次"), attributes: AttributeContainer([
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

// Lecture row: number column, title/status, trailing state glyph, inline progress while transcribing, active left rule.
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
                statusLabel.text = String(localized: "下载中 \(Int(value * 100))%")
                progress = value
                stateLabel.text = "\(Int(value * 100))"
                stateLabel.textColor = RecapTheme.quiet
            case .waitingToTranscribe:
                statusLabel.text = String(localized: "排队等待转写")
                stateLabel.text = "·"
                stateLabel.textColor = RecapTheme.quiet
            case .transcribing(let value):
                statusLabel.text = String(localized: "转写中 \(Int(value * 100))%")
                progress = value
                stateLabel.text = "\(Int(value * 100))"
                stateLabel.textColor = RecapTheme.quiet
            case .analyzing:
                statusLabel.text = String(localized: "正在提取重点…")
                stateLabel.text = "✦"
                stateLabel.textColor = RecapTheme.signalText
            }
        } else {
            switch lecture.phase {
            case .pending:
                statusLabel.text = String(localized: "等待处理")
                stateLabel.text = "·"
                stateLabel.textColor = RecapTheme.quiet
            case .downloaded:
                statusLabel.text = String(localized: "文稿未转写")
                stateLabel.text = "·"
                stateLabel.textColor = RecapTheme.quiet
            case .transcribed:
                if let keyPointCount, keyPointCount > 0 {
                    statusLabel.text = String(localized: "已完成 · \(keyPointCount) 个重点")
                } else {
                    statusLabel.text = String(localized: "文稿已就绪 · 等待提取重点")
                }
                stateLabel.text = keyPointCount == nil ? "◆" : "✓"
                stateLabel.textColor = keyPointCount == nil ? RecapTheme.time : RecapTheme.complete
            case .failed:
                statusLabel.text = String(localized: "失败：\(lecture.errorMessage ?? String(localized: "未知错误"))")
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

extension LectureListViewController: UIDropInteractionDelegate {

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: [UTType.audiovisualContent.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for item in session.items {
            group.enter()
            item.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.audiovisualContent.identifier) { url, _ in
                // The provider's URL dies with the callback — copy it out first
                if let url {
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                        urls.append(dest)
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.handleIncomingFiles(urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
    }
}

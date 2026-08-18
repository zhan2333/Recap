//
//  LectureListViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

/// Middle column: lectures of one course, with live queue state.
final class LectureListViewController: UIViewController, UICollectionViewDelegate {

    private enum Section { case main }

    private let course: Course
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!

    init(course: Course) {
        self.course = course
        super.init(nibName: nil, bundle: nil)
        title = course.name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let layout = UICollectionViewCompositionalLayout { _, environment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.swipeActions(at: indexPath)
            }
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> {
            [weak self] cell, _, lectureID in
            guard let self, let lecture = LibraryStore.shared.lecture(id: lectureID, in: self.course) else { return }
            cell.contentConfiguration = Self.content(for: lecture)
            cell.accessories = Self.accessories(for: lecture)
        }
        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
            collectionView, indexPath, lectureID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: lectureID)
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            primaryAction: UIAction { [weak self] _ in self?.promptNewLecture() }
        )

        LectureQueue.shared.onActivity = { [weak self] lectureID in
            self?.reconfigure(lectureID)
        }
        reload()
    }

    // MARK: - Cell content

    private static func content(for lecture: Lecture) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = lecture.name
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)

        if let activity = LectureQueue.shared.activity(for: lecture.id) {
            switch activity {
            case .downloading(let progress):
                content.secondaryText = "下载中 \(Int(progress * 100))%"
            case .waitingToTranscribe:
                content.secondaryText = "排队等待转写"
            case .transcribing(let progress):
                content.secondaryText = "转写中 \(Int(progress * 100))%"
            }
        } else {
            switch lecture.phase {
            case .pending: content.secondaryText = "等待处理"
            case .downloaded: content.secondaryText = "已下载，未转写"
            case .transcribed: content.secondaryText = "已完成"
            case .failed: content.secondaryText = "失败：\(lecture.errorMessage ?? "未知错误")"
            }
        }
        return content
    }

    private static func accessories(for lecture: Lecture) -> [UICellAccessory] {
        if LectureQueue.shared.activity(for: lecture.id) != nil {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            return [.customView(configuration: .init(customView: spinner, placement: .trailing()))]
        }
        switch lecture.phase {
        case .transcribed:
            let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            check.tintColor = .systemGreen
            return [.customView(configuration: .init(customView: check, placement: .trailing()))]
        case .failed:
            let warn = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
            warn.tintColor = .systemOrange
            return [.customView(configuration: .init(customView: warn, placement: .trailing()))]
        default:
            return []
        }
    }

    // MARK: - Data

    private func reload() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(LibraryStore.shared.lectures(in: course).map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func reconfigure(_ lectureID: UUID) {
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(lectureID) else { return reload() }
        snapshot.reconfigureItems([lectureID])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Actions

    private func promptNewLecture() {
        let alert = UIAlertController(
            title: "添加讲次",
            message: "粘贴课程回放的媒体直链（带 token 的 mp4 地址）",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "讲次名（如：第1讲 03-04）" }
        alert.addTextField {
            $0.placeholder = "https://look.tongji.edu.cn/...mp4?...."
            if let paste = UIPasteboard.general.string, paste.hasPrefix("http") {
                $0.text = paste
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "入队", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?[0].text?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let urlString = alert?.textFields?[1].text?.trimmingCharacters(in: .whitespaces),
                  let url = URL(string: urlString) else { return }
            let lecture = LibraryStore.shared.addLecture(named: name, url: url, to: self.course)
            LectureQueue.shared.enqueue(lecture, in: self.course)
        })
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
        (splitViewController as? MainSplitViewController)?.show(lecture: lecture, in: course)
    }
}

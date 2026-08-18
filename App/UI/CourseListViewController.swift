//
//  CourseListViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

/// Sidebar: course list.
final class CourseListViewController: UIViewController, UICollectionViewDelegate {

    private enum Section { case main }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "课程"

        let layout = UICollectionViewCompositionalLayout { _, environment in
            var config = UICollectionLayoutListConfiguration(appearance: .sidebar)
            config.showsSeparators = false
            config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.deleteActions(at: indexPath)
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

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { cell, _, courseID in
            guard let course = LibraryStore.shared.courses.first(where: { $0.id == courseID }) else { return }
            var content = UIListContentConfiguration.sidebarCell()
            content.text = course.name
            content.image = UIImage(systemName: "books.vertical")
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
            collectionView, indexPath, courseID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: courseID)
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            primaryAction: UIAction { [weak self] _ in self?.promptNewCourse() }
        )

        LibraryStore.shared.onChange = { [weak self] in self?.reload() }
        reload()
    }

    private func reload() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(LibraryStore.shared.courses.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func promptNewCourse() {
        let alert = UIAlertController(title: "新建课程", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "课程名（如：习概）" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            let course = LibraryStore.shared.addCourse(named: name)
            self?.select(course)
        })
        present(alert, animated: true)
    }

    private func deleteActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let courseID = dataSource.itemIdentifier(for: indexPath),
              let course = LibraryStore.shared.courses.first(where: { $0.id == courseID }) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "删除") { _, _, done in
            LibraryStore.shared.deleteCourse(course)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func select(_ course: Course) {
        (splitViewController as? MainSplitViewController)?.show(course: course)
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let courseID = dataSource.itemIdentifier(for: indexPath),
              let course = LibraryStore.shared.courses.first(where: { $0.id == courseID }) else { return }
        select(course)
    }
}

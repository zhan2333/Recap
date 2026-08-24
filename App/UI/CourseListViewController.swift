//
//  CourseListViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

// Sidebar: course list, Evidence Thread chrome.
final class CourseListViewController: UIViewController, UICollectionViewDelegate {

    private enum Section { case main }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!
    private var selectedCourseID: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "课程"
        view.backgroundColor = RecapTheme.surface
        navigationController?.navigationBar.isHidden = true

        let paneBar = PaneBar(title: "课程")
        paneBar.addButton.addAction(UIAction { [weak self] _ in self?.promptNewCourse() }, for: .touchUpInside)

        var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfig.showsSeparators = false
        listConfig.backgroundColor = .clear
        listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.deleteActions(at: indexPath)
        }
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8)
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self

        let settingsButton = UIButton(type: .system)
        var settingsConfig = UIButton.Configuration.plain()
        settingsConfig.image = UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        settingsConfig.title = "设置…"
        settingsConfig.imagePadding = 7
        settingsConfig.baseForegroundColor = RecapTheme.muted
        settingsConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        settingsConfig.attributedTitle = AttributedString("设置…", attributes: AttributeContainer([
            .font: RecapTheme.body(12), .foregroundColor: RecapTheme.muted,
        ]))
        settingsButton.configuration = settingsConfig
        settingsButton.tintColor = RecapTheme.muted
        settingsButton.contentHorizontalAlignment = .leading
        settingsButton.addAction(UIAction { [weak self] _ in
            self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
        }, for: .touchUpInside)

        for subview in [paneBar, collectionView, settingsButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            paneBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            paneBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paneBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneBar.heightAnchor.constraint(equalToConstant: 46),
            collectionView.topAnchor.constraint(equalTo: paneBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsButton.topAnchor.constraint(equalTo: collectionView.bottomAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            settingsButton.heightAnchor.constraint(equalToConstant: 34),
            settingsButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])

        let cellRegistration = UICollectionView.CellRegistration<CourseCell, UUID> { [weak self] cell, _, courseID in
            guard let course = LibraryStore.shared.courses.first(where: { $0.id == courseID }) else { return }
            let lectures = LibraryStore.shared.lectures(in: course)
            let analyzed = lectures.filter { lecture in
                FileManager.default.fileExists(
                    atPath: LibraryStore.shared.productURL(lecture, in: course, ext: "analysis.json").path)
            }.count
            cell.configure(
                name: course.name,
                lectureCount: lectures.count,
                analyzedCount: analyzed,
                isActive: courseID == self?.selectedCourseID
            )
        }
        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
            collectionView, indexPath, courseID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: courseID)
        }

        LibraryStore.shared.onChange = { [weak self] in self?.reload() }
        reload()
    }

    private func reload() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(LibraryStore.shared.courses.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
        var reconfigure = dataSource.snapshot()
        reconfigure.reconfigureItems(reconfigure.itemIdentifiers)
        dataSource.apply(reconfigure, animatingDifferences: false)
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
        selectedCourseID = course.id
        reload()
        (splitViewController as? MainSplitViewController)?.show(course: course)
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let courseID = dataSource.itemIdentifier(for: indexPath),
              let course = LibraryStore.shared.courses.first(where: { $0.id == courseID }) else { return }
        select(course)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let courseID = dataSource.itemIdentifier(for: indexPath),
              let course = LibraryStore.shared.courses.first(where: { $0.id == courseID }) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            let rename = UIAction(title: "重命名…", image: UIImage(systemName: "pencil")) { _ in
                self?.promptRename(course)
            }
            let reveal = UIAction(title: "在访达中显示", image: UIImage(systemName: "folder")) { _ in
                let dir = LibraryStore.shared.courseDirectory(course)
                UIApplication.shared.open(URL(fileURLWithPath: dir.path, isDirectory: true))
            }
            let delete = UIAction(title: "删除课程", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDelete(course)
            }
            return UIMenu(children: [
                UIMenu(options: .displayInline, children: [rename, reveal]),
                UIMenu(options: .displayInline, children: [delete]),
            ])
        })
    }

    private func promptRename(_ course: Course) {
        let alert = UIAlertController(title: "重命名课程", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = course.name }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            var renamed = course
            renamed.name = name
            LibraryStore.shared.updateCourse(renamed)
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ course: Course) {
        let lectureCount = LibraryStore.shared.lectures(in: course).count
        let alert = UIAlertController(
            title: "删除「\(course.name)」？",
            message: lectureCount > 0 ? "该课程的 \(lectureCount) 个讲次及全部文稿、重点、讲义都会一并删除。" : nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            LibraryStore.shared.deleteCourse(course)
        })
        present(alert, animated: true)
    }
}

// Shared 46pt pane header: bold title + trailing plus button.
final class PaneBar: UIView {

    let titleLabel = UILabel()
    let addButton = UIButton(type: .system)

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = RecapTheme.body(13, weight: .semibold)
        titleLabel.textColor = RecapTheme.ink

        addButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
            for: .normal
        )
        addButton.tintColor = RecapTheme.muted

        for subview in [titleLabel, addButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// Course row: spine glyph + name/stats + count, ink-tint selection.
final class CourseCell: UICollectionViewCell {

    private let spine = CourseSpineView()
    private let nameLabel = UILabel()
    private let statsLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()

        contentView.layer.cornerRadius = 7
        contentView.layer.cornerCurve = .continuous

        nameLabel.font = RecapTheme.body(13, weight: .medium)
        statsLabel.font = RecapTheme.body(11)
        statsLabel.textColor = RecapTheme.quiet
        countLabel.font = RecapTheme.body(11, weight: .medium)
        countLabel.textColor = RecapTheme.quiet

        let textStack = UIStackView(arrangedSubviews: [nameLabel, statsLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        spine.translatesAutoresizingMaskIntoConstraints = false
        textStack.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spine)
        contentView.addSubview(textStack)
        contentView.addSubview(countLabel)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            spine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            spine.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            spine.widthAnchor.constraint(equalToConstant: 14),
            spine.heightAnchor.constraint(equalToConstant: 12),
            textStack.leadingAnchor.constraint(equalTo: spine.trailingAnchor, constant: 7),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 5),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 7),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, lectureCount: Int, analyzedCount: Int, isActive: Bool) {
        nameLabel.text = name
        if lectureCount == 0 {
            statsLabel.text = "还没有讲次"
        } else if analyzedCount == lectureCount {
            statsLabel.text = "\(lectureCount) 个讲次 · 已完成"
        } else if analyzedCount > 0 {
            statsLabel.text = "\(lectureCount) 个讲次 · \(analyzedCount) 已分析"
        } else {
            statsLabel.text = "\(lectureCount) 个讲次"
        }
        countLabel.text = lectureCount > 0 ? "\(lectureCount)" : ""
        nameLabel.textColor = isActive ? RecapTheme.ink : RecapTheme.muted
        spine.tintColor = isActive ? RecapTheme.ink : RecapTheme.muted
        contentView.backgroundColor = isActive ? RecapTheme.selection : .clear
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        if state.isHighlighted && contentView.backgroundColor == .clear {
            contentView.backgroundColor = RecapTheme.hover
        }
    }
}

// The little book-spine glyph from the design: rounded border + inner rule.
final class CourseSpineView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let color = tintColor.withAlphaComponent(0.64)
        color.setStroke()
        let border = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 2)
        border.lineWidth = 1.5
        border.stroke()
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: 4, y: 2.5))
        rule.addLine(to: CGPoint(x: 4, y: bounds.height - 2.5))
        rule.lineWidth = 1
        rule.stroke()
    }
}

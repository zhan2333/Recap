//
//  PDFOutlineViewController.swift
//  Recap
//
//  Created by Rio on 9/20/26.
//

import UIKit

final class PDFOutlineViewController: UITableViewController {

    private var entries: [PDFNavigation.OutlineEntry]
    private let onSelect: (PDFNavigation.Target) -> Void
    private let reuseIdentifier = "PDFOutlineEntry"

    init(entries: [PDFNavigation.OutlineEntry], onSelect: @escaping (PDFNavigation.Target) -> Void) {
        self.entries = entries
        self.onSelect = onSelect
        super.init(style: .plain)
        title = String(localized: "目录")
        preferredContentSize = CGSize(width: 360, height: 480)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = RecapTheme.paper
        tableView.separatorColor = RecapTheme.line
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.tableFooterView = UIView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: reuseIdentifier)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "完成")
        navigationItem.rightBarButtonItem?.tintColor = RecapTheme.ink
        updateEmptyState()
    }

    func update(entries: [PDFNavigation.OutlineEntry]) {
        self.entries = entries
        guard isViewLoaded else { return }
        tableView.reloadData()
        updateEmptyState()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier, for: indexPath)
        let canNavigate = entry.target != nil
        let pageDescription = entry.pageIndex.map { String(localized: "第 \($0 + 1) 页") }
        var content = cell.defaultContentConfiguration()
        content.text = entry.title
        content.textProperties.font = RecapTheme.body(15, weight: canNavigate ? .regular : .semibold)
        content.textProperties.color = RecapTheme.ink
        content.textProperties.numberOfLines = 2
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryText = pageDescription
        content.secondaryTextProperties.font = RecapTheme.body(12)
        content.secondaryTextProperties.color = RecapTheme.quiet
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12, leading: 16 + CGFloat(min(max(entry.depth, 0), 5)) * 14, bottom: 12, trailing: 16
        )
        cell.contentConfiguration = content
        cell.backgroundColor = RecapTheme.paper
        cell.selectionStyle = canNavigate ? .default : .none
        cell.accessoryType = .none
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = RecapTheme.selection
        cell.selectedBackgroundView = selectedBackground
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = [entry.title, pageDescription].compactMap { $0 }.joined(separator: ", ")
        cell.accessibilityTraits = canNavigate ? .button : .header
        return cell
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        entries[indexPath.row].target == nil ? nil : indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let target = entries[indexPath.row].target else { return }
        let onSelect = onSelect
        dismiss(animated: true) { onSelect(target) }
    }

    private func updateEmptyState() {
        guard entries.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let label = UILabel()
        label.text = String(localized: "此 PDF 没有目录书签")
        label.font = RecapTheme.body(15)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = RecapTheme.quiet
        label.textAlignment = .center
        label.numberOfLines = 0
        tableView.backgroundView = label
    }
}

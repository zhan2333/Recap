//
//  PDFFindViewController.swift
//  Recap
//
//  Created by Rio on 9/20/26.
//

import UIKit
import PDFKit

final class PDFFindViewController: UITableViewController, UISearchResultsUpdating {

    private struct Result {
        let selection: PDFSelection
        let context: String
        let pageIndex: Int
    }

    private let document: PDFDocument
    private let onSelect: (PDFSelection) -> Void
    private let searchController = UISearchController(searchResultsController: nil)
    private let maximumResults = 500
    private var results: [Result] = []
    private var query = ""
    private var generation = 0
    private var isSearching = false
    private var reachedLimit = false
    private var ownsSearch = false
    private var searchTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(document: PDFDocument, onSelect: @escaping (PDFSelection) -> Void) {
        self.document = document
        self.onSelect = onSelect
        super.init(style: .plain)
        title = String(localized: "在 PDF 中查找")
        preferredContentSize = CGSize(width: 420, height: 520)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        searchTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        if ownsSearch { document.cancelFindString() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = RecapTheme.paper
        tableView.separatorColor = RecapTheme.line
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.tableFooterView = UIView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PDFFindResult")
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "输入要查找的文字")
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.close() }
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "完成")
        navigationItem.rightBarButtonItem?.tintColor = RecapTheme.ink
        definesPresentationContext = true
        refreshResults()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true || view.window == nil {
            stopSearch()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let newQuery = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard newQuery != query else { return }
        stopSearch()
        query = newQuery
        results.removeAll()
        reachedLimit = false
        isSearching = !query.isEmpty
        refreshResults()
        guard !query.isEmpty else { return }
        let currentGeneration = generation
        let currentQuery = query
        searchTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            guard let self, self.generation == currentGeneration else { return }
            while self.document.isFinding {
                do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
                guard self.generation == currentGeneration else { return }
            }
            self.observeSearch(generation: currentGeneration)
            self.ownsSearch = true
            self.document.beginFindString(currentQuery, withOptions: .caseInsensitive)
        }
    }

    private func observeSearch(generation: Int) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFDocumentDidFindMatch, object: document, queue: .main) { [weak self] note in
            guard let selection = note.userInfo?[PDFDocumentFoundSelectionKey] as? PDFSelection else { return }
            Task { @MainActor [weak self] in self?.receive(selection, generation: generation) }
        })
        observers.append(center.addObserver(forName: .PDFDocumentDidEndFind, object: document, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.ownsSearch = false
                self.isSearching = false
                self.removeObservers()
                self.refreshResults()
            }
        })
    }

    private func receive(_ selection: PDFSelection, generation: Int) {
        guard self.generation == generation, !reachedLimit,
              let page = selection.pages.first, page.document === document else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, pageIndex < document.pageCount else { return }
        let context = selection.copy() as? PDFSelection
        context?.extend(atStart: 40)
        context?.extend(atEnd: 60)
        let text = (context?.string ?? selection.string ?? query)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        results.append(Result(selection: selection, context: text, pageIndex: pageIndex))
        if results.count >= maximumResults {
            reachedLimit = true
            isSearching = false
            ownsSearch = false
            removeObservers()
            document.cancelFindString()
        }
        refreshResults()
    }

    private func stopSearch() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        removeObservers()
        if ownsSearch { document.cancelFindString() }
        ownsSearch = false
        isSearching = false
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func refreshResults() {
        guard isViewLoaded else { return }
        let status: String
        if query.isEmpty { status = String(localized: "输入要查找的文字") }
        else if reachedLimit { status = String(localized: "已显示前 \(maximumResults) 处结果，请缩小查找范围。") }
        else if isSearching { status = String(localized: "正在查找…") }
        else if results.isEmpty { status = String(localized: "未找到匹配文字") }
        else { status = String(localized: "找到 \(results.count) 处结果") }
        navigationItem.prompt = status
        if results.isEmpty {
            let label = UILabel()
            label.text = status
            label.font = RecapTheme.body(15)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = RecapTheme.quiet
            label.textAlignment = .center
            label.numberOfLines = 0
            tableView.backgroundView = label
        } else { tableView.backgroundView = nil }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let result = results[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "PDFFindResult", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = result.context
        content.textProperties.font = RecapTheme.body(15)
        content.textProperties.color = RecapTheme.ink
        content.textProperties.numberOfLines = 3
        content.textProperties.adjustsFontForContentSizeCategory = true
        let page = String(localized: "第 \(result.pageIndex + 1) 页")
        content.secondaryText = page
        content.secondaryTextProperties.font = RecapTheme.body(12)
        content.secondaryTextProperties.color = RecapTheme.quiet
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        cell.contentConfiguration = content
        cell.backgroundColor = RecapTheme.paper
        cell.accessibilityLabel = "\(result.context), \(page)"
        cell.accessibilityTraits = .button
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = RecapTheme.selection
        cell.selectedBackgroundView = selectedBackground
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selection = results[indexPath.row].selection
        let onSelect = onSelect
        stopSearch()
        searchController.isActive = false
        (navigationController ?? self).dismiss(animated: true) { onSelect(selection) }
    }

    private func close() {
        stopSearch()
        searchController.isActive = false
        (navigationController ?? self).dismiss(animated: true)
    }
}

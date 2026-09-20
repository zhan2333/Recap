//
//  PDFViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit
import PDFKit

// PDFKit renders the document; navigation also handles Catalyst's detached link hit views.
final class PDFViewController: UIViewController, UIDocumentPickerDelegate, PDFViewDelegate {

    private var fileURL: URL
    private let courseID: UUID?
    private let resolveFile: (() -> (url: URL, title: String)?)?
    private let openURL: (URL, @escaping (Bool) -> Void) -> Void
    private var exportStorageToken: UUID?
    private let pdfView = PDFLinkView()
    private let navigationBar = UIToolbar()
    private var detectedPages = Set<ObjectIdentifier>()
    private weak var outlineController: PDFOutlineViewController?
    private weak var findController: PDFFindViewController?

    private lazy var backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"),
        primaryAction: UIAction(title: String(localized: "返回跳转前的位置")) { [weak self] _ in self?.pdfView.goBack(nil) })
    private lazy var forwardButton = UIBarButtonItem(image: UIImage(systemName: "chevron.right"),
        primaryAction: UIAction(title: String(localized: "前进到下一位置")) { [weak self] _ in self?.pdfView.goForward(nil) })
    private lazy var pageButton = UIBarButtonItem(title: "—", style: .plain, target: self, action: #selector(showPagePrompt))
    private lazy var outlineButton = UIBarButtonItem(image: UIImage(systemName: "list.bullet.indent"),
        primaryAction: UIAction(title: String(localized: "目录")) { [weak self] _ in self?.showOutline() })
    private lazy var findButton = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"),
        primaryAction: UIAction(title: String(localized: "在 PDF 中查找")) { [weak self] _ in self?.showFind() })
    private lazy var exportButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"),
        primaryAction: UIAction(title: String(localized: "导出 PDF")) { [weak self] _ in self?.exportPDF() })
    private lazy var invertButton = UIBarButtonItem(image: UIImage(systemName: "circle.lefthalf.filled"),
        primaryAction: UIAction(title: String(localized: "反转 PDF 明暗")) { [weak self] _ in self?.invertsInDark.toggle() })

    init(fileURL: URL, title: String, courseID: UUID? = nil,
         resolveFile: (() -> (url: URL, title: String)?)? = nil,
         openURL: @escaping (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
             UIApplication.shared.open(url, options: [:], completionHandler: completion)
         }) {
        self.fileURL = fileURL
        self.courseID = courseID
        self.resolveFile = resolveFile
        self.openURL = openURL
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let token = exportStorageToken {
            Task { @MainActor in LibraryStore.shared.endUsingStorage(token) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        detectVisibleLinks()
        updateNavigation()
    }

    // Invert luminance and rotate hues so colored emphasis stays recognizable on dark paper.
    private var invertsInDark = UserDefaults.standard.object(forKey: "pdfInvertsInDark") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(invertsInDark, forKey: "pdfInvertsInDark")
            applyAppearance()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        pdfView.delegate = self
        pdfView.onActivateLink = { [weak self] annotation in self?.activateLink(annotation) }
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.pageBreakMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        pdfView.isFindInteractionEnabled = true
        pdfView.document = PDFDocument(url: fileURL)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pathsDidChange(_:)), name: LibraryStore.pathsDidChange, object: nil)
        for name in [Notification.Name.PDFViewChangedHistory, .PDFViewPageChanged, .PDFViewDocumentChanged] {
            center.addObserver(self, selector: #selector(navigationChanged), name: name, object: pdfView)
        }
        center.addObserver(self, selector: #selector(visiblePagesChanged), name: .PDFViewVisiblePagesChanged, object: pdfView)

        backButton.accessibilityLabel = String(localized: "返回跳转前的位置")
        forwardButton.accessibilityLabel = String(localized: "前进到下一位置")
        outlineButton.accessibilityLabel = String(localized: "目录")
        findButton.accessibilityLabel = String(localized: "在 PDF 中查找")
        pageButton.accessibilityLabel = String(localized: "跳转到页码")
        navigationBar.tintColor = RecapTheme.ink
        navigationBar.items = [backButton, forwardButton, .flexibleSpace(), pageButton,
                               .flexibleSpace(), outlineButton, findButton]
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pdfView)
        view.addSubview(navigationBar)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: navigationBar.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            navigationBar.heightAnchor.constraint(equalToConstant: 44),
        ])
        navigationItem.rightBarButtonItems = [exportButton, invertButton]
        updateNavigation()
        applyAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle { applyAppearance() }
    }

    private func applyAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        invertButton.isHidden = !isDark
        if isDark && invertsInDark,
           let invert = CIFilter(name: "CIColorInvert"), let hue = CIFilter(name: "CIHueAdjust") {
            hue.setValue(CGFloat.pi, forKey: kCIInputAngleKey)
            pdfView.layer.filters = [invert, hue]
            pdfView.backgroundColor = UIColor(red: 0.878, green: 0.886, blue: 0.898, alpha: 1)
            invertButton.tintColor = RecapTheme.ink
        } else {
            pdfView.layer.filters = nil
            pdfView.backgroundColor = RecapTheme.canvas
            invertButton.tintColor = RecapTheme.quiet
        }
    }

    // MARK: - Navigation

    @objc private func navigationChanged() { updateNavigation() }
    @objc private func visiblePagesChanged() { detectVisibleLinks() }

    private func updateNavigation() {
        let count = pdfView.document?.pageCount ?? 0
        let hasPages = count > 0 && pdfView.document?.isLocked == false
        backButton.isEnabled = hasPages && pdfView.canGoBack
        forwardButton.isEnabled = hasPages && pdfView.canGoForward
        pageButton.isEnabled = hasPages
        outlineButton.isEnabled = hasPages
        findButton.isEnabled = hasPages
        exportButton.isEnabled = pdfView.document != nil
        if let document = pdfView.document, let page = pdfView.currentPage {
            let index = document.index(for: page)
            pageButton.title = index < count ? "\(index + 1) / \(count)" : "— / \(count)"
        } else { pageButton.title = "— / \(count)" }
        pageButton.accessibilityValue = pageButton.title
    }

    private func detectVisibleLinks() {
        for page in pdfView.visiblePages where detectedPages.insert(ObjectIdentifier(page)).inserted {
            PDFNavigation.addDetectedLinks(on: page)
        }
    }

    private func showOutline() {
        guard presentedViewController == nil, let document = pdfView.document else { return }
        let outline = PDFOutlineViewController(entries: PDFNavigation.outlineEntries(in: document)) { [weak self] target in
            self?.navigate(to: target)
        }
        outlineController = outline
        let navigation = UINavigationController(rootViewController: outline)
        navigation.modalPresentationStyle = .popover
        navigation.preferredContentSize = outline.preferredContentSize
        navigation.popoverPresentationController?.barButtonItem = outlineButton
        present(navigation, animated: true)
    }

    private func navigate(to target: PDFNavigation.Target) {
        guard let document = pdfView.document else { return }
        switch target {
        case .destination(let destination):
            guard let destination = PDFNavigation.validDestination(destination, in: document) else { return }
            pdfView.go(to: destination)
        case .url(let url): openExternalLink(url)
        case .named(let name): pdfView.perform(PDFActionNamed(name: name))
        }
        updateNavigation()
    }

    private func activateLink(_ annotation: PDFAnnotation) {
        guard let document = pdfView.document, annotation.page?.document === document else { return }
        if let action = annotation.action as? PDFActionURL, let url = action.url {
            openExternalLink(url)
        } else if let action = annotation.action as? PDFActionRemoteGoTo {
            pdfViewOpenPDF(pdfView, forRemoteGoToAction: action)
        } else if let action = annotation.action as? PDFActionNamed, action.name == .find {
            showFind()
        } else if let action = annotation.action as? PDFActionNamed, action.name == .goToPage {
            showPagePrompt()
        } else if let target = PDFNavigation.target(for: annotation.action, in: document)
            ?? annotation.destination.flatMap({ PDFNavigation.validDestination($0, in: document) }).map(PDFNavigation.Target.destination) {
            navigate(to: target)
        }
    }

    private func showFind() {
        guard presentedViewController == nil, let document = pdfView.document, !document.isLocked else { return }
        if pdfView.isFindInteractionEnabled {
            pdfView.findInteraction.presentFindNavigator(showingReplace: false)
            return
        }
        let finder = PDFFindViewController(document: document) { [weak self] selection in
            guard let self, let document = self.pdfView.document,
                  !selection.pages.isEmpty, selection.pages.allSatisfy({ $0.document === document }) else { return }
            self.pdfView.setCurrentSelection(selection, animate: true)
            self.pdfView.go(to: selection)
        }
        findController = finder
        let navigation = UINavigationController(rootViewController: finder)
        navigation.modalPresentationStyle = .popover
        navigation.preferredContentSize = finder.preferredContentSize
        navigation.popoverPresentationController?.barButtonItem = findButton
        present(navigation, animated: true)
    }

    @objc private func showPagePrompt() {
        guard presentedViewController == nil, let document = pdfView.document, document.pageCount > 0 else { return }
        let alert = UIAlertController(title: String(localized: "跳转到页码"),
                                      message: String(localized: "输入 1–\(document.pageCount) 之间的页码"), preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "1–\(document.pageCount)"
            if let page = self.pdfView.currentPage { field.text = "\(document.index(for: page) + 1)" }
        }
        alert.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        let jump = UIAlertAction(title: String(localized: "跳转"), style: .default) { [weak self, weak alert] _ in
            guard let self, self.pdfView.document === document,
                  let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let number = Int(text), (1...document.pageCount).contains(number),
                  let page = document.page(at: number - 1) else { return }
            self.pdfView.go(to: page)
        }
        alert.addAction(jump)
        let validate = { [weak alert, weak jump] in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            jump?.isEnabled = Int(text).map { (1...document.pageCount).contains($0) } ?? false
        }
        alert.textFields?.first?.addAction(UIAction { _ in validate() }, for: .editingChanged)
        validate()
        present(alert, animated: true)
    }

    // MARK: - PDFViewDelegate

    func pdfViewParentViewController() -> UIViewController { self }
    func pdfViewPerformFind(_ sender: PDFView) { showFind() }
    func pdfViewPerformGo(toPage sender: PDFView) { showPagePrompt() }

    func pdfViewWillClick(onLink sender: PDFView, with url: URL) { openExternalLink(url) }

    func pdfViewOpenPDF(_ sender: PDFView, forRemoteGoToAction action: PDFActionRemoteGoTo) {
        showLinkError(String(localized: "此链接指向另一个 PDF，请先在访达中打开对应文件。"))
    }

    private func openExternalLink(_ url: URL) {
        guard let url = PDFNavigation.allowedURL(url) else {
            showLinkError(String(localized: "暂不支持打开这种链接。"))
            return
        }
        openURL(url) { [weak self] opened in
            Task { @MainActor in
                if !opened { self?.showLinkError(String(localized: "未找到可以打开此链接的应用。")) }
            }
        }
    }

    private func showLinkError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: String(localized: "无法打开链接"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "好"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - File changes and export

    @objc private func pathsDidChange(_ note: Notification) {
        guard let courseID, note.userInfo?["courseID"] as? UUID == courseID else { return }
        refreshFile()
    }

    private func refreshFile() {
        guard let file = resolveFile?() else { return }
        title = file.title
        guard file.url != fileURL, let document = PDFDocument(url: file.url) else { return }
        let destination = pdfView.currentDestination
        let pageIndex = destination?.page.flatMap { pdfView.document?.index(for: $0) }
        let scale = pdfView.scaleFactor
        fileURL = file.url
        detectedPages.removeAll()
        if pdfView.isFindInteractionEnabled { pdfView.findInteraction.dismissFindNavigator() }
        if findController != nil { presentedViewController?.dismiss(animated: false) }
        pdfView.document = document
        if let pageIndex, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: PDFDestination(page: page, at: destination?.point ?? .zero))
        }
        if !pdfView.autoScales { pdfView.scaleFactor = scale }
        outlineController?.update(entries: PDFNavigation.outlineEntries(in: document))
        updateNavigation()
        detectVisibleLinks()
    }

    private func exportPDF() {
        refreshFile()
        guard FileManager.default.fileExists(atPath: fileURL.path), presentedViewController == nil else { return }
        if let courseID, let course = LibraryStore.shared.course(id: courseID) {
            exportStorageToken = LibraryStore.shared.beginUsingStorage(in: course)
        }
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { endExport() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { endExport() }

    private func endExport() {
        if let token = exportStorageToken { LibraryStore.shared.endUsingStorage(token) }
        exportStorageToken = nil
    }
}

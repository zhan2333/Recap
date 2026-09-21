//
//  PDFReaderTests.swift
//  RecapPDFTests
//
//  Created by Rio on 9/20/26.
//

#if canImport(UIKit)
import UIKit
import PDFKit
#if targetEnvironment(macCatalyst)
import AppKit
#endif
import XCTest
@testable import RecapPDFTestHost

@MainActor
final class PDFReaderTests: XCTestCase {

    override func tearDown() async throws {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.first?.rootViewController = UIViewController()
        }
    }

    func testLoadedReaderShowsPageControlsAndDetectsLinksWithoutChangingPDF() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Data(contentsOf: fixture.url)
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
        let (pdfView, toolbar) = try await load(controller)

        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        pdfView.go(to: page)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        XCTAssertEqual(toolbar.items?[3].title, "1 / 3")
        XCTAssertEqual(toolbar.items?[3].accessibilityValue, "1 / 3")
        XCTAssertTrue(try XCTUnwrap(toolbar.items?[3]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(toolbar.items?[5]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(toolbar.items?[6]).isEnabled)
        XCTAssertTrue(page.annotations.contains { ($0.action as? PDFActionURL)?.url?.host == "example.com" })
        XCTAssertEqual(try Data(contentsOf: fixture.url), original)
        XCTAssertEqual(PDFDocument(url: fixture.url)?.page(at: 0)?.annotations.count, 0)
    }

    func testMissingPDFDisablesNavigationAndExport() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        let controller = PDFViewController(fileURL: missing, title: "Missing")
        let (pdfView, toolbar) = try await load(controller)

        XCTAssertNil(pdfView.document)
        XCTAssertEqual(toolbar.items?[3].title, "— / 0")
        for index in [0, 1, 3, 5, 6] {
            XCTAssertFalse(try XCTUnwrap(toolbar.items?[index]).isEnabled)
        }
        XCTAssertFalse(try XCTUnwrap(controller.navigationItem.rightBarButtonItems?.first).isEnabled)
    }

    func testNativeGoToAndHistoryUpdateToolbarAndReturnToPriorPage() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
        let (pdfView, toolbar) = try await load(controller)
        let document = try XCTUnwrap(pdfView.document)
        let first = try XCTUnwrap(document.page(at: 0))
        let last = try XCTUnwrap(document.page(at: 2))
        pdfView.go(to: first)

        pdfView.perform(PDFActionGoTo(destination: PDFDestination(page: last, at: CGPoint(x: 0, y: 792))))
        let reachedLast = await eventually { pdfView.currentPage === last && pdfView.canGoBack }
        XCTAssertTrue(reachedLast)
        XCTAssertEqual(toolbar.items?[3].title, "3 / 3")
        XCTAssertTrue(try XCTUnwrap(toolbar.items?.first).isEnabled)

        try trigger(try XCTUnwrap(toolbar.items?[0]))
        let returned = await eventually { pdfView.currentPage === first && pdfView.canGoForward }
        XCTAssertTrue(returned)
        XCTAssertEqual(toolbar.items?[3].title, "1 / 3")
        XCTAssertTrue(try XCTUnwrap(toolbar.items?[1]).isEnabled)

        try trigger(try XCTUnwrap(toolbar.items?[1]))
        let advanced = await eventually { pdfView.currentPage === last }
        XCTAssertTrue(advanced)
        XCTAssertEqual(toolbar.items?[3].title, "3 / 3")
    }

    func testLinkDelegateCallsInjectedOpenerOnceWithTheOriginalURL() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var opened: [URL] = []
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader", openURL: { url, completion in
            opened.append(url)
            completion(true)
        })
        let (pdfView, _) = try await load(controller)
        let url = try XCTUnwrap(URL(string: "https://example.com/notes?q=%E8%AF%BE%E7%A8%8B#chapter-2"))
        XCTAssertTrue(pdfView.delegate === controller)

        pdfView.delegate?.pdfViewWillClick?(onLink: pdfView, with: url)
        await Task.yield()

        XCTAssertEqual(opened, [url])
        XCTAssertEqual(opened.first?.absoluteString, url.absoluteString)
    }

    func testCoordinateEntryUsesAttachedScrollHierarchyAndKeepsNavigationHistory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try addNavigationLink(to: fixture.url)
        let original = try Data(contentsOf: fixture.url)
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
        let (view, toolbar) = try await load(controller)
        let pdfView = try XCTUnwrap(view as? PDFLinkView)
        let document = try XCTUnwrap(pdfView.document)
        let first = try XCTUnwrap(document.page(at: 0))
        let last = try XCTUnwrap(document.page(at: 2))
        let annotation = try XCTUnwrap(first.annotations.first { $0.action is PDFActionGoTo })
        pdfView.go(to: annotation.bounds, on: first)
        let point = pdfView.convert(CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), from: first)

        XCTAssertTrue(pdfView.linkAnnotation(at: point) === annotation)
        try assertAttachedScrollHit(at: point, in: pdfView)
        XCTAssertTrue(pdfView.activateLink(at: point))
        let reachedLast = await eventually { pdfView.currentPage === last && pdfView.canGoBack }
        XCTAssertTrue(reachedLast)
        XCTAssertEqual(toolbar.items?[3].title, "3 / 3")

        try trigger(try XCTUnwrap(toolbar.items?[0]))
        let returned = await eventually { pdfView.currentPage === first && pdfView.canGoForward }
        XCTAssertTrue(returned)
        try trigger(try XCTUnwrap(toolbar.items?[1]))
        let advanced = await eventually { pdfView.currentPage === last }
        XCTAssertTrue(advanced)
        XCTAssertEqual(try Data(contentsOf: fixture.url), original)
    }

    func testCoordinateURLEntryOpensOncePerActivationWithoutChangingTheURL() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let url = try XCTUnwrap(URL(string: "https://example.com/source?q=%E8%AF%BE%E7%A8%8B#chapter-2"))
        try addNavigationLink(to: fixture.url, url: url)
        var opened: [URL] = []
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader", openURL: { url, completion in
            opened.append(url)
            completion(true)
        })
        let (view, _) = try await load(controller)
        let pdfView = try XCTUnwrap(view as? PDFLinkView)
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first {
            ($0.action as? PDFActionURL)?.url?.absoluteString == url.absoluteString
        })
        pdfView.go(to: annotation.bounds, on: page)
        let point = pdfView.convert(CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), from: page)

        try assertAttachedScrollHit(at: point, in: pdfView)
        XCTAssertTrue(pdfView.activateLink(at: point))
        await Task.yield()
        XCTAssertEqual(opened.map(\.absoluteString), [url.absoluteString])

        XCTAssertTrue(pdfView.activateLink(at: point))
        await Task.yield()
        XCTAssertEqual(opened.map(\.absoluteString), [url.absoluteString, url.absoluteString])
    }

    func testNonLinkCoordinatesStayInTheScrollHierarchyAndAreNotConsumed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try addNavigationLink(to: fixture.url)
        var opened: [URL] = []
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader", openURL: { url, completion in
            opened.append(url)
            completion(true)
        })
        let (view, _) = try await load(controller)
        let pdfView = try XCTUnwrap(view as? PDFLinkView)
        let first = try XCTUnwrap(pdfView.document?.page(at: 0))
        let annotation = try XCTUnwrap(first.annotations.first { $0.action is PDFActionGoTo })
        pdfView.go(to: annotation.bounds, on: first)
        let canGoBack = pdfView.canGoBack
        let pagePoints = [CGPoint(x: 400, y: annotation.bounds.midY),
                          CGPoint(x: annotation.bounds.maxX + 2, y: annotation.bounds.midY)]

        for pagePoint in pagePoints {
            let point = pdfView.convert(pagePoint, from: first)
            XCTAssertTrue(pdfView.bounds.contains(point))
            XCTAssertNil(pdfView.linkAnnotation(at: point))
            try assertAttachedScrollHit(at: point, in: pdfView)
            XCTAssertFalse(pdfView.activateLink(at: point))
        }

        XCTAssertTrue(pdfView.currentPage === first)
        XCTAssertEqual(pdfView.canGoBack, canGoBack)
        XCTAssertTrue(opened.isEmpty)
    }

    func testRotatedCroppedPageKeepsLinkCoordinateMappingAcrossScales() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try addNavigationLink(to: fixture.url, rotation: 90,
                              cropBox: CGRect(x: 30, y: 40, width: 552, height: 700))
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
        let (view, _) = try await load(controller)
        let pdfView = try XCTUnwrap(view as? PDFLinkView)
        let page = try XCTUnwrap(pdfView.document?.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first { $0.action is PDFActionGoTo })
        let pagePoint = CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY)
        pdfView.displayBox = .cropBox
        pdfView.autoScales = false

        for scale in [CGFloat(0.7), CGFloat(1.5)] {
            pdfView.scaleFactor = scale
            pdfView.layoutDocumentView()
            pdfView.go(to: annotation.bounds, on: page)
            controller.view.layoutIfNeeded()
            await Task.yield()
            let point = pdfView.convert(pagePoint, from: page)
            let roundTrip = pdfView.convert(point, to: page)

            XCTAssertTrue(pdfView.bounds.contains(point))
            XCTAssertEqual(roundTrip.x, pagePoint.x, accuracy: 0.01)
            XCTAssertEqual(roundTrip.y, pagePoint.y, accuracy: 0.01)
            XCTAssertTrue(pdfView.linkAnnotation(at: point) === annotation)
            try assertAttachedScrollHit(at: point, in: pdfView)
        }
    }

    func testFindPanelSearchesAndNavigatesToSelectedMatch() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
        let (pdfView, toolbar) = try await load(controller)
        // Exercise the Catalyst fallback even on OS versions with built-in find support.
        pdfView.isFindInteractionEnabled = false
        try trigger(try XCTUnwrap(toolbar.items?[6]))
        let presented = await eventually { controller.presentedViewController is UINavigationController }
        XCTAssertTrue(presented)
        let navigation = try XCTUnwrap(controller.presentedViewController as? UINavigationController)
        let finder = try XCTUnwrap(navigation.topViewController as? PDFFindViewController)
        finder.loadViewIfNeeded()
        let search = try XCTUnwrap(finder.navigationItem.searchController)
        search.searchBar.text = "example.com"
        search.searchResultsUpdater?.updateSearchResults(for: search)

        let found = await eventually { finder.tableView.numberOfRows(inSection: 0) == 3 }
        XCTAssertTrue(found)
        guard found else { return }
        search.searchBar.text = "missing query"
        search.searchResultsUpdater?.updateSearchResults(for: search)
        search.searchBar.text = "example.com/notes-3"
        search.searchResultsUpdater?.updateSearchResults(for: search)
        let narrowed = await eventually { finder.tableView.numberOfRows(inSection: 0) == 1 }
        XCTAssertTrue(narrowed)
        guard narrowed else { return }
        finder.tableView(finder.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        let navigated = await eventually {
            guard let document = pdfView.document, let page = pdfView.currentPage else { return false }
            return controller.presentedViewController == nil && document.index(for: page) == 2
                && pdfView.currentSelection?.string?.lowercased() == "example.com/notes-3"
        }
        XCTAssertTrue(navigated)
    }

    func testPagePromptDisablesInvalidAndOutOfRangeInput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
        let (pdfView, _) = try await load(controller)
        controller.pdfViewPerformGo(toPage: pdfView)
        let presented = await eventually { controller.presentedViewController is UIAlertController }
        XCTAssertTrue(presented)
        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        let field = try XCTUnwrap(alert.textFields?.first)
        let jump = try XCTUnwrap(alert.actions.first { $0.style == .default })

        for input in ["", "0", "4", "text"] {
            field.text = input
            field.sendActions(for: .editingChanged)
            XCTAssertFalse(jump.isEnabled, input)
        }
        for input in ["1", " 3 "] {
            field.text = input
            field.sendActions(for: .editingChanged)
            XCTAssertTrue(jump.isEnabled, input)
        }
    }

    func testOutlineGroupsCannotBeSelectedAndDestinationRowsRemainSelectable() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let document = try XCTUnwrap(PDFDocument(url: fixture.url))
        let page = try XCTUnwrap(document.page(at: 2))
        let entries = [
            PDFNavigation.OutlineEntry(title: "Part", depth: 0, target: nil, pageIndex: nil),
            PDFNavigation.OutlineEntry(title: "Chapter", depth: 1,
                target: .destination(PDFDestination(page: page, at: .zero)), pageIndex: 2)
        ]
        var selections = 0
        let controller = PDFOutlineViewController(entries: entries) { _ in selections += 1 }
        controller.loadViewIfNeeded()
        let table = controller.tableView!
        let group = IndexPath(row: 0, section: 0)
        let chapter = IndexPath(row: 1, section: 0)

        XCTAssertNil(controller.tableView(table, willSelectRowAt: group))
        XCTAssertEqual(controller.tableView(table, willSelectRowAt: chapter), chapter)
        XCTAssertEqual(controller.tableView(table, cellForRowAt: group).selectionStyle, .none)
        XCTAssertTrue(controller.tableView(table, cellForRowAt: group).accessibilityTraits.contains(.header))
        XCTAssertTrue(controller.tableView(table, cellForRowAt: chapter).accessibilityTraits.contains(.button))
        controller.tableView(table, didSelectRowAt: group)
        XCTAssertEqual(selections, 0)

        controller.update(entries: [])
        XCTAssertEqual(controller.tableView(table, numberOfRowsInSection: 0), 0)
        XCTAssertNotNil(table.backgroundView)
        controller.update(entries: entries)
        XCTAssertEqual(controller.tableView(table, numberOfRowsInSection: 0), 2)
        XCTAssertNil(table.backgroundView)
    }

    func testRenameNotificationRebindsDocumentAndPreservesTheCurrentPage() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let renamedURL = fixture.directory.appendingPathComponent("Renamed course - 12345678.handout.pdf")
        let courseID = UUID()
        var resolvedURL = fixture.url
        var resolvedTitle = "Original title"
        var resolutions = 0
        let controller = PDFViewController(fileURL: fixture.url, title: resolvedTitle, courseID: courseID, resolveFile: {
            resolutions += 1
            return (resolvedURL, resolvedTitle)
        })
        let (pdfView, toolbar) = try await load(controller)
        let originalDocument = try XCTUnwrap(pdfView.document)
        let last = try XCTUnwrap(originalDocument.page(at: 2))
        pdfView.go(to: PDFDestination(page: last, at: CGPoint(x: 0, y: 792)))
        let reachedLast = await eventually { pdfView.currentPage === last }
        XCTAssertTrue(reachedLast)

        try FileManager.default.moveItem(at: fixture.url, to: renamedURL)
        resolvedURL = renamedURL
        resolvedTitle = "Renamed title"
        NotificationCenter.default.post(name: LibraryStore.pathsDidChange, object: nil, userInfo: ["courseID": UUID()])
        XCTAssertEqual(resolutions, 0)
        XCTAssertTrue(pdfView.document === originalDocument)

        NotificationCenter.default.post(name: LibraryStore.pathsDidChange, object: nil, userInfo: ["courseID": courseID])
        let reloaded = await eventually {
            guard let document = pdfView.document, let page = pdfView.currentPage else { return false }
            return document !== originalDocument && document.index(for: page) == 2
        }

        XCTAssertTrue(reloaded)
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(controller.title, resolvedTitle)
        XCTAssertEqual(pdfView.document?.documentURL, renamedURL)
        XCTAssertEqual(toolbar.items?[3].title, "3 / 3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
    }

    #if targetEnvironment(macCatalyst)
    func testWindowSidebarButtonHidesBothColumnsAndShowsBothWithoutReloadingPDF() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for mode in [UISplitViewController.DisplayMode.twoBesideSecondary, .oneBesideSecondary] {
            let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
            let (split, navigation, pdfView, toolbarDelegate, button) = try await loadSplitReader(controller, mode: mode)
            defer { withExtendedLifetime(toolbarDelegate) {} }
            let document = try XCTUnwrap(pdfView.document)
            let last = try XCTUnwrap(document.page(at: 2))
            pdfView.go(to: last)
            let originalWidth = pdfView.bounds.width
            let couldGoBack = pdfView.canGoBack

            try triggerSidebarButton(button)
            let focused = await eventually { split.displayMode == .secondaryOnly && pdfView.bounds.width > originalWidth }
            XCTAssertTrue(focused)
            XCTAssertEqual(navigation.view.bounds.width, split.view.bounds.width, accuracy: 1)
            XCTAssertTrue(pdfView.document === document)
            XCTAssertTrue(pdfView.currentPage === last)
            XCTAssertEqual(pdfView.canGoBack, couldGoBack)

            try triggerSidebarButton(button)
            let restored = await eventually { split.displayMode == .twoBesideSecondary }
            XCTAssertTrue(restored)
            XCTAssertTrue(pdfView.document === document)
            XCTAssertTrue(pdfView.currentPage === last)
        }
    }

    func testWindowSidebarButtonStillWorksAfterLeavingPushedAndRootPDFReaders() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for pushed in [true, false] {
            let controller = PDFViewController(fileURL: fixture.url, title: "Reader")
            let (split, navigation, _, toolbarDelegate, button) = try await loadSplitReader(controller, pushed: pushed)
            defer { withExtendedLifetime(toolbarDelegate) {} }
            try triggerSidebarButton(button)
            let focused = await eventually { split.displayMode == .secondaryOnly }
            XCTAssertTrue(focused)

            if pushed {
                navigation.popViewController(animated: false)
            } else {
                split.setViewController(UINavigationController(rootViewController: UIViewController()), for: .secondary)
            }

            XCTAssertEqual(split.displayMode, .secondaryOnly)
            try triggerSidebarButton(button)
            let restored = await eventually { split.displayMode == .twoBesideSecondary }
            XCTAssertTrue(restored)
        }
    }

    private func loadSplitReader(_ controller: PDFViewController,
                                 mode: UISplitViewController.DisplayMode = .twoBesideSecondary,
                                 pushed: Bool = false) async throws -> (UISplitViewController, UINavigationController, PDFView, BrandToolbarDelegate, NSToolbarItem) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first)
        let split = UISplitViewController(style: .tripleColumn)
        split.preferredSplitBehavior = .tile
        split.preferredDisplayMode = mode
        split.minimumPrimaryColumnWidth = 160
        split.preferredPrimaryColumnWidth = 180
        split.minimumSupplementaryColumnWidth = 180
        split.preferredSupplementaryColumnWidth = 200
        split.setViewController(UINavigationController(rootViewController: UIViewController()), for: .primary)
        split.setViewController(UINavigationController(rootViewController: UIViewController()), for: .supplementary)
        let navigation = UINavigationController(rootViewController: pushed ? UIViewController() : controller)
        split.setViewController(navigation, for: .secondary)
        window.rootViewController = split
        window.makeKeyAndVisible()
        if pushed { navigation.pushViewController(controller, animated: false) }
        let ready = await eventually { split.displayMode == mode && controller.view.window != nil }
        XCTAssertTrue(ready)
        split.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let pdfView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? PDFView }.first)
        pdfView.layoutDocumentView()
        let toolbarDelegate = BrandToolbarDelegate()
        toolbarDelegate.splitViewController = split
        let toolbar = NSToolbar(identifier: "ReaderTest")
        XCTAssertEqual(toolbarDelegate.toolbarDefaultItemIdentifiers(toolbar).first, BrandToolbarDelegate.sidebarsID)
        let button = try XCTUnwrap(toolbarDelegate.toolbar(toolbar, itemForItemIdentifier: BrandToolbarDelegate.sidebarsID,
                                                         willBeInsertedIntoToolbar: true))
        return (split, navigation, pdfView, toolbarDelegate, button)
    }

    private func triggerSidebarButton(_ item: NSToolbarItem) throws {
        let target = try XCTUnwrap(item.target as? NSObject)
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(target.responds(to: action))
        target.perform(action)
    }
    #endif

    private func load(_ controller: PDFViewController) async throws -> (PDFView, UIToolbar) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        await Task.yield()
        let pdfView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? PDFView }.first)
        let toolbar = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIToolbar }.first)
        pdfView.layoutDocumentView()
        controller.viewDidLayoutSubviews()
        return (pdfView, toolbar)
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    private func trigger(_ item: UIBarButtonItem) throws {
        let action = try XCTUnwrap(item.primaryAction)
        let button = UIButton(primaryAction: action)
        button.sendActions(for: .primaryActionTriggered)
    }

    private func assertAttachedScrollHit(at point: CGPoint, in pdfView: PDFView,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        let window = try XCTUnwrap(pdfView.window, file: file, line: line)
        let windowPoint = pdfView.convert(point, to: window)
        let hit = try XCTUnwrap(window.hitTest(windowPoint, with: nil), file: file, line: line)
        XCTAssertTrue(hit.window === window, file: file, line: line)
        XCTAssertTrue(hit.isDescendant(of: pdfView), file: file, line: line)
        var ancestor: UIView? = hit
        var scrollIsInTheHitChain = false
        while let current = ancestor, current !== pdfView {
            if current is UIScrollView { scrollIsInTheHitChain = true }
            ancestor = current.superview
        }
        XCTAssertTrue(scrollIsInTheHitChain, "Link routing must preserve the PDF scroll view's gesture chain", file: file, line: line)
    }

    private func addNavigationLink(to fileURL: URL, url: URL? = nil, rotation: Int = 0,
                                   cropBox: CGRect? = nil) throws {
        // Write explicit page references: Catalyst's PDFKit serializer drops GoTo targets in this fixture.
        let action: String
        if let url {
            let literal = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
            action = "<< /S /URI /URI (\(literal)) >>"
        } else {
            action = "<< /S /GoTo /D (last-page) >>"
        }
        let crop = cropBox.map { "/CropBox [\($0.minX) \($0.minY) \($0.maxX) \($0.maxY)]" } ?? ""
        let text = "BT /F1 12 Tf 140 624 Td (Native link) Tj ET"
        let pageFields = "/Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 6 0 R >> >> /Contents 7 0 R"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /Names << /Dests << /Names [(last-page) [5 0 R /XYZ 0 792 null]] >> >> >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< \(pageFields) /Annots [8 0 R] /Rotate \(rotation) \(crop) >>",
            "<< \(pageFields) >>",
            "<< \(pageFields) >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(text.utf8.count) >>\nstream\n\(text)\nendstream",
            "<< /Type /Annot /Subtype /Link /Rect [140 620 320 646] /Border [0 0 0] /A \(action) >>"
        ]
        var pdf = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let data = Data(pdf.utf8)
        let document = try XCTUnwrap(PDFDocument(data: data))
        if url == nil {
            let annotation = try XCTUnwrap(document.page(at: 0)?.annotations.first)
            let destination = try XCTUnwrap((annotation.action as? PDFActionGoTo)?.destination.page)
            XCTAssertTrue(destination === document.page(at: 2))
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func makeFixture() throws -> (directory: URL, url: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Course - 12345678.handout.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            for number in 1...3 {
                context.beginPage()
                let text = "Page \(number)\nhttps://example.com/notes-\(number)"
                (text as NSString).draw(in: CGRect(x: 40, y: 40, width: 500, height: 100),
                                       withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
        try data.write(to: url)
        return (directory, url)
    }
}
#endif

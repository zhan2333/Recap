//
//  PDFNavigation.swift
//  Recap
//
//  Created by Rio on 9/20/26.
//

import Foundation
import PDFKit

enum PDFNavigation {

    enum Target {
        case destination(PDFDestination)
        case url(URL)
        case named(PDFActionNamedName)
    }

    struct OutlineEntry {
        let title: String
        let depth: Int
        let target: Target?
        let pageIndex: Int?
    }

    static func outlineEntries(in document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        var visited = Set<ObjectIdentifier>()

        func appendChildren(of parent: PDFOutline, depth: Int) {
            guard visited.insert(ObjectIdentifier(parent)).inserted else { return }
            for index in 0..<parent.numberOfChildren {
                guard let child = parent.child(at: index), !visited.contains(ObjectIdentifier(child)) else { continue }
                let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let navigation = target(for: child.action, in: document)
                    ?? child.destination.flatMap { validDestination($0, in: document) }.map(Target.destination)
                let pageIndex: Int?
                if case let .destination(destination) = navigation, let page = destination.page {
                    pageIndex = document.index(for: page)
                } else {
                    pageIndex = nil
                }
                entries.append(OutlineEntry(title: label.flatMap { $0.isEmpty ? nil : $0 }
                                             ?? String(localized: "未命名章节"),
                                            depth: depth, target: navigation, pageIndex: pageIndex))
                appendChildren(of: child, depth: depth + 1)
            }
        }

        appendChildren(of: root, depth: 0)
        return entries
    }

    static func target(for action: PDFAction?, in document: PDFDocument) -> Target? {
        switch action {
        case let action as PDFActionGoTo:
            return validDestination(action.destination, in: document).map(Target.destination)
        case let action as PDFActionURL:
            return allowedURL(action.url).map(Target.url)
        case let action as PDFActionNamed:
            switch action.name {
            case .nextPage, .previousPage, .firstPage, .lastPage, .goBack, .goForward:
                return .named(action.name)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    static func canActivate(_ annotation: PDFAnnotation, in document: PDFDocument) -> Bool {
        guard annotation.page?.document === document else { return false }
        if target(for: annotation.action, in: document) != nil { return true }
        if let action = annotation.action as? PDFActionURL { return action.url != nil }
        if annotation.action is PDFActionRemoteGoTo { return true }
        if let action = annotation.action as? PDFActionNamed, action.name == .find || action.name == .goToPage { return true }
        return annotation.destination.flatMap { validDestination($0, in: document) } != nil
    }

    static func validDestination(_ destination: PDFDestination, in document: PDFDocument) -> PDFDestination? {
        guard let page = destination.page, page.document === document else { return nil }
        let index = document.index(for: page)
        guard index != NSNotFound, index >= 0, index < document.pageCount else { return nil }
        return destination
    }

    static func allowedURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else { return nil }
        case "mailto", "tel":
            // PDFKit may return an opaque NSURL whose path is empty for these schemes.
            let recipient = url.absoluteString.dropFirst(scheme.count + 1).prefix { $0 != "?" && $0 != "#" }
            guard !recipient.isEmpty else { return nil }
        default:
            return nil
        }
        return url
    }

    // Add links to the in-memory document only; native annotations always keep priority.
    @discardableResult
    static func addDetectedLinks(on page: PDFPage) -> Int {
        guard let text = page.string, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return 0 }
        var linkBounds = page.annotations.filter { $0.type == "Link" }.map(\.bounds)
        var count = 0

        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = allowedURL(match.url), let selection = page.selection(for: match.range) else { continue }
            let bounds = selection.selectionsByLine().map { $0.bounds(for: page) }.filter {
                !$0.isNull && !$0.isEmpty && !$0.isInfinite
                    && $0.origin.x.isFinite && $0.origin.y.isFinite
            }
            guard !bounds.isEmpty,
                  !bounds.contains(where: { rect in linkBounds.contains(where: { $0.intersects(rect) }) }) else { continue }

            for rect in bounds {
                let annotation = PDFAnnotation(bounds: rect, forType: .link, withProperties: nil)
                annotation.action = PDFActionURL(url: url)
                let border = PDFBorder()
                border.lineWidth = 0
                annotation.border = border
                annotation.color = .clear
                annotation.shouldPrint = false
                page.addAnnotation(annotation)
                linkBounds.append(rect)
                count += 1
            }
        }
        return count
    }
}

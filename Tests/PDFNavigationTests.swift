//
//  PDFNavigationTests.swift
//  RecapLibraryTests
//
//  Created by Rio on 9/20/26.
//

import Foundation
import PDFKit
import XCTest

@MainActor
final class PDFNavigationTests: XCTestCase {

    func testSerializedOutlinesResolveNamedAndExplicitDestinations() async throws {
        let document = try XCTUnwrap(PDFDocument(data: fixture()))
        XCTAssertEqual(document.pageCount, 3)

        let entries = PDFNavigation.outlineEntries(in: document)

        XCTAssertEqual(entries.map(\.title), ["Part", "Named chapter", "Action chapter"])
        XCTAssertEqual(entries.map(\.depth), [0, 1, 0])
        XCTAssertEqual(entries.map(\.pageIndex), [nil, 1, 2])
        XCTAssertNil(entries[0].target)
        guard case let .destination(destination) = entries[1].target else {
            return XCTFail("Named outline destination was not resolved")
        }
        XCTAssertTrue(destination.page === document.page(at: 1))
        XCTAssertEqual(destination.point.y, 720)
    }

    func testSerializedAnnotationsResolveNamedDirectAndURLLinks() async throws {
        let document = try XCTUnwrap(PDFDocument(data: fixture()))
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.annotations.count, 3)

        guard case let .destination(named) = PDFNavigation.target(for: page.annotations[0].action, in: document),
              case let .destination(direct) = PDFNavigation.target(for: page.annotations[1].action, in: document),
              case let .url(url) = PDFNavigation.target(for: page.annotations[2].action, in: document) else {
            return XCTFail("Serialized link actions did not resolve")
        }

        XCTAssertTrue(named.page === document.page(at: 1))
        XCTAssertTrue(direct.page === document.page(at: 2))
        XCTAssertEqual(url.absoluteString, "https://example.com/source")
    }

    func testMissingNamedDestinationKeepsOutlineWithoutNavigation() async throws {
        let document = try XCTUnwrap(PDFDocument(data: fixture(namedOutlineDestination: "missing-chapter")))

        let entries = PDFNavigation.outlineEntries(in: document)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].title, "Named chapter")
        XCTAssertNil(entries[1].target)
        XCTAssertNil(entries[1].pageIndex)
    }

    func testEmptyDocumentHasNoOutline() async {
        XCTAssertTrue(PDFNavigation.outlineEntries(in: PDFDocument()).isEmpty)
    }

    func testForeignAndDetachedPagesCannotBeDestinations() async throws {
        let document = try XCTUnwrap(PDFDocument(data: fixture()))
        let other = try XCTUnwrap(PDFDocument(data: fixture()))
        let foreignPage = try XCTUnwrap(other.page(at: 0))
        let foreign = PDFDestination(page: foreignPage, at: .zero)
        XCTAssertNil(PDFNavigation.validDestination(foreign, in: document))
        XCTAssertNil(PDFNavigation.target(for: PDFActionGoTo(destination: foreign), in: document))

        let localPage = try XCTUnwrap(document.page(at: 2))
        let removed = PDFDestination(page: localPage, at: .zero)
        document.removePage(at: 2)
        XCTAssertNil(PDFNavigation.validDestination(removed, in: document))
    }

    func testNamedNavigationPreservesNativeHistoryActions() async {
        let document = PDFDocument()
        let navigation: [PDFActionNamedName] = [.nextPage, .previousPage, .firstPage, .lastPage, .goBack, .goForward]
        for name in navigation {
            guard case let .named(result) = PDFNavigation.target(for: PDFActionNamed(name: name), in: document) else {
                return XCTFail("Missing named action \(name)")
            }
            XCTAssertEqual(result, name)
        }
        for name in [PDFActionNamedName.none, .goToPage, .find, .print, .zoomIn, .zoomOut] {
            XCTAssertNil(PDFNavigation.target(for: PDFActionNamed(name: name), in: document))
        }
    }

    func testOnlySupportedExternalSchemesAreAccepted() async throws {
        for value in ["https://example.com/a#section", "http://example.com", "HTTPS://example.com", "mailto:reader@example.com", "tel:+861234567890"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(PDFNavigation.allowedURL(url), url, value)
        }
        for value in ["file:///tmp/notes.pdf", "javascript:alert(1)", "data:text/plain,hello", "recap://delete", "ftp://example.com", "/tmp/notes.pdf", "mailto:", "tel:", "https:"] {
            XCTAssertNil(PDFNavigation.allowedURL(URL(string: value)), value)
        }
        XCTAssertNil(PDFNavigation.allowedURL(nil))
    }

    func testURLActionsUseTheSameExternalSchemePolicy() async throws {
        let document = PDFDocument()
        let unsafe = PDFActionURL(url: try XCTUnwrap(URL(string: "file:///tmp/notes.pdf")))
        XCTAssertNil(PDFNavigation.target(for: unsafe, in: document))
        let safe = PDFActionURL(url: try XCTUnwrap(URL(string: "mailto:reader@example.com")))
        guard case let .url(url) = PDFNavigation.target(for: safe, in: document) else {
            return XCTFail("Mail link was not accepted")
        }
        XCTAssertEqual(url.absoluteString, "mailto:reader@example.com")
    }

    func testDetectedLinksFollowTextBoundsWithoutDuplicateAnnotations() async throws {
        let document = try XCTUnwrap(PDFDocument(data: fixture()))
        let page = try XCTUnwrap(document.page(at: 0))
        let text = try XCTUnwrap(page.string)
        let range = (text as NSString).range(of: "https://example.com/notes")
        let selection = try XCTUnwrap(page.selection(for: range))
        let previousCount = page.annotations.count

        XCTAssertEqual(PDFNavigation.addDetectedLinks(on: page), 1)

        XCTAssertEqual(page.annotations.count, previousCount + 1)
        let annotation = try XCTUnwrap(page.annotations.last)
        XCTAssertEqual(annotation.bounds, selection.bounds(for: page))
        XCTAssertFalse(annotation.shouldPrint)
        XCTAssertEqual((annotation.action as? PDFActionURL)?.url?.absoluteString, "https://example.com/notes")
        XCTAssertEqual(PDFNavigation.addDetectedLinks(on: page), 0)
        XCTAssertEqual(page.annotations.count, previousCount + 1)
    }

    func testExistingLinkWinsOverDetectedURLAtTheSamePosition() async throws {
        let document = try XCTUnwrap(PDFDocument(data: fixture()))
        let page = try XCTUnwrap(document.page(at: 0))
        let text = try XCTUnwrap(page.string)
        let range = (text as NSString).range(of: "https://example.com/notes")
        let selection = try XCTUnwrap(page.selection(for: range))
        let original = PDFAnnotation(bounds: selection.bounds(for: page), forType: .link, withProperties: nil)
        let destinationPage = try XCTUnwrap(document.page(at: 2))
        original.action = PDFActionGoTo(destination: PDFDestination(page: destinationPage, at: .zero))
        page.addAnnotation(original)

        XCTAssertEqual(PDFNavigation.addDetectedLinks(on: page), 0)
        XCTAssertTrue((original.action as? PDFActionGoTo)?.destination.page === destinationPage)
    }

    func testDetectionLeavesOriginalPDFBytesUnchanged() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        let original = fixture()
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(document.page(at: 0))

        XCTAssertEqual(PDFNavigation.addDetectedLinks(on: page), 1)

        XCTAssertEqual(try Data(contentsOf: url), original)
        let reopened = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.count, 3)
    }

    // Exercise PDFKit's PDF parser instead of only constructing PDFKit objects.
    private func fixture(namedOutlineDestination: String = "chapter-two") -> Data {
        let content = "BT /F1 12 Tf 20 700 Td (https://example.com/notes) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R /Names << /Dests << /Names [(chapter-two) [4 0 R /XYZ 30 720 null]] >> >> >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 10 0 R >> >> /Contents 11 0 R /Annots [12 0 R 13 0 R 14 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            "<< /Type /Outlines /First 7 0 R /Last 9 0 R /Count 3 >>",
            "<< /Title (Part) /Parent 6 0 R /Next 9 0 R /First 8 0 R /Last 8 0 R /Count 1 >>",
            "<< /Title (Named chapter) /Parent 7 0 R /Dest (\(namedOutlineDestination)) >>",
            "<< /Title (Action chapter) /Parent 6 0 R /Prev 7 0 R /A << /S /GoTo /D [5 0 R /XYZ 30 720 null] >> >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /Annot /Subtype /Link /Rect [20 665 180 685] /Border [0 0 0] /A << /S /GoTo /D (chapter-two) >> >>",
            "<< /Type /Annot /Subtype /Link /Rect [20 640 180 660] /Border [0 0 0] /Dest [5 0 R /XYZ 30 720 null] >>",
            "<< /Type /Annot /Subtype /Link /Rect [20 615 180 635] /Border [0 0 0] /A << /S /URI /URI (https://example.com/source) >> >>"
        ]
        var pdf = "%PDF-1.7\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}

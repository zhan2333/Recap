//
//  TerminalStudioReferenceTests.swift
//  RecapLibraryTests
//
//  Created by Rio on 10/21/26.
//

import Foundation
import CoreGraphics
import XCTest

final class TerminalStudioReferenceTests: XCTestCase {

    func testSanitizedPasteRemovesTerminalControlsAndPreservesUnicode() {
        let controlValues = Array(0...8) + [11, 12] + Array(14...31) + Array(127...159)
        let controls = controlValues.map { String(UnicodeScalar($0)!) }.joined()
        let content = "链式法则 ∂L/∂x · café e\u{0301} 👩🏽‍💻"

        let sanitized = TerminalStudioReference.sanitizedPaste(controls + content + controls)

        XCTAssertEqual(sanitized, content)
        XCTAssertFalse(sanitized.unicodeScalars.contains { controlValues.contains(Int($0.value)) })
    }

    func testSanitizedPasteNormalizesLineEndingsAndPreservesTabs() {
        let input = "第一行\r\n\t第二行\r第三行\n\n\t结尾"

        XCTAssertEqual(TerminalStudioReference.sanitizedPaste(input), "第一行\n\t第二行\n第三行\n\n\t结尾")
    }

    func testSourceTextCannotCloseOrReopenTheBracketedPaste() {
        let input = "before\u{1b}[201~\u{03}command\u{1b}[200~after\u{9b}201~"
        let sanitized = TerminalStudioReference.sanitizedPaste(input)
        let pasted = "\u{1b}[200~" + sanitized + "\u{1b}[201~"

        XCTAssertEqual(sanitized, "before[201~command[200~after201~")
        XCTAssertFalse(sanitized.contains("\u{1b}"))
        XCTAssertFalse(sanitized.contains("\u{9b}"))
        XCTAssertEqual(pasted.components(separatedBy: "\u{1b}[200~").count - 1, 1)
        XCTAssertEqual(pasted.components(separatedBy: "\u{1b}[201~").count - 1, 1)
    }

    func testPDFPromptIncludesTheFilenameAndOneBasedPageNumber() {
        let reference = TerminalStudioReference(
            title: "讲义选区",
            text: "先求梯度，再更新参数。",
            location: .pdf(url: URL(fileURLWithPath: "/tmp/Course Notes.handout.pdf"),
                           pageIndex: 5, selectionBounds: CGRect(x: 40, y: 600, width: 200, height: 50))
        )

        XCTAssertEqual(reference.promptText,
                       "[讲义选区 · Course Notes.handout.pdf · p.6]\n先求梯度，再更新参数。")
    }

    func testPlaybackPromptUsesTheCapturedGlobalTimeWithoutApplyingLeadIn() {
        for leadIn in [false, true] {
            let reference = TerminalStudioReference(title: "课堂重点", text: "原话",
                                                    location: .playback(time: 7_323.9, leadIn: leadIn))

            XCTAssertEqual(reference.promptText, "[课堂重点 · 02:02:03]\n原话")
        }
        for time in [-12.0, .nan, .infinity, -.infinity] {
            let reference = TerminalStudioReference(title: "播放位置", text: "",
                                                    location: .playback(time: time, leadIn: false))
            XCTAssertEqual(reference.promptText, "[播放位置 · 00:00:00]\n")
        }
    }

    func testReferencesKeepTheirCapturedValuesAfterTheReaderAndPlayerMove() {
        var pageIndex = 5
        var selection = CGRect(x: 40, y: 600, width: 200, height: 50)
        var excerpt = "最初选中的原话"
        var globalTime = 3_661.0
        let url = URL(fileURLWithPath: "/tmp/handout.pdf")
        let pdf = TerminalStudioReference(title: "选区", text: excerpt,
                                          location: .pdf(url: url, pageIndex: pageIndex, selectionBounds: selection))
        let playback = TerminalStudioReference(title: "播放位置", text: excerpt,
                                               location: .playback(time: globalTime, leadIn: false))

        pageIndex = 8
        selection.origin.y = 200
        excerpt = "之后选择的另一段文字"
        globalTime = 7_200

        XCTAssertEqual(pdf.location, .pdf(url: url, pageIndex: 5,
                                         selectionBounds: CGRect(x: 40, y: 600, width: 200, height: 50)))
        XCTAssertEqual(pdf.promptText, "[选区 · handout.pdf · p.6]\n最初选中的原话")
        XCTAssertEqual(playback.location, .playback(time: 3_661, leadIn: false))
        XCTAssertEqual(playback.promptText, "[播放位置 · 01:01:01]\n最初选中的原话")
        XCTAssertNotEqual(pdf.location, .pdf(url: url, pageIndex: pageIndex, selectionBounds: selection))
        XCTAssertNotEqual(playback.location, .playback(time: globalTime, leadIn: false))
        XCTAssertNotEqual(pdf.text, excerpt)
    }
}

//
//  LibraryFileNamingTests.swift
//  PipelineKitTests
//
//  Created by Rio on 9/20/26.
//

import Foundation
import XCTest
@testable import PipelineKit

final class LibraryFileNamingTests: XCTestCase {

    private let id = UUID(uuidString: "12345678-ABCD-4000-8000-000000000001")!

    func testChineseAndEnglishNamesStayReadable() {
        XCTAssertEqual(LibraryFileNaming.safeStem("基础工程 第 3 讲", fallback: "Lecture"), "基础工程 第 3 讲")
        XCTAssertEqual(LibraryFileNaming.safeStem("Teacher's review — Part 2", fallback: "Lecture"),
                       "Teacher's review — Part 2")
    }

    func testPathAndTeXCharactersCannotEscapeOrHideAFile() {
        XCTAssertEqual(LibraryFileNaming.safeStem(" ../课程\\复习:重点%#{}$&^~\"<>|?*\n第二讲... ", fallback: "Lecture"),
                       "课程 复习 重点 第二讲")
        XCTAssertEqual(LibraryFileNaming.safeStem("\u{0}../..\u{1}", fallback: "备用课程"), "备用课程")
        XCTAssertEqual(LibraryFileNaming.safeStem("...\n\t", fallback: ".../\\"), "Untitled")
        XCTAssertEqual(LibraryFileNaming.safeStem("  第一讲 \t 第二节  ", fallback: "Lecture"), "第一讲 第二节")
    }

    func testNamesNormalizeToNFC() {
        let result = LibraryFileNaming.safeStem("Cafe\u{301}", fallback: "Lecture")
        XCTAssertEqual(Array(result.unicodeScalars), Array("Café".unicodeScalars))
    }

    func testLongUnicodeNamesKeepWholeCharactersWithinTheByteLimit() {
        let family = "👨‍👩‍👧‍👦"
        let result = LibraryFileNaming.safeStem(String(repeating: family, count: 20), fallback: "Lecture")
        XCTAssertFalse(result.isEmpty)
        XCTAssertLessThanOrEqual(result.utf8.count, 150)
        XCTAssertTrue(result.allSatisfy { String($0) == family })
        XCTAssertGreaterThan(result.utf8.count + family.utf8.count, 150)
        XCTAssertEqual(LibraryFileNaming.safeStem(String(repeating: "课", count: 100), fallback: "Lecture").count, 50)
        let oversizedCharacter = "a" + String(repeating: "\u{301}", count: 200)
        XCTAssertEqual(LibraryFileNaming.safeStem(oversizedCharacter, fallback: "备用"), "备用")
    }

    func testEveryNameIncludesItsShortIdentifier() {
        XCTAssertEqual(LibraryFileNaming.uniqueStem("第一讲", fallback: "Lecture", id: id, occupied: ["第二讲"]),
                       "第一讲 - 12345678")
        XCTAssertEqual(LibraryFileNaming.uniqueStem("Teacher's review", fallback: "Lecture", id: id, occupied: []),
                       "Teacher's review - 12345678")
    }

    func testDuplicateNamesUseTheStableShortIdentifier() {
        XCTAssertEqual(LibraryFileNaming.uniqueStem("第一讲", fallback: "Lecture", id: id, occupied: ["第一讲"]),
                       "第一讲 - 12345678")
    }

    func testCaseAndCanonicalUnicodeCollisionsAreDetected() {
        XCTAssertEqual(LibraryFileNaming.uniqueStem("REVIEW", fallback: "Lecture", id: id,
                                                   occupied: ["review - 12345678"]),
                       "REVIEW - 12345678 - 2")
        XCTAssertEqual(LibraryFileNaming.uniqueStem("Café", fallback: "Lecture", id: id,
                                                   occupied: ["CAFE\u{301} - 12345678"]),
                       "Café - 12345678 - 2")
    }

    func testEqualNamesWithDifferentIdentitiesStayDistinct() {
        let first = LibraryFileNaming.uniqueStem("第一讲", fallback: "Lecture", id: id, occupied: [])
        let otherID = UUID(uuidString: "ABCDEF12-ABCD-4000-8000-000000000001")!
        let second = LibraryFileNaming.uniqueStem("第一讲", fallback: "Lecture", id: otherID, occupied: [first])
        XCTAssertEqual(first, "第一讲 - 12345678")
        XCTAssertEqual(second, "第一讲 - ABCDEF12")
    }

    func testTitleChangesKeepTheSameShortIdentifier() {
        let first = LibraryFileNaming.uniqueStem("旧名称", fallback: "Lecture", id: id, occupied: [])
        let renamed = LibraryFileNaming.uniqueStem("新名称", fallback: "Lecture", id: id, occupied: [first])
        XCTAssertEqual(first, "旧名称 - 12345678")
        XCTAssertEqual(renamed, "新名称 - 12345678")
    }

    func testShortIdentifierCollisionsReceiveACounter() {
        let occupied = ["Review", "REVIEW - 12345678", "Review - 12345678 - 2"]
        XCTAssertEqual(LibraryFileNaming.uniqueStem("Review", fallback: "Lecture", id: id, occupied: occupied),
                       "Review - 12345678 - 3")
    }

    func testCollisionSuffixAlsoFitsTheByteLimit() {
        let name = String(repeating: "课", count: 100)
        let existing = LibraryFileNaming.uniqueStem(name, fallback: "Lecture", id: id, occupied: [])
        let result = LibraryFileNaming.uniqueStem(name, fallback: "Lecture", id: id, occupied: [existing])
        XCTAssertTrue(existing.hasSuffix(" - 12345678"))
        XCTAssertLessThanOrEqual(existing.utf8.count, 150)
        XCTAssertTrue(result.hasSuffix(" - 12345678 - 2"))
        XCTAssertLessThanOrEqual(result.utf8.count, 150)
        XCTAssertNotEqual(result, existing)
        XCTAssertTrue(result.dropLast(" - 12345678 - 2".count).allSatisfy { $0 == "课" })
    }
}

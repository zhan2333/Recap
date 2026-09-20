//
//  LibraryFileMigrationTests.swift
//  PipelineKitTests
//
//  Created by Rio on 9/20/26.
//

import Foundation
import XCTest
@testable import PipelineKit

final class LibraryFileMigrationTests: XCTestCase {

    private var directory: URL!
    private let files = FileManager.default

    override func setUpWithError() throws {
        directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory, files.fileExists(atPath: directory.path) {
            try files.removeItem(at: directory)
        }
    }

    func testFileMovesWithoutChangingItsContents() throws {
        let legacy = directory.appendingPathComponent("lecture.handout.pdf")
        let preferred = directory.appendingPathComponent("第一讲.handout.pdf")
        let contents = Data([0, 1, 2, 127, 128, 255])
        try contents.write(to: legacy)

        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred), legacy)
        try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)

        XCTAssertFalse(files.fileExists(atPath: legacy.path))
        XCTAssertEqual(try Data(contentsOf: preferred), contents)
        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred), preferred)
    }

    func testCourseMovePreservesNestedMediaAndEveryArtifact() throws {
        let legacy = directory.appendingPathComponent("COURSE-ID", isDirectory: true)
        let preferred = directory.appendingPathComponent("基础工程", isDirectory: true)
        let artifacts: [String: Data] = [
            "lectures.json": Data("[{\"name\":\"第一讲\"}]".utf8),
            "PART-ID.mp4": Data([0, 1, 255, 2]),
            "PART-ID.part.json": Data("[{\"start\":0,\"text\":\"课程\"}]".utf8),
            "LECTURE-ID.txt": Data("完整文稿".utf8),
            "LECTURE-ID.analysis.json": Data("{\"exam_signals\":[]}".utf8),
            "LECTURE-ID.handout.tex": Data("\\documentclass{article}".utf8),
            "LECTURE-ID.handout.pdf": Data([37, 80, 68, 70]),
            "LECTURE-ID.文稿分段/part01.txt": Data("第一段".utf8),
            ".agents/skills/recap-review/SKILL.md": Data("# Review".utf8),
        ]
        for (path, contents) in artifacts {
            let url = legacy.appendingPathComponent(path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url)
        }

        try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)

        XCTAssertFalse(files.fileExists(atPath: legacy.path))
        for (path, contents) in artifacts {
            XCTAssertEqual(try Data(contentsOf: preferred.appendingPathComponent(path)), contents, path)
        }
    }

    func testRepeatedMigrationIsIdempotent() throws {
        let legacy = directory.appendingPathComponent("old.tex")
        let preferred = directory.appendingPathComponent("讲义.tex")
        let contents = Data("original contents".utf8)
        try contents.write(to: legacy)

        try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)
        try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)

        XCTAssertEqual(try Data(contentsOf: preferred), contents)
    }

    func testCollisionPreservesBothFilesAndResolvesToLegacy() throws {
        let legacy = directory.appendingPathComponent("old.pdf")
        let preferred = directory.appendingPathComponent("讲义.pdf")
        let original = Data("legacy handout".utf8)
        let other = Data("a different handout".utf8)
        try original.write(to: legacy)
        try other.write(to: preferred)

        XCTAssertThrowsError(try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)) { error in
            guard case LibraryFileMigration.MigrationError.destinationExists(let url) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, preferred)
        }
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertEqual(try Data(contentsOf: preferred), other)
        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred), legacy)
    }

    func testRestartAfterACompletedMoveUsesThePreferredFile() throws {
        let legacy = directory.appendingPathComponent("old.pdf")
        let preferred = directory.appendingPathComponent("讲义.pdf")
        let contents = Data("already migrated".utf8)
        try contents.write(to: preferred)

        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred), preferred)
        try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)
        XCTAssertEqual(try Data(contentsOf: preferred), contents)
        XCTAssertFalse(files.fileExists(atPath: legacy.path))
    }

    func testMoveFailureLeavesLegacyReadable() throws {
        let legacy = directory.appendingPathComponent("old.pdf")
        let preferred = directory.appendingPathComponent("missing-parent/讲义.pdf")
        let contents = Data("keep this handout".utf8)
        try contents.write(to: legacy)

        XCTAssertThrowsError(try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred))

        XCTAssertEqual(try Data(contentsOf: legacy), contents)
        XCTAssertFalse(files.fileExists(atPath: preferred.path))
        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred), legacy)
    }

    func testTheSameLocationIsANoOp() throws {
        let url = directory.appendingPathComponent("讲义.pdf")
        let contents = Data("unchanged".utf8)
        try contents.write(to: url)

        try LibraryFileMigration.migrate(legacy: url, preferred: url)

        XCTAssertEqual(try Data(contentsOf: url), contents)
        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: url, preferred: url), url)
    }

    func testMissingLegacyNeedsNoMigration() throws {
        let legacy = directory.appendingPathComponent("old.pdf")
        let preferred = directory.appendingPathComponent("讲义.pdf")

        try LibraryFileMigration.migrate(legacy: legacy, preferred: preferred)

        XCTAssertFalse(files.fileExists(atPath: legacy.path))
        XCTAssertFalse(files.fileExists(atPath: preferred.path))
        XCTAssertEqual(LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred), preferred)
    }
}

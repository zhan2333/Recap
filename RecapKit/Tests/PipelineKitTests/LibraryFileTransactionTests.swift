//
//  LibraryFileTransactionTests.swift
//  PipelineKitTests
//
//  Created by Rio on 9/20/26.
//

import Foundation
import XCTest
@testable import PipelineKit

final class LibraryFileTransactionTests: XCTestCase {

    private typealias Transaction = LibraryFileTransaction
    private var directory: URL!
    private let files = FileManager.default
    private var journalURL: URL { directory.appendingPathComponent("transaction.json") }

    override func setUpWithError() throws {
        directory = files.temporaryDirectory.appendingPathComponent("RecapTransactionTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory, files.fileExists(atPath: directory.path) {
            try files.removeItem(at: directory)
        }
    }

    func testFileMoveCommitsItsMetadataLast() throws {
        let source = try write("original PDF", at: "old.pdf")
        let destination = directory.appendingPathComponent("新讲义.pdf")
        let metadata = try write("old metadata", at: "lectures.json")

        try Transaction.commit(moves: [.init(source: source, destination: destination)],
                               writes: [.init(url: metadata, data: data("new metadata"))], journalURL: journalURL)

        XCTAssertFalse(files.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), data("original PDF"))
        XCTAssertEqual(try Data(contentsOf: metadata), data("new metadata"))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testDirectoryThenChildMovesCommitMultipleMetadataFiles() throws {
        let fixture = try directoryFixture()

        try Transaction.commit(moves: fixture.moves,
                               writes: [.init(url: fixture.courses, data: data("new courses")),
                                        .init(url: fixture.newLectures, data: data("new lectures"), originalURL: fixture.oldLectures)],
                               journalURL: journalURL)

        XCTAssertFalse(files.fileExists(atPath: fixture.oldDirectory.path))
        XCTAssertEqual(try Data(contentsOf: fixture.newPDF), data("original PDF"))
        XCTAssertEqual(try Data(contentsOf: fixture.newDirectory.appendingPathComponent("media.mp4")), data("media bytes"))
        XCTAssertEqual(try Data(contentsOf: fixture.courses), data("new courses"))
        XCTAssertEqual(try Data(contentsOf: fixture.newLectures), data("new lectures"))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testAllConflictsAreCheckedBeforeAnyFileMoves() throws {
        let first = try write("first", at: "first.pdf")
        let second = try write("second", at: "second.pdf")
        let occupied = try write("unrelated", at: "occupied.pdf")
        let firstDestination = directory.appendingPathComponent("renamed.pdf")

        XCTAssertThrowsError(try Transaction.commit(
            moves: [.init(source: first, destination: firstDestination), .init(source: second, destination: occupied)],
            writes: [], journalURL: journalURL))

        XCTAssertEqual(try Data(contentsOf: first), data("first"))
        XCTAssertEqual(try Data(contentsOf: second), data("second"))
        XCTAssertEqual(try Data(contentsOf: occupied), data("unrelated"))
        XCTAssertFalse(files.fileExists(atPath: firstDestination.path))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testMetadataFailureRestoresEveryMoveAndBothOriginalMetadataFiles() throws {
        let fixture = try directoryFixture()
        let impossibleWrite = directory.appendingPathComponent("missing-parent/metadata.json")

        XCTAssertThrowsError(try Transaction.commit(
            moves: fixture.moves,
            writes: [.init(url: fixture.courses, data: data("new courses")),
                     .init(url: fixture.newLectures, data: data("new lectures"), originalURL: fixture.oldLectures),
                     .init(url: impossibleWrite, data: data("cannot write"))], journalURL: journalURL))

        XCTAssertEqual(try Data(contentsOf: fixture.oldPDF), data("original PDF"))
        XCTAssertEqual(try Data(contentsOf: fixture.courses), data("old courses"))
        XCTAssertEqual(try Data(contentsOf: fixture.oldLectures), data("old lectures"))
        XCTAssertFalse(files.fileExists(atPath: fixture.newDirectory.path))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testMoveFailureRestoresTheTemporaryHopAndEarlierFiles() throws {
        let first = try write("first", at: "first.pdf")
        let second = try write("second", at: "second.pdf")
        let firstDestination = directory.appendingPathComponent("renamed.pdf")
        let impossibleDestination = directory.appendingPathComponent("missing-parent/second.pdf")

        XCTAssertThrowsError(try Transaction.commit(
            moves: [.init(source: first, destination: firstDestination), .init(source: second, destination: impossibleDestination)],
            writes: [], journalURL: journalURL))

        XCTAssertEqual(try Data(contentsOf: first), data("first"))
        XCTAssertEqual(try Data(contentsOf: second), data("second"))
        XCTAssertFalse(files.fileExists(atPath: firstDestination.path))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
        XCTAssertFalse(try files.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".recap-move-") })
    }

    func testUnattemptedChildMovesDoNotPreventDirectoryRollback() throws {
        let source = directory.appendingPathComponent("old", isDirectory: true)
        let destination = directory.appendingPathComponent("missing-parent/new", isDirectory: true)
        let oldPDF = try write("original PDF", at: "old/old.pdf")

        XCTAssertThrowsError(try Transaction.commit(
            moves: [.init(source: source, destination: destination),
                    .init(source: destination.appendingPathComponent("old.pdf"), destination: destination.appendingPathComponent("new.pdf"))],
            writes: [], journalURL: journalURL))

        XCTAssertEqual(try Data(contentsOf: oldPDF), data("original PDF"))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testMissingOptionalProductsAreSkipped() throws {
        let metadata = try write("old", at: "lectures.json")

        try Transaction.commit(moves: [.init(source: directory.appendingPathComponent("absent.pdf"),
                                            destination: directory.appendingPathComponent("renamed.pdf"))],
                               writes: [.init(url: metadata, data: data("new"))], journalURL: journalURL)

        XCTAssertEqual(try Data(contentsOf: metadata), data("new"))
        XCTAssertFalse(files.fileExists(atPath: directory.appendingPathComponent("renamed.pdf").path))
    }

    func testCaseOnlyRenamePreservesContentsAndChangesDisplayedSpelling() throws {
        let source = try write("original PDF", at: "Review.pdf")
        let destination = directory.appendingPathComponent("review.pdf")

        try Transaction.commit(moves: [.init(source: source, destination: destination)], writes: [], journalURL: journalURL)

        XCTAssertEqual(try Data(contentsOf: destination), data("original PDF"))
        let names = try files.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains("review.pdf"))
        XCTAssertFalse(names.contains("Review.pdf"))
    }

    func testRecoveryRecognizesAMoveBeforeItsCompletionWasRecorded() throws {
        let source = directory.appendingPathComponent("old.pdf")
        let destination = try write("original PDF", at: "new.pdf")
        let temporary = directory.appendingPathComponent(".recap-move-test")
        let metadata = try write("old metadata", at: "lectures.json")
        try writeJournal(moves: [recordedMove(source, destination, temporary: temporary, state: "moving")],
                         writes: [recordedWrite(metadata, old: "old metadata", new: "new metadata")])

        try Transaction.recover(journalURL: journalURL)
        try Transaction.recover(journalURL: journalURL)

        XCTAssertEqual(try Data(contentsOf: destination), data("original PDF"))
        XCTAssertEqual(try Data(contentsOf: metadata), data("new metadata"))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testRecoveryFinishesAnInterruptedTemporaryHop() throws {
        let source = directory.appendingPathComponent("old.pdf")
        let destination = directory.appendingPathComponent("new.pdf")
        let temporary = try write("original PDF", at: ".recap-move-test")
        try writeJournal(moves: [recordedMove(source, destination, temporary: temporary, state: "moving")])

        try Transaction.recover(journalURL: journalURL)

        XCTAssertEqual(try Data(contentsOf: destination), data("original PDF"))
        XCTAssertFalse(files.fileExists(atPath: source.path))
        XCTAssertFalse(files.fileExists(atPath: temporary.path))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testRecoveryContinuesChildrenAfterAnUnrecordedParentMove() throws {
        let fixture = try directoryFixture()
        let oldChildInNewDirectory = fixture.newDirectory.appendingPathComponent("old.pdf")
        let moves = [
            recordedMove(fixture.oldDirectory, fixture.newDirectory, temporary: directory.appendingPathComponent(".parent-hop"),
                         isDirectory: true, state: "moving"),
            recordedMove(oldChildInNewDirectory, fixture.newPDF, temporary: fixture.newDirectory.appendingPathComponent(".child-hop")),
        ]
        let writes = [recordedWrite(fixture.courses, old: "old courses", new: "new courses"),
                      recordedWrite(fixture.newLectures, originalURL: fixture.oldLectures, old: "old lectures", new: "new lectures")]
        try writeJournal(moves: moves, writes: writes)
        try files.moveItem(at: fixture.oldDirectory, to: fixture.newDirectory)

        try Transaction.recover(journalURL: journalURL)

        XCTAssertEqual(try Data(contentsOf: fixture.newPDF), data("original PDF"))
        XCTAssertEqual(try Data(contentsOf: fixture.courses), data("new courses"))
        XCTAssertEqual(try Data(contentsOf: fixture.newLectures), data("new lectures"))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    func testFailedRollbackRetainsTheJournalAndCanResumeSafely() throws {
        let source = try write("unexpected occupant", at: "old.pdf")
        let destination = try write("original PDF", at: "new.pdf")
        let metadata = try write("new metadata", at: "lectures.json")
        let move = recordedMove(source, destination, temporary: directory.appendingPathComponent(".recap-move-test"), state: "complete")
        let write = recordedWrite(metadata, old: "old metadata", new: "new metadata", state: "complete")
        try writeJournal(phase: "rollback", moves: [move], writes: [write])

        XCTAssertThrowsError(try Transaction.recover(journalURL: journalURL))
        XCTAssertTrue(files.fileExists(atPath: journalURL.path))
        XCTAssertEqual(try Data(contentsOf: source), data("unexpected occupant"))
        XCTAssertEqual(try Data(contentsOf: destination), data("original PDF"))
        XCTAssertEqual(try Data(contentsOf: metadata), data("old metadata"))

        try files.removeItem(at: source)
        try Transaction.recover(journalURL: journalURL)

        XCTAssertEqual(try Data(contentsOf: source), data("original PDF"))
        XCTAssertFalse(files.fileExists(atPath: destination.path))
        XCTAssertFalse(files.fileExists(atPath: journalURL.path))
    }

    private struct DirectoryFixture {
        let oldDirectory: URL
        let newDirectory: URL
        let oldPDF: URL
        let newPDF: URL
        let courses: URL
        let oldLectures: URL
        let newLectures: URL
        var moves: [Transaction.Move] {
            [.init(source: oldDirectory, destination: newDirectory),
             .init(source: newDirectory.appendingPathComponent("old.pdf"), destination: newPDF)]
        }
    }

    private func directoryFixture() throws -> DirectoryFixture {
        let oldDirectory = directory.appendingPathComponent("old-course", isDirectory: true)
        let newDirectory = directory.appendingPathComponent("new-course", isDirectory: true)
        let oldPDF = try write("original PDF", at: "old-course/old.pdf")
        _ = try write("media bytes", at: "old-course/media.mp4")
        let courses = try write("old courses", at: "courses.json")
        let oldLectures = try write("old lectures", at: "old-course/lectures.json")
        return DirectoryFixture(oldDirectory: oldDirectory, newDirectory: newDirectory, oldPDF: oldPDF,
                                newPDF: newDirectory.appendingPathComponent("new.pdf"), courses: courses,
                                oldLectures: oldLectures, newLectures: newDirectory.appendingPathComponent("lectures.json"))
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    private func write(_ text: String, at path: String) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data(text).write(to: url)
        return url
    }

    private func recordedMove(_ source: URL, _ destination: URL, temporary: URL,
                              isDirectory: Bool = false, state: String = "pending") -> [String: Any] {
        ["source": source.absoluteString, "destination": destination.absoluteString,
         "temporary": temporary.absoluteString, "isDirectory": isDirectory, "state": state]
    }

    private func recordedWrite(_ url: URL, originalURL: URL? = nil,
                               old: String, new: String, state: String = "pending") -> [String: Any] {
        ["url": url.absoluteString, "originalURL": (originalURL ?? url).absoluteString,
         "originalData": data(old).base64EncodedString(), "data": data(new).base64EncodedString(), "state": state]
    }

    private func writeJournal(phase: String = "forward", moves: [[String: Any]], writes: [[String: Any]] = []) throws {
        let contents: [String: Any] = ["version": 1, "phase": phase, "moves": moves, "writes": writes]
        try JSONSerialization.data(withJSONObject: contents).write(to: journalURL, options: .atomic)
    }
}

//
//  LibraryStoreTests.swift
//  RecapLibraryTests
//
//  Created by Rio on 9/20/26.
//

import Foundation
import XCTest

@MainActor
final class LibraryStoreTests: XCTestCase {

    private let files = FileManager.default
    private let lectureKinds = ["mp4", "mp4.part", "txt", "srt", "segments.json", "analysis.json",
                                "analysis-raw.txt", "handout.pdf", "handout.tex", "handout.md",
                                "waveform.json", "matches.json", "part.json", "合并前重点.json", "文稿索引.md", "文稿分段"]
    private let courseKinds = ["textbook.txt", "review.pdf", "review.tex", "review.md", "教材目录.md", "教材分章"]
    private let partKinds = ["mp4", "mp4.part", "part.json", "waveform.json"]

    func testNewRecordsAlwaysIncludeTheirShortIDsAndKeepProtocolNames() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let course = store.addCourse(named: "基础工程")
        let lecture = store.addLecture(named: "第一讲", url: nil, to: course)
        let explicit = store.addLecture(named: "第二讲", url: nil,
                                        parts: [MediaPart(id: UUID(), sourceURL: nil, duration: 12)], to: course)

        XCTAssertEqual(course.directoryName, stem(course.name, id: course.id))
        XCTAssertEqual(course.fileStem, stem(course.name, id: course.id))
        XCTAssertEqual(lecture.fileStem, stem(lecture.name, id: lecture.id))
        XCTAssertEqual(explicit.parts?.first?.fileStem, stem(explicit.name, id: try XCTUnwrap(explicit.parts?.first?.id)))
        XCTAssertTrue(files.fileExists(atPath: root.appendingPathComponent("courses.json").path))
        let directory = store.courseDirectory(course)
        XCTAssertTrue(files.fileExists(atPath: directory.appendingPathComponent("lectures.json").path))
        XCTAssertTrue(files.fileExists(atPath: directory.appendingPathComponent(".recap-files.json").path))
        for kind in lectureKinds {
            XCTAssertEqual(store.productURL(lecture, in: course, ext: kind).lastPathComponent,
                           "\(stem(lecture.name, id: lecture.id)).\(kind)")
        }
        for kind in courseKinds {
            XCTAssertEqual(store.courseFileURL(course, name: kind).lastPathComponent,
                           "\(stem(course.name, id: course.id)).\(kind)")
        }
        try assertManifest(store, course: course)
    }

    func testLegacyMigrationPreservesEveryArtifactAndUpdatesChunkReferences() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)

        let store = LibraryStore(root: root)
        let course = try XCTUnwrap(store.courses.first)
        let lecture = try XCTUnwrap(store.lectures(in: course).first)

        XCTAssertEqual(course.id, fixture.course.id)
        XCTAssertEqual(lecture.id, fixture.lecture.id)
        XCTAssertEqual(course.directoryName, stem(course.name, id: course.id))
        XCTAssertEqual(course.fileStem, stem(course.name, id: course.id))
        XCTAssertEqual(lecture.fileStem, stem(lecture.name, id: lecture.id))
        XCTAssertFalse(files.fileExists(atPath: root.appendingPathComponent(course.id.uuidString).path))
        XCTAssertEqual(lecture.parts?.map(\.id), fixture.lecture.parts?.map(\.id))
        for part in lecture.parts ?? [] {
            XCTAssertEqual(part.fileStem, stem(lecture.name, id: part.id))
        }
        try assertFixture(fixture, in: store)
        try assertManifest(store, course: course)
        let directory = store.courseDirectory(course)
        for oldName in fixture.legacyArtifactPaths {
            XCTAssertFalse(files.fileExists(atPath: directory.appendingPathComponent(oldName).path), oldName)
        }
    }

    func testPartiallyMigratedReadableNamesAreUpgradedWithoutLosingFiles() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        var course = fixture.course
        course.directoryName = "Former readable course"
        course.reviewFileStem = "Former review title"
        var lecture = fixture.lecture
        lecture.handoutFileStem = "Former handout title"
        let legacyDirectory = root.appendingPathComponent(course.id.uuidString, isDirectory: true)
        let readableDirectory = root.appendingPathComponent(try XCTUnwrap(course.directoryName), isDirectory: true)
        try write([course], to: root.appendingPathComponent("courses.json"))
        try write([lecture], to: legacyDirectory.appendingPathComponent("lectures.json"))
        try files.moveItem(at: legacyDirectory.appendingPathComponent("review.pdf"),
                           to: legacyDirectory.appendingPathComponent("Former review title.review.pdf"))
        try files.moveItem(at: legacyDirectory.appendingPathComponent("\(lecture.id.uuidString).handout.tex"),
                           to: legacyDirectory.appendingPathComponent("Former handout title.handout.tex"))
        try files.moveItem(at: legacyDirectory, to: readableDirectory)

        let store = LibraryStore(root: root)

        XCTAssertEqual(store.courseDirectory(course).lastPathComponent, stem(course.name, id: course.id))
        XCTAssertFalse(files.fileExists(atPath: readableDirectory.path))
        try assertFixture(fixture, in: store)
        try assertManifest(store, course: course)
    }

    func testCourseRenameMovesCourseArtifactsAndPreservesLecturePathsInsideIt() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        let oldDirectory = store.courseDirectory(fixture.course)
        let lectureFileName = store.productURL(fixture.lecture, in: fixture.course, ext: "txt").lastPathComponent
        let oldCoursePaths = courseKinds.map { store.courseFileURL(fixture.course, name: $0).lastPathComponent }

        try store.renameCourse(fixture.course, to: "Renamed course")

        let renamed = try XCTUnwrap(store.courses.first)
        let directory = store.courseDirectory(fixture.course)
        XCTAssertEqual(renamed.name, "Renamed course")
        XCTAssertEqual(directory.lastPathComponent, stem(renamed.name, id: renamed.id))
        XCTAssertFalse(files.fileExists(atPath: oldDirectory.path))
        XCTAssertEqual(store.productURL(fixture.lecture, in: fixture.course, ext: "txt").lastPathComponent, lectureFileName)
        for oldName in oldCoursePaths {
            XCTAssertFalse(files.fileExists(atPath: directory.appendingPathComponent(oldName).path), oldName)
        }
        try assertFixture(fixture, in: store)
        try assertManifest(store, course: renamed)
    }

    func testLectureRenameMovesMediaPartsCachesAndChunksWithoutChangingIDs() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        let oldPaths = ownedLectureURLs(fixture.lecture, course: fixture.course, store: store)
        let coursePath = store.courseDirectory(fixture.course)

        try store.renameLecture(fixture.lecture, to: "Renamed lecture", in: fixture.course)

        let renamed = try XCTUnwrap(store.lecture(id: fixture.lecture.id, in: fixture.course))
        XCTAssertEqual(renamed.name, "Renamed lecture")
        XCTAssertEqual(renamed.fileStem, stem(renamed.name, id: renamed.id))
        XCTAssertEqual(renamed.parts?.map(\.id), fixture.lecture.parts?.map(\.id))
        XCTAssertEqual(store.courseDirectory(fixture.course), coursePath)
        for part in renamed.parts ?? [] {
            XCTAssertEqual(part.fileStem, stem(renamed.name, id: part.id))
        }
        for oldURL in oldPaths { XCTAssertFalse(files.fileExists(atPath: oldURL.path), oldURL.path) }
        try assertFixture(fixture, in: store)
        try assertManifest(store, course: fixture.course)
    }

    func testStaleProcessingUpdatesKeepTheRenamedTitleAndCurrentPaths() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        try store.renameCourse(fixture.course, to: "Current course")
        try store.renameLecture(fixture.lecture, to: "Current lecture", in: fixture.course)
        let current = try XCTUnwrap(store.lecture(id: fixture.lecture.id, in: fixture.course))
        let paths = ownedLectureURLs(current, course: fixture.course, store: store)
        var stale = fixture.lecture
        stale.phase = .failed
        stale.errorMessage = "A processing callback"
        stale.parts?[0].duration = 24

        try store.updateLecture(stale, in: fixture.course).get()

        let updated = try XCTUnwrap(store.lecture(id: fixture.lecture.id, in: fixture.course))
        XCTAssertEqual(store.courses.first?.name, "Current course")
        XCTAssertEqual(updated.name, "Current lecture")
        XCTAssertEqual(updated.fileStem, current.fileStem)
        XCTAssertEqual(updated.parts?.map(\.fileStem), current.parts?.map(\.fileStem))
        XCTAssertEqual(updated.parts?.first?.duration, 24)
        XCTAssertEqual(updated.phase, .failed)
        XCTAssertEqual(updated.errorMessage, stale.errorMessage)
        XCTAssertEqual(ownedLectureURLs(stale, course: fixture.course, store: store), paths)
        try assertFixture(fixture, in: store)
        try assertManifest(store, course: fixture.course)
    }

    func testRepeatedRenamesAndRestartKeepOnlyTheLatestPaths() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        var formerDirectories: [URL] = []
        for name in ["Revised", "Final", "Revised"] {
            formerDirectories.append(store.courseDirectory(fixture.course))
            try store.renameCourse(fixture.course, to: "\(name) course")
            try store.renameLecture(fixture.lecture, to: "\(name) lecture", in: fixture.course)
            try assertFixture(fixture, in: store)
        }
        let expectedCourse = try XCTUnwrap(store.courses.first)
        let expectedLecture = try XCTUnwrap(store.lectures(in: fixture.course).first)
        let expectedPaths = ownedLectureURLs(fixture.lecture, course: fixture.course, store: store)
        let currentDirectory = store.courseDirectory(fixture.course)

        let restarted = LibraryStore(root: root)

        XCTAssertEqual(restarted.courses.first, expectedCourse)
        XCTAssertEqual(restarted.lectures(in: fixture.course).first, expectedLecture)
        XCTAssertEqual(restarted.courseDirectory(fixture.course), currentDirectory)
        XCTAssertEqual(ownedLectureURLs(fixture.lecture, course: fixture.course, store: restarted), expectedPaths)
        for former in formerDirectories where former != currentDirectory {
            XCTAssertFalse(files.fileExists(atPath: former.path), former.path)
        }
        try assertFixture(fixture, in: restarted)
        try assertManifest(restarted, course: fixture.course)
    }

    func testRunningStorageUsersRejectBothRenamesWithoutAnyDiskMutation() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        let first = store.beginUsingStorage(in: fixture.course)
        let second = store.beginUsingStorage(in: fixture.course)
        let before = try snapshot(root)
        let courseBefore = store.courses
        let lecturesBefore = store.lectures(in: fixture.course)

        XCTAssertThrowsError(try store.renameCourse(fixture.course, to: "Blocked course"))
        XCTAssertThrowsError(try store.renameLecture(fixture.lecture, to: "Blocked lecture", in: fixture.course))
        store.endUsingStorage(first)
        XCTAssertThrowsError(try store.renameCourse(fixture.course, to: "Still blocked"))

        XCTAssertEqual(store.courses, courseBefore)
        XCTAssertEqual(store.lectures(in: fixture.course), lecturesBefore)
        XCTAssertEqual(try snapshot(root), before)
        store.endUsingStorage(second)
        try store.renameCourse(fixture.course, to: "Available course")
        try store.renameLecture(fixture.lecture, to: "Available lecture", in: fixture.course)
        try assertFixture(fixture, in: store)
    }

    func testStorageUseInAnotherCourseDoesNotBlockRename() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let activeCourse = store.addCourse(named: "Active")
        let editableCourse = store.addCourse(named: "Editable")
        let lecture = store.addLecture(named: "Lecture", url: nil, to: editableCourse)
        let lease = store.beginUsingStorage(in: activeCourse)
        defer { store.endUsingStorage(lease) }

        try store.renameCourse(editableCourse, to: "Renamed")
        try store.renameLecture(lecture, to: "Renamed lecture", in: editableCourse)

        XCTAssertEqual(store.courses.first { $0.id == activeCourse.id }?.name, "Active")
        XCTAssertEqual(store.courses.first { $0.id == editableCourse.id }?.name, "Renamed")
        XCTAssertEqual(store.lecture(id: lecture.id, in: editableCourse)?.name, "Renamed lecture")
        try assertManifest(store, course: editableCourse)
    }

    func testDestinationCollisionsNeverOverwriteForeignFiles() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        let foreignDirectory = root.appendingPathComponent(stem("Conflicting course", id: fixture.course.id), isDirectory: true)
        let foreignCourseData = Data("belongs to another directory".utf8)
        try writeData(foreignCourseData, to: foreignDirectory.appendingPathComponent("keep.bin"))
        let beforeCourseRename = try snapshot(root)
        do {
            try store.renameCourse(fixture.course, to: "Conflicting course")
            XCTAssertNotEqual(store.courseDirectory(fixture.course), foreignDirectory)
        } catch {
            XCTAssertEqual(try snapshot(root), beforeCourseRename)
        }
        XCTAssertEqual(try Data(contentsOf: foreignDirectory.appendingPathComponent("keep.bin")), foreignCourseData)
        let foreignLectureFile = store.courseDirectory(fixture.course)
            .appendingPathComponent("\(stem("Conflicting lecture", id: fixture.lecture.id)).handout.pdf")
        let foreignLectureData = Data("belongs to another document".utf8)
        try foreignLectureData.write(to: foreignLectureFile)
        let beforeLectureRename = try snapshot(root)
        do {
            try store.renameLecture(fixture.lecture, to: "Conflicting lecture", in: fixture.course)
            XCTAssertNotEqual(store.productURL(fixture.lecture, in: fixture.course, ext: "handout.pdf"), foreignLectureFile)
        } catch {
            XCTAssertEqual(try snapshot(root), beforeLectureRename)
        }
        XCTAssertEqual(try Data(contentsOf: foreignLectureFile), foreignLectureData)
        try assertFixture(fixture, in: store)
    }

    func testDuplicateAndReservedDisplayNamesNeverShareStorage() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let courses = ["Review", "review", "courses.json", "教材 / Review"].map { store.addCourse(named: $0) }
        XCTAssertEqual(Set(courses.map { store.courseDirectory($0).path.lowercased() }).count, courses.count)
        for course in courses {
            XCTAssertTrue(store.courseDirectory(course).lastPathComponent.contains(String(course.id.uuidString.prefix(8))))
            XCTAssertFalse(store.courseDirectory(course).lastPathComponent.contains("/"))
        }
        let course = try XCTUnwrap(courses.first)
        let lectures = ["Topic", "topic", "lectures.json", "Topic / A"].map { store.addLecture(named: $0, url: nil, to: course) }
        let paths = lectures.map { store.productURL($0, in: course, ext: "txt").path.lowercased() }
        XCTAssertEqual(Set(paths).count, lectures.count)
        for lecture in lectures {
            XCTAssertTrue(try XCTUnwrap(lecture.fileStem).contains(String(lecture.id.uuidString.prefix(8))))
        }
        XCTAssertNoThrow(try JSONDecoder().decode([Course].self, from: Data(contentsOf: root.appendingPathComponent("courses.json"))))
        try assertManifest(store, course: course)
    }

    func testUnreadableLectureMetadataAndItsArtifactsSurviveStartup() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let directory = root.appendingPathComponent(fixture.course.id.uuidString, isDirectory: true)
        let corrupted = Data("{incomplete lecture metadata".utf8)
        try corrupted.write(to: directory.appendingPathComponent("lectures.json"))
        let before = try snapshot(directory)

        let store = LibraryStore(root: root)

        let actualDirectory = store.courseDirectory(fixture.course)
        XCTAssertEqual(try Data(contentsOf: actualDirectory.appendingPathComponent("lectures.json")), corrupted)
        XCTAssertTrue(store.lectures(in: fixture.course).isEmpty)
        for (name, contents) in before where !name.hasSuffix("/") {
            XCTAssertEqual(try Data(contentsOf: actualDirectory.appendingPathComponent(name)), contents, name)
        }
    }

    func testDeletionAfterRenameRemovesAllOwnedArtifactsAndKeepsOtherLectures() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let fixture = try makeLegacyLibrary(at: root)
        let store = LibraryStore(root: root)
        let other = store.addLecture(named: "Keep lecture", url: nil, to: fixture.course)
        let otherURL = store.productURL(other, in: fixture.course, ext: "handout.pdf")
        let otherData = Data("keep this lecture".utf8)
        try otherData.write(to: otherURL)
        try store.renameLecture(fixture.lecture, to: "Delete lecture", in: fixture.course)
        let owned = ownedLectureURLs(fixture.lecture, course: fixture.course, store: store)
        let textbook = store.courseFileURL(fixture.course, name: "textbook.txt")
        let textbookData = try Data(contentsOf: textbook)

        store.deleteLecture(fixture.lecture, in: fixture.course)

        XCTAssertEqual(store.lectures(in: fixture.course).map(\.id), [other.id])
        for url in owned { XCTAssertFalse(files.fileExists(atPath: url.path), url.path) }
        XCTAssertEqual(try Data(contentsOf: otherURL), otherData)
        XCTAssertEqual(try Data(contentsOf: textbook), textbookData)
        try assertManifest(store, course: fixture.course)
        let otherCourse = store.addCourse(named: "Keep course")
        let directory = store.courseDirectory(fixture.course)
        store.deleteCourse(fixture.course)
        XCTAssertFalse(files.fileExists(atPath: directory.path))
        XCTAssertEqual(store.courses.map(\.id), [otherCourse.id])
        XCTAssertEqual(LibraryStore(root: root).courses.map(\.id), [otherCourse.id])
    }

    func testMergePreservesPartMediaAndCachesThenDeletesThemWithMergedLecture() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let course = store.addCourse(named: "Merge course")
        var first = store.addLecture(named: "First", url: nil, to: course)
        var second = store.addLecture(named: "Second", url: nil, to: course)
        let untouched = store.addLecture(named: "Untouched", url: nil, to: course)
        let untouchedURL = store.productURL(untouched, in: course, ext: "txt")
        try Data("untouched".utf8).write(to: untouchedURL)
        first.phase = .transcribed
        second.phase = .transcribed
        try store.updateLecture(first, in: course).get()
        try store.updateLecture(second, in: course).get()
        var expectedMedia: [UUID: Data] = [:]
        var expectedCaches: [UUID: Data] = [:]
        for lecture in [first, second] {
            let data = Data("media for \(lecture.id)".utf8)
            let transcript = Data("[{\"start\":0,\"end\":12,\"text\":\"\(lecture.name)\"}]".utf8)
            expectedMedia[lecture.id] = data
            expectedCaches[lecture.id] = transcript
            try data.write(to: store.mediaURL(lecture, in: course))
            try transcript.write(to: store.productURL(lecture, in: course, ext: "segments.json"))
            try analysisData.write(to: store.productURL(lecture, in: course, ext: "analysis.json"))
            try Data("stale handout".utf8).write(to: store.productURL(lecture, in: course, ext: "handout.pdf"))
        }
        let firstPart = try XCTUnwrap(store.mediaParts(of: first, in: course).first?.part)
        let existingCache = Data("[{\"start\":0,\"end\":12,\"text\":\"authoritative part cache\"}]".utf8)
        try existingCache.write(to: store.partTranscriptURL(firstPart, in: course))
        expectedCaches[firstPart.id] = existingCache

        let merged = try XCTUnwrap(store.mergeLectures([first.id, second.id], in: course))

        XCTAssertEqual(merged.id, first.id)
        XCTAssertEqual(Set(merged.parts?.map(\.id) ?? []), Set([first.id, second.id]))
        XCTAssertNil(store.lecture(id: second.id, in: course))
        XCTAssertEqual(store.priorAnalyses(of: merged, in: course).count, 2)
        for entry in store.mediaParts(of: merged, in: course) {
            XCTAssertEqual(try Data(contentsOf: entry.url), expectedMedia[entry.part.id])
            XCTAssertEqual(try Data(contentsOf: store.partTranscriptURL(entry.part, in: course)), expectedCaches[entry.part.id])
            XCTAssertEqual(entry.part.fileStem, stem(merged.name, id: entry.part.id))
        }
        XCTAssertFalse(files.fileExists(atPath: store.productURL(merged, in: course, ext: "handout.pdf").path))
        try assertManifest(store, course: course)
        let owned = ownedLectureURLs(merged, course: course, store: store)
        store.deleteLecture(merged, in: course)
        for url in owned { XCTAssertFalse(files.fileExists(atPath: url.path), url.path) }
        XCTAssertEqual(try String(contentsOf: untouchedURL, encoding: .utf8), "untouched")
        XCTAssertEqual(store.lectures(in: course).map(\.id), [untouched.id])
    }

    func testCorruptCourseMetadataSurvivesStartupAndAddingACourse() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let corrupted = Data("[{\"id\":\"unfinished course metadata".utf8)
        try corrupted.write(to: root.appendingPathComponent("courses.json"))
        let existingArtifact = root.appendingPathComponent("Existing course/lecture.txt")
        try writeData(Data("irreplaceable transcript".utf8), to: existingArtifact)
        let before = try snapshot(root)

        let store = LibraryStore(root: root)
        _ = store.addCourse(named: "Must not replace unreadable metadata")

        XCTAssertTrue(store.courses.isEmpty)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("courses.json")), corrupted)
        XCTAssertEqual(try snapshot(root), before)
        let restarted = LibraryStore(root: root)
        _ = restarted.addCourse(named: "Still unreadable")
        XCTAssertTrue(restarted.courses.isEmpty)
        XCTAssertEqual(try snapshot(root), before)
    }

    func testMatchingShortIDsKeepDistinctCourseAndLectureStorageThroughRename() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let firstCourse = Course(id: try XCTUnwrap(UUID(uuidString: "ABCD1234-1111-1111-1111-111111111111")), name: "Shared course")
        let secondCourse = Course(id: try XCTUnwrap(UUID(uuidString: "ABCD1234-2222-2222-2222-222222222222")), name: "Shared course")
        let firstLecture = Lecture(id: try XCTUnwrap(UUID(uuidString: "1234ABCD-1111-1111-1111-111111111111")),
                                   name: "Shared lecture", sourceURL: nil, phase: .transcribed, errorMessage: nil)
        let secondLecture = Lecture(id: try XCTUnwrap(UUID(uuidString: "1234ABCD-2222-2222-2222-222222222222")),
                                    name: "Shared lecture", sourceURL: nil, phase: .transcribed, errorMessage: nil)
        let firstCourseData = Data("first course textbook".utf8)
        let secondCourseData = Data("second course textbook".utf8)
        let firstLectureData = Data("first lecture transcript".utf8)
        let secondLectureData = Data("second lecture transcript".utf8)
        let firstDirectory = root.appendingPathComponent(firstCourse.id.uuidString, isDirectory: true)
        let secondDirectory = root.appendingPathComponent(secondCourse.id.uuidString, isDirectory: true)
        try write([firstCourse, secondCourse], to: root.appendingPathComponent("courses.json"))
        try write([firstLecture, secondLecture], to: firstDirectory.appendingPathComponent("lectures.json"))
        try write([Lecture](), to: secondDirectory.appendingPathComponent("lectures.json"))
        try writeData(firstCourseData, to: firstDirectory.appendingPathComponent("textbook.txt"))
        try writeData(secondCourseData, to: secondDirectory.appendingPathComponent("textbook.txt"))
        try writeData(firstLectureData, to: firstDirectory.appendingPathComponent("\(firstLecture.id.uuidString).txt"))
        try writeData(secondLectureData, to: firstDirectory.appendingPathComponent("\(secondLecture.id.uuidString).txt"))

        func assertDistinctStorage(_ store: LibraryStore) throws {
            XCTAssertNotEqual(store.courseDirectory(firstCourse), store.courseDirectory(secondCourse))
            XCTAssertNotEqual(store.productURL(firstLecture, in: firstCourse, ext: "txt"),
                              store.productURL(secondLecture, in: firstCourse, ext: "txt"))
            XCTAssertEqual(try Data(contentsOf: store.courseFileURL(firstCourse, name: "textbook.txt")), firstCourseData)
            XCTAssertEqual(try Data(contentsOf: store.courseFileURL(secondCourse, name: "textbook.txt")), secondCourseData)
            XCTAssertEqual(try Data(contentsOf: store.productURL(firstLecture, in: firstCourse, ext: "txt")), firstLectureData)
            XCTAssertEqual(try Data(contentsOf: store.productURL(secondLecture, in: firstCourse, ext: "txt")), secondLectureData)
            try assertManifest(store, course: firstCourse)
            try assertManifest(store, course: secondCourse)
        }

        let store = LibraryStore(root: root)
        try assertDistinctStorage(store)
        let existingSecondCourseDirectory = store.courseDirectory(secondCourse)
        let existingSecondLectureURL = store.productURL(secondLecture, in: firstCourse, ext: "txt")
        try store.renameLecture(firstLecture, to: "Renamed shared lecture", in: firstCourse)
        XCTAssertEqual(store.productURL(secondLecture, in: firstCourse, ext: "txt"), existingSecondLectureURL)
        try store.renameLecture(secondLecture, to: "Renamed shared lecture", in: firstCourse)
        try assertDistinctStorage(store)
        try store.renameCourse(firstCourse, to: "Renamed shared course")
        XCTAssertEqual(store.courseDirectory(secondCourse), existingSecondCourseDirectory)
        try store.renameCourse(secondCourse, to: "Renamed shared course")
        try assertDistinctStorage(store)

        let restarted = LibraryStore(root: root)
        try assertDistinctStorage(restarted)
        XCTAssertEqual(restarted.courses, store.courses)
        XCTAssertEqual(restarted.lectures(in: firstCourse), store.lectures(in: firstCourse))
    }

    func testMergeAfterFailedMigrationCleansHandoutsAtTheFinalPathsAndKeepsCaches() async throws {
        let root = try temporaryRoot()
        defer { try? files.removeItem(at: root) }
        let course = Course(id: UUID(), name: "Recoverable course")
        let first = Lecture(id: UUID(), name: "First", sourceURL: nil, phase: .transcribed, errorMessage: nil)
        let second = Lecture(id: UUID(), name: "Second", sourceURL: nil, phase: .transcribed, errorMessage: nil)
        let directory = root.appendingPathComponent(course.id.uuidString, isDirectory: true)
        let textbook = Data("preserved textbook".utf8)
        try write([course], to: root.appendingPathComponent("courses.json"))
        try write([first, second], to: directory.appendingPathComponent("lectures.json"))
        try writeData(textbook, to: directory.appendingPathComponent("textbook.txt"))
        let conflictingTextbook = directory.appendingPathComponent("\(stem(course.name, id: course.id)).textbook.txt")
        let conflictData = Data("conflicting migration destination".utf8)
        try writeData(conflictData, to: conflictingTextbook)
        var media: [UUID: Data] = [:]
        var caches: [UUID: Data] = [:]
        for lecture in [first, second] {
            media[lecture.id] = Data("source media \(lecture.name)".utf8)
            caches[lecture.id] = Data("[{\"start\":0,\"end\":12,\"text\":\"\(lecture.name)\"}]".utf8)
            try writeData(try XCTUnwrap(media[lecture.id]), to: directory.appendingPathComponent("\(lecture.id.uuidString).mp4"))
            try writeData(try XCTUnwrap(caches[lecture.id]), to: directory.appendingPathComponent("\(lecture.id.uuidString).segments.json"))
            try writeData(analysisData, to: directory.appendingPathComponent("\(lecture.id.uuidString).analysis.json"))
            for kind in ["handout.pdf", "handout.tex", "handout.md"] {
                try writeData(Data("stale \(lecture.name) \(kind)".utf8), to: directory.appendingPathComponent("\(lecture.id.uuidString).\(kind)"))
            }
        }
        let store = LibraryStore(root: root)
        XCTAssertNil(store.courses.first?.fileStem)
        XCTAssertEqual(store.courseDirectory(course), directory)
        XCTAssertEqual(try Data(contentsOf: conflictingTextbook), conflictData)
        XCTAssertEqual(store.lectures(in: course).map(\.id), [first.id, second.id])
        try files.removeItem(at: conflictingTextbook)

        let merged = try XCTUnwrap(store.mergeLectures([first.id, second.id], in: course))

        XCTAssertEqual(merged.id, first.id)
        XCTAssertNotNil(store.courses.first?.fileStem)
        XCTAssertFalse(files.fileExists(atPath: directory.path))
        let finalDirectory = store.courseDirectory(course)
        XCTAssertEqual(try Data(contentsOf: store.courseFileURL(course, name: "textbook.txt")), textbook)
        for kind in ["handout.pdf", "handout.tex", "handout.md"] {
            XCTAssertFalse(files.fileExists(atPath: store.productURL(merged, in: course, ext: kind).path))
            for source in [first, second] {
                XCTAssertFalse(files.fileExists(atPath: finalDirectory.appendingPathComponent("\(source.id.uuidString).\(kind)").path))
            }
        }
        let mergedParts = store.mediaParts(of: merged, in: course)
        XCTAssertEqual(Set(mergedParts.map { $0.part.id }), Set([first.id, second.id]))
        for entry in mergedParts {
            XCTAssertEqual(try Data(contentsOf: entry.url), media[entry.part.id])
            XCTAssertEqual(try Data(contentsOf: store.partTranscriptURL(entry.part, in: course)), caches[entry.part.id])
        }
        XCTAssertEqual(store.priorAnalyses(of: merged, in: course).count, 2)
        try assertManifest(store, course: course)
    }

    private struct Fixture {
        let course: Course
        let lecture: Lecture
        let courseArtifacts: [String: Data]
        let lectureArtifacts: [String: Data]
        let partArtifacts: [UUID: [String: Data]]
        let protocolArtifacts: [String: Data]

        var legacyArtifactPaths: [String] {
            Array(courseArtifacts.keys) + lectureArtifacts.keys.map { "\(lecture.id.uuidString).\($0)" }
                + partArtifacts.flatMap { id, artifacts in artifacts.keys.map { "\(id.uuidString).\($0)" } }
        }
    }

    private struct Manifest: Decodable {
        let version: Int
        let course: Record
        let lectures: [Record]
    }

    private struct Record: Decodable {
        let id: UUID
        let name: String
        let files: [String: String]
        let parts: [PartRecord]?
    }

    private struct PartRecord: Decodable {
        let id: UUID
        let files: [String: String]
    }

    private var analysisData: Data {
        Data("{\"exam_signals\":[],\"must_memorize\":[],\"answer_approaches\":[],\"confusable_points\":[],\"key_concepts\":[\"课堂原文\"],\"assignments\":[]}".utf8)
    }

    private func stem(_ name: String, id: UUID) -> String {
        "\(name) - \(id.uuidString.prefix(8))"
    }

    private func temporaryRoot() throws -> URL {
        let root = files.temporaryDirectory.appendingPathComponent("RecapLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try writeData(JSONEncoder().encode(value), to: url)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func snapshot(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                result[url.lastPathComponent + "/"] = Data()
                for (path, data) in try snapshot(url) { result[url.lastPathComponent + "/" + path] = data }
            } else {
                result[url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return result
    }

    private func ownedLectureURLs(_ lecture: Lecture, course: Course, store: LibraryStore) -> [URL] {
        var result = lectureKinds.map { store.productURL(lecture, in: course, ext: $0) }
        for entry in store.mediaParts(of: lecture, in: course) {
            result += [entry.url, entry.url.appendingPathExtension("part"),
                       store.partTranscriptURL(entry.part, in: course), store.partWaveformURL(entry.part, in: course)]
        }
        return result
    }

    private func assertManifest(_ store: LibraryStore, course: Course, file: StaticString = #filePath, line: UInt = #line) throws {
        let directory = store.courseDirectory(course)
        let data = try Data(contentsOf: directory.appendingPathComponent(".recap-files.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        XCTAssertEqual(manifest.version, 1, file: file, line: line)
        XCTAssertEqual(manifest.course.id, course.id, file: file, line: line)
        XCTAssertEqual(manifest.course.name, store.courses.first { $0.id == course.id }?.name, file: file, line: line)
        XCTAssertEqual(Set(manifest.course.files.keys), Set(courseKinds), file: file, line: line)
        XCTAssertEqual(Set(manifest.lectures.map(\.id)), Set(store.lectures(in: course).map(\.id)), file: file, line: line)
        for (kind, path) in manifest.course.files {
            XCTAssertFalse(path.hasPrefix("/"), file: file, line: line)
            XCTAssertEqual(directory.appendingPathComponent(path).path,
                           store.courseFileURL(course, name: kind).path, file: file, line: line)
        }
        for record in manifest.lectures {
            let lecture = try XCTUnwrap(store.lecture(id: record.id, in: course), file: file, line: line)
            XCTAssertEqual(record.name, lecture.name, file: file, line: line)
            XCTAssertEqual(Set(record.files.keys), Set(lectureKinds), file: file, line: line)
            for (kind, path) in record.files {
                XCTAssertFalse(path.hasPrefix("/"), file: file, line: line)
                XCTAssertEqual(directory.appendingPathComponent(path).path,
                               store.productURL(lecture, in: course, ext: kind).path, file: file, line: line)
            }
            let parts = try XCTUnwrap(record.parts, file: file, line: line)
            let actualParts = store.mediaParts(of: lecture, in: course)
            XCTAssertEqual(Set(parts.map(\.id)), Set(actualParts.map { $0.part.id }), file: file, line: line)
            for part in parts {
                XCTAssertEqual(Set(part.files.keys), Set(partKinds), file: file, line: line)
                let actual = try XCTUnwrap(actualParts.first { $0.part.id == part.id }, file: file, line: line)
                let expected = ["mp4": actual.url, "mp4.part": actual.url.appendingPathExtension("part"),
                                "part.json": store.partTranscriptURL(actual.part, in: course),
                                "waveform.json": store.partWaveformURL(actual.part, in: course)]
                for (kind, path) in part.files {
                    XCTAssertFalse(path.hasPrefix("/"), file: file, line: line)
                    XCTAssertEqual(directory.appendingPathComponent(path).path, expected[kind]?.path, file: file, line: line)
                }
            }
        }
    }

    private func assertFixture(_ fixture: Fixture, in store: LibraryStore, file: StaticString = #filePath, line: UInt = #line) throws {
        let course = fixture.course
        let lecture = fixture.lecture
        let directory = store.courseDirectory(course)
        for (kind, original) in fixture.courseArtifacts {
            let pieces = kind.split(separator: "/", maxSplits: 1).map(String.init)
            var url = store.courseFileURL(course, name: pieces[0])
            if pieces.count == 2 { url.appendPathComponent(pieces[1]) }
            var expected = original
            if kind == "教材目录.md" {
                let current = store.courseFileURL(course, name: "教材分章").lastPathComponent
                expected = Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "教材分章/", with: current + "/").utf8)
            }
            XCTAssertEqual(try Data(contentsOf: url), expected, kind, file: file, line: line)
        }
        for (kind, original) in fixture.lectureArtifacts {
            let pieces = kind.split(separator: "/", maxSplits: 1).map(String.init)
            var url = store.productURL(lecture, in: course, ext: pieces[0])
            if pieces.count == 2 { url.appendPathComponent(pieces[1]) }
            var expected = original
            if kind == "文稿索引.md" {
                let current = store.chunkDirectory(lecture, in: course).lastPathComponent
                expected = Data(String(decoding: original, as: UTF8.self)
                    .replacingOccurrences(of: "\(lecture.id.uuidString).文稿分段/", with: current + "/").utf8)
            }
            XCTAssertEqual(try Data(contentsOf: url), expected, kind, file: file, line: line)
        }
        for entry in store.mediaParts(of: lecture, in: course) {
            let artifacts = try XCTUnwrap(fixture.partArtifacts[entry.part.id], file: file, line: line)
            let paths = ["mp4": entry.url, "mp4.part": entry.url.appendingPathExtension("part"),
                         "part.json": store.partTranscriptURL(entry.part, in: course),
                         "waveform.json": store.partWaveformURL(entry.part, in: course)]
            for (kind, original) in artifacts {
                let url = try XCTUnwrap(paths[kind], file: file, line: line)
                XCTAssertEqual(try Data(contentsOf: url), original, kind, file: file, line: line)
            }
        }
        for (path, contents) in fixture.protocolArtifacts {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(path)), contents, path, file: file, line: line)
        }
    }

    private func makeLegacyLibrary(at root: URL) throws -> Fixture {
        let course = Course(id: UUID(), name: "基础工程")
        let parts = [MediaPart(id: UUID(), sourceURL: nil, duration: 12),
                     MediaPart(id: UUID(), sourceURL: nil, duration: 18)]
        let lecture = Lecture(id: UUID(), name: "第一讲", sourceURL: nil, phase: .transcribed,
                              errorMessage: nil, parts: parts)
        let segments = Data("[{\"start\":0,\"end\":12,\"text\":\"课堂原文\"}]".utf8)
        let courseArtifacts: [String: Data] = [
            "textbook.txt": Data("教材原文".utf8),
            "review.pdf": Data("existing review PDF".utf8),
            "review.tex": Data("existing review TeX".utf8),
            "review.md": Data("existing review Markdown".utf8),
            "教材目录.md": Data("章节对应：`教材分章/ch01.txt`\n".utf8),
            "教材分章/ch01.txt": Data("【第1页】教材第一章".utf8),
        ]
        let lectureArtifacts: [String: Data] = [
            "mp4": Data([0, 1, 127, 128, 255]), "mp4.part": Data([23, 0, 255]),
            "txt": Data("课堂原文".utf8),
            "srt": Data("1\n00:00:00,000 --> 00:00:12,000\n课堂原文\n".utf8),
            "segments.json": segments, "analysis.json": analysisData,
            "analysis-raw.txt": Data("raw analysis response".utf8),
            "handout.pdf": Data("existing lecture PDF".utf8),
            "handout.tex": Data("existing lecture TeX".utf8),
            "handout.md": Data("existing lecture Markdown".utf8),
            "waveform.json": Data("[0.5,0.2]".utf8),
            "matches.json": Data("[]".utf8), "part.json": segments,
            "合并前重点.json": Data("[]".utf8),
            "文稿索引.md": Data("范围：`\(lecture.id.uuidString).文稿分段/part01.txt` · 00:00–00:12\n".utf8),
            "文稿分段/part01.txt": Data("第一块原文".utf8),
            "文稿分段/part02.txt": Data("第二块原文".utf8),
        ]
        let partArtifacts = Dictionary(uniqueKeysWithValues: parts.map { part in
            (part.id, ["mp4": Data("media \(part.id)".utf8), "mp4.part": Data("partial \(part.id)".utf8),
                       "part.json": segments, "waveform.json": Data("[0.1,0.2,0.3]".utf8)])
        })
        let protocolArtifacts = ["AGENTS.md", "GEMINI.md", ".claude/skills/recap-review/SKILL.md", ".agents/skills/recap-review/SKILL.md"]
            .reduce(into: [String: Data]()) { $0[$1] = Data("fixed protocol path \($1)".utf8) }
        let fixture = Fixture(course: course, lecture: lecture, courseArtifacts: courseArtifacts,
                              lectureArtifacts: lectureArtifacts, partArtifacts: partArtifacts,
                              protocolArtifacts: protocolArtifacts)
        let directory = root.appendingPathComponent(course.id.uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try write([course], to: root.appendingPathComponent("courses.json"))
        try write([lecture], to: directory.appendingPathComponent("lectures.json"))
        for (kind, contents) in courseArtifacts { try writeData(contents, to: directory.appendingPathComponent(kind)) }
        for (kind, contents) in lectureArtifacts {
            try writeData(contents, to: directory.appendingPathComponent("\(lecture.id.uuidString).\(kind)"))
        }
        for (id, artifacts) in partArtifacts {
            for (kind, contents) in artifacts {
                try writeData(contents, to: directory.appendingPathComponent("\(id.uuidString).\(kind)"))
            }
        }
        for (path, contents) in protocolArtifacts { try writeData(contents, to: directory.appendingPathComponent(path)) }
        return fixture
    }
}

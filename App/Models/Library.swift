//
//  Library.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import AnalysisKit
import TranscriptionKit
import PipelineKit

struct Course: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var directoryName: String?
    var reviewFileStem: String?
    var fileStem: String?
}

// One media file of a lecture
struct MediaPart: Codable, Hashable, Identifiable {
    let id: UUID
    var sourceURL: URL?
    var duration: TimeInterval?   // known after transcription; offsets the next part
    var fileStem: String?
}

struct Lecture: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var sourceURL: URL?
    var phase: Phase
    var errorMessage: String?
    var parts: [MediaPart]?       // nil = legacy single-media lecture
    var handoutFileStem: String?
    var fileStem: String?

    enum Phase: String, Codable {
        case pending        // queued, nothing on disk yet
        case downloaded     // media on disk, not transcribed
        case transcribed    // srt/txt/segments ready
        case failed
    }
}

// Owns the course records; file mappings and rename transactions live in the storage extensions below
@MainActor
final class LibraryStore {

    static let shared = LibraryStore()

    // onChange belongs to the list that owns it; anyone else watching a record listens for this
    static let didChange = Notification.Name("LibraryStoreDidChange")

    private(set) var courses: [Course] = []
    private var lecturesByCourse: [UUID: [Lecture]] = [:]
    private var storageUsers: [UUID: UUID] = [:]
    var hasActiveStorageUsers: Bool { !storageUsers.isEmpty }
    private var storageRecoveryError: Error?
    static let pathsDidChange = Notification.Name("LibraryStorePathsDidChange")

    // Fired after any mutation
    var onChange: (() -> Void)?

    let root: URL

    private convenience init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(root: support.appendingPathComponent("Recap", isDirectory: true))
    }

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Queries

    func lectures(in course: Course) -> [Lecture] {
        lecturesByCourse[course.id] ?? []
    }

    func lecture(id: UUID, in course: Course) -> Lecture? {
        lectures(in: course).first { $0.id == id }
    }

    // One skill, every discovery convention: .claude/skills (claude, grok), .agents/skills (the neutral
    // standard), AGENTS.md (codex, kimi, grok, deepseek), GEMINI.md (gemini, qwen)
    private func installSkillIfNeeded(in courseDir: URL) {
        guard let source = Bundle.main.url(forResource: "recap-review-skill", withExtension: "md"),
              let text = try? String(contentsOf: source, encoding: .utf8) else { return }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let sourceModified = modified(source)

        let targets: [(path: String, stripFrontmatter: Bool)] = [
            (".claude/skills/recap-review/SKILL.md", false),
            (".agents/skills/recap-review/SKILL.md", false),
            ("AGENTS.md", true),
            ("GEMINI.md", true),
        ]
        for entry in targets {
            let target = courseDir.appendingPathComponent(entry.path)
            guard sourceModified > modified(target) else { continue }
            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let content = entry.stripFrontmatter ? Self.strippingFrontmatter(text) : text
            try? content.write(to: target, atomically: true, encoding: .utf8)
        }
    }

    private static func strippingFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let parts = text.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else { return text }
        return parts.dropFirst().joined(separator: "\n---\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    func locate(lectureID: UUID) -> (course: Course, lecture: Lecture)? {
        for course in courses {
            if let lecture = lecture(id: lectureID, in: course) { return (course, lecture) }
        }
        return nil
    }

    // MARK: - Mutations

    func addCourse(named name: String) -> Course {
        let course = Course(id: UUID(), name: name)
        do {
            try checkStorageRecovery()
            let updated = namedCourse(course)
            courses.append(updated)
            lecturesByCourse[updated.id] = []
            guard persistCourses() else {
                courses.removeAll { $0.id == updated.id }
                lecturesByCourse[updated.id] = nil
                return course
            }
            _ = courseDirectory(updated)
            notify()
            return updated
        } catch {
            NSLog("Recap could not create a course: %@", error.localizedDescription)
            return course
        }
    }

    @discardableResult
    func updateCourse(_ course: Course) -> Result<Void, Error> {
        Result { try renameCourse(course, to: course.name) }
    }

    func deleteCourse(_ course: Course) {
        guard (try? requireIdleStorage(in: course)) != nil,
              let current = self.course(id: course.id) else { return }
        let directory = current.directoryURL(in: root)
        courses.removeAll { $0.id == course.id }
        lecturesByCourse[course.id] = nil
        try? FileManager.default.removeItem(at: directory)
        persistCourses()
        notify()
    }

    func addLecture(named name: String, url: URL?, parts: [MediaPart]? = nil, to course: Course) -> Lecture {
        let lecture = Lecture(id: UUID(), name: name, sourceURL: url, phase: .pending, errorMessage: nil, parts: parts)
        guard let current = self.course(id: course.id) else { return lecture }
        do {
            try synchronizeStorage(for: current, lectures: lectures(in: current) + [lecture])
            notify()
            return self.lecture(id: lecture.id, in: current) ?? lecture
        } catch {
            NSLog("Recap could not create a lecture: %@", error.localizedDescription)
            return lecture
        }
    }

    // Merging preserves part identities and caches while their filenames adopt the retained lecture title.
    @discardableResult
    func mergeLectures(_ ids: [UUID], in course: Course) -> Lecture? {
        guard (try? requireIdleStorage(in: course)) != nil else { return nil }
        let list = lectures(in: course)
        let sources = ids.compactMap { id in list.first { $0.id == id } }
        guard sources.count > 1, var merged = sources.first else { return nil }

        merged.parts = sources.flatMap { mediaParts(of: $0, in: course).map(\.part) }
        merged.sourceURL = nil
        merged.phase = .downloaded
        merged.errorMessage = nil

        let absorbed = Set(sources.dropFirst().map(\.id))
        var updated = list.filter { !absorbed.contains($0.id) }
        guard let index = updated.firstIndex(where: { $0.id == merged.id }) else { return nil }
        updated[index] = merged
        var staleProducts: [(Lecture, String)] = []
        var priors: [PriorAnalysis] = []
        for lecture in sources {
            keepTranscriptAsPartCache(of: lecture, in: course)
            if let prior = priorAnalysis(of: lecture, in: course) { priors.append(prior) }
            // Every product describes the pre-merge lecture: its timeline is gone, its findings are kept above
            for ext in ["srt", "txt", "segments.json", "analysis.json", "analysis-raw.txt",
                        "handout.pdf", "handout.tex", "handout.md", "matches.json"] {
                staleProducts.append((lecture, ext))
            }
        }
        do {
            try synchronizeStorage(for: storedCourse(course), lectures: updated)
        } catch {
            NSLog("Recap could not merge lecture storage: %@", error.localizedDescription)
            return nil
        }
        let directory = courseDirectory(course)
        for (source, kind) in staleProducts {
            let url = self.lecture(id: source.id, in: course).map { productURL($0, in: course, ext: kind) }
                ?? directory.appendingPathComponent(source.fileName(kind, in: directory))
            try? FileManager.default.removeItem(at: url)
        }
        if let data = try? JSONEncoder().encode(priors), !priors.isEmpty {
            try? data.write(to: productURL(merged, in: course, ext: "合并前重点.json"), options: .atomic)
        }
        notify()
        return self.lecture(id: merged.id, in: course)
    }

    // A single-media lecture's transcript already sits on its part's own timeline
    private func keepTranscriptAsPartCache(of lecture: Lecture, in course: Course) {
        guard (try? checkStorageRecovery()) != nil else { return }
        let parts = mediaParts(of: lecture, in: course)
        guard parts.count == 1 else { return }
        let cache = partTranscriptURL(parts[0].part, in: course)
        let transcript = productURL(lecture, in: course, ext: "segments.json")
        guard !FileManager.default.fileExists(atPath: cache.path),
              FileManager.default.fileExists(atPath: transcript.path) else { return }
        try? FileManager.default.copyItem(at: transcript, to: cache)
    }

    // A lecture transcribed before part caches existed still knows where each part sits, so the
    // finished transcript can be cut back into per-part pieces instead of being heard again
    func backfillPartCaches(of lecture: Lecture, in course: Course) {
        guard (try? checkStorageRecovery()) != nil else { return }
        let parts = mediaParts(of: lecture, in: course)
        let transcriptURL = productURL(lecture, in: course, ext: "segments.json")
        guard lecture.phase == .transcribed,
              parts.contains(where: { !FileManager.default.fileExists(atPath: partTranscriptURL($0.part, in: course).path) }),
              let data = try? Data(contentsOf: transcriptURL),
              let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data),
              !segments.isEmpty else { return }
        let transcribedAt = modified(transcriptURL)

        var offset: TimeInterval = 0
        for (index, entry) in parts.enumerated() {
            // Past a part of unknown length nothing can be placed on the timeline any more
            guard let duration = entry.part.duration, duration > 0 else { return }
            let start = offset
            offset += duration
            // The tail keeps anything past the summed durations, so no line is lost
            let upper = index == parts.count - 1 ? TimeInterval.infinity : offset
            let cache = partTranscriptURL(entry.part, in: course)
            guard !FileManager.default.fileExists(atPath: cache.path),
                  modified(entry.url) <= transcribedAt else { continue }
            // A segment belongs to the part its start falls in, so nothing lands in two pieces
            let own = segments.filter { $0.start >= start && $0.start < upper }
                .map { TranscriptSegment(start: $0.start - start, end: $0.end - start, text: $0.text) }
            guard !own.isEmpty, let encoded = try? JSONEncoder().encode(own) else { continue }
            try? encoded.write(to: cache, options: .atomic)
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func priorAnalysis(of lecture: Lecture, in course: Course) -> PriorAnalysis? {
        guard let data = try? Data(contentsOf: productURL(lecture, in: course, ext: "analysis.json")),
              let analysis = try? JSONDecoder().decode(LectureAnalysis.self, from: data) else { return nil }
        return PriorAnalysis(
            name: lecture.name,
            partIDs: mediaParts(of: lecture, in: course).map(\.part.id),
            analysis: analysis
        )
    }

    func priorAnalyses(of lecture: Lecture, in course: Course) -> [PriorAnalysis] {
        guard let data = try? Data(contentsOf: productURL(lecture, in: course, ext: "合并前重点.json")),
              let priors = try? JSONDecoder().decode([PriorAnalysis].self, from: data) else { return [] }
        return priors
    }

    // Transcription is what learns where each part sits, so it stamps the ranges back in
    func stampPriorSpans(_ spans: [UUID: ClosedRange<TimeInterval>], of lecture: Lecture, in course: Course) {
        guard (try? checkStorageRecovery()) != nil else { return }
        var priors = priorAnalyses(of: lecture, in: course)
        guard !priors.isEmpty else { return }
        for index in priors.indices {
            let ranges = priors[index].partIDs.compactMap { spans[$0] }
            guard let start = ranges.map(\.lowerBound).min(), let end = ranges.map(\.upperBound).max() else { continue }
            priors[index].start = start
            priors[index].end = end
        }
        guard let data = try? JSONEncoder().encode(priors) else { return }
        try? data.write(to: productURL(lecture, in: course, ext: "合并前重点.json"), options: .atomic)
    }

    // State callbacks keep the current title; explicit rename APIs own title and path changes.
    @discardableResult
    func updateLecture(_ lecture: Lecture, in course: Course) -> Result<Void, Error> {
        Result {
            guard let current = self.course(id: course.id),
                  var list = lecturesByCourse[course.id],
                  let index = list.firstIndex(where: { $0.id == lecture.id }) else { throw StorageError.missingRecord }
            var updated = lecture
            updated.name = list[index].name
            updated.fileStem = list[index].fileStem
            updated.handoutFileStem = list[index].handoutFileStem
            list[index] = updated
            try synchronizeStorage(for: current, lectures: list)
            notify()
        }
    }

    func deleteLecture(_ lecture: Lecture, in course: Course) {
        guard (try? requireIdleStorage(in: course)) != nil else { return }
        let lecture = storedLecture(lecture, in: course)
        lecturesByCourse[course.id]?.removeAll { $0.id == lecture.id }
        for ext in Lecture.fileKinds {
            try? FileManager.default.removeItem(at: productURL(lecture, in: course, ext: ext))
        }
        for part in lecture.mediaParts {
            for ext in MediaPart.fileKinds {
                try? FileManager.default.removeItem(at: courseDirectory(course).appendingPathComponent(part.fileName(ext)))
            }
        }
        persistLectures(of: course)
        notify()
    }

    private func notify() {
        onChange?()
        NotificationCenter.default.post(name: LibraryStore.didChange, object: nil)
    }
}

// MARK: - Storage paths and operations

extension LibraryStore {
    enum StorageError: LocalizedError {
        case busy, missingRecord, recoveryRequired, unreadableMetadata

        var errorDescription: String? {
            switch self {
            case .busy:
                return String(localized: "课程正在处理文件或运行终端会话，请在任务结束或关闭终端后重命名。")
            case .missingRecord:
                return String(localized: "课程或讲次已不存在。")
            case .recoveryRequired:
                return String(localized: "上次文件改名尚未恢复，请重新打开 Recap 后再试。")
            case .unreadableMetadata:
                return String(localized: "课程记录无法读取，原文件已保留，暂时不能修改此课程。")
            }
        }
    }

    func course(id: UUID) -> Course? { courses.first { $0.id == id } }

    func canWriteFiles(in course: Course) -> Bool {
        (try? checkStorageRecovery()) != nil && self.course(id: course.id) != nil && lecturesByCourse[course.id] != nil
    }

    func beginUsingStorage(in course: Course) -> UUID {
        let token = UUID()
        storageUsers[token] = course.id
        return token
    }

    func endUsingStorage(_ token: UUID) { storageUsers[token] = nil }

    func renameCourse(_ course: Course, to name: String) throws {
        guard var current = self.course(id: course.id) else { throw StorageError.missingRecord }
        guard current.name != name else { return }
        try requireIdleStorage(in: current)
        current.name = name
        try synchronizeStorage(for: current, lectures: lectures(in: current))
        notify()
    }

    func renameLecture(_ lecture: Lecture, to name: String, in course: Course) throws {
        guard let current = self.course(id: course.id),
              var list = lecturesByCourse[course.id],
              let index = list.firstIndex(where: { $0.id == lecture.id }) else { throw StorageError.missingRecord }
        guard list[index].name != name else { return }
        try requireIdleStorage(in: current)
        list[index].name = name
        try synchronizeStorage(for: current, lectures: list)
        notify()
    }

    func courseDirectory(_ course: Course) -> URL {
        let current = storedCourse(course)
        let directory = current.directoryURL(in: root)
        // Deleted snapshots may still be displayed, but must never recreate their course.
        guard self.course(id: current.id) != nil, storageRecoveryError == nil,
              !FileManager.default.fileExists(atPath: renameJournalURL.path) else { return directory }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        installSkillIfNeeded(in: directory)
        let manifestURL = directory.appendingPathComponent(".recap-files.json")
        if let list = lecturesByCourse[current.id], !FileManager.default.fileExists(atPath: manifestURL.path) {
            try? manifestData(course: current, lectures: list, directory: directory).write(to: manifestURL, options: .atomic)
        }
        return directory
    }

    func productURL(_ lecture: Lecture, in course: Course, ext: String) -> URL {
        let directory = courseDirectory(course)
        return directory.appendingPathComponent(storedLecture(lecture, in: course).fileName(ext, in: directory))
    }

    func courseFileURL(_ course: Course, name: String) -> URL {
        let directory = courseDirectory(course)
        return directory.appendingPathComponent(storedCourse(course).fileName(name, in: directory))
    }

    func mediaURL(_ lecture: Lecture, in course: Course) -> URL {
        productURL(lecture, in: course, ext: "mp4")
    }

    func partMediaURL(_ part: MediaPart, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent(storedPart(part, in: course).fileName("mp4"))
    }

    func partTranscriptURL(_ part: MediaPart, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent(storedPart(part, in: course).fileName("part.json"))
    }

    func partWaveformURL(_ part: MediaPart, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent(storedPart(part, in: course).fileName("waveform.json"))
    }

    func chunkDirectory(_ lecture: Lecture, in course: Course) -> URL {
        productURL(lecture, in: course, ext: "文稿分段")
    }

    func mediaParts(of lecture: Lecture, in course: Course) -> [(part: MediaPart, url: URL)] {
        storedLecture(lecture, in: course).mediaParts.map { ($0, partMediaURL($0, in: course)) }
    }
}

private extension LibraryStore {
    var renameJournalURL: URL { root.appendingPathComponent(".recap-rename.json") }

    func storedCourse(_ course: Course) -> Course { self.course(id: course.id) ?? course }
    func storedLecture(_ lecture: Lecture, in course: Course) -> Lecture {
        self.lecture(id: lecture.id, in: course) ?? lecture
    }
    func storedPart(_ part: MediaPart, in course: Course) -> MediaPart {
        lectures(in: course).flatMap(\.mediaParts).first { $0.id == part.id } ?? part
    }

    func checkStorageRecovery() throws {
        guard storageRecoveryError == nil,
              !FileManager.default.fileExists(atPath: renameJournalURL.path) else { throw StorageError.recoveryRequired }
    }

    func requireIdleStorage(in course: Course) throws {
        try checkStorageRecovery()
        guard !storageUsers.values.contains(course.id) else { throw StorageError.busy }
    }

    func directoryEntries(_ directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func namedStem(_ name: String, fallback: String, id: UUID, current: String?, occupied: [String]) -> String {
        let base = LibraryFileNaming.uniqueStem(name, fallback: fallback, id: id, occupied: [])
        let key: (String) -> String = { $0.precomposedStringWithCanonicalMapping.lowercased() }
        let available = current.map { value in !occupied.contains { key($0) == key(value) } } ?? false
        if let current, available, current == base { return current }
        if let current, available, current.hasPrefix(base + " - "),
           Int(current.dropFirst((base + " - ").count)) != nil { return current }
        return LibraryFileNaming.uniqueStem(name, fallback: fallback, id: id, occupied: occupied)
    }

    func namedCourse(_ course: Course) -> Course {
        var result = course
        let old = self.course(id: course.id) ?? course
        let oldName = old.directoryURL(in: root).lastPathComponent
        let occupied = directoryEntries(root).filter { $0 != oldName }
            + courses.filter { $0.id != course.id }.compactMap(\.directoryName)
        result.directoryName = namedStem(course.name, fallback: "Course", id: course.id,
                                         current: course.fileStem == nil ? nil : course.directoryName, occupied: occupied)
        result.fileStem = result.directoryName
        result.reviewFileStem = nil
        return result
    }

    // The keys express ownership, allowing parts to keep their identity when lectures are merged.
    func fileMap(course: Course, lectures: [Lecture], directory: URL) -> [String: URL] {
        var files: [String: URL] = [:]
        let texSidecars = ["aux", "log", "out", "toc", "synctex.gz", "fls", "fdb_latexmk"]
        for kind in Course.fileKinds + texSidecars.map({ "review.\($0)" }) {
            let fileName: String
            if kind.hasPrefix("review."), !Course.fileKinds.contains(kind) {
                fileName = String(course.fileName("review.tex", in: directory).dropLast(3)) + kind.dropFirst(7)
            } else { fileName = course.fileName(kind, in: directory) }
            files["course:\(kind)"] = directory.appendingPathComponent(fileName)
        }
        for lecture in lectures {
            for kind in Lecture.fileKinds + texSidecars.map({ "handout.\($0)" }) {
                let fileName: String
                if kind.hasPrefix("handout."), !Lecture.fileKinds.contains(kind) {
                    fileName = String(lecture.fileName("handout.tex", in: directory).dropLast(3)) + kind.dropFirst(8)
                } else { fileName = lecture.fileName(kind, in: directory) }
                files["lecture:\(lecture.id):\(kind)"] = directory.appendingPathComponent(fileName)
            }
            for part in lecture.mediaParts {
                for kind in MediaPart.fileKinds {
                    files["part:\(part.id):\(kind)"] = directory.appendingPathComponent(part.fileName(kind))
                }
            }
        }
        return files
    }

    func namedLectures(_ list: [Lecture], old: [Lecture], course: Course, directory: URL) -> [Lecture] {
        let owned = Set(fileMap(course: course, lectures: old, directory: directory).values.map(\.lastPathComponent))
        let kinds = Array(Set(Lecture.fileKinds + MediaPart.fileKinds)).sorted { $0.count > $1.count }
        let unrelated = directoryEntries(directory).filter { !owned.contains($0) }.compactMap { file -> String? in
            guard let kind = kinds.first(where: { file.hasSuffix("." + $0) }) else { return nil }
            return String(file.dropLast(kind.count + 1))
        }
        var assigned: [UUID: String] = [:]
        for lecture in list {
            if let stem = lecture.fileStem { assigned[lecture.id] = stem }
            for part in lecture.mediaParts {
                if let stem = part.fileStem { assigned[part.id] = stem }
            }
        }
        func occupied(excluding id: UUID) -> [String] { unrelated + assigned.filter { $0.key != id }.map(\.value) }
        return list.map { lecture in
            var result = lecture
            let stem = namedStem(lecture.name, fallback: "Lecture", id: lecture.id,
                                 current: lecture.fileStem, occupied: occupied(excluding: lecture.id))
            result.fileStem = stem
            result.handoutFileStem = nil
            assigned[lecture.id] = stem
            if let parts = lecture.parts {
                result.parts = parts.map { part in
                    var updated = part
                    updated.fileStem = part.id == lecture.id ? stem : namedStem(
                        lecture.name, fallback: "Lecture", id: part.id,
                        current: part.fileStem, occupied: occupied(excluding: part.id))
                    assigned[part.id] = updated.fileStem
                    return updated
                }
            }
            return result
        }
    }

    func synchronizeStorage(for candidate: Course, lectures candidates: [Lecture]) throws {
        try checkStorageRecovery()
        guard let oldCourse = course(id: candidate.id) else { throw StorageError.missingRecord }
        guard let oldLectures = lecturesByCourse[oldCourse.id] else { throw StorageError.unreadableMetadata }
        let oldDirectory = oldCourse.directoryURL(in: root)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let updatedCourse = namedCourse(candidate)
        let updatedLectures = namedLectures(candidates, old: oldLectures, course: oldCourse, directory: oldDirectory)
        let newDirectory = updatedCourse.directoryURL(in: root)
        let oldMap = fileMap(course: oldCourse, lectures: oldLectures, directory: oldDirectory)
        let newMap = fileMap(course: updatedCourse, lectures: updatedLectures, directory: newDirectory)
        var moves: [LibraryFileTransaction.Move] = []
        if oldDirectory != newDirectory { moves.append(.init(source: oldDirectory, destination: newDirectory)) }
        var movedSources = Set<URL>()
        for key in newMap.keys.sorted() {
            guard let target = newMap[key] else { continue }
            // Newly appended media can have been copied under its UUID before it joins the record.
            let source = oldMap[key] ?? legacySource(for: key, in: oldDirectory)
            guard let source, FileManager.default.fileExists(atPath: source.path), movedSources.insert(source).inserted else { continue }
            let relocatedSource = newDirectory.appendingPathComponent(source.lastPathComponent)
            if relocatedSource != target { moves.append(.init(source: relocatedSource, destination: target)) }
        }
        var updatedCourses = courses
        if let index = updatedCourses.firstIndex(where: { $0.id == updatedCourse.id }) { updatedCourses[index] = updatedCourse }
        var writes: [LibraryFileTransaction.Write] = [
            .init(url: root.appendingPathComponent("courses.json"), data: try JSONEncoder().encode(updatedCourses)),
            .init(url: newDirectory.appendingPathComponent("lectures.json"), data: try JSONEncoder().encode(updatedLectures),
                  originalURL: oldDirectory.appendingPathComponent("lectures.json")),
            .init(url: newDirectory.appendingPathComponent(".recap-files.json"),
                  data: try manifestData(course: updatedCourse, lectures: updatedLectures, directory: newDirectory),
                  originalURL: oldDirectory.appendingPathComponent(".recap-files.json"))
        ]
        for lecture in oldLectures {
            guard let updated = updatedLectures.first(where: { $0.id == lecture.id }),
                  let oldIndex = oldMap["lecture:\(lecture.id):文稿索引.md"],
                  let newIndex = newMap["lecture:\(lecture.id):文稿索引.md"],
                  var text = try? String(contentsOf: oldIndex, encoding: .utf8) else { continue }
            let oldChunk = lecture.fileName("文稿分段", in: oldDirectory)
            let newChunk = updated.fileName("文稿分段", in: newDirectory)
            if oldChunk != newChunk { text = text.replacingOccurrences(of: oldChunk + "/", with: newChunk + "/") }
            if lecture.name != updated.name {
                text = text.replacingOccurrences(of: "# \(lecture.name) · 文稿分段\n", with: "# \(updated.name) · 文稿分段\n")
            }
            if text != (try? String(contentsOf: oldIndex, encoding: .utf8)) {
                writes.append(.init(url: newIndex, data: Data(text.utf8), originalURL: oldIndex))
            }
        }
        let oldTextbookIndex = oldDirectory.appendingPathComponent(oldCourse.fileName("教材目录.md", in: oldDirectory))
        if let text = try? String(contentsOf: oldTextbookIndex, encoding: .utf8) {
            let rewritten = text.replacingOccurrences(of: oldCourse.fileName("教材分章", in: oldDirectory) + "/",
                                                      with: updatedCourse.fileName("教材分章", in: newDirectory) + "/")
            if rewritten != text {
                writes.append(.init(url: newDirectory.appendingPathComponent(updatedCourse.fileName("教材目录.md", in: newDirectory)),
                                    data: Data(rewritten.utf8), originalURL: oldTextbookIndex))
            }
        }
        do {
            try LibraryFileTransaction.commit(moves: moves, writes: writes, journalURL: renameJournalURL)
        } catch {
            if FileManager.default.fileExists(atPath: renameJournalURL.path) { storageRecoveryError = error }
            throw error
        }
        courses = updatedCourses
        lecturesByCourse[candidate.id] = updatedLectures
        installSkillIfNeeded(in: newDirectory)
        if !moves.isEmpty || oldCourse.name != updatedCourse.name || zip(oldLectures, updatedLectures).contains(where: { $0.0.name != $0.1.name }) {
            NotificationCenter.default.post(name: Self.pathsDidChange, object: self, userInfo: ["courseID": candidate.id])
        }
    }

    func legacySource(for key: String, in directory: URL) -> URL? {
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, UUID(uuidString: parts[1]) != nil else { return nil }
        return directory.appendingPathComponent("\(parts[1]).\(parts[2])")
    }

    func manifestData(course: Course, lectures: [Lecture], directory: URL) throws -> Data {
        let courseFiles = Dictionary(uniqueKeysWithValues: Course.fileKinds.map { ($0, course.fileName($0, in: directory)) })
        let records: [[String: Any]] = lectures.map { lecture in
            let files = Dictionary(uniqueKeysWithValues: Lecture.fileKinds.map { ($0, lecture.fileName($0, in: directory)) })
            let parts: [[String: Any]] = lecture.mediaParts.map { part in
                ["id": part.id.uuidString,
                 "files": Dictionary(uniqueKeysWithValues: MediaPart.fileKinds.map { ($0, part.fileName($0)) })]
            }
            return ["id": lecture.id.uuidString, "name": lecture.name, "files": files, "parts": parts]
        }
        return try JSONSerialization.data(withJSONObject: [
            "version": 1, "course": ["id": course.id.uuidString, "name": course.name, "files": courseFiles], "lectures": records
        ], options: [.prettyPrinted, .sortedKeys])
    }

    func load() {
        do { try LibraryFileTransaction.recover(journalURL: renameJournalURL) }
        catch {
            storageRecoveryError = error
            NSLog("Recap preserved an unfinished rename: %@", error.localizedDescription)
            return
        }
        let coursesURL = root.appendingPathComponent("courses.json")
        if FileManager.default.fileExists(atPath: coursesURL.path) {
            do { courses = try JSONDecoder().decode([Course].self, from: Data(contentsOf: coursesURL)) }
            catch {
                storageRecoveryError = error
                NSLog("Recap preserved unreadable course metadata: %@", error.localizedDescription)
                return
            }
        }
        for course in courses {
            guard storageRecoveryError == nil else { break }
            let file = course.directoryURL(in: root).appendingPathComponent("lectures.json")
            do {
                let decoded = FileManager.default.fileExists(atPath: file.path)
                    ? try JSONDecoder().decode([Lecture].self, from: Data(contentsOf: file)) : []
                lecturesByCourse[course.id] = decoded
                try synchronizeStorage(for: course, lectures: decoded)
            } catch {
                NSLog("Recap kept the existing course storage at %@: %@", file.path, error.localizedDescription)
            }
        }
    }

    @discardableResult
    func persistCourses() -> Bool {
        guard (try? checkStorageRecovery()) != nil else { return false }
        do {
            try JSONEncoder().encode(courses).write(to: root.appendingPathComponent("courses.json"), options: .atomic)
            return true
        } catch {
            NSLog("Recap could not save course metadata: %@", error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func persistLectures(of course: Course) -> Bool {
        do {
            try synchronizeStorage(for: storedCourse(course), lectures: lectures(in: course))
            return true
        } catch {
            NSLog("Recap could not save lecture metadata: %@", error.localizedDescription)
            return false
        }
    }
}

//
//  Library.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import AnalysisKit
import TranscriptionKit

struct Course: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
}

// One media file of a lecture
struct MediaPart: Codable, Hashable, Identifiable {
    let id: UUID
    var sourceURL: URL?
    var duration: TimeInterval?   // known after transcription; offsets the next part
}

struct Lecture: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var sourceURL: URL?
    var phase: Phase
    var errorMessage: String?
    var parts: [MediaPart]?       // nil = legacy single-media lecture

    enum Phase: String, Codable {
        case pending        // queued, nothing on disk yet
        case downloaded     // media on disk, not transcribed
        case transcribed    // srt/txt/segments ready
        case failed
    }
}

// Owns the on-disk library: Application Support/Recap/ ├─ courses.json └─ <courseID>/ ├─ lectures.json └─ <lectureID>.{mp4,srt,txt,segments.json}
@MainActor
final class LibraryStore {

    static let shared = LibraryStore()

    // onChange belongs to the list that owns it; anyone else watching a record listens for this
    static let didChange = Notification.Name("LibraryStoreDidChange")

    private(set) var courses: [Course] = []
    private var lecturesByCourse: [UUID: [Lecture]] = [:]

    // Fired after any mutation
    var onChange: (() -> Void)?

    let root: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Recap", isDirectory: true)
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

    func courseDirectory(_ course: Course) -> URL {
        let dir = root.appendingPathComponent(course.id.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        installSkillIfNeeded(in: dir)
        return dir
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

    func mediaURL(_ lecture: Lecture, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent("\(lecture.id.uuidString).mp4")
    }

    func partMediaURL(_ part: MediaPart, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent("\(part.id.uuidString).mp4")
    }

    // A part's own transcript on its own timeline, so merging and resuming never re-run whisper on it
    func partTranscriptURL(_ part: MediaPart, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent("\(part.id.uuidString).part.json")
    }

    // Holds the pieces a long transcript is cut into for the CLI channel
    func chunkDirectory(_ lecture: Lecture, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent("\(lecture.id.uuidString).文稿分段", isDirectory: true)
    }

    // Uniform media view: multi-part lectures list their parts
    func mediaParts(of lecture: Lecture, in course: Course) -> [(part: MediaPart, url: URL)] {
        if let parts = lecture.parts, !parts.isEmpty {
            return parts.map { ($0, partMediaURL($0, in: course)) }
        }
        let implicit = MediaPart(id: lecture.id, sourceURL: lecture.sourceURL, duration: nil)
        return [(implicit, mediaURL(lecture, in: course))]
    }

    func productURL(_ lecture: Lecture, in course: Course, ext: String) -> URL {
        courseDirectory(course).appendingPathComponent("\(lecture.id.uuidString).\(ext)")
    }

    // Course-level files (textbook.txt, review.md).
    func courseFileURL(_ course: Course, name: String) -> URL {
        courseDirectory(course).appendingPathComponent(name)
    }

    // MARK: - Mutations

    func addCourse(named name: String) -> Course {
        let course = Course(id: UUID(), name: name)
        courses.append(course)
        persistCourses()
        notify()
        return course
    }

    func updateCourse(_ course: Course) {
        guard let index = courses.firstIndex(where: { $0.id == course.id }) else { return }
        courses[index] = course
        persistCourses()
        notify()
    }

    func deleteCourse(_ course: Course) {
        courses.removeAll { $0.id == course.id }
        lecturesByCourse[course.id] = nil
        try? FileManager.default.removeItem(at: root.appendingPathComponent(course.id.uuidString))
        persistCourses()
        notify()
    }

    func addLecture(named name: String, url: URL?, parts: [MediaPart]? = nil, to course: Course) -> Lecture {
        let lecture = Lecture(id: UUID(), name: name, sourceURL: url, phase: .pending, errorMessage: nil, parts: parts)
        lecturesByCourse[course.id, default: []].append(lecture)
        persistLectures(of: course)
        notify()
        return lecture
    }

    // Folds several lectures into the first one as its parts. A lecture without parts has an
    // implicit part carrying its own id, and part media is named after the part, so the files
    // already sit where the merged lecture will look for them — nothing moves on disk.
    @discardableResult
    func mergeLectures(_ ids: [UUID], in course: Course) -> Lecture? {
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
        lecturesByCourse[course.id] = updated

        var priors: [PriorAnalysis] = []
        for lecture in sources {
            keepTranscriptAsPartCache(of: lecture, in: course)
            if let prior = priorAnalysis(of: lecture, in: course) { priors.append(prior) }
            // Every product describes the pre-merge lecture: its timeline is gone, its findings are kept above
            for ext in ["srt", "txt", "segments.json", "analysis.json", "analysis-raw.txt",
                        "handout.pdf", "handout.tex", "handout.md", "matches.json"] {
                try? FileManager.default.removeItem(at: productURL(lecture, in: course, ext: ext))
            }
        }
        if let data = try? JSONEncoder().encode(priors), !priors.isEmpty {
            try? data.write(to: productURL(merged, in: course, ext: "合并前重点.json"), options: .atomic)
        }
        persistLectures(of: course)
        notify()
        return merged
    }

    // A single-media lecture's transcript already sits on its part's own timeline
    private func keepTranscriptAsPartCache(of lecture: Lecture, in course: Course) {
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

    func updateLecture(_ lecture: Lecture, in course: Course) {
        guard var list = lecturesByCourse[course.id],
              let index = list.firstIndex(where: { $0.id == lecture.id }) else { return }
        list[index] = lecture
        lecturesByCourse[course.id] = list
        persistLectures(of: course)
        notify()
    }

    func deleteLecture(_ lecture: Lecture, in course: Course) {
        lecturesByCourse[course.id]?.removeAll { $0.id == lecture.id }
        for ext in ["mp4", "srt", "txt", "segments.json", "analysis.json", "analysis-raw.txt",
                    "handout.pdf", "handout.tex", "handout.md", "waveform.json", "matches.json",
                    "part.json", "合并前重点.json", "文稿索引.md"] {
            try? FileManager.default.removeItem(at: productURL(lecture, in: course, ext: ext))
        }
        try? FileManager.default.removeItem(at: chunkDirectory(lecture, in: course))
        for (part, url) in mediaParts(of: lecture, in: course) {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: partTranscriptURL(part, in: course))
        }
        persistLectures(of: course)
        notify()
    }

    // MARK: - Persistence

    private func load() {
        let coursesFile = root.appendingPathComponent("courses.json")
        if let data = try? Data(contentsOf: coursesFile),
           let decoded = try? JSONDecoder().decode([Course].self, from: data) {
            courses = decoded
        }
        for course in courses {
            let file = courseDirectory(course).appendingPathComponent("lectures.json")
            if let data = try? Data(contentsOf: file),
               let decoded = try? JSONDecoder().decode([Lecture].self, from: data) {
                lecturesByCourse[course.id] = decoded
            }
        }
    }

    private func persistCourses() {
        let file = root.appendingPathComponent("courses.json")
        try? JSONEncoder().encode(courses).write(to: file, options: .atomic)
    }

    private func persistLectures(of course: Course) {
        let file = courseDirectory(course).appendingPathComponent("lectures.json")
        try? JSONEncoder().encode(lectures(in: course)).write(to: file, options: .atomic)
    }

    private func notify() {
        onChange?()
        NotificationCenter.default.post(name: LibraryStore.didChange, object: nil)
    }
}

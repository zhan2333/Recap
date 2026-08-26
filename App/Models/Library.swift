//
//  Library.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import Foundation

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
                    "handout.pdf", "handout.tex", "handout.md", "waveform.json", "matches.json"] {
            try? FileManager.default.removeItem(at: productURL(lecture, in: course, ext: ext))
        }
        for part in lecture.parts ?? [] {
            try? FileManager.default.removeItem(at: partMediaURL(part, in: course))
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
    }
}

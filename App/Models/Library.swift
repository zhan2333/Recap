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

struct Lecture: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var sourceURL: URL?
    var phase: Phase
    var errorMessage: String?

    enum Phase: String, Codable {
        case pending        // queued, nothing on disk yet
        case downloaded     // media on disk, not transcribed
        case transcribed    // srt/txt/segments ready
        case failed
    }
}

/// Owns the on-disk library:
///
///     Application Support/Recap/
///     ├─ courses.json
///     └─ <courseID>/
///        ├─ lectures.json
///        └─ <lectureID>.{mp4,srt,txt,segments.json}
@MainActor
final class LibraryStore {

    static let shared = LibraryStore()

    private(set) var courses: [Course] = []
    private var lecturesByCourse: [UUID: [Lecture]] = [:]

    /// Fired after any mutation; UI reloads from it.
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func mediaURL(_ lecture: Lecture, in course: Course) -> URL {
        courseDirectory(course).appendingPathComponent("\(lecture.id.uuidString).mp4")
    }

    func productURL(_ lecture: Lecture, in course: Course, ext: String) -> URL {
        courseDirectory(course).appendingPathComponent("\(lecture.id.uuidString).\(ext)")
    }

    // MARK: - Mutations

    func addCourse(named name: String) -> Course {
        let course = Course(id: UUID(), name: name)
        courses.append(course)
        persistCourses()
        notify()
        return course
    }

    func deleteCourse(_ course: Course) {
        courses.removeAll { $0.id == course.id }
        lecturesByCourse[course.id] = nil
        try? FileManager.default.removeItem(at: root.appendingPathComponent(course.id.uuidString))
        persistCourses()
        notify()
    }

    func addLecture(named name: String, url: URL?, to course: Course) -> Lecture {
        let lecture = Lecture(id: UUID(), name: name, sourceURL: url, phase: .pending, errorMessage: nil)
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
        for ext in ["mp4", "srt", "txt", "segments.json"] {
            try? FileManager.default.removeItem(at: productURL(lecture, in: course, ext: ext))
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

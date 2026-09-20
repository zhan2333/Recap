//
//  Library+Files.swift
//  Recap
//
//  Created by Rio on 9/20/26.
//

import Foundation
import PipelineKit

// Protocol files keep fixed names; every course, lecture and media artifact uses its owner's stem.
extension Course {
    static let fileKinds = ["textbook.txt", "review.pdf", "review.tex", "review.md", "教材目录.md", "教材分章"]

    func directoryURL(in root: URL) -> URL {
        let legacy = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let preferred = root.appendingPathComponent(Self.validStem(directoryName, fallback: id.uuidString), isDirectory: true)
        return fileStem == nil ? LibraryFileMigration.resolvedURL(legacy: legacy, preferred: preferred) : preferred
    }

    func fileName(_ kind: String, in directory: URL) -> String {
        guard Self.fileKinds.contains(kind) else { return kind }
        if let fileStem { return "\(Self.validStem(fileStem, fallback: id.uuidString)).\(kind)" }
        guard kind.hasPrefix("review."), let reviewFileStem else { return kind }
        return LibraryFileMigration.resolvedURL(
            legacy: directory.appendingPathComponent(kind),
            preferred: directory.appendingPathComponent("\(Self.validStem(reviewFileStem, fallback: id.uuidString)).\(kind)")
        ).lastPathComponent
    }

    static func validStem(_ value: String?, fallback: String) -> String {
        guard let value, LibraryFileNaming.safeStem(value, fallback: fallback) == value else { return fallback }
        return value
    }
}

extension Lecture {
    static let fileKinds = ["mp4", "mp4.part", "srt", "txt", "segments.json", "analysis.json", "analysis-raw.txt",
                            "handout.pdf", "handout.tex", "handout.md", "waveform.json", "matches.json",
                            "part.json", "合并前重点.json", "文稿索引.md", "文稿分段"]

    func fileName(_ kind: String, in directory: URL) -> String {
        if let fileStem { return "\(Course.validStem(fileStem, fallback: id.uuidString)).\(kind)" }
        let legacy = directory.appendingPathComponent("\(id.uuidString).\(kind)")
        guard kind.hasPrefix("handout."), let handoutFileStem else { return legacy.lastPathComponent }
        return LibraryFileMigration.resolvedURL(
            legacy: legacy,
            preferred: directory.appendingPathComponent("\(Course.validStem(handoutFileStem, fallback: id.uuidString)).\(kind)")
        ).lastPathComponent
    }

    var mediaParts: [MediaPart] {
        if let parts, !parts.isEmpty { return parts }
        return [MediaPart(id: id, sourceURL: sourceURL, duration: nil, fileStem: fileStem)]
    }
}

extension MediaPart {
    static let fileKinds = ["mp4", "mp4.part", "part.json", "waveform.json"]

    func fileName(_ kind: String) -> String {
        "\(Course.validStem(fileStem, fallback: id.uuidString)).\(kind)"
    }
}

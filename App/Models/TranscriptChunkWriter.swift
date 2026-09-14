//
//  TranscriptChunkWriter.swift
//  Recap
//
//  Created by Rio on 2026/9/14.
//

import Foundation
import AnalysisKit
import TranscriptionKit

// A CLI agent runs on this machine, so a long transcript is handed over as files it can
// open one at a time instead of as one wall of text in the prompt.
@MainActor
enum TranscriptChunkWriter {

    static func chunkDirectory(for lecture: Lecture, in course: Course) -> URL {
        LibraryStore.shared.chunkDirectory(lecture, in: course)
    }

    static func indexURL(for lecture: Lecture, in course: Course) -> URL {
        LibraryStore.shared.productURL(lecture, in: course, ext: "文稿索引.md")
    }

    // Returns the index path when the transcript was long enough to split, nil otherwise
    @discardableResult
    static func writeIfNeeded(lecture: Lecture, in course: Course,
                              segments: [TranscriptSegment], maxTokens: Int = 12_000) -> URL? {
        let lines = segments.map { TranscriptLine(start: $0.start, end: $0.end, text: $0.text) }
        let chunks = TranscriptChunker.chunks(from: lines, maxTokens: maxTokens)
        guard chunks.count > 1 else { return nil }

        let directory = chunkDirectory(for: lecture, in: course)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var index = "# \(lecture.name) · 文稿分段\n\n"
        index += "共 \(chunks.count) 段，按时间顺序。需要某段内容时读对应文件，不要一次读完整份文稿。\n\n"
        for chunk in chunks {
            let name = String(format: "part%02d.txt", chunk.index + 1)
            try? chunk.text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
            let opening = chunk.text.prefix(40).replacingOccurrences(of: "\n", with: " ")
            index += "- `\(directory.lastPathComponent)/\(name)` · \(chunk.timeRange) · \(opening)…\n"
        }
        let indexURL = self.indexURL(for: lecture, in: course)
        try? index.write(to: indexURL, atomically: true, encoding: .utf8)
        return indexURL
    }
}

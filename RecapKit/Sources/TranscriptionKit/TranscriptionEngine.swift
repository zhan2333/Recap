//
//  TranscriptionEngine.swift
//  TranscriptionKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// One recognized segment with source timestamps.
public struct TranscriptSegment: Sendable, Codable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

// Full result of transcribing one piece of audio.
public struct Transcript: Sendable, Codable {
    public let segments: [TranscriptSegment]

    public init(segments: [TranscriptSegment]) {
        self.segments = segments
    }

    // Plain text, one segment per line.
    public var text: String {
        segments.map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // SubRip document with millisecond timestamps.
    public var srt: String {
        var out = ""
        for (i, seg) in segments.enumerated() {
            out += "\(i + 1)\n"
            out += "\(Self.srtTimestamp(seg.start)) --> \(Self.srtTimestamp(seg.end))\n"
            out += seg.text.trimmingCharacters(in: .whitespaces) + "\n\n"
        }
        return out
    }

    private static func srtTimestamp(_ t: TimeInterval) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d",
                      ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}

// Progress reported while a transcription is running.
public enum TranscriptionEvent: Sendable {
    case segment(TranscriptSegment)
    case progress(Double) // 0...1
}

// Abstraction over speech-to-text backends (whisper.cpp now
public protocol TranscriptionEngine {
    // - Parameter samples: mono PCM, 16 kHz, Float32 in [-1, 1].
    func transcribe(
        samples: [Float],
        language: String,
        onEvent: (@Sendable (TranscriptionEvent) -> Void)?
    ) throws -> Transcript
}

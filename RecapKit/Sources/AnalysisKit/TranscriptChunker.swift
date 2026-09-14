//
//  TranscriptChunker.swift
//  RecapKit
//
//  Created by Rio on 2026/9/14.
//

import Foundation

// One timed line of a transcript, kept independent of TranscriptionKit
public struct TranscriptLine: Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct TranscriptChunk: Sendable {
    public let index: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public var timeRange: String {
        "\(TranscriptChunker.stamp(start)) – \(TranscriptChunker.stamp(end))"
    }
}

// Splits a long transcript on sentence boundaries so each piece fits a model's budget.
// A whole course merged into one lecture can run past any context window, and both the
// CLI and the API path need the same pieces.
public enum TranscriptChunker {

    // No tokenizer here, so this counts CJK as one token per character and the rest
    // at four characters per token. It only has to be close enough to pick a split.
    public static func estimatedTokens(_ text: String) -> Int {
        let counted = counts(of: text)
        return counted.cjk + counted.other / 4
    }

    // Counts are carried rather than per-line estimates: rounding each line down
    // separately lets a chunk drift past the budget once the lines are joined
    static func counts(of text: String) -> (cjk: Int, other: Int) {
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                cjk += 1
            default:
                other += 1
            }
        }
        return (cjk, other)
    }

    public static func chunks(from lines: [TranscriptLine], maxTokens: Int = 12_000) -> [TranscriptChunk] {
        guard !lines.isEmpty else { return [] }
        var chunks: [TranscriptChunk] = []
        var current: [TranscriptLine] = []
        var cjk = 0
        var other = 0

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            chunks.append(TranscriptChunk(
                index: chunks.count,
                start: first.start,
                end: last.end,
                text: current.map(\.text).joined(separator: "\n")
            ))
            current = []
            cjk = 0
            other = 0
        }

        for line in lines {
            let cost = counts(of: line.text)
            // The joining newline counts too, so the chunk's own estimate stays under budget
            let separator = current.isEmpty ? 0 : 1
            let projected = (cjk + cost.cjk) + (other + cost.other + separator) / 4
            // A single line over budget still goes in alone rather than being cut mid-sentence
            if projected > maxTokens, !current.isEmpty {
                flush()
            }
            if !current.isEmpty { other += 1 }
            current.append(line)
            cjk += cost.cjk
            other += cost.other
        }
        flush()
        return chunks
    }

    public static func stamp(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

//
//  EvidenceMatcher.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// Matches extracted exam-signal quotes back to transcript segments so the Evidence Thread can point at real timestamps
public struct EvidenceMatch: Sendable {
    public let signalIndex: Int      // index into LectureAnalysis.examSignals
    public let segmentIndex: Int     // index into the segment array
    public let start: TimeInterval   // segment start time
}

public enum EvidenceMatcher {

    // - Parameter segments: (start, text) pairs in transcript order.
    public static func match(
        signals: [LectureAnalysis.ExamSignal],
        segments: [(start: TimeInterval, text: String)]
    ) -> [EvidenceMatch] {
        let normalizedSegments = segments.map { normalize($0.text) }
        var matches: [EvidenceMatch] = []
        var claimed = Set<Int>()

        for (signalIndex, signal) in signals.enumerated() {
            let quote = normalize(signal.quote)
            guard quote.count >= 6 else { continue }

            var best: (index: Int, score: Double)?
            for (segmentIndex, segment) in normalizedSegments.enumerated() where !claimed.contains(segmentIndex) {
                guard !segment.isEmpty else { continue }
                let score = overlapScore(quote: quote, segment: segment)
                if score > (best?.score ?? 0) {
                    best = (segmentIndex, score)
                }
            }
            if let best, best.score >= 0.55 {
                claimed.insert(best.index)
                matches.append(EvidenceMatch(
                    signalIndex: signalIndex,
                    segmentIndex: best.index,
                    start: segments[best.index].start
                ))
            }
        }
        return matches.sorted { $0.segmentIndex < $1.segmentIndex }
    }

    // Fraction of the quote covered by its longest common substring with the segment
    static func overlapScore(quote: String, segment: String) -> Double {
        if segment.contains(quote) || quote.contains(segment) { return 1 }
        let a = Array(quote), b = Array(segment)
        var previous = [Int](repeating: 0, count: b.count + 1)
        var longest = 0
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            for j in 1...b.count where a[i - 1] == b[j - 1] {
                current[j] = previous[j - 1] + 1
                longest = max(longest, current[j])
            }
            previous = current
        }
        return Double(longest) / Double(a.count)
    }

    // Strips whitespace and punctuation so tone particles and commas don't break the match.
    static func normalize(_ text: String) -> String {
        String(text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        })
    }
}

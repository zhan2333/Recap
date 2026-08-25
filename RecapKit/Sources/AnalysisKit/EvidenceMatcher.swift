//
//  EvidenceMatcher.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// Matches extracted exam-signal quotes back to transcript segments so the Evidence Thread can point at real timestamps
public struct EvidenceMatch: Codable, Sendable {
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

    // MARK: - Result cache

    // Bump when the scoring changes so stale cached matches recompute
    private static let algorithmVersion = 2

    private struct CacheEnvelope: Codable {
        var version: Int?
        let segmentsModified: TimeInterval
        let analysisModified: TimeInterval
        let matches: [EvidenceMatch]
    }

    // Matching is O(quotes × rows × LCS) — reuse the result while both inputs are unchanged
    public static func cachedMatches(at url: URL, segmentsModified: Date, analysisModified: Date) -> [EvidenceMatch]? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              envelope.version == algorithmVersion,
              abs(envelope.segmentsModified - segmentsModified.timeIntervalSince1970) < 0.001,
              abs(envelope.analysisModified - analysisModified.timeIntervalSince1970) < 0.001
        else { return nil }
        return envelope.matches
    }

    public static func cache(_ matches: [EvidenceMatch], at url: URL, segmentsModified: Date, analysisModified: Date) {
        let envelope = CacheEnvelope(
            version: algorithmVersion,
            segmentsModified: segmentsModified.timeIntervalSince1970,
            analysisModified: analysisModified.timeIntervalSince1970,
            matches: matches
        )
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // Best of two views: longest common substring (exact spans) and bigram overlap
    // (robust to the scattered single-character fixes LLMs apply to whisper output)
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
        let substring = Double(longest) / Double(a.count)
        return max(substring, bigramScore(quote: a, segment: b))
    }

    private static func bigramScore(quote: [Character], segment: [Character]) -> Double {
        guard quote.count >= 2, segment.count >= 2 else { return 0 }
        var quoteBigrams = Set<String>()
        for i in 0..<(quote.count - 1) { quoteBigrams.insert(String(quote[i...i + 1])) }
        var segmentBigrams = Set<String>()
        for i in 0..<(segment.count - 1) { segmentBigrams.insert(String(segment[i...i + 1])) }
        return Double(quoteBigrams.intersection(segmentBigrams).count) / Double(quoteBigrams.count)
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

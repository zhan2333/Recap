//
//  PriorAnalysis.swift
//  Recap
//
//  Created by Rio on 2026/9/15.
//

import Foundation
import AnalysisKit

// Key points a lecture already had before it was merged away, kept as reference for the merged lecture
struct PriorAnalysis: Codable {
    var name: String
    var partIDs: [UUID]
    var start: TimeInterval?
    var end: TimeInterval?
    var analysis: LectureAnalysis

    enum CodingKeys: String, CodingKey {
        case name, start, end, analysis
        case partIDs = "part_ids"
    }

    // Compact rendering, so a prompt carries the findings without the old transcript
    var referenceText: String {
        var lines: [String] = []
        for signal in analysis.examSignals {
            let tags = [signal.strength, signal.qtype, signal.topic]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
            lines.append("- 「\(signal.quote)」" + (tags.isEmpty ? "" : "（\(tags)）"))
        }
        for item in analysis.mustMemorize { lines.append("- 必背：\(item)") }
        for item in analysis.answerApproaches { lines.append("- 答题思路：\(item)") }
        for item in analysis.confusablePoints { lines.append("- 辨析：\(item)") }
        for item in analysis.keyConcepts { lines.append("- 概念：\(item)") }
        for item in analysis.assignments { lines.append("- 作业：\(item)") }
        guard !lines.isEmpty else { return "" }
        return "【\(name)】\n" + lines.joined(separator: "\n")
    }
}

extension Array where Element == PriorAnalysis {

    // Ranges are known only once transcription has placed each part on the merged timeline
    var references: [LectureAnalyzer.AnalysisReference] {
        compactMap { prior in
            let text = prior.referenceText
            guard !text.isEmpty else { return nil }
            guard let start = prior.start, let end = prior.end, end >= start else {
                return .init(text: text)
            }
            return .init(range: start...end, text: text)
        }
    }
}

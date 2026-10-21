//
//  TerminalStudioReference.swift
//  Recap
//
//  Created by Rio on 10/21/26.
//

import Foundation
import CoreGraphics

/// A value captured when the user adds a source, independent of subsequent navigation.
struct TerminalStudioReference: Equatable, Identifiable {
    enum Location: Equatable {
        case pdf(url: URL, pageIndex: Int, selectionBounds: CGRect?)
        case playback(time: TimeInterval, leadIn: Bool)
    }

    let id = UUID()
    let title: String
    let text: String
    let location: Location

    var promptText: String {
        let source: String
        switch location {
        case let .pdf(url, pageIndex, _): source = "\(url.lastPathComponent) · p.\(pageIndex + 1)"
        case let .playback(time, _):
            let seconds = Int(max(0, time.isFinite ? time : 0))
            source = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return "[\(title) · \(source)]\n\(text)"
    }

    /// Source text cannot terminate a bracketed paste or inject terminal control sequences.
    static func sanitizedPaste(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return String(normalized.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || ($0.value >= 0x20 && !(0x7f...0x9f).contains($0.value))
        })
    }
}

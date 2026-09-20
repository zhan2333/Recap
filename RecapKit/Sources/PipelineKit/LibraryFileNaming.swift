//
//  LibraryFileNaming.swift
//  PipelineKit
//
//  Created by Rio on 9/20/26.
//

import Foundation

public enum LibraryFileNaming {

    private static let maximumBytes = 150
    private static let unsafeCharacters = CharacterSet(charactersIn: "/\\:%#{}$&^~\"<>|?*")
        .union(.controlCharacters)
        .subtracting(CharacterSet(charactersIn: "\u{200C}\u{200D}"))
    private static let edgeCharacters = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "."))
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    // Keep readable Unicode names while leaving room for extensions and compiler output.
    public static func safeStem(_ name: String, fallback: String) -> String {
        let stem = shortened(cleaned(name), maximumBytes: maximumBytes)
        guard stem.isEmpty else { return stem }
        let backup = shortened(cleaned(fallback), maximumBytes: maximumBytes)
        return backup.isEmpty ? "Untitled" : backup
    }

    // Every readable name carries its identity; a counter resolves rare short-ID collisions.
    public static func uniqueStem(_ name: String, fallback: String, id: UUID,
                                  occupied: [String]) -> String {
        let base = safeStem(name, fallback: fallback)
        let existing = Set(occupied.map(comparisonKey))
        let identity = String(id.uuidString.prefix(8))
        var counter = 1
        while true {
            let suffix = counter == 1 ? " - \(identity)" : " - \(identity) - \(counter)"
            let prefix = shortened(base, maximumBytes: maximumBytes - suffix.utf8.count)
            let candidate = prefix + suffix
            if !existing.contains(comparisonKey(candidate)) { return candidate }
            counter += 1
        }
    }

    private static func cleaned(_ value: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        let replaced = normalized.map { character -> String in
            character.unicodeScalars.contains(where: unsafeCharacters.contains) ? " " : String(character)
        }.joined()
        return replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: edgeCharacters)
    }

    private static func shortened(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let length = String(character).utf8.count
            guard byteCount + length <= maximumBytes else { break }
            result.append(character)
            byteCount += length
        }
        return result.trimmingCharacters(in: edgeCharacters)
    }

    private static func comparisonKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: comparisonLocale)
            .precomposedStringWithCanonicalMapping
    }
}

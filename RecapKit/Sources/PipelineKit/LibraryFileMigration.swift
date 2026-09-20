//
//  LibraryFileMigration.swift
//  PipelineKit
//
//  Created by Rio on 9/20/26.
//

import Foundation

public enum LibraryFileMigration {

    public enum MigrationError: Error {
        case destinationExists(URL)
    }

    // An unfinished move keeps the existing library usable and can be retried next launch.
    public static func resolvedURL(legacy: URL, preferred: URL) -> URL {
        guard legacy.standardizedFileURL != preferred.standardizedFileURL else { return legacy }
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : preferred
    }

    // Storage names must be persisted before moving, so a restart can resolve either location.
    public static func migrate(legacy: URL, preferred: URL) throws {
        guard legacy.standardizedFileURL != preferred.standardizedFileURL else { return }
        let files = FileManager.default
        guard files.fileExists(atPath: legacy.path) else { return }
        guard !files.fileExists(atPath: preferred.path) else {
            throw MigrationError.destinationExists(preferred)
        }
        try files.moveItem(at: legacy, to: preferred)
    }
}

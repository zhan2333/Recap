//
//  LibraryFileTransaction.swift
//  PipelineKit
//
//  Created by Rio on 9/20/26.
//

import Foundation

public enum LibraryFileTransaction {

    public struct Move {
        public let source: URL
        public let destination: URL

        public init(source: URL, destination: URL) {
            self.source = source
            self.destination = destination
        }
    }

    public struct Write {
        public let url: URL
        public let data: Data
        public let originalURL: URL?

        public init(url: URL, data: Data, originalURL: URL? = nil) {
            self.url = url
            self.data = data
            self.originalURL = originalURL
        }
    }

    public enum TransactionError: LocalizedError {
        case destinationExists(URL)
        case sourceMissing(URL)
        case journalExists(URL)
        case invalidPlan(String)
        case rollbackFailed(operation: String, rollback: String)

        public var errorDescription: String? {
            switch self {
            case .destinationExists(let url): return "The destination already exists: \(url.path)"
            case .sourceMissing(let url): return "The source is missing: \(url.path)"
            case .journalExists(let url): return "Recover the existing file transaction first: \(url.path)"
            case .invalidPlan(let message): return message
            case .rollbackFailed(let operation, let rollback):
                return "\(operation) Recovery is still required: \(rollback)"
            }
        }
    }

    private enum Phase: String, Codable { case forward, rollback, committed }
    private enum MoveState: String, Codable { case pending, moving, complete, rollingBack, restored, skipped }
    private enum WriteState: String, Codable { case pending, writing, complete, restored }

    private struct RecordedMove: Codable {
        let source: URL
        let destination: URL
        let temporary: URL
        let isDirectory: Bool
        var state: MoveState
    }

    private struct RecordedWrite: Codable {
        let url: URL
        let originalURL: URL
        let originalData: Data?
        let data: Data
        var state: WriteState
    }

    private struct Journal: Codable {
        let version: Int
        var phase: Phase
        var moves: [RecordedMove]
        var writes: [RecordedWrite]
    }

    // Move parent directories first, then address children using their new parent path.
    // The journal must sit outside moved directories; missing source products are optional.
    public static func commit(moves: [Move], writes: [Write], journalURL: URL) throws {
        guard !exists(journalURL) else { throw TransactionError.journalExists(journalURL) }
        var journal = try prepare(moves: moves, writes: writes, journalURL: journalURL)
        try save(journal, to: journalURL)
        try complete(&journal, at: journalURL)
    }

    // A crash resumes forward work unless a previous failure already started a rollback.
    public static func recover(journalURL: URL) throws {
        guard exists(journalURL) else { return }
        var journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.version == 1 else { throw TransactionError.invalidPlan("Unsupported file transaction version.") }
        if journal.phase == .rollback {
            try rollback(&journal, at: journalURL)
        } else if journal.phase == .committed {
            try FileManager.default.removeItem(at: journalURL)
        } else {
            try complete(&journal, at: journalURL)
        }
    }

    private static func prepare(moves: [Move], writes: [Write], journalURL: URL) throws -> Journal {
        var recorded: [RecordedMove] = []
        for move in moves {
            let source = move.source.standardizedFileURL
            let destination = move.destination.standardizedFileURL
            guard source != destination else { continue }
            guard source != journalURL.standardizedFileURL, destination != journalURL.standardizedFileURL else {
                throw TransactionError.invalidPlan("A transaction cannot move its journal.")
            }
            let physicalSource = originalLocation(of: source, after: recorded)
            let sourceExists = physicalSource.map(exists) ?? false
            let isDirectory = physicalSource.map(isDirectoryAt) ?? false
            if isDirectory, contains(destination, inside: source) {
                throw TransactionError.invalidPlan("A directory cannot move inside itself: \(source.path)")
            }
            if isDirectory, contains(journalURL, inside: source) || contains(journalURL, inside: destination) {
                throw TransactionError.invalidPlan("The transaction journal must remain outside moved directories.")
            }
            if sourceExists,
               let physicalDestination = originalLocation(of: destination, after: recorded),
               exists(physicalDestination),
               !sameCaseVariant(physicalSource!, physicalDestination) {
                throw TransactionError.destinationExists(destination)
            }
            let temporary = source.deletingLastPathComponent()
                .appendingPathComponent(".recap-move-\(UUID().uuidString)", isDirectory: isDirectory)
            recorded.append(RecordedMove(source: source, destination: destination, temporary: temporary,
                                         isDirectory: isDirectory, state: sourceExists ? .pending : .skipped))
        }

        var writeURLs = Set<URL>()
        let snapshots = try writes.map { write -> RecordedWrite in
            let url = write.url.standardizedFileURL
            guard url != journalURL.standardizedFileURL, writeURLs.insert(url).inserted else {
                throw TransactionError.invalidPlan("Transaction writes must have distinct paths outside the journal.")
            }
            let inferredOriginal = originalLocation(of: url, after: recorded)
            if let supplied = write.originalURL?.standardizedFileURL,
               let inferredOriginal, supplied != inferredOriginal {
                throw TransactionError.invalidPlan("A write's original URL must match its location before the moves.")
            }
            let original = write.originalURL?.standardizedFileURL ?? inferredOriginal
            let backup = try original.flatMap { exists($0) ? try Data(contentsOf: $0) : nil }
            return RecordedWrite(url: url, originalURL: original ?? url, originalData: backup,
                                 data: write.data, state: .pending)
        }
        return Journal(version: 1, phase: .forward, moves: recorded, writes: snapshots)
    }

    private static func complete(_ journal: inout Journal, at journalURL: URL) throws {
        do {
            for index in journal.moves.indices {
                let move = journal.moves[index]
                guard move.state != .complete, move.state != .skipped else { continue }
                journal.moves[index].state = .moving
                try save(journal, to: journalURL)
                try moveForward(move)
                journal.moves[index].state = .complete
                try save(journal, to: journalURL)
            }
            for index in journal.writes.indices {
                guard journal.writes[index].state != .complete else { continue }
                journal.writes[index].state = .writing
                try save(journal, to: journalURL)
                let write = journal.writes[index]
                try write.data.write(to: write.url, options: .atomic)
                journal.writes[index].state = .complete
                try save(journal, to: journalURL)
            }
            journal.phase = .committed
            try save(journal, to: journalURL)
        } catch {
            let operationError = error
            do {
                journal.phase = .rollback
                try save(journal, to: journalURL)
                try rollback(&journal, at: journalURL)
            } catch {
                throw TransactionError.rollbackFailed(operation: operationError.localizedDescription,
                                                      rollback: error.localizedDescription)
            }
            throw operationError
        }
        // All writes are durable. A leftover committed journal is harmless and recoverable.
        try? FileManager.default.removeItem(at: journalURL)
    }

    private static func moveForward(_ move: RecordedMove) throws {
        let files = FileManager.default
        if exists(move.temporary) {
            guard !exists(move.source) else { throw TransactionError.destinationExists(move.source) }
            guard !exists(move.destination) else { throw TransactionError.destinationExists(move.destination) }
            try files.moveItem(at: move.temporary, to: move.destination)
        } else if exists(move.source) {
            if exists(move.destination), !sameCaseVariant(move.source, move.destination) {
                throw TransactionError.destinationExists(move.destination)
            }
            try files.moveItem(at: move.source, to: move.temporary)
            guard !exists(move.destination) else { throw TransactionError.destinationExists(move.destination) }
            try files.moveItem(at: move.temporary, to: move.destination)
        } else if !exists(move.destination) {
            throw TransactionError.sourceMissing(move.source)
        }
    }

    private static func rollback(_ journal: inout Journal, at journalURL: URL) throws {
        // Restore metadata before undoing its parent-directory moves.
        for index in journal.writes.indices.reversed() {
            let write = journal.writes[index]
            guard write.state != .restored else { continue }
            if write.state != .pending {
                if let original = write.originalData {
                    if (try? Data(contentsOf: write.url)) != original {
                        try original.write(to: write.url, options: .atomic)
                    }
                } else if exists(write.url) {
                    try FileManager.default.removeItem(at: write.url)
                }
            }
            journal.writes[index].state = .restored
            try save(journal, to: journalURL)
        }
        for index in journal.moves.indices.reversed() {
            let move = journal.moves[index]
            guard move.state != .restored, move.state != .skipped else { continue }
            if move.state == .pending {
                journal.moves[index].state = .restored
                try save(journal, to: journalURL)
                continue
            }
            journal.moves[index].state = .rollingBack
            try save(journal, to: journalURL)
            try moveBackward(move)
            journal.moves[index].state = .restored
            try save(journal, to: journalURL)
        }
        try FileManager.default.removeItem(at: journalURL)
    }

    private static func moveBackward(_ move: RecordedMove) throws {
        let files = FileManager.default
        if exists(move.temporary) {
            guard !exists(move.source) else { throw TransactionError.destinationExists(move.source) }
            try files.moveItem(at: move.temporary, to: move.source)
        } else if exists(move.destination) {
            if exists(move.source), !sameCaseVariant(move.source, move.destination) {
                throw TransactionError.destinationExists(move.source)
            }
            try files.moveItem(at: move.destination, to: move.temporary)
            guard !exists(move.source) else { throw TransactionError.destinationExists(move.source) }
            try files.moveItem(at: move.temporary, to: move.source)
        } else if !exists(move.source) {
            throw TransactionError.sourceMissing(move.source)
        }
    }

    // Resolve a future path against disk before the preceding moves have happened.
    private static func originalLocation(of url: URL, after moves: [RecordedMove]) -> URL? {
        var result = url.standardizedFileURL
        for move in moves.reversed() where move.state != .skipped {
            if result == move.destination || (move.isDirectory && contains(result, inside: move.destination)) {
                let suffix = String(result.path.dropFirst(move.destination.path.count))
                result = URL(fileURLWithPath: move.source.path + suffix)
            } else if result == move.source || (move.isDirectory && contains(result, inside: move.source)) {
                return nil
            }
        }
        return result
    }

    private static func contains(_ child: URL, inside parent: URL) -> Bool {
        child.standardizedFileURL.path.hasPrefix(parent.standardizedFileURL.path + "/")
    }

    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isDirectoryAt(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeDirectory
    }

    private static func sameCaseVariant(_ first: URL, _ second: URL) -> Bool {
        guard first.path.compare(second.path, options: [.caseInsensitive]) == .orderedSame,
              let firstAttributes = try? FileManager.default.attributesOfItem(atPath: first.path),
              let secondAttributes = try? FileManager.default.attributesOfItem(atPath: second.path),
              let firstInode = firstAttributes[.systemFileNumber] as? NSNumber,
              let secondInode = secondAttributes[.systemFileNumber] as? NSNumber,
              let firstDevice = firstAttributes[.systemNumber] as? NSNumber,
              let secondDevice = secondAttributes[.systemNumber] as? NSNumber else { return false }
        return firstInode == secondInode && firstDevice == secondDevice
    }

    private static func save(_ journal: Journal, to url: URL) throws {
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }
}

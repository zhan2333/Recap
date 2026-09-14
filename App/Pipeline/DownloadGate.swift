//
//  DownloadGate.swift
//  Recap
//
//  Created by Rio on 2026/9/14.
//

import Foundation

// Holds every download in one line: a few run at once, the rest wait their turn.
// Without it a lecture with many parts opens one connection per part, and several
// lectures enqueued together multiply that.
actor DownloadGate {

    static let shared = DownloadGate(limit: 5)

    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    var queueDepth: Int { waiting.count }

    func acquire() async {
        guard running >= limit else {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    // The slot goes straight to whoever is next, so it is never idle while a part waits
    func release() {
        guard waiting.isEmpty else {
            waiting.removeFirst().resume()
            return
        }
        running = max(0, running - 1)
    }
}

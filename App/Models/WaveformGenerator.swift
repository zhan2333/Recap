//
//  WaveformGenerator.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import Foundation
import PipelineKit

// Buckets the lecture audio into a normalized RMS envelope for the Focus Rail
enum WaveformGenerator {

    static let bucketCount = 600

    static func waveform(for mediaURL: URL, cacheURL: URL) async throws -> [Float] {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([Float].self, from: data),
           !cached.isEmpty {
            return cached
        }

        let samples = try await AudioExtractor.pcm16kMono(from: mediaURL)
        let buckets = await Task.detached(priority: .utility) { () -> [Float] in
            guard !samples.isEmpty else { return [] }
            let bucketSize = max(1, samples.count / bucketCount)
            var result: [Float] = []
            result.reserveCapacity(bucketCount)
            var index = 0
            while index < samples.count && result.count < bucketCount {
                let end = min(index + bucketSize, samples.count)
                var sum: Float = 0
                for i in index..<end {
                    sum += samples[i] * samples[i]
                }
                result.append(sqrt(sum / Float(end - index)))
                index = end
            }
            let peak = result.max() ?? 1
            guard peak > 0 else { return result }
            return result.map { min(1, $0 / peak) }
        }.value

        if let data = try? JSONEncoder().encode(buckets) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return buckets
    }
}

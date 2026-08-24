//
//  LectureQueue.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import AVFoundation
import PipelineKit
import TranscriptionKit
import AnalysisKit

/// Drives lectures through download → transcribe. Downloads run in parallel;
/// transcriptions are chained strictly serially (one Metal context at a time).
@MainActor
final class LectureQueue {

    static let shared = LectureQueue()

    /// Transient per-lecture state; coarse phases persist in LibraryStore.
    enum Activity {
        case downloading(Double)
        case waitingToTranscribe
        case transcribing(Double)
        case analyzing
    }

    private(set) var activities: [UUID: Activity] = [:]
    var onActivity: ((UUID) -> Void)?

    private var transcribeTail: Task<Void, Never>?
    private lazy var engine: Result<WhisperCppEngine, Error> = {
        Result { try WhisperCppEngine(modelPath: Settings.modelPath) }
    }()

    private init() {}

    func activity(for lectureID: UUID) -> Activity? {
        activities[lectureID]
    }

    func enqueue(_ lecture: Lecture, in course: Course) {
        let store = LibraryStore.shared
        let parts = store.mediaParts(of: lecture, in: course)
        guard parts.contains(where: { $0.part.sourceURL != nil }) else { return }

        Task {
            do {
                setActivity(.downloading(0), for: lecture.id)
                var partProgress = [Int: Double]()
                let lectureID = lecture.id
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (index, entry) in parts.enumerated() {
                        guard let sourceURL = entry.part.sourceURL else { continue }
                        let destination = entry.url
                        let total = parts.count
                        group.addTask {
                            try await Downloader().download(
                                .init(url: sourceURL, referer: "https://look.tongji.edu.cn/"),
                                to: destination
                            ) { progress in
                                Task { @MainActor in
                                    partProgress[index] = progress
                                    let aggregate = partProgress.values.reduce(0, +) / Double(total)
                                    LectureQueue.shared.setActivity(.downloading(aggregate), for: lectureID)
                                }
                            }
                        }
                    }
                    try await group.waitForAll()
                }
                self.mark(lecture, in: course) { $0.phase = .downloaded }

                setActivity(.waitingToTranscribe, for: lecture.id)
                await self.chainTranscription(of: lecture, in: course)
            } catch {
                self.fail(lecture, in: course, error: error)
            }
        }
    }

    /// Re-runs transcription for an already-downloaded lecture.
    func retranscribe(_ lecture: Lecture, in course: Course) {
        let store = LibraryStore.shared
        let parts = store.mediaParts(of: lecture, in: course)
        guard parts.contains(where: { FileManager.default.fileExists(atPath: $0.url.path) }) else { return }
        setActivity(.waitingToTranscribe, for: lecture.id)
        Task { await chainTranscription(of: lecture, in: course) }
    }

    private func chainTranscription(of lecture: Lecture, in course: Course) async {
        let previous = transcribeTail
        let task = Task {
            await previous?.value
            await self.runTranscription(of: lecture, in: course)
        }
        transcribeTail = task
        await task.value
    }

    /// Transcribes every part in order and concatenates onto one global
    /// timeline — downstream products stay single-lecture.
    private func runTranscription(of lecture: Lecture, in course: Course) async {
        let store = LibraryStore.shared
        let token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled,
                      .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Transcribing lecture"
        )
        defer { ProcessInfo.processInfo.endActivity(token) }

        do {
            setActivity(.transcribing(0), for: lecture.id)
            let parts = store.mediaParts(of: lecture, in: course)
                .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            let engine = try self.engine.get()
            let lectureID = lecture.id
            let partCount = parts.count

            var allSegments: [TranscriptSegment] = []
            var updatedParts: [MediaPart] = []
            var offset: TimeInterval = 0

            for (index, entry) in parts.enumerated() {
                let samples = try await AudioExtractor.pcm16kMono(from: entry.url)
                let assetDuration = try? await AVURLAsset(url: entry.url).load(.duration).seconds
                let transcript = try await Self.transcribeOffMain(engine: engine, samples: samples) { [weak self] progress in
                    Task { @MainActor in
                        self?.setActivity(.transcribing((Double(index) + progress) / Double(partCount)), for: lectureID)
                    }
                }
                let currentOffset = offset
                allSegments += transcript.segments.map {
                    TranscriptSegment(start: $0.start + currentOffset, end: $0.end + currentOffset, text: $0.text)
                }
                let partDuration: TimeInterval
                if let assetDuration, assetDuration.isFinite, assetDuration > 0 {
                    partDuration = assetDuration
                } else {
                    partDuration = transcript.segments.last?.end ?? 0
                }
                var updated = entry.part
                updated.duration = partDuration
                updatedParts.append(updated)
                offset += partDuration
            }

            let merged = Transcript(segments: allSegments)
            try merged.srt.write(to: store.productURL(lecture, in: course, ext: "srt"), atomically: true, encoding: .utf8)
            try merged.text.write(to: store.productURL(lecture, in: course, ext: "txt"), atomically: true, encoding: .utf8)
            try JSONEncoder().encode(merged.segments)
                .write(to: store.productURL(lecture, in: course, ext: "segments.json"), options: .atomic)

            mark(lecture, in: course) {
                if $0.parts != nil { $0.parts = updatedParts }
                $0.phase = .transcribed
                $0.errorMessage = nil
            }
            setActivity(nil, for: lecture.id)
            // Auto-extract key points; fire-and-forget so the transcription
            // chain moves on to the next lecture immediately.
            Task { await self.autoExtract(of: lecture, in: course) }
        } catch {
            fail(lecture, in: course, error: error)
        }
    }

    /// Runs key-point extraction right after a transcription lands. Skips
    /// silently when the LLM endpoint isn't configured; a failure leaves the
    /// lecture transcribed so the user can retry from the detail view.
    private func autoExtract(of lecture: Lecture, in course: Course) async {
        guard let config = Settings.chatConfig else { return }
        let store = LibraryStore.shared
        let analysisURL = store.productURL(lecture, in: course, ext: "analysis.json")
        guard !FileManager.default.fileExists(atPath: analysisURL.path),
              let transcript = try? String(contentsOf: store.productURL(lecture, in: course, ext: "txt"), encoding: .utf8),
              !transcript.isEmpty else { return }

        setActivity(.analyzing, for: lecture.id)
        do {
            let result = try await LectureAnalyzer().extract(transcript: transcript, client: ChatClient(config: config))
            try JSONEncoder().encode(result).write(to: analysisURL, options: .atomic)
            mark(lecture, in: course) { $0.errorMessage = nil }
        } catch {
            if let analyzeError = error as? LectureAnalyzer.AnalyzeError {
                let rawURL = store.productURL(lecture, in: course, ext: "analysis-raw.txt")
                try? analyzeError.rawResponse.write(to: rawURL, atomically: true, encoding: .utf8)
            }
            NSLog("Recap auto-extract failed for %@: %@", lecture.name, error.localizedDescription)
        }
        setActivity(nil, for: lecture.id)
    }

    /// whisper_full blocks; run it on a dedicated thread, not the cooperative pool.
    private static func transcribeOffMain(
        engine: WhisperCppEngine,
        samples: [Float],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcript {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                do {
                    let transcript = try engine.transcribe(samples: samples, language: "zh") { event in
                        if case .progress(let value) = event { onProgress(value) }
                    }
                    continuation.resume(returning: transcript)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - State plumbing

    private func setActivity(_ activity: Activity?, for lectureID: UUID) {
        activities[lectureID] = activity
        onActivity?(lectureID)
    }

    private func mark(_ lecture: Lecture, in course: Course, _ mutate: (inout Lecture) -> Void) {
        guard var current = LibraryStore.shared.lecture(id: lecture.id, in: course) else { return }
        mutate(&current)
        LibraryStore.shared.updateLecture(current, in: course)
    }

    private func fail(_ lecture: Lecture, in course: Course, error: Error) {
        setActivity(nil, for: lecture.id)
        mark(lecture, in: course) {
            $0.phase = .failed
            $0.errorMessage = error.localizedDescription
        }
    }
}

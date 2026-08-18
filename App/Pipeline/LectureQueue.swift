//
//  LectureQueue.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import PipelineKit
import TranscriptionKit

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
        guard let sourceURL = lecture.sourceURL else { return }
        let store = LibraryStore.shared
        let mediaURL = store.mediaURL(lecture, in: course)

        Task {
            do {
                setActivity(.downloading(0), for: lecture.id)
                try await Downloader().download(
                    .init(url: sourceURL, referer: "https://look.tongji.edu.cn/"),
                    to: mediaURL
                ) { [weak self] progress in
                    Task { @MainActor in self?.setActivity(.downloading(progress), for: lecture.id) }
                }
                self.mark(lecture, in: course) { $0.phase = .downloaded }

                setActivity(.waitingToTranscribe, for: lecture.id)
                await self.chainTranscription(of: lecture, in: course, mediaURL: mediaURL)
            } catch {
                self.fail(lecture, in: course, error: error)
            }
        }
    }

    /// Re-runs transcription for an already-downloaded lecture.
    func retranscribe(_ lecture: Lecture, in course: Course) {
        let mediaURL = LibraryStore.shared.mediaURL(lecture, in: course)
        guard FileManager.default.fileExists(atPath: mediaURL.path) else { return }
        setActivity(.waitingToTranscribe, for: lecture.id)
        Task { await chainTranscription(of: lecture, in: course, mediaURL: mediaURL) }
    }

    private func chainTranscription(of lecture: Lecture, in course: Course, mediaURL: URL) async {
        let previous = transcribeTail
        let task = Task {
            await previous?.value
            await self.runTranscription(of: lecture, in: course, mediaURL: mediaURL)
        }
        transcribeTail = task
        await task.value
    }

    private func runTranscription(of lecture: Lecture, in course: Course, mediaURL: URL) async {
        let store = LibraryStore.shared
        let token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Transcribing lecture"
        )
        defer { ProcessInfo.processInfo.endActivity(token) }

        do {
            setActivity(.transcribing(0), for: lecture.id)
            let samples = try await AudioExtractor.pcm16kMono(from: mediaURL)

            let engine = try self.engine.get()
            let lectureID = lecture.id
            let transcript = try await Self.transcribeOffMain(engine: engine, samples: samples) { [weak self] progress in
                Task { @MainActor in self?.setActivity(.transcribing(progress), for: lectureID) }
            }

            try transcript.srt.write(to: store.productURL(lecture, in: course, ext: "srt"), atomically: true, encoding: .utf8)
            try transcript.text.write(to: store.productURL(lecture, in: course, ext: "txt"), atomically: true, encoding: .utf8)
            try JSONEncoder().encode(transcript.segments)
                .write(to: store.productURL(lecture, in: course, ext: "segments.json"), options: .atomic)

            mark(lecture, in: course) {
                $0.phase = .transcribed
                $0.errorMessage = nil
            }
            setActivity(nil, for: lecture.id)
        } catch {
            fail(lecture, in: course, error: error)
        }
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

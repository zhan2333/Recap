//
//  LectureQueue.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit
import AVFoundation
import UserNotifications
import PipelineKit
import TranscriptionKit
import AnalysisKit

// Drives lectures through download → transcribe
@MainActor
final class LectureQueue {

    static let shared = LectureQueue()

    // Posted after every activity change; userInfo carries "lectureID"
    static let activityDidChange = Notification.Name("LectureQueueActivityDidChange")

    // Transient per-lecture state
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
        guard let course = store.course(id: course.id),
              let lecture = store.lecture(id: lecture.id, in: course) else { return }
        let parts = store.mediaParts(of: lecture, in: course)
        // Parts already on disk are never re-downloaded (their token may have expired)
        let pending = parts.filter {
            $0.part.sourceURL != nil && !FileManager.default.fileExists(atPath: $0.url.path)
        }
        let onDisk = parts.contains { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !pending.isEmpty || onDisk else { return }

        let storageToken = store.beginUsingStorage(in: course)
        Task {
            defer { store.endUsingStorage(storageToken) }
            do {
                if !pending.isEmpty {
                    setActivity(.downloading(0), for: lecture.id)
                    var partProgress = [Int: Double]()
                    let lectureID = lecture.id
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (index, entry) in pending.enumerated() {
                            guard let sourceURL = entry.part.sourceURL else { continue }
                            let destination = entry.url
                            let total = pending.count
                            group.addTask {
                                // Waits for a slot, so many parts queue instead of all opening at once
                                await DownloadGate.shared.acquire()
                                defer { Task { await DownloadGate.shared.release() } }
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
                    // Fresh media invalidates whatever that part transcribed to last time
                    for entry in pending {
                        try? FileManager.default.removeItem(at: store.partTranscriptURL(entry.part, in: course))
                    }
                }
                self.mark(lecture, in: course) { $0.phase = .downloaded }

                setActivity(.waitingToTranscribe, for: lecture.id)
                await self.chainTranscription(of: lecture, in: course)
            } catch {
                self.fail(lecture, in: course, error: error)
            }
        }
    }

    // Re-runs transcription for an already-downloaded lecture. Parts already transcribed are
    // reused, so merging and resuming cost nothing; freshPass throws that away and runs whisper again.
    func retranscribe(_ lecture: Lecture, in course: Course, freshPass: Bool = false) {
        let store = LibraryStore.shared
        guard let course = store.course(id: course.id),
              let lecture = store.lecture(id: lecture.id, in: course) else { return }
        let parts = store.mediaParts(of: lecture, in: course)
        guard parts.contains(where: { FileManager.default.fileExists(atPath: $0.url.path) }) else { return }
        if freshPass {
            for entry in parts {
                try? FileManager.default.removeItem(at: store.partTranscriptURL(entry.part, in: course))
            }
        }
        setActivity(.waitingToTranscribe, for: lecture.id)
        let storageToken = store.beginUsingStorage(in: course)
        Task {
            defer { store.endUsingStorage(storageToken) }
            await chainTranscription(of: lecture, in: course, reuseParts: !freshPass)
        }
    }

    private func chainTranscription(of lecture: Lecture, in course: Course, reuseParts: Bool = true) async {
        let previous = transcribeTail
        let task = Task {
            await previous?.value
            await self.runTranscription(of: lecture, in: course, reuseParts: reuseParts)
        }
        transcribeTail = task
        await task.value
    }

    // Transcribes every part in order and concatenates onto one global timeline
    private func runTranscription(of lecture: Lecture, in course: Course, reuseParts: Bool = true) async {
        let store = LibraryStore.shared
        guard let course = store.course(id: course.id),
              let lecture = store.lecture(id: lecture.id, in: course) else {
            setActivity(nil, for: lecture.id)
            return
        }
        let token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled,
                      .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Transcribing lecture"
        )
        defer { ProcessInfo.processInfo.endActivity(token) }

        do {
            setActivity(.transcribing(0), for: lecture.id)
            if reuseParts { store.backfillPartCaches(of: lecture, in: course) }
            let parts = store.mediaParts(of: lecture, in: course)
                .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            let lectureID = lecture.id
            let partCount = parts.count

            var allSegments: [TranscriptSegment] = []
            var updatedParts: [MediaPart] = []
            var spans: [UUID: ClosedRange<TimeInterval>] = [:]
            var offset: TimeInterval = 0

            for (index, entry) in parts.enumerated() {
                let cacheURL = store.partTranscriptURL(entry.part, in: course)
                let assetDuration = try? await AVURLAsset(url: entry.url).load(.duration).seconds
                let transcript: Transcript
                if reuseParts, let cached = Self.cachedTranscript(at: cacheURL) {
                    transcript = cached
                    setActivity(.transcribing(Double(index + 1) / Double(partCount)), for: lectureID)
                } else {
                    // The model is only needed for parts that still have to be heard
                    let engine = try self.engine.get()
                    let samples = try await AudioExtractor.pcm16kMono(from: entry.url)
                    transcript = try await Self.transcribeOffMain(engine: engine, samples: samples) { [weak self] progress in
                        Task { @MainActor in
                            self?.setActivity(.transcribing((Double(index) + progress) / Double(partCount)), for: lectureID)
                        }
                    }
                    try? JSONEncoder().encode(transcript.segments).write(to: cacheURL, options: .atomic)
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
                spans[entry.part.id] = currentOffset...(currentOffset + partDuration)
                offset += partDuration
            }
            store.stampPriorSpans(spans, of: lecture, in: course)

            let merged = Transcript(segments: allSegments)
            try merged.srt.write(to: store.productURL(lecture, in: course, ext: "srt"), atomically: true, encoding: .utf8)
            try merged.text.write(to: store.productURL(lecture, in: course, ext: "txt"), atomically: true, encoding: .utf8)
            try JSONEncoder().encode(merged.segments)
                .write(to: store.productURL(lecture, in: course, ext: "segments.json"), options: .atomic)

            mark(lecture, in: course) {
                // Merge by id so parts whose media was missing are not dropped
                if var existing = $0.parts {
                    for updated in updatedParts {
                        if let i = existing.firstIndex(where: { $0.id == updated.id }) { existing[i] = updated }
                    }
                    $0.parts = existing
                }
                $0.phase = .transcribed
                $0.errorMessage = nil
            }
            setActivity(nil, for: lecture.id)
            notifyIfBackgrounded(lecture)
            // Auto-extract key points; fire-and-forget so the chain moves on immediately
            Task { await self.autoExtract(of: lecture, in: course) }
        } catch {
            fail(lecture, in: course, error: error)
        }
    }

    // Runs key-point extraction right after a transcription lands
    private func autoExtract(of lecture: Lecture, in course: Course) async {
        guard let config = Settings.chatConfig else { return }
        let store = LibraryStore.shared
        guard let course = store.course(id: course.id),
              let lecture = store.lecture(id: lecture.id, in: course) else { return }
        let storageToken = store.beginUsingStorage(in: course)
        defer { store.endUsingStorage(storageToken) }
        let analysisURL = store.productURL(lecture, in: course, ext: "analysis.json")
        let segmentsURL = store.productURL(lecture, in: course, ext: "segments.json")
        // Re-extract when the transcript is newer than the analysis (e.g. after appending a part)
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let analysisFresh = FileManager.default.fileExists(atPath: analysisURL.path)
            && modified(analysisURL) >= modified(segmentsURL)
        guard !analysisFresh,
              let transcript = try? String(contentsOf: store.productURL(lecture, in: course, ext: "txt"), encoding: .utf8),
              !transcript.isEmpty else { return }
        // A transcript past the budget is a job worth choosing a channel for, not one to start silently
        guard TranscriptChunker.estimatedTokens(transcript) <= 12_000 else { return }

        setActivity(.analyzing, for: lecture.id)
        do {
            let references = store.priorAnalyses(of: lecture, in: course).references
            let result = try await LectureAnalyzer().extract(
                transcript: transcript, client: ChatClient(config: config), references: references
            )
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

    // whisper_full blocks
    private static func cachedTranscript(at url: URL) -> Transcript? {
        guard let data = try? Data(contentsOf: url),
              let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data),
              !segments.isEmpty else { return nil }
        return Transcript(segments: segments)
    }

    private static func transcribeOffMain(
        engine: WhisperCppEngine,
        samples: [Float],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcript {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                do {
                    let transcript = try engine.transcribe(samples: samples, language: Settings.transcriptionLanguage) { event in
                        if case .progress(let value) = event { onProgress(value) }
                    }
                    continuation.resume(returning: transcript)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Banner only when the app is in the background — foreground users see the list update live
    private func notifyIfBackgrounded(_ lecture: Lecture) {
        guard UIApplication.shared.applicationState != .active else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = lecture.name
            content.body = String(localized: "转写完成，可以提取重点了")
            content.userInfo = ["lectureID": lecture.id.uuidString]
            center.add(UNNotificationRequest(identifier: lecture.id.uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - State plumbing

    private func setActivity(_ activity: Activity?, for lectureID: UUID) {
        activities[lectureID] = activity
        onActivity?(lectureID)
        NotificationCenter.default.post(
            name: Self.activityDidChange, object: nil, userInfo: ["lectureID": lectureID]
        )
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

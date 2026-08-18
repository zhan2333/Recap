//
//  WhisperCppEngine.swift
//  TranscriptionKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import whisper

/// whisper.cpp (GGML, Metal) backend. Mirrors the proven CLI setup:
/// `whisper-cli -l zh -mc 0` — language pinned, context carry-over disabled
/// to avoid repetition loops on long lecture audio.
public final class WhisperCppEngine: TranscriptionEngine {

    public enum EngineError: Error, LocalizedError {
        case modelLoadFailed(URL)
        case inferenceFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let url): "Failed to load whisper model at \(url.path)"
            case .inferenceFailed(let code): "whisper_full failed with code \(code)"
            }
        }
    }

    private let ctx: OpaquePointer

    public init(modelPath: URL) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        // Do NOT enable flash_attn: the v1.9.2 prebuilt xcframework returns
        // zero segments with it on (verified by bisection, 2026-08-19).
        guard let ctx = whisper_init_from_file_with_params(modelPath.path, cparams) else {
            throw EngineError.modelLoadFailed(modelPath)
        }
        self.ctx = ctx
    }

    deinit {
        whisper_free(ctx)
    }

    public func transcribe(
        samples: [Float],
        language: String = "zh",
        onEvent: (@Sendable (TranscriptionEvent) -> Void)? = nil
    ) throws -> Transcript {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.no_context = true      // never condition on previous text (repetition-loop guard)
        params.n_max_text_ctx = 0
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))

        let box = CallbackBox(onEvent: onEvent)
        if onEvent != nil {
            let boxPtr = Unmanaged.passUnretained(box).toOpaque()
            params.new_segment_callback = newSegmentCallback
            params.new_segment_callback_user_data = boxPtr
            params.progress_callback = progressCallback
            params.progress_callback_user_data = boxPtr
        }

        let status = language.withCString { lang -> Int32 in
            params.language = lang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        withExtendedLifetime(box) {}
        guard status == 0 else { throw EngineError.inferenceFailed(status) }

        let count = whisper_full_n_segments(ctx)
        let segments = (0..<count).map { makeSegment(ctx, $0) }
        return Transcript(segments: segments)
    }
}

/// Bridges Swift closures through whisper's C function-pointer callbacks.
private final class CallbackBox {
    let onEvent: (@Sendable (TranscriptionEvent) -> Void)?

    init(onEvent: (@Sendable (TranscriptionEvent) -> Void)?) {
        self.onEvent = onEvent
    }
}

private func makeSegment(_ ctx: OpaquePointer, _ i: Int32) -> TranscriptSegment {
    let text = whisper_full_get_segment_text(ctx, i).map { String(cString: $0) } ?? ""
    // whisper timestamps are in centiseconds
    let t0 = Double(whisper_full_get_segment_t0(ctx, i)) / 100.0
    let t1 = Double(whisper_full_get_segment_t1(ctx, i)) / 100.0
    return TranscriptSegment(start: t0, end: t1, text: text)
}

private func newSegmentCallback(
    ctx: OpaquePointer?,
    state: OpaquePointer?,
    nNew: Int32,
    userData: UnsafeMutableRawPointer?
) {
    guard let ctx, let userData else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
    let total = whisper_full_n_segments(ctx)
    for i in (total - nNew)..<total {
        box.onEvent?(.segment(makeSegment(ctx, i)))
    }
}

private func progressCallback(
    ctx: OpaquePointer?,
    state: OpaquePointer?,
    progress: Int32,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
    box.onEvent?(.progress(Double(progress) / 100.0))
}

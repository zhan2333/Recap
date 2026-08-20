//
//  AudioExtractor.swift
//  PipelineKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import AVFoundation

/// Decodes the audio track of any AVFoundation-readable media into
/// 16 kHz mono Float32 PCM — the exact input whisper expects.
/// Replaces `ffmpeg -vn -ac 1 -ar 16000` without touching disk.
///
/// AVAssetReader only decompresses (Float32, source rate/channels kept);
/// resampling + downmix go through AVAudioConverter. Asking the reader's
/// outputSettings for 16 kHz directly yields silently corrupted samples
/// for some sources (e.g. 22.05 kHz big-endian AIFC), so don't.
public enum AudioExtractor {

    public enum ExtractError: Error, LocalizedError {
        case noAudioTrack(URL)
        case readerFailed(Error?)
        case conversionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noAudioTrack(let url): "No audio track in \(url.lastPathComponent)"
            case .readerFailed(let error): "Asset reading failed: \(error.map(String.init(describing:)) ?? "unknown")"
            case .conversionFailed(let reason): "Audio conversion failed: \(reason)"
            }
        }
    }

    public static let targetSampleRate = 16_000.0

    public static func pcm16kMono(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExtractError.noAudioTrack(url)
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw ExtractError.conversionFailed("cannot create target format")
        }

        var converter: AVAudioConverter?
        var samples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let chunk = Self.pcmBuffer(from: sampleBuffer) else { continue }
            if converter == nil {
                converter = AVAudioConverter(from: chunk.format, to: dstFormat)
                guard converter != nil else {
                    throw ExtractError.conversionFailed("no converter \(chunk.format) → 16k mono")
                }
            }
            try Self.convert(chunk, with: converter!, isLast: false, into: &samples)
        }

        guard reader.status == .completed else {
            throw ExtractError.readerFailed(reader.error)
        }
        if let converter {
            try Self.convert(nil, with: converter, isLast: true, into: &samples)
        }
        return samples
    }

    /// Wraps one CMSampleBuffer's interleaved Float32 data in an AVAudioPCMBuffer.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let format = AVAudioFormat(streamDescription: asbd),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames

        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        let dst = buffer.mutableAudioBufferList.pointee.mBuffers
        guard let mData = dst.mData, byteCount <= Int(dst.mDataByteSize) else { return nil }
        guard CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: mData) == noErr else {
            return nil
        }
        return buffer
    }

    /// Streams one chunk (or the end-of-stream flush) through the converter.
    private static func convert(
        _ chunk: AVAudioPCMBuffer?,
        with converter: AVAudioConverter,
        isLast: Bool,
        into samples: inout [Float]
    ) throws {
        var chunkServed = false
        while true {
            let capacity = AVAudioFrameCount(8192)
            guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
                throw ExtractError.conversionFailed("cannot allocate output buffer")
            }
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
                if !chunkServed, let chunk {
                    chunkServed = true
                    inputStatus.pointee = .haveData
                    return chunk
                }
                inputStatus.pointee = isLast ? .endOfStream : .noDataNow
                return nil
            }

            if out.frameLength > 0, let data = out.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
            }

            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream:
                return
            case .error:
                throw ExtractError.conversionFailed(conversionError?.localizedDescription ?? "unknown")
            @unknown default:
                return
            }
        }
    }
}

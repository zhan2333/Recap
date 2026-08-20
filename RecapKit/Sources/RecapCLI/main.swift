//
//  main.swift
//  RecapCLI
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import PipelineKit
import TranscriptionKit
import AnalysisKit

let defaultModelPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("whisper-models/ggml-large-v3-turbo.bin")

func usage() -> Never {
    print("""
    Usage: recap <command>

      transcribe <media-file>   Transcribe a local audio/video file to .srt + .txt
      run <url>                 Download (cloud-classroom headers) then transcribe
      sample                    Self-check: synthesize a Mandarin clip via `say`, transcribe it
      textbook <pdf>            Extract textbook text (text layer + Vision OCR fallback)

    Options:
      --model <path>   whisper model (default: \(defaultModelPath.path))
      --out <dir>      output directory (default: alongside input / cwd)
      --lang <code>    language (default: zh)
      --referer <url>  Referer header for `run` (default: https://look.tongji.edu.cn/)
    """)
    exit(64)
}

struct Options {
    var model = defaultModelPath
    var out: URL?
    var lang = "zh"
    var referer = "https://look.tongji.edu.cn/"
    var positional: [String] = []

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--model": model = URL(fileURLWithPath: args[i + 1]); i += 2
            case "--out": out = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 2
            case "--lang": lang = args[i + 1]; i += 2
            case "--referer": referer = args[i + 1]; i += 2
            default: positional.append(args[i]); i += 1
            }
        }
    }
}

func transcribeFile(_ input: URL, options: Options) async throws {
    let outDir = options.out ?? input.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let baseName = input.deletingPathExtension().lastPathComponent

    FileHandle.standardError.write(Data("Extracting audio…\n".utf8))
    let samples = try await AudioExtractor.pcm16kMono(from: input)
    let duration = Double(samples.count) / 16_000
    FileHandle.standardError.write(Data(String(format: "Audio: %.1f s, loading model…\n", duration).utf8))

    let engine = try WhisperCppEngine(modelPath: options.model)
    let clock = ContinuousClock()
    let start = clock.now
    let transcript = try engine.transcribe(samples: samples, language: options.lang) { event in
        if case .segment(let seg) = event {
            let line = String(format: "[%7.2f → %7.2f] %@\n", seg.start, seg.end, seg.text)
            FileHandle.standardError.write(Data(line.utf8))
        }
    }
    let elapsed = start.duration(to: clock.now)

    let srtURL = outDir.appendingPathComponent(baseName + ".srt")
    let txtURL = outDir.appendingPathComponent(baseName + ".txt")
    try transcript.srt.write(to: srtURL, atomically: true, encoding: .utf8)
    try transcript.text.write(to: txtURL, atomically: true, encoding: .utf8)
    print("Done in \(elapsed). \(transcript.segments.count) segments → \(srtURL.path)")
}

func run() async throws {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else { usage() }
    let command = args.removeFirst()
    let options = Options(args)

    switch command {
    case "transcribe":
        guard let path = options.positional.first else { usage() }
        try await transcribeFile(URL(fileURLWithPath: path), options: options)

    case "run":
        guard let urlString = options.positional.first, let url = URL(string: urlString) else { usage() }
        let outDir = options.out ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let dest = outDir.appendingPathComponent(url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent)
        FileHandle.standardError.write(Data("Downloading \(url.absoluteString.prefix(80))…\n".utf8))
        try await Downloader().download(.init(url: url, referer: options.referer), to: dest) { progress in
            FileHandle.standardError.write(Data(String(format: "\r%3.0f%%", progress * 100).utf8))
        }
        FileHandle.standardError.write(Data("\nDownloaded → \(dest.path)\n".utf8))
        try await transcribeFile(dest, options: options)

    case "textbook":
        guard let path = options.positional.first else { usage() }
        let pdfURL = URL(fileURLWithPath: path)
        let text = try await TextbookImporter.extractText(from: pdfURL) { done, total in
            if done % 20 == 0 || done == total {
                FileHandle.standardError.write(Data("\r\(done)/\(total) pages".utf8))
            }
        }
        let outURL = (options.out ?? pdfURL.deletingLastPathComponent())
            .appendingPathComponent(pdfURL.deletingPathExtension().lastPathComponent + ".txt")
        try text.write(to: outURL, atomically: true, encoding: .utf8)
        print("\n\(text.count) characters → \(outURL.path)")

    case "sample":
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recap-sample")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let aiff = dir.appendingPathComponent("sample.aiff")
        let text = "同学们大家好,今天我们复习期末考试的重点内容。第一,土的压缩性和固结理论必考。第二,请大家记住有效应力原理。"
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Tingting", "-o", aiff.path, text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else {
            print("`say` failed — is the Tingting voice installed?")
            exit(1)
        }
        var opts = options
        opts.out = dir
        try await transcribeFile(aiff, options: opts)
        print("Expected: \(text)")

    default:
        usage()
    }
}

let semaphore = DispatchSemaphore(value: 0)
let task = Task {
    do {
        try await run()
    } catch {
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()

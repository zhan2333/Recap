# Recap

A native Mac study player for lecture recordings: fetch classroom replays, transcribe them locally with whisper, and distill exam-focused review notes with an LLM.

Everything runs on-device except the optional analysis step — no ffmpeg, no Python, no external binaries.

## Architecture

```
Recap.app (Mac Catalyst, UIKit)     — planned
├─ PipelineKit        download (URLSession) + audio decode (AVAssetReader)
├─ TranscriptionKit   TranscriptionEngine protocol + whisper.cpp/Metal backend
└─ AnalysisKit        single-turn LLM analysis (OpenAI-compatible) — planned
```

## CLI (current demo)

```sh
swift run recap sample                 # self-check with a synthesized Mandarin clip
swift run recap transcribe lecture.mp4 # local file → .srt + .txt
swift run recap run "<direct mp4 url>" # download with classroom headers, then transcribe
```

Requirements: macOS 14+, a ggml whisper model (default path `~/whisper-models/ggml-large-v3-turbo.bin`).

## Pipeline lineage

Ports a shell pipeline proven on 100+ lecture transcriptions:

| shell | native |
|---|---|
| `curl` (no proxy, UA + Referer) | `URLSession`, `connectionProxyDictionary = [:]` |
| `ffmpeg -vn -ac 1 -ar 16000` | `AVAssetReader` → Float32 PCM in memory |
| `whisper-cli -l zh -mc 0 -otxt -osrt` | whisper.cpp via SPM, `no_context = true` |

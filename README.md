<p align="center">
  <img src="docs/icon.png" width="128" alt="Recap app icon">
</p>

<h1 align="center">Recap</h1>

<p align="center">
  <b>Follow the source. Return to the lecture.</b><br>
  <i>把一节课，收束成一条复习路径。</i>
</p>

<p align="center">
  English · <a href="README.zh-Hans.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/floonetio/Recap?color=1B3A5C&logo=github&logoColor=white" alt="Release">
  <img src="https://img.shields.io/badge/macOS-14%2B-1B3A5C?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Mac%20Catalyst-UIKit-1B3A5C?logo=swift&logoColor=white" alt="Mac Catalyst">
  <img src="https://img.shields.io/badge/whisper.cpp-on--device-C75B39" alt="whisper.cpp">
</p>

![Recap](docs/hero-en.png)

Course replay → on-device transcript → exam key points → lecture-note PDF, all inside one native Mac app. Transcription runs a whisper model fully offline; only the optional analysis step talks to an LLM endpoint you configure yourself — no ffmpeg, no Python, no external binaries.

## Features

### Course workspace · Evidence Thread

![Course workspace](docs/workspace.png)

- Paste direct links to classroom replays or import local audio/video; whisper transcribes on this device. Batch-paste many links at once, and merge multi-part videos into a single lecture
- **Evidence Thread**: every extracted key point links back to the teacher's exact words in the transcript — takeaways are reading entry points, never posing as something the teacher said
- The key-points page collects must-memorize items, core concepts, solution paths, common mix-ups, and assignments; a course-wide exam review is one click away

### Learning player · Focus Rail

![Learning player](docs/player.png)

- Playback keeps AVKit semantics and presents multi-part lectures part by part; the Focus Rail waveform marks the teacher's exact words as **ranges**, not single points
- Selecting a key point starts 3 seconds before the quote to preserve the lead-in; previous/next stepping crosses parts automatically, and parts auto-advance when one ends

### Terminal Studio

- Run your own CLI inside the course context: installed tools (claude / codex / gemini / grok / kimi) are detected automatically, with the bundled skill, transcript, and key points already attached
- Watch the live terminal output, stop anytime, and open the finished PDF straight from the artifact pane — the command stays here, and so does its artifact

### Lecture notes

- One command produces LaTeX-typeset lecture notes as a PDF (with TikZ diagrams), rendered inside the app with a night mode — `claude "为「第一周」生成讲义"`
- Or pick "Generate with API": your configured endpoint follows the same bundled skill to write the LaTeX, compiled locally into the same PDF

## macOS Integration

- Native Mac Catalyst app built with UIKit — not a web wrapper
- Notarized, Developer ID–signed dmg with a drag-to-install window
- In-place updates: a persistent pill downloads the new release, installs it, and relaunches
- The bundled skill installs under every CLI convention (`.claude/skills`, `.agents/skills`, `AGENTS.md`, `GEMINI.md`) — any agent that enters the course folder picks it up
- Bilingual interface (English / Simplified Chinese) following the system language; reveal-in-Finder throughout

## Requirements

- macOS 14 Sonoma or later, Apple silicon
- A ggml whisper model (~1.5 GB, downloaded in onboarding — or bring your own `.bin`)
- Optional: an OpenAI-compatible endpoint (OpenRouter, a private gateway, or local Ollama) for key-point extraction
- Optional: BasicTeX (`xelatex`) for locally compiled lecture notes; a CLI agent for Terminal Studio

## Installation

1. Download the latest dmg from **[Releases](https://github.com/floonetio/Recap/releases)**
2. Drag Recap into Applications — the dmg is notarized and opens right away
3. Follow onboarding to fetch the whisper model, then create a course and add your first lecture

<p align="center">
  <img src="docs/icon-default.png" width="88" alt="Default icon">
  &nbsp;
  <img src="docs/icon-dark.png" width="88" alt="Dark icon">
  &nbsp;
  <img src="docs/icon-clear-light.png" width="88" alt="Clear light icon">
  &nbsp;
  <img src="docs/icon-clear-dark.png" width="88" alt="Clear dark icon">
</p>

## Architecture

```
Recap.app (Mac Catalyst, UIKit)     — App/ + RecapApp.xcodeproj (xcodegen)
└─ RecapKit/                        — local SPM package
   ├─ PipelineKit        download (URLSession) + audio decode (AVAssetReader)
   ├─ TranscriptionKit   TranscriptionEngine protocol + whisper.cpp/Metal backend
   ├─ AnalysisKit        LLM analysis (OpenAI-compatible), textbook OCR, evidence matching
   └─ recap (CLI)        pipeline demo / verification tool
```

## CLI

```sh
cd RecapKit
swift run recap sample                 # self-check with a synthesized Mandarin clip
swift run recap transcribe lecture.mp4 # local file → .srt + .txt
swift run recap run "<direct mp4 url>" # download with classroom headers, then transcribe
swift run recap textbook book.pdf      # extract textbook text (OCR fallback)
```

Requirements: macOS 14+, a ggml whisper model (default path `~/whisper-models/ggml-large-v3-turbo.bin`).

## Pipeline lineage

Ports a shell pipeline proven on 100+ lecture transcriptions:

| shell | native |
|---|---|
| `curl` (no proxy, UA + Referer) | `URLSession`, `connectionProxyDictionary = [:]` |
| `ffmpeg -vn -ac 1 -ar 16000` | `AVAssetReader` → Float32 PCM in memory |
| `whisper-cli -l zh -mc 0 -otxt -osrt` | whisper.cpp via SPM, `no_context = true` |

## Building

```sh
brew install xcodegen
scripts/fetch-whisper.sh               # vendored binaryTarget (gitignored)
xcodegen generate
open RecapApp.xcodeproj                # scheme: Recap (My Mac / Mac Catalyst)
scripts/package-release.sh             # Release build → dist/Recap-<version>.dmg
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — build setup, architecture notes, coding guidelines, and how AI-assisted contributions work here.

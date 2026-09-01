<p align="center">
  <img src="docs/icon.png" width="128" alt="Recap app icon">
</p>

<h1 align="center">Recap</h1>

<p align="center">
  <b>Follow the source. Return to the lecture.</b><br>
  <i>把一节课，收束成一条复习路径。</i>
</p>

<p align="center">
  <a href="https://recap.rio2333.com/"><b>recap.rio2333.com</b></a>
</p>

<p align="center">
  English · <a href="README.zh-Hans.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/zhan2333/Recap?color=1B3A5C&logo=github&logoColor=white" alt="Release">
  <img src="https://img.shields.io/badge/macOS-14%2B-1B3A5C?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Mac%20Catalyst-UIKit-1B3A5C?logo=swift&logoColor=white" alt="Mac Catalyst">
  <img src="https://img.shields.io/badge/whisper.cpp-on--device-C75B39" alt="whisper.cpp">
  <img src="https://img.shields.io/badge/license-GPL--3.0--only-2F2D29" alt="License: GPL-3.0-only">
</p>

![Recap](docs/hero-en.png)

Course replay → on-device transcript → exam key points → lecture-note PDF, all inside one native Mac app. Transcription runs a whisper model fully offline. Only the step that organises key points needs a model, and it uses whatever endpoint you configure. No ffmpeg, no Python, nothing else to install.

## Features

### Course workspace · Evidence Thread

<p align="center">
  <img src="docs/workspace-en.png" width="49.5%" alt="Course workspace (light)">
  <img src="docs/workspace-en-dark.png" width="49.5%" alt="Course workspace (dark)">
</p>

- Paste direct links to classroom replays or import local audio/video; whisper transcribes on this device. Batch-paste many links at once, and merge multi-part videos into a single lecture
- **Evidence Thread**: every extracted key point links back to where the teacher said it in the transcript. The takeaway is the way in; the words are what count
- The key-points page collects must-memorize items, core concepts, solution paths, common mix-ups, and assignments; a course-wide exam review is one click away

### Learning player · Focus Rail

<p align="center">
  <img src="docs/player-en.png" width="49.5%" alt="Learning player (light)">
  <img src="docs/player-en-dark.png" width="49.5%" alt="Learning player (dark)">
</p>

- Playback keeps AVKit semantics and presents multi-part lectures part by part; the Focus Rail waveform marks the teacher's exact words as **ranges**, not single points
- Selecting a key point starts 3 seconds before the quote to preserve the lead-in; previous/next stepping crosses parts automatically, and parts auto-advance when one ends

### Terminal Studio

<p align="center">
  <img src="docs/studio-en.png" width="49.5%" alt="Terminal Studio (light)">
  <img src="docs/studio-en-dark.png" width="49.5%" alt="Terminal Studio (dark)">
</p>

- Run your own CLI inside the course context: installed tools (claude / codex / gemini / grok / kimi) are detected automatically, with the bundled skill, transcript, and key points already attached
- Terminal output is live and you can stop at any point. Finished files appear in the artifact pane on the right, one click to open

### Lecture notes

- No need to leave the app: run your CLI in Terminal Studio, or pick "Generate with API". Both follow the same bundled skill and end in a LaTeX-typeset PDF with TikZ diagrams, readable in the app with a night mode
- Notes follow the course language: English courses use an English template, Chinese courses the ctex one. You can also just tell a CLI in the course folder: `claude "Generate lecture notes for Week 1"`

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

1. Download the latest dmg from **[recap.rio2333.com](https://recap.rio2333.com/)** or the **[Releases](https://github.com/zhan2333/Recap/releases)** page
2. Drag Recap into Applications. The dmg is notarized, so it opens right away
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

## How it is built

Recap is a native Mac Catalyst app written in UIKit. One trade-off runs through it: do on this machine whatever can be done here, and for the parts that need a model, use the tools you already have rather than building another stack inside the app.

**Use the CLI subscription you already pay for**

Terminal Studio is a real terminal: a login shell on a PTY, opened in the course folder. It detects which agents are installed on your Mac (claude, codex, gemini, grok, kimi) and runs them as you, with the accounts they are already signed into. So if you pay for a Claude or Codex subscription, extracting key points and writing lecture notes run on that subscription, and you don't need a separate API account to reach the good models. If you would rather use an API key, the same jobs run through any OpenAI-compatible endpoint you configure. Both paths follow the same instructions.

**The skill ships with the app, so an agent knows what to do on arrival**

`App/recap-review-skill.md` is both the product spec and the agent's instructions: it says what each file in a course folder is called and what shape it has. It installs itself under four conventions (`.claude/skills`, `.agents/skills`, `AGENTS.md`, `GEMINI.md`), so whichever agent you start in that folder knows what to read and where to write. You don't write prompts for it, and what it produces is what the app already renders.

**A course is a plain folder, not a database**

Media, `segments.json`, `analysis.json`, the LaTeX source and the PDF all sit in one directory. The same course works from the app, from your own terminal, or from a script.

**Transcription stays on this Mac**

whisper.cpp is vendored as the official XCFramework, plus an arm64 Mac Catalyst slice built from the same tag, so a recording is decoded and transcribed in-process. Decoding uses `AVAssetReader`, and resampling to 16 kHz mono is a separate streaming pass: letting the reader convert in one step returns the right frame count with the wrong audio.

**Every key point can go back to the words**

`EvidenceMatcher` matches each point against the transcript, taking the better of a longest-common-substring and a bigram-overlap score and accepting anything above 0.55. That is what lets a key point send the player to the moment it was said, and it is why the skill asks for quotes written close to the spoken words rather than tidied into prose.

**Importing the textbook makes an agent noticeably better**

Speech-to-text mishears the words that matter most: names, formulas, domain terms. Given only a transcript, an agent has no way to tell a mishearing from a real term. Once the textbook is imported, the app extracts its text with page markers, and the skill builds a table of contents, splits the book into one file per chapter, and reads only the chapter a lecture belongs to. With the correct terminology and the surrounding argument at hand, the agent can fix misheard terms, say which page a claim comes from, and follow the book's structure instead of guessing at it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — build setup, architecture notes, coding guidelines, and how AI-assisted contributions work here.

## License

Copyright © 2026 zhan2333. The current Recap source is licensed under the [GNU General Public License v3.0 only](LICENSE). Third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Releases up to and including v2.1.0 were published under the MIT License. The existing MIT grants for those versions remain in effect.

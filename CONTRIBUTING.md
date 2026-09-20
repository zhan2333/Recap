# Contributing to Recap

Thanks for your interest in Recap — a native Mac Catalyst app that turns course replays into transcripts, key points, and lecture-note PDFs.

## Getting Started

Requirements: macOS 14+, Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
scripts/fetch-whisper.sh        # vendors whisper.xcframework (gitignored)
xcodegen generate               # RecapApp.xcodeproj is generated — never edit it by hand
open RecapApp.xcodeproj         # scheme: Recap (My Mac / Mac Catalyst)
```

Command-line build and the pipeline self-check:

```sh
xcodebuild -project RecapApp.xcodeproj -scheme Recap \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -skipPackagePluginValidation build
cd RecapKit && swift run recap sample   # end-to-end smoke test with a synthesized clip
```

`-skipPackagePluginValidation` is needed on the command line because SwiftTerm ships a build plugin; in the Xcode GUI, trust the plugin once when prompted instead.

## Project Structure

```
App/                  UIKit app target (Mac Catalyst)
├─ UI/                view controllers and views (Evidence Thread design system in RecapTheme)
├─ Models/            library store, settings, shell bridge, update checker
├─ Pipeline/          download → transcribe → analyze queue
└─ recap-review-skill.md   the bundled agent skill — also the product contract
RecapKit/             local SPM package
├─ TranscriptionKit   whisper.cpp backend (vendored xcframework)
├─ PipelineKit        downloader + audio decode
├─ AnalysisKit        LLM analysis, evidence matching, handout generation
└─ RecapCLI           `recap` demo/verification tool
Plugin/               macOS glue bundle: PTY subprocess support for Catalyst
scripts/              fetch/build/package scripts
```

## Architecture Notes

- **xcodegen owns the project.** Edit `project.yml`, run `xcodegen generate`. New source files require a regenerate.
- **Catalyst cannot spawn processes.** `Plugin/ShellRunner.swift` is a plain-macOS bundle loaded at runtime; its `@objc` protocol is mirrored byte-for-byte in `App/Models/ShellBridge.swift`. Change both sides together or the cast fails silently.
- **The course folder is a contract.** Every course directory and business artifact uses a readable name with an eight-character ID suffix, even without a collision: `Name - ABCD1234`. `Course.directoryName` / `fileStem`, `Lecture.fileStem`, and `MediaPart.fileStem` record the app-assigned names; a media part uses its owning lecture's name and its own ID suffix. Legacy `reviewFileStem` / `handoutFileStem` fields exist only for migration compatibility. This naming applies to handouts, reviews, transcripts, analyses, indexes, media, download and transcription caches, waveforms, matches, transcript-chunk directories, and textbook artifacts. Ordered leaf names such as `partNN.txt` and `chNN.txt` remain inside their named directories. The protocol metadata `courses.json`, `lectures.json`, `.recap-files.json`, and skill installation paths keep fixed names.
- **Display renames update storage.** The app renames the corresponding directories and artifacts when a course or lecture name changes, then refreshes the manifest after success. The fixed root-level `.recap-rename.json` journal supports recovery and must not be edited by CLI agents. The app rejects renames within a course while that course has a running shell session; end the session before renaming in the app. CLI agents must not rename or migrate these files themselves and must reload paths when starting or resuming a session.
- **The file manifest owns CLI paths.** The app writes version 1 of `.recap-files.json`: `course: {id, name, files}` and `lectures: [{id, name, files, parts}]`. Course file keys include `textbook.txt`, `review.tex`, `review.pdf`, `review.md`, `教材目录.md`, and `教材分章`. Lecture file keys cover all `Lecture.fileKinds`, including media, caches, handouts, and transcript chunks. Each lecture's `parts: [{id, files}]` covers explicit or implicit media parts with `mp4`, `mp4.part`, `part.json`, and `waveform.json` keys. All file values are actual paths relative to the course directory. Resolve lectures and parts by UUID and use those values, including legacy paths retained after a migration failure; never derive paths from display names. A missing required key is a contract gap, not permission to guess a path. Agents must not edit the manifest, `courses.json`, or `lectures.json`, or extend the six-field analysis JSON schema. Only courses without a manifest retain the legacy UUID paths, `review.*`, `textbook.txt`, `教材目录.md`, and `教材分章/`. Keep `App/recap-review-skill.md` synchronized with both sides in the same PR — it installs into every course folder under four fixed CLI conventions (`.claude/skills`, `.agents/skills`, `AGENTS.md`, `GEMINI.md`).
- **Localization is a build artifact.** Source language is zh-Hans; every user-facing string goes through `String(localized:)`. After adding strings, build once and add English values for the new keys in `App/Localizable.xcstrings`.
- **Catalyst UIKit quirks are load-bearing.** Buttons that restyle their configuration at runtime need `preferredBehavioralStyle = .pad`; keep compression-resistance fixes on leaf views, not stack rows.

## Coding Guidelines

- Comments: `//` only (never `///`), one line max, prefer `// MARK: -` for structure, and write them only to explain code — no progress notes or history.
- Every new file starts with the standard `Created by` header.
- Code, identifiers, and comments are English; user-facing strings are Chinese source (localized to English via the String Catalog).
- No new third-party dependencies without prior discussion. The app currently ships with whisper.cpp and SwiftTerm; keep version provenance and notices in `THIRD_PARTY_NOTICES.md` current.
- Verify with a Catalyst build before opening a PR.

## Pull Requests

- Keep PRs small and focused; one concern per PR.
- Commit messages follow `feat:` / `fix:` / `perf:` / `docs:` / `chore:`, written in English, bullets on single lines.
- Confirm the build passes and, when the pipeline is touched, that `swift run recap sample` still succeeds.

## AI-Assisted Contributions

Recap is itself built around agent workflows, and AI-assisted PRs are welcome:

- Disclose the prompts or the agent setup you used in the PR description.
- Point your agent at this file and `App/recap-review-skill.md` first — the skill doubles as the spec for every artifact the app reads.
- Agents must not change the course-folder contract casually; contract changes need the app, the skill, and this document updated together.

## Licensing Contributions

Unless explicitly stated otherwise, contributions intentionally submitted for inclusion in Recap are licensed under GPL-3.0-only, the same terms as the project.

## Releases (maintainers)

`scripts/package-release.sh` builds Release, signs with Developer ID + hardened runtime when the certificate exists, produces the styled installer dmg, notarizes, and staples. Bump `MARKETING_VERSION` in `project.yml` first.

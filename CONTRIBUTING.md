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
- **The course folder is a contract.** File names and JSON shapes under a course directory (`segments.json`, `analysis.json`, `handout.pdf`, …) are shared between the app and the bundled skill. If you change one side, update `App/recap-review-skill.md` in the same PR — it installs into every course folder under four CLI conventions (`.claude/skills`, `.agents/skills`, `AGENTS.md`, `GEMINI.md`).
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

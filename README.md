<p align="center">
  <img src="docs/icon.png" width="128" alt="Recap app icon">
</p>

<h1 align="center">Recap</h1>

<p align="center">
  <b>把一节课，收束成一条复习路径。</b><br>
  <i>Follow the source. Return to the lecture.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/floonetio/Recap?color=1B3A5C" alt="Release">
  <img src="https://img.shields.io/badge/macOS-14%2B-1B3A5C" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Mac%20Catalyst-UIKit-1B3A5C" alt="Mac Catalyst">
  <img src="https://img.shields.io/badge/whisper.cpp-on--device-C75B39" alt="whisper.cpp">
</p>

![Recap](docs/hero.png)

课堂回放 → 本机转写 → 考试重点 → 讲义 PDF，全流程在一个原生 Mac app 里完成。转写全程离线跑 whisper 模型，只有可选的分析步骤走你自己配置的 LLM 接口——没有 ffmpeg，没有 Python，没有外部二进制。

## 课堂工作台 · Evidence Thread

![Course workspace](docs/workspace.png)

- 粘贴云课堂视频直链或导入本地音视频，whisper 在本机离线转写；批量粘贴多条直链一次入队，多段视频可合成一个讲次
- **证据线索**：AI 提取的每条考试重点都连回老师原话所在的文稿位置——结论是阅读入口，不伪装成老师亲口说过的话
- 重点页汇总必背、核心概念、解题方法、易混易错与作业；课程级考试重点一键汇总

## 学习播放器 · Focus Rail

![Learning player](docs/player.png)

- 播放器保持 AVKit 习惯，分段呈现多个视频；Focus Rail 波形轨道用**区间**标出老师原话所在位置
- 点击重点跳到原话前 3 秒，保留老师铺垫；上一/下一重点跨段自动切换视频，段播完自动接续

## 讲义 · claude skill

讲次目录内置 [claude](https://claude.com/claude-code) skill——一条命令生成 LaTeX 排版的本讲讲义 PDF（含 TikZ 示意图），app 内直接阅读，支持夜间模式：

```sh
claude "为「第一周」生成讲义"
```

## 快速开始

1. 从 [Releases](https://github.com/floonetio/Recap/releases) 下载 dmg，拖入「应用程序」；首次打开右键选「打开」（或 `xattr -d com.apple.quarantine /Applications/Recap.app`）
2. 引导页内置终端直接下载 whisper 模型（约 1.5 GB，走 HF 镜像），也可以选择自备的 ggml `.bin`
3. 「设置」里配置任意 OpenAI-compatible 接口（OpenRouter、自建网关或本地 Ollama），用于提取重点
4. 新建课程 → 添加讲次 → 转写完成后提取重点

**系统要求**：macOS 14 Sonoma 及以上，Apple silicon。界面中英双语，跟随系统语言。

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

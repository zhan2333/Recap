<p align="center">
  <img src="docs/icon.png" width="128" alt="Recap app icon">
</p>

<h1 align="center">Recap</h1>

<p align="center">
  <b>把一节课，收束成一条复习路径。</b><br>
  <i>Follow the source. Return to the lecture.</i>
</p>

<p align="center">
  <a href="https://recap.rio2333.com/"><b>recap.rio2333.com</b></a>
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/zhan2333/Recap?color=1B3A5C&logo=github&logoColor=white" alt="Release">
  <img src="https://img.shields.io/badge/macOS-14%2B-1B3A5C?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Mac%20Catalyst-UIKit-1B3A5C?logo=swift&logoColor=white" alt="Mac Catalyst">
  <img src="https://img.shields.io/badge/whisper.cpp-on--device-C75B39" alt="whisper.cpp">
  <img src="https://img.shields.io/badge/license-GPL--3.0--only-2F2D29" alt="License: GPL-3.0-only">
</p>

![Recap](docs/hero.png)

课堂回放 → 本机转写 → 考试重点 → 讲义 PDF，整条流程都在一个原生 Mac app 里跑完。转写用 whisper 模型，全程离线；只有整理重点这一步会用到模型，走你自己配置的接口。不用装 ffmpeg，不用装 Python，也没有额外的外部程序。

## 功能

### 课堂工作台 · Evidence Thread

<p align="center">
  <img src="docs/workspace.png" width="49.5%" alt="课堂工作台 (light)">
  <img src="docs/workspace-dark.png" width="49.5%" alt="课堂工作台 (dark)">
</p>

- 粘贴云课堂视频直链或导入本地音视频，whisper 在本机离线转写；批量粘贴多条直链一次入队，多段视频可合成一个讲次
- **证据线索**：每条提取出来的重点都连着老师原话在文稿里的位置。结论只是入口，作数的是原话
- 重点页汇总必背、核心概念、解题方法、易混易错与作业；课程级考试重点一键汇总

### 学习播放器 · Focus Rail

<p align="center">
  <img src="docs/player.png" width="49.5%" alt="学习播放器 (light)">
  <img src="docs/player-dark.png" width="49.5%" alt="学习播放器 (dark)">
</p>

- 播放器保持 AVKit 习惯，分段呈现多个视频；Focus Rail 波形轨道用**区间**标出老师原话所在位置
- 点击重点跳到原话前 3 秒，保留老师铺垫；上一/下一重点跨段自动切换视频，段播完自动接续

### Terminal Studio

<p align="center">
  <img src="docs/studio.png" width="49.5%" alt="Terminal Studio (light)">
  <img src="docs/studio-dark.png" width="49.5%" alt="Terminal Studio (dark)">
</p>

- 在课程上下文里直接运行你自己的 CLI：自动检测本机已装的工具（claude / codex / gemini / grok / kimi），skill、文稿和重点已自动就位
- 终端输出实时可见，随时可以停；生成好的讲义 PDF 出现在右侧产物区，点一下就能打开

### 讲义

- 不用离开 app：在 Terminal Studio 里跑你的 CLI，或者选「用 API 生成」。两条路用的是同一份内置 skill，产出 LaTeX 排版的讲义 PDF（含 TikZ 示意图），可以直接在 app 里读，支持夜间模式
- 讲义跟着课程语言走：英文课程用英文模板，中文课程用 ctex 模板。也可以在课程目录里直接对 CLI 说 `claude "为「第一周」生成讲义"`

## macOS 集成

- UIKit 编写的原生 Mac Catalyst app，不是网页套壳
- Developer ID 签名并经过公证的 dmg，打开即是拖拽安装界面
- 就地更新：底部常驻 pill 一键下载新版本、安装并自动重启
- 内置 skill 按各家 CLI 的约定同时落盘（`.claude/skills`、`.agents/skills`、`AGENTS.md`、`GEMINI.md`），任何 agent 进入课程目录即可使用
- 界面中英双语，跟随系统语言；各处支持「在访达中显示」

## 系统要求

- macOS 14 Sonoma 及以上，Apple silicon
- 一个 ggml 格式的 whisper 模型（约 1.5 GB，引导页内下载，也可自备 `.bin`）
- 可选：任意 OpenAI-compatible 接口（OpenRouter、自建网关或本地 Ollama），用于提取重点
- 可选：BasicTeX（`xelatex`）用于本机编译讲义；一个 CLI agent 用于 Terminal Studio

## 安装

1. 从 **[recap.rio2333.com](https://recap.rio2333.com/)** 或 **[Releases](https://github.com/zhan2333/Recap/releases)** 下载最新 dmg
2. 把 Recap 拖进「应用程序」。dmg 已经过公证，直接打开就行
3. 跟随引导下载 whisper 模型，然后新建课程、添加第一个讲次

<p align="center">
  <img src="docs/icon-default.png" width="88" alt="Default icon">
  &nbsp;
  <img src="docs/icon-dark.png" width="88" alt="Dark icon">
  &nbsp;
  <img src="docs/icon-clear-light.png" width="88" alt="Clear light icon">
  &nbsp;
  <img src="docs/icon-clear-dark.png" width="88" alt="Clear dark icon">
</p>

## 技术实现

Recap 是用 UIKit 写的原生 Mac Catalyst app。做法上有个一以贯之的取舍：能在本机做的事就在本机做，需要模型的部分交给你已经在用的工具，而不是让 app 自己再攒一套。

**用你已有的 CLI 订阅，不用再买一份 API**

Terminal Studio 是一个真正的终端：一个跑在 PTY 上的登录 shell，起点就在课程目录。它会检测你这台 Mac 上装了哪些 agent（claude、codex、gemini、grok、kimi），然后以你的身份运行，用的是它们已经登录好的账号。所以如果你已经在付 Claude 或 Codex 的订阅，提取重点和生成讲义就跑在这份订阅上，不必为了用上好模型再单独开一个 API 账号。想用 API key 也可以，同样的任务能走你自己配置的 OpenAI-compatible 接口，两条路遵循同一份说明。

**skill 跟着 app 走，agent 进门就知道该做什么**

`App/recap-review-skill.md` 这一份文件同时是产品规格和给 agent 的说明书，写清楚了课程目录里每个文件叫什么、里面是什么结构。它会按四种约定自动装好（`.claude/skills`、`.agents/skills`、`AGENTS.md`、`GEMINI.md`），所以你在课程目录里启动哪个 agent，它都知道该读哪些文件、把结果写到哪。你不用自己写提示词，它写出来的东西 app 也认得，界面上直接能看到。

**课程目录是普通文件夹，不是数据库**

媒体、`segments.json`、`analysis.json`、LaTeX 源码和 PDF 都放在同一个目录里。同一门课，你可以在 app 里用，也可以在自己的终端里用，还可以写脚本处理。

**转写不出这台 Mac**

whisper.cpp 以官方 XCFramework 的形式打包进来，另外从同一个 tag 编了一份 arm64 Mac Catalyst 切片，课程录像就在进程内解码和转写。解码用 `AVAssetReader`，重采样到 16 kHz 单声道单独走一遍流式转换：让 reader 一步做完会得到帧数对、内容却是坏的音频。

**每条重点都能回到原话**

`EvidenceMatcher` 把每条重点匹配回文稿，取「最长公共子串」和「二元组重合度」里分数更高的那个，超过 0.55 才算匹配上。点一条重点、播放器能跳到老师说这句话的位置，靠的就是它；skill 里要求引用贴着口语写、不要改成书面语，也是为了让这一步匹配得上。

**导入教材以后，agent 会准不少**

语音转写最容易听错的，恰恰是最要紧的那些词：人名、公式、专业术语。只给一份转写稿，agent 没法判断某个词是听错了还是本来就这么说。导入教材后，app 会带着页码标记把全文提取出来，skill 先整理目录、把教材切成一章一个文件，之后只读这一讲对应的那章。手里同时有正确的术语和上下文，agent 就能纠正听错的词、说明某个结论出自第几页，讲义也能顺着教材的结构写，而不是靠猜。

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)——构建配置、架构要点、代码规范，以及 AI 协作贡献的方式。

## 许可证

Copyright © 2026 zhan2333。Recap 当前源码采用 [GNU General Public License v3.0 only](LICENSE) 许可。第三方组件保留各自的许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

截至 v2.1.0（含）的发行版此前按 MIT License 发布，这些版本已经授予的 MIT 权利继续有效。

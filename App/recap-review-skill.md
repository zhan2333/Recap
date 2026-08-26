---
name: recap-review
description: 在 Recap 课程目录里做课堂复习资料：提取老师强调的重点、分章处理教材、生成讲义与考试重点。当用户要求提取重点、处理教材、生成讲义/考试重点/复习资料时使用。
---

# Recap 课程复习工作法

你在一个 Recap.app 的课程目录里工作。这套方法在 100+ 节课的复习资料生产中验证过，按它执行。产物会被 Recap.app 直接读取，**文件名与 JSON 字段必须严格遵守本文约定**。

## 课程语言 / Course language

课程语言以转写稿（`<讲次UUID>.txt`）的语言为准，所有产物跟随它：

- **中文课程**：产物全部用中文，讲义用下文的 ctexart 模板。
- **英文课程（English courses）**：analysis.json 的 quote/topic/各清单、讲义、考试重点、review.md 全部用英文。`strength` 用 `must-know|key|likely` 代替 `必考|重点|可能考`。讲义 LaTeX 把文档类换成 `\documentclass[11pt]{article}`，去掉 ctex/xeCJK 相关设置，其余配色与 framed 环境规范不变，环境标题用 Key Point / Memorize / Distinguish / In Class，编译命令仍是 xelatex 两遍。文件名约定不变。

## 目录布局（当前目录 = 一门课程）

```
./lectures.json                讲次清单：[{id, name, phase, ...}]，id 是 UUID
./<讲次UUID>.txt               转写稿全文（每段一行）
./<讲次UUID>.segments.json     分段：[{start, end, text}]，秒为单位
./<讲次UUID>.srt               字幕（回溯"老师第几分钟说的"）
./<讲次UUID>.analysis.json     重点提取结果（本 skill 的产物之一）
./<讲次UUID>.handout.md        本讲讲义（产物）
./textbook.txt                 教材全文，含【第N页】页码标记（可能不存在）
./教材目录.md                  教材目录（产物，分章的依据）
./教材分章/chNN.txt            教材分章原文（产物）
./review.md                    课程考试重点总表（产物）
../courses.json                上级目录的课程清单（一般不用动）
```

**开工第一步永远是读 `lectures.json`**，建立 UUID → 讲次名的映射；讲次相关产物一律用 UUID 命名写回，Recap.app 才能识别。

## 转写稿的已知缺陷（处理任何 .txt/.segments.json 前先记住）

- 来自 whisper 语音识别，**专业术语常有同音错字**（如"土力学→图的学"、"固结→固解"、"有效应力原理→有效应力原你"），按上下文和专业知识纠正后再使用；引用老师原话时可在原话后注明校正。
- 静音段会出现"请点赞订阅""优优独播剧场"等幻觉文本，直接忽略。
- 课前等待、点名、学生汇报、闲聊段落不提取、不采用。

## 任务一：提取本讲重点 → `<UUID>.analysis.json`

通读该讲转写稿，输出**严格符合以下结构**的 JSON（字段名一字不差，Recap.app 按此解码）：

```json
{
  "exam_signals": [{"quote": "老师原话", "strength": "必考|重点|可能考", "qtype": "题型(可选)", "topic": "知识点(可选)"}],
  "must_memorize": ["需逐字背诵的规范表述"],
  "answer_approaches": ["老师讲的答题套路，分步骤、含踩点术语"],
  "confusable_points": ["易混易错辨析"],
  "key_concepts": ["核心概念及一句话讲解"],
  "assignments": ["布置的作业/思考题"]
}
```

- `quote` 必须贴近老师原话（纠正错字后的版本），不改写成书面语——Recap.app 靠它把重点匹配回转写稿的时间轴。
- 没有内容的字段给空数组，不要省略字段。

## 任务二：教材处理（存在 textbook.txt 时）

**绝不把整本教材塞进一次阅读。** 流程：

1. 通读教材开头部分，提取完整目录写到 `教材目录.md`（章节标题 + 起始页码【第N页】）。
2. 按目录把 `textbook.txt` 切分成 `教材分章/ch00.txt、ch01.txt…`（保留页码标记）。用脚本或分段读写完成，核对每章首尾不丢段落。
3. 之后任何需要教材的任务，**只读对应章的分章文件**。

## 任务三：生成本讲讲义（LaTeX → PDF）→ `<UUID>.handout.pdf`

输入：该讲 `analysis.json` + 转写稿 + （有教材时）对应章节的分章原文。产物是 **LaTeX 编译的 PDF**，Recap.app 直接展示 `<UUID>.handout.pdf`；同时保留 `<UUID>.handout.tex` 源。

### 结构（对齐验证过的开卷资料风格）

1. `\section{讲次名}` 开头，紧接 `\dw{一句话定位：本讲在课程体系中的位置 + 最核心命题}`
2. `suvlan` 环境：要点速览（enumerate 骨架，复习时可秒定位）
3. 按主题分 `\subsection`，正文讲解帮理解；关键术语 `\tj{加粗}`、核心词 `\kw{标红}`
4. `kaodian` 环境：★老师强调的考点，**保留老师原话**（`\textit{原话}`）并标注题型——这是资料的灵魂，把 exam_signals 的高强度项做足
5. `bibei` 环境：■必背（有教材时逐字取自课本原文，不得杜撰；OCR 错字按规范用语修正）
6. `bianxi` 环境：◆易混易错辨析
7. `ketang` 环境：►答题思路（分步骤、踩点术语，来自 answer_approaches）

硬规则：讲解基于转写稿实际讲过的内容；老师讲得薄或跳过的小节从教材对应章补齐并注明"（老师未展开，据教材补充）"；语言平实直接，不灌水、不杜撰。

### 自足模板（每份讲义一个独立 .tex，用此 preamble）

```latex
\documentclass[11pt]{ctexart}
\usepackage[a4paper,margin=2.2cm]{geometry}
\usepackage{xcolor}
\usepackage{framed}
\usepackage{enumitem}
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning}
\setlist{nosep,leftmargin=2em}
\definecolor{signal}{HTML}{D97757}
\definecolor{signaltext}{HTML}{9A452F}
\definecolor{completec}{HTML}{63715F}
\definecolor{errorc}{HTML}{B84B43}
\definecolor{timec}{HTML}{6B655C}
\newcommand{\kw}[1]{\textcolor{signaltext}{\textbf{#1}}}
\newcommand{\tj}[1]{\textbf{#1}}
\newcommand{\dw}[1]{{\small\color{timec}▸ #1}\par\medskip}
\newenvironment{reviewbox}[2]{%
  \def\FrameCommand{{\color{#1}\vrule width 2.5pt}\hspace{8pt}}%
  \MakeFramed{\advance\hsize-\width\FrameRestore}%
  \noindent{\small\color{#1}\textbf{#2}}\par\smallskip}%
  {\endMakeFramed\medskip}
\newenvironment{kaodian}{\begin{reviewbox}{signal}{★ 考点（老师原话）}}{\end{reviewbox}}
\newenvironment{bibei}{\begin{reviewbox}{completec}{■ 必背}}{\end{reviewbox}}
\newenvironment{bianxi}{\begin{reviewbox}{errorc}{◆ 易混辨析}}{\end{reviewbox}}
\newenvironment{ketang}{\begin{reviewbox}{timec}{► 答题思路}}{\end{reviewbox}}
\newenvironment{suvlan}{\par\noindent{\small\color{timec}\textbf{要点速览}}\par\begin{enumerate}}{\end{enumerate}\medskip}
\begin{document}
% 正文
\end{document}
```

### 示意图（TikZ，本机已装 tikz + pgfplots）

**老师明确说"要会画"的图必须画进讲义**——这类图本身就是考点（作图题）。核心概念有标准示意图的（应力-应变曲线、受力/计算简图、破坏形态、流程关系）也优先配图。规范：

- 简洁线条图：坐标轴 + 曲线 + 特征点，不加装饰。特征点用字母标注（A、B、C…），图下用一两行说明每个点的含义——这正是考试要写的内容。
- 关键曲线/特征点用 `signal` 色标出，其余用黑与 `timec` 灰；坐标轴一律带物理量与符号标注。
- 放 `\begin{center}\begin{tikzpicture}[...]` 中，宽度控制在版面内（约 10–12cm）。
- 考试要求会画的图，在图注前加 ★ 并写明"考试要求会画"。
- TikZ 语法错误是编译失败高发点：一图一图加、先简后繁；某张图连续两次编译失败就简化为更朴素的版本（直线段近似曲线也可接受），不死磕。
- 需要函数曲线时可 `\usepackage{pgfplots}\pgfplotsset{compat=1.18}`（本机已装）；简单示意优先手绘 `\draw` 坐标点连线。

### 编译与注意（本机 BasicTeX 已验证的配方）

- 编译：`/Library/TeX/texbin/xelatex -interaction=nonstopmode <file>.tex` 跑两遍；找不到 xelatex 时试 `which xelatex`，仍没有则告知用户需安装 BasicTeX，改出 `<UUID>.handout.md` 降级产物。
- **BasicTeX 没有 tcolorbox/mdframed/titlesec**——只用上面模板里的包，不要 `\usepackage` 其他包。
- 特殊字符转义：`% → \%`、`& → \&`、`# → \#`、`_ → \_`；引号用中文""''；`$` 慎用。
- ★■◆► 等符号若编译警告缺字形，换成【考点】【必背】等文字标签。
- 编译失败时读 log 定位（通常是转义漏了），修正 .tex 重编，不超过 3 轮。
- 成功后把 PDF 命名为 `<UUID>.handout.pdf` 放课程目录，辅助文件（.aux/.log）删除。

## 任务四：课程考试重点总表 → `review.md`

输入：全部讲次的 `analysis.json`（+ 讲次名映射）。结构固定：

```markdown
# <课程名>考试重点
## 必考清单        （strength=必考，按知识点归并，注明出自哪一讲）
## 重点清单        （strength=重点）
## 必背汇总
## 答题套路汇总
## 易混辨析汇总
## 各讲要点索引    （每讲一行：讲次名 — 一句话核心内容）
```

- 跨讲重复提到的同一知识点合并成一条，标注「多次强调」。
- 保留老师原话的关键表述。

## 汇报口径

每完成一个任务，向用户简报：写了哪个文件、覆盖情况、有什么缺口（如"第九章老师只讲前两节，第三节全部据教材补齐"）。缺口如实说明，不掩饰。

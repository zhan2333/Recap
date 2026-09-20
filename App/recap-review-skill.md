---
name: recap-review
description: 在 Recap 课程目录里提取课堂考点、分章核对教材、生成可导航的 LaTeX/PDF 讲义与课程考试重点。用于提取重点、处理教材、生成或修订复习资料；保持 Recap 的文件名和 JSON 契约。
---

# Recap 课程复习工作法

把课堂原话、教材依据和复习组织分开处理：转写决定老师讲了什么、强调什么；教材用于核对术语和补充说明；讲义负责解释、组织和回查。先提取，再按实际章节整合，最后独立核验内容与 PDF。

## 执行环境与任务边界

- **CLI 文件环境**：先读当前课程的 `lectures.json`，建立 UUID → 讲次名映射；再读隐藏文件 `.recap-files.json`，按 UUID 查找本次输入和输出的实际路径。清点转写、重点、教材和已有讲义后，按下面流程读写文件、编译和验收。没有路径清单的旧版课程按下文旧版约定处理。
- **API 文本环境**：若调用方明确说明不能读写文件，只使用本次传入材料。执行对应任务的内容与排版规范，直接返回调用方要求的 JSON 或完整 `.tex`，不执行文件/子代理/编译步骤。未收到教材、时间戳或全部讲次时，在正文中简明注明资料范围；不得声称读过本地文件、核过教材、编译成功或完成页面检查。不要在 `.tex` 外附汇报文字。
- 只处理用户指定的讲次和范围。课程文件名、课表顺序、已有分析都只是线索，实际章节与考试口径回到来源核实。
- 保留原始媒体、转写、分段缓存、教材和已交付成果；不替 App 合并/删除讲次、不重转写，也不照搬旧脚本的媒体清理步骤。修订先备份旧的 `.tex`/PDF/分析到独立工作目录，候选成果验证后再替换对应文件。
- 长任务在独立工作目录按讲次/章节保存中间稿和完成记录，记录输入版本、已读块、对应教材章、输出和待核项；汇报该目录以便续作。可用子代理时按独立单元分工、分批汇总；没有子代理则逐章执行。共享主模板和最终文件由一个执行者组装，避免并发覆盖。

## 课程语言 / Course language

语言跟随转写稿或用户明确指定的目标语言，引用保留来源原话：

- **中文课程**：中文正文，下文 `ctexart` 模板。
- **英文课程**：英文正文、目录、图表标题、各类提示框及缺口说明；使用 `article`，不加载 ctex/xeCJK。框标题依次为 Key Point / Memorize / Distinguish / Answer Steps，`strength` 使用 `must-know|key|likely`。确需引用其他语言原文时选用覆盖该文字的字体，不把译文称为逐字引用。
- 混合语言保留专业名词，不把翻译后的句子冒充老师原话或教材逐字引用。文件名遵循 App 的路径清单，文件类型后缀和 JSON 字段名不随语言改变。

## 课程目录契约

课程目录和全部课程/讲次业务产物均使用 App 分配的“名称 + 8 位短 ID”存储名，即使没有重名也保留短 ID，例如 `结构力学 - ABCD1234`。课程记录使用 `directoryName` / `fileStem`，讲次和媒体分段使用 `fileStem`；分段存储名采用所属讲次名称和分段自身的短 ID。旧 `reviewFileStem` / `handoutFileStem` 仅供兼容迁移。转写、分析、媒体、缓存、文稿分段目录和教材文件都遵循此规则；分段目录内的 `partNN.txt`、教材分章目录内的 `chNN.txt` 等有序块名保持不变。

修改显示名称时，App 同步重命名相应目录和业务产物，成功后刷新路径清单；名称不再是首次分配后固定。课程中有正在运行的 shell 会话时，App 拒绝该课程范围内的改名，需结束会话后再在 App 改名。CLI 不自行重命名或迁移课程文件；会话恢复或重新开始时重读当前目录和清单。**不要根据课程名或讲次名自行清洗、拼接或猜测路径。**

优先读取 `.recap-files.json`（`version: 1`）：

- `course` 包含 `id`、`name` 和 `files`；`files` 的键为 `textbook.txt`、`review.tex`、`review.pdf`、`review.md`、`教材目录.md`、`教材分章`。
- `lectures` 是 `[{id, name, files, parts}]`；按 `lectures.json` 的讲次 UUID 匹配 `id`，不要用可能重名或已修改的 `name` 匹配。每讲 `files` 的键为 `mp4`、`mp4.part`、`txt`、`srt`、`segments.json`、`analysis.json`、`analysis-raw.txt`、`handout.tex`、`handout.pdf`、`handout.md`、`waveform.json`、`matches.json`、`part.json`、`合并前重点.json`、`文稿索引.md`、`文稿分段`。
- 每讲 `parts` 是 `[{id, files}]`，列出显式分段或单媒体讲次的隐式分段；分段 `files` 的键为 `mp4`、`mp4.part`、`part.json`、`waveform.json`。需要读取分段媒体或缓存时按分段 UUID 匹配，不从讲次文件名推导分段路径。旧版清单可能没有 `parts`，缺少所需路径时报告缺口。
- `files` 的值均为相对当前课程目录的**实际文件名或目录名**，读写时直接使用对应值。例如单讲讲义写入该讲 `files["handout.tex"]` 和 `files["handout.pdf"]`，课程总表写入 `course.files["review.tex"]` 和 `course.files["review.pdf"]`。清单列出路径不表示文件已经存在，仍需检查输入是否可读。
- 迁移未完成时，清单可能仍指向 UUID 文件名或旧的 `review.*`；这些路径仍然有效，以清单为准，不擅自迁移、覆盖同名其他文件或创建另一套名字。清单损坏或缺少所需路径时报告问题，不猜输出位置。
- **仅在没有 `.recap-files.json` 的旧版课程中**，单讲全部沿用 `<UUID>.<后缀>`（含 `<UUID>.handout.tex/pdf/md`），课程总表沿用 `review.tex/pdf/md`，教材沿用 `textbook.txt`、`教材目录.md` 和 `教材分章/`；UUID 取自 `lectures.json`。不为了采用新名称而由 CLI 迁移旧文件。

以下为新版通常使用的布局；其中“存储名”已包含名称和短 ID，实际读写路径仍以清单为准：

~~~text
./.recap-files.json              App 维护的版本 1 路径清单，只读
./lectures.json                  讲次清单：[{id, name, phase, parts?, fileStem?, ...}]
./<讲次存储名>.txt               转写全文，每段一行
./<讲次存储名>.segments.json     [{start, end, text}]，本讲时间轴上的秒数
./<讲次存储名>.srt               字幕与时间戳
./<讲次存储名>.analysis.json     六字段重点提取结果
./<讲次存储名>.analysis-raw.txt  API 分析原始响应，可能不存在
./<讲次存储名>.handout.tex       可独立编译的本讲讲义源码
./<讲次存储名>.handout.pdf       App 主阅读器读取的讲义
./<讲次存储名>.handout.md        无法编译时的降级稿，不替代 PDF
./<讲次存储名>.文稿索引.md       长文稿各块的路径和时间范围
./<讲次存储名>.文稿分段/partNN.txt 文稿块，只有正文，不等于视频分段
./<讲次存储名>.合并前重点.json   合并前分析参考，可能不存在
./<分段存储名>.mp4              分段媒体；单媒体讲次使用隐式分段
./<分段存储名>.mp4.part         下载中的媒体缓存，可能不存在
./<分段存储名>.part.json        分段转写缓存，可能不存在
./<讲次存储名>.waveform.json    波形缓存，分段缓存路径另见 parts
./<讲次存储名>.matches.json     原话匹配缓存，可能不存在
./<课程存储名>.textbook.txt      教材提取文本，可能不存在
./<课程存储名>.教材目录.md       教材章/节和页码对应
./<课程存储名>.教材分章/chNN.txt 保留页码标记的教材分章文本
./<课程存储名>.review.tex        课程考试重点源码
./<课程存储名>.review.pdf        课程考试重点，App 优先读取
./<课程存储名>.review.md         课程总表的降级稿/明确要求的 Markdown
../courses.json                 课程清单，只读
~~~

机器协议元数据 `.recap-files.json`、`courses.json`、`lectures.json`、改名恢复日志 `.recap-rename.json` 及 skill 安装路径（`.claude/skills`、`.agents/skills`、`AGENTS.md`、`GEMINI.md`）保持固定，不加业务名称或短 ID。不得修改这些元数据或恢复日志、移动 skill 安装路径，也不扩展分析 JSON 的六字段 Schema。

讲义最终 `.tex` 应自足：分章草稿可在工作目录用 `\input` 组装，交付前合成正文，避免留下对临时目录的依赖。文档与工作记录引用文件时保留清单给出的实际名称。

当前 App 只为单讲 `files["handout.pdf"]` 提供主阅读器入口；`files["handout.md"]` 仅是可在终端产物区或文件管理器打开的降级文件。课程入口在没有 `course.files["review.pdf"]` 所指 PDF 时才回退到 `course.files["review.md"]`，不能把仍存在的旧 PDF 当成此次新成果。旧版课程使用上述旧版路径。

## 来源、范围与转写纠错

- 只把老师本人讲授、确认的内容作为课堂证据；排除点名、闲聊、学生汇报和静音幻觉（如“请点赞订阅”/“Thanks for watching”）。不把学生观点归给老师。
- 专业术语同音错字据上下文和教材核对。仅修明确的识别错误；数字、公式、否定词或版本差异不确定时保留疑点，不能靠猜补齐。不改写原始转写文件。
- 提取考试形式、题型、范围、允许携带的资料，以及“不考、只需了解、自学、公式会提供”等边界。一般强调不等于必考，教材补充不等于老师划重点。
- 课堂与教材冲突、前后课堂口径不同，记录来源和时间；只有明确更正证据才采用新口径，不因位置靠后就自动覆盖。缺少考核说明时不要假设开卷、闭卷或分值。
- 内容标明属于“老师讲授”“教材补充”还是“整理说明/推导”。教材原文与其释义分开；教师原话与转述分开。
- 精确回听位置从 `.segments.json` / `.srt` 核实。索引中的块时间范围不能充当某句话的时间戳；同名 `partNN.txt` 也不能直接当作第 N 个视频。多段视频用 `lectures.json` 的 parts/duration 核对偏移；资料不足就只标已知讲次或文稿范围，不造时间。

## 任务一：提取本讲重点 → 该讲 `files["analysis.json"]`

1. 通读目标讲次。存在文稿索引时逐块读、逐块提取，保留覆盖清单；完整任务必须覆盖全部块，不能只搜“考试”关键词。没有索引的长文稿按可管理范围分批读，保留跨块句子上下文。
2. 核实实际讲授章节和每章重点，纳入跨讲收尾、补讲和案例；在工作记录中建立“章/节 → 讲次/文稿范围 → 教材范围”的映射，不假设一讲一章或同日文件必为连堂。
3. 有该讲 `files["合并前重点.json"]` 所指文件时，将 `[{name, part_ids, start?, end?, analysis}]` 当参考，回原文校正、补漏、去重。时间范围可能尚未填写；旧分析不能替代全量阅读。
4. 输出严格的六字段 JSON。相同原话可去重；同一主题的不同条件、不同考试口径和不同例子不要合成一句不存在的原话。

~~~json
{
  "exam_signals": [{"quote": "老师原话", "strength": "重点", "qtype": "计算题", "topic": "知识点"}],
  "must_memorize": ["老师要求记忆的表述"],
  "answer_approaches": ["题型：步骤、踩点术语；相关老师原话（有则保留）"],
  "confusable_points": ["易混概念与区分条件"],
  "key_concepts": ["概念及讲解；相关课堂案例与它说明的原理"],
  "assignments": ["作业、思考题或阅读要求"]
}
~~~

- 六个顶层字段都必须是数组，无内容填 `[]`。`exam_signals` 元素是对象，其余五个数组的元素只能是字符串；不要恢复旧工作流的嵌套对象结构。
- `quote` 是连续、贴近口语的原话，供 App 匹配文稿。不要放入时间戳、页码、纠错说明、教材引文或省略拼接出来的句子；说明另写工作记录/讲义。
- `strength` 只用 `必考|重点|可能考`（英文 `must-know|key|likely`）；“必考”必须有明确考试承诺，“可能考”也须有课堂依据。一般教学内容放 `key_concepts`，不要为填满数组推断考试概率。`qtype`/`topic` 不明确时可省略或为 `null`，不猜题型。
- 考试排除项和条件保留在 `key_concepts` 的“考试范围与条件”条目中，英文用 “Exam scope and conditions”，方便后续讲义/总表保留边界。不要把“不考”硬编码为正向考试信号。
- `must_memorize` 先保留老师要求；任务三再据教材核对规范表述。不要把所有教材定义自动标成必背。
- 保留答题方法的题型、步骤、条件及原话依据；课堂案例应说明“案例是什么、用来说明什么”，放入相关 `key_concepts`/`answer_approaches` 字符串。作业题号或截止要求不清楚时注明，不编造。
- 保存前检查 JSON 可解析、数组/元素类型正确、无多余说明文字，再替换正式文件。没有有效教学内容时允许六个空数组，并如实说明原因。

## 任务二：教材处理与章节映射

1. 从 `course.files["textbook.txt"]` 读取教材，存在时先查看书名、版本、目录和正文起始处，将章/节、起止页、来源版本写入 `course.files["教材目录.md"]`，分章保存到 `course.files["教材分章"]` 所指目录；仅无清单旧版课程使用前述旧路径。目录找不到时从正文标题建立暂定结构并注明依据。复用现有分章前核对教材版本和边界。
2. App 的 `【第N页】` 是原 PDF 的第 N 个物理页面，**不是书印页码**。只有实查建立映射后才能同时引用二者；不得沿用别的教材的固定页差。
3. 分章保留页码和章首/章尾；同页跨章保留清楚的分界，不能截断公式、表格或句子。核对覆盖与接缝。之后只读取当前章相关内容，不一次载入全书。
4. 将实际讲授映射回教材；同一章可对应多讲，一讲也可跨章。课件/教材的优先级依老师说明或用户指定，没有依据时不自行定主次。
5. App 通常只保存提取文本，原 PDF 未必在课程目录。OCR 中的公式、上下标、数字和图表不能视为可靠原稿；有明确可用的原 PDF 才回查对应页，无原页则保留待核项，不能声称看过原图。

## 任务三：生成本讲讲义 → 该讲 `files["handout.tex"]` + `files["handout.pdf"]`

### 组织与覆盖

- 输入是该讲分析、完整转写及相关教材分章；分析缺失/过期则先在授权范围内提取，缺少教材时按课堂生成并注明。不得捏造教材原文或页码。
- 开头给出讲次标题、来源与覆盖范围、简短阅读说明、考试边界（有证据才写）。短讲义用紧凑标题区；跨章/长讲义再增加使用说明和速查结构，不固定字数或章节数。
- 先据章节映射列生成单元，明确每单元的课堂输入、教材范围、重点和缺口。长文稿逐章生成并保存草稿，核对所有输入均已归属；分工时只给当前单元所需材料。
- 正文使用带编号的 `\section` / `\subsection`。每章先 `\dw{定位}` 和 `suvlan` 要点速览，再解释主题；保留考点、必背、辨析、答题思路。编号层级随材料规模调整。
- 老师薄讲的内容可用相关教材帮助理解，并标“教材补充”；明确排除的内容不扩充成考试重点。用户要求完整教材讲义时可单列拓展，保持考试边界。
- 需逐字背诵的定义、法条或规范表述采用可核实的教材/指定来源原文，标明来源和版本，解释另写；原文缺失或 OCR 不清时标待核，不能把自己改写的句子当成原文。
- 理工科按“概念/物理意义 → 公式与符号、单位、成立条件 → 使用步骤/课堂例题 → 易错与关联”展开。法条、规范、常数和定义核对版本；课堂案例和已有例题优先，自拟练习明确标注。纯文字学科不强塞公式和图。
- 长讲义按需要加入必背、辨析、题型/答题思路、回听来源索引。索引链接到正文已有条目，避免大段重复；不给短讲义强加固定四附录。

### PDF 导航与排版

- 默认生成**可点击目录和章节书签**，标题及目录页码均可跳转。使用 `hyperref`、`linktoc=all`、`\tableofcontents`，保留带编号书签；用户明确要求不显示目录时仍保留章节书签。
- 正文交叉引用用唯一 `\label` + `\ref` / `\eqref` / `\hyperref`，不要手写目标页码。图表 `\label` 放在 `\caption` 后；无编号标题入目录时用 `\phantomsection` + `\addcontentsline`。
- 书签用可读纯文本；标题含公式时写 `\texorpdfstring{$...$}{纯文本}`，避免格式命令或缺字污染书签。设准确 PDF 标题；作者信息仅用用户提供的值。
- 页眉提供当前章节，页脚保留页码；长标题用短标题，防止页眉重叠。沿用 Recap 配色，不硬套旧资料的学校、作者、开卷说明和课程专属颜色。
- 数学使用 LaTeX 数学命令（`\neq`、`\times` 等）；表格优先 `booktabs`/`tabularx`，跨页长表按需 `longtable`，检查列宽和表头续页。大框、图表和标题要检查分页，不把整章塞进不可分页环境。
- 正文中的 `%`、`&`、`#`、`_`、`$`、`{`、`}` 等 LaTeX 特殊字符须按文本语境转义；数学模式保留运算、下标与分组语义，不对整份源码盲目替换。URL 用 `\url{...}`，原话中的百分数不能因 `%` 注释而丢失。

### 自足模板

下面是中文基线，替换文档标题和正文；英文课程按前述规则换文档类及所有显示文字。按内容可删掉未使用的数学/表格包，但保留导航配置。

~~~latex
\documentclass[11pt]{ctexart}
\usepackage[a4paper,margin=2.2cm]{geometry}
\usepackage{xcolor}
\usepackage{framed}
\usepackage{enumitem}
\usepackage{amsmath,amssymb}
\usepackage{booktabs,array,tabularx,longtable}
\usepackage{fancyhdr}
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning}
\setlist{nosep,leftmargin=2em}
\renewcommand{\arraystretch}{1.15}
\definecolor{signal}{HTML}{D97757}
\definecolor{signaltext}{HTML}{9A452F}
\definecolor{completec}{HTML}{63715F}
\definecolor{errorc}{HTML}{B84B43}
\definecolor{timec}{HTML}{6B655C}
\newcommand{\reviewtitle}{课程复习讲义}
\newcommand{\kw}[1]{\textcolor{signaltext}{\textbf{#1}}}
\newcommand{\tj}[1]{\textbf{#1}}
\newcommand{\dw}[1]{{\small\color{timec}定位：#1}\par\medskip}
\newenvironment{reviewbox}[2]{%
  \def\FrameCommand{{\color{#1}\vrule width 2.5pt}\hspace{8pt}}%
  \MakeFramed{\advance\hsize-\width\FrameRestore}%
  \noindent{\small\color{#1}\textbf{#2}}\par\smallskip}%
  {\endMakeFramed\medskip}
\newenvironment{kaodian}{\begin{reviewbox}{signal}{【考点】老师原话}}{\end{reviewbox}}
\newenvironment{bibei}{\begin{reviewbox}{completec}{【必背】规范表述与来源}}{\end{reviewbox}}
\newenvironment{bianxi}{\begin{reviewbox}{errorc}{【辨析】易混易错}}{\end{reviewbox}}
\newenvironment{ketang}{\begin{reviewbox}{timec}{【答题】思路与步骤}}{\end{reviewbox}}
\newenvironment{suvlan}{\par\noindent{\small\color{timec}\textbf{要点速览}}\par\begin{enumerate}}{\end{enumerate}\medskip}
\setlength{\emergencystretch}{2em}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\color{timec}\nouppercase{\leftmark}}
\fancyfoot[C]{\small\thepage}
\setlength{\headheight}{15pt}
\renewcommand{\sectionmark}[1]{\markboth{#1}{}}
\usepackage[unicode,bookmarksnumbered=true,bookmarksopen=true,linktoc=all]{hyperref}
\hypersetup{colorlinks=true,linkcolor=signaltext,urlcolor=signaltext,citecolor=signaltext,pdftitle={\reviewtitle}}
\pdfstringdefDisableCommands{\def\kw#1{#1}\def\tj#1{#1}}
\setcounter{tocdepth}{2}
\begin{document}
\pdfbookmark[0]{\reviewtitle}{recap-title}
\section*{\reviewtitle}
% 来源、覆盖范围、考试边界与阅读说明
\dw{本讲在课程体系中的位置}
\pdfbookmark[0]{\contentsname}{recap-contents}
\tableofcontents
\clearpage
% 正文：\section{主题}\label{sec:topic}，依次补齐章/节
\end{document}
~~~

如需“计算题步骤”等自定义框标题，可直接用 `\begin{reviewbox}{timec}{标题}`，不另造未定义命令。模板用文字标签避免装饰符号缺字；英文版须同时翻译这些标签、`\reviewtitle`、`\dw` 和 `suvlan`。

### 示意图

- 老师明确要求会画的图必须覆盖；标准受力图、流程图、应力应变曲线等按教学需要补充。自行重画标“整理示意”，不能称课堂截图。
- 有明确考试依据的作图题标“考试要求会画”，说明特征点、曲线/受力关系及作答要点；关键部分用 `signal` 色，其余以黑色和 `timec` 灰为主。
- TikZ 图一图一验；线条、坐标、变量与单位清楚，配图解释特征点和适用条件。图宽不超正文区；含坐标轴的函数图可按需加载 `pgfplots`，引用外部图片才加载 `graphicx`。
- API 只返回单个 `.tex`，不能引用未提供的外部图片、章节子文件或临时路径。图用内联 TikZ，无法可靠绘制时说明缺口。
- 连续两次编译失败可简化绘图实现，不能改变受力关系或曲线含义；无法可靠画出的图保留缺口。图片文件交付时与源码一并保留，使用相对路径。

### 编译与验收（CLI）

1. 先确认 `xelatex`（找不到再查 `/Library/TeX/texbin/xelatex`）及实际用到的包：`kpsewhich hyperref.sty` 等。不要把某台电脑的 BasicTeX 包清单当通用事实。轻量 `framed` 为默认；额外包按需检查，不无条件禁止，也不未经授权全局安装依赖。
2. 在工作目录生成候选 `.tex`/PDF，执行 `xelatex -interaction=nonstopmode -halt-on-error -jobname=<目标PDF去掉.pdf的文件名> <讲义源码文件>` 至少两遍。源码和目标 PDF 分别按清单的对应键取路径；部分迁移时两者可能是不同名称，不能由 `.tex` 名推导 PDF 名。把完整 `-jobname=...` 安全引用为单个参数，源码文件名也安全引用并加 `./` 防止前导短横线被当作选项；目录和文件名可能含空格、中文或单引号，不把未转义名称直接拼进 shell 命令。只有目录/引用仍要求重跑才继续；报错读 log 定位，最多三轮修复，不用旧 PDF 冒充编译成功。
3. **内容核验**：对照输入覆盖表，逐章复核强考试信号、原话、教材原文、数字/公式/定义、适用条件、同音错字、版本差异、跨章重复/矛盾与排除范围。有条件由独立审阅者执行；记录具体位置、依据和修正，未解决项明确保留。
4. **文档核验**：检查页数、文本提取、目录/页码、字体缺字和未解析的 `??`；检查所有链接目标有效、书签名称可读、章节齐全。可用 PDF 工具（如 pypdf/PDFKit）检查链接注释、书签和目标页；仅看到目录文字不算通过。
5. **页面核验**：渲染最终 PDF 检查全部页面，可先总览再放大目录、公式、表格、图和跨页处；解决截断、重叠、缺字、空白异常及影响阅读的溢出。没有渲染/交互工具时明确报告未做的检查，不宣称视觉验收或实点跳转通过。
6. 验证通过才以正确文件名交付 PDF 和可编辑源码；保留原始输入、旧版备份、必要图像和待续工作记录。辅助文件仅清理本次工作目录中的已知 `.aux/.log/.toc/.out` 等，失败时保留 log 便于恢复，不通配删除课程文件。

无法编译时保留 `.tex`、失败信息和 Markdown 降级稿，报告缺少的工具/包；不要覆盖仍可用的旧 PDF，不把“已写源码”报告成“已生成讲义 PDF”。API 只输出源码，以上落盘/编译/验收是否执行由宿主程序决定。

## 任务四：课程考试重点 → `course.files["review.tex"]` + `course.files["review.pdf"]`

CLI 先按 `lectures.json` 清点各讲分析，明确缺失、过期、无法解析的讲次；不能静默跳过后声称覆盖全课程。API 仅汇总实际提供的讲次，并明确覆盖数量/范围。

默认交付与任务三相同的可导航 LaTeX/PDF；用户明确要 Markdown 或无法编译时写 `course.files["review.md"]` 指定文件（旧版课程写 `review.md`）。API 仍只返回源文档，不自行决定或操作文件路径。内容按课程语言组织：

1. 来源与覆盖范围、已确认的考试形式/题型/排除项。
2. 必考清单（仅明确承诺的项目）；重点清单与有依据的可能考内容。
3. 必背汇总、答题步骤与题型、易混辨析。
4. 各讲/章节索引，必要时加入回听定位和作业复习线索。

跨讲同一知识点可归并并标“多次强调”，保留来源讲次和各自条件；强度不能仅由出现次数升级。重讲、补讲和后来更正要合并核对，不能拼接成虚构引文。按章组织长总表，索引指向已有正文；资料范围外的教材补充明确分开，不把总表扩写成未经请求的整本教材。

## 汇报与续作

说明交付路径、实际覆盖的讲次/章节/文稿块、教材使用情况、纠错或来源冲突、缺失材料及待核项。分别报告“源码已写、编译通过、内容核验、链接结构检查、页面检查、交互点击验证”的实际完成情况。中断时提供工作目录、已完成单元和下一步；保留可用旧成果，不用部分草稿冒充全量交付。

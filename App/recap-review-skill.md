---
name: recap-review
description: 在 Recap 课程目录里以视频课堂及其转写为主线把握讲授轻重、提取考点、生成可导航的 LaTeX/PDF 复习讲义；教材辅助校正转写和理解，不主导讲义范围。用于提取重点、教材校核、生成或修订复习资料；保持 Recap 的文件名和 JSON 契约。
---

# Recap 课程复习工作法

**视频为主，教材为辅。** 讲义首先要还原老师传递的轻重：内容范围、复习重心、案例和考试边界由视频中的实际课堂讲授决定，转写稿是整理课堂的工作入口。教材用于校正语音识别错误，以及因转写造成的术语、公式、指代和概念理解偏差；讲义沿课堂主线分清主次、解释重点并提供回查，不将每个知识点平均展开。先理解课堂并识别轻重，再按疑点查教材，最后核验内容与 PDF。

## 执行环境与任务边界

- **CLI 文件环境**：先读当前课程的 `lectures.json`，建立 UUID → 讲次名映射；再读隐藏文件 `.recap-files.json`，按 UUID 查找本次输入和输出的实际路径。清点转写、重点、教材和已有讲义后，按下面流程读写文件、编译和验收。没有路径清单的旧版课程按下文旧版约定处理。
- **API 文本环境**：若调用方明确说明不能读写文件，只使用本次传入材料。执行对应任务的内容与排版规范，直接返回调用方要求的 JSON 或完整 `.tex`，不执行文件/子代理/编译步骤。未收到教材、时间戳或全部讲次时，在正文中简明注明资料范围；不得声称读过本地文件、核过教材、编译成功或完成页面检查。不要在 `.tex` 外附汇报文字。
- 只处理用户指定的讲次和范围。课程文件名、课表顺序、已有分析都只是线索，实际章节与考试口径回到来源核实。
- 保留原始媒体、转写、分段缓存、教材和已交付成果；不替 App 合并/删除讲次、不重转写，也不照搬旧脚本的媒体清理步骤。修订先备份旧的 `.tex`/PDF/分析到独立工作目录，候选成果验证后再替换对应文件。
- 长任务在独立工作目录按讲次/章节保存中间稿和完成记录，记录输入版本、已读块、对应教材章、输出和待核项；汇报该目录以便续作。可用子代理时按独立单元分工、分批汇总；没有子代理则逐章执行。共享主模板和最终文件由一个执行者组装，避免并发覆盖。

## 课程语言 / Course language

以下来源优先级适用于中英文课程，语言切换不改变依据。Lecture first: use the video lecture and its transcript to determine scope, sequence, examples, and exam emphasis. Reflect the instructor’s priorities in the depth and space given to each topic; complete transcript review does not mean equal coverage in the handout. Textbook headings and length are not evidence of lecture importance. Use the textbook only to clarify or correct transcript interpretation; do not add textbook-only topics or silently replace explicit classroom statements.

语言跟随转写稿或用户明确指定的目标语言，引用保留来源原话：

- **中文课程**：中文正文，下文 `ctexart` 模板。
- **英文课程**：英文正文、目录、图表标题、各类提示框及缺口说明；使用 `article`，不加载 ctex/xeCJK。框标题依次为 Key Point / Memorize / Distinguish / Answer Steps，“标记说明”用 Marking Guide；使用与中文相同的命名色和 `\reviewtag`，不生成只有文字、没有实际色彩的英文图例。`strength` 使用 `must-know|key|likely`。确需引用其他语言原文时选用覆盖该文字的字体，不把译文称为逐字引用。
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
- 先读课堂上下文定位疑点，再查相关教材条目；原视频/音频可用时按已核实的时间定位回听，公式或板书必要时回看。未实际回听或回看不得声称已核验视频。教材用于确认同音术语、符号、单位和概念关系，不将书中的完整论述当作视频里被漏识别的内容。
- 仅修有明确依据的识别或理解错误，在工作记录中保留“原转写 → 校正后的理解 → 课堂上下文/回听位置及教材依据”。数字、公式、否定词或版本差异不确定时保留待核项，不能因教材有一个常见答案就补齐。不改写原始媒体、转写文件，也不把校正后的解释伪装为老师逐字原话。
- 提取考试形式、题型、范围、允许携带的资料，以及“不考、只需了解、自学、公式会提供”等边界。一般强调不等于必考，教材补充不等于老师划重点。
- 课堂与教材冲突时，先区分识别错误、适用条件/版本不同和真实观点差异。明确的课堂表述不能仅因教材不同而被判为转写错误；分别记录老师说法、教材说法和待核原因，不静默覆盖，也不将有争议的说法包装为已核实事实。前后课堂口径不同，只有明确更正证据才采用新口径，不因位置靠后就自动覆盖。缺少考核说明时不要假设开卷、闭卷或分值。
- 内容标明属于“老师讲授”“教材校核/释义”还是“整理说明/推导”。教材说明只保留理解当前课堂知识点所必需的部分；课堂未涉及的教材知识点不进入讲义主体，不据教材自行新增考点、必背要求或例题。用户明确要求教材拓展时单列“教材拓展”，保持来源与考试边界。教材原文与其释义分开；教师原话与转述分开。
- 精确回听位置从 `.segments.json` / `.srt` 核实。索引中的块时间范围不能充当某句话的时间戳；同名 `partNN.txt` 也不能直接当作第 N 个视频。多段视频用 `lectures.json` 的 parts/duration 核对偏移；资料不足就只标已知讲次或文稿范围，不造时间。

## 任务一：提取本讲重点 → 该讲 `files["analysis.json"]`

1. 通读目标讲次。存在文稿索引时逐块读、逐块提取，保留覆盖清单；完整任务必须覆盖全部块，不能只搜“考试”关键词。没有索引的长文稿按可管理范围分批读，保留跨块句子上下文。
2. 核实实际讲授章节和每章重点，纳入跨讲收尾、补讲和案例；在工作记录中建立“课堂主题/讲授单元 → 讲次/文稿范围 → 所需教材条目”的映射，不假设一讲一章或同日文件必为连堂。
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
- `must_memorize` 保留老师实际要求；明确指定背诵教材原文时，任务三再核对该版本原文，不用教材定义自动替换课堂记忆要求。不要把所有教材定义标成必背。
- 保留答题方法的题型、步骤、条件及原话依据；课堂案例应说明“案例是什么、用来说明什么”，放入相关 `key_concepts`/`answer_approaches` 字符串。作业题号或截止要求不清楚时注明，不编造。
- 保存前检查 JSON 可解析、数组/元素类型正确、无多余说明文字，再替换正式文件。没有有效教学内容时允许六个空数组，并如实说明原因。

## 任务二：教材辅助校正与章节索引

1. 有需要校正或澄清的课堂内容时，从 `course.files["textbook.txt"]` 查相关条目。已有索引/分章则核对版本后复用；缺少索引且需要反复校核，或用户明确要求处理教材时，查看书名、版本、目录和正文起始处，将章/节、起止页、来源版本写入 `course.files["教材目录.md"]`，分章保存到 `course.files["教材分章"]` 所指目录。仅无清单旧版课程使用前述旧路径；目录找不到时从正文标题建立暂定结构并注明依据。教材索引用于定位校核，不是讲义提纲，也不是生成讲义的必备输入。
2. App 的 `【第N页】` 是原 PDF 的第 N 个物理页面，**不是书印页码**。只有实查建立映射后才能同时引用二者；不得沿用别的教材的固定页差。
3. 分章保留页码和章首/章尾；同页跨章保留清楚的分界，不能截断公式、表格或句子。核对覆盖与接缝。之后只读取当前章相关内容，不一次载入全书。
4. 建立“课堂知识点/疑点 → 对应教材条目”的辅助映射；同一章可对应多讲，一讲也可跨章。讲义依据实际课堂主题和轻重组织，不照教材目录或篇幅补齐未讲章节。老师指定的教材/课件用于确定校核版本，不能因此取代课堂主线；用户明确要求教材型资料时才按该任务另行组织。
5. App 通常只保存提取文本，原 PDF 未必在课程目录。OCR 中的公式、上下标、数字和图表不能视为可靠原稿；有明确可用的原 PDF 才回查对应页，无原页则保留待核项，不能声称看过原图。

## 任务三：生成本讲讲义 → 该讲 `files["handout.tex"]` + `files["handout.pdf"]`

### 组织与覆盖

- 主要输入是完整课堂转写及从中提取的分析，原视频/音频用于必要的回听回看，相关教材条目是可选校核材料。分析缺失/过期则先在授权范围内提取；缺少教材仍按课堂生成，只标出具体待核疑点。仅有教材而没有课堂材料时，不能声称生成了本讲课堂讲义。不得捏造教材原文或页码。
- 开头给出讲次标题、来源与覆盖范围、简短阅读说明、考试边界（有证据才写）。短讲义用紧凑标题区；跨章/长讲义再增加使用说明和速查结构，不固定字数或章节数。
- 先按实际课堂主题列生成单元，以老师传递的重要程度安排阅读层级；保留讲授中的推导、答题步骤和课堂案例。可将重点前置、合并重复主题，但保留课堂来源、条件和必要的知识依赖，不用教材顺序取代课堂逻辑。每单元明确课堂输入、重点、待核疑点及所需教材条目，不能让教材章节映射反过来决定内容。长文稿按课堂单元生成并保存草稿，核对全部课堂输入均已归属；分工时只给当前单元所需材料。
- 正文使用带编号的 `\section` / `\subsection`。每章先 `\dw{定位}` 和 `suvlan` 要点速览，再解释主题；保留考点、必背、辨析、答题思路。编号层级随材料规模调整。
- 老师简略带过的内容，只有理解已讲内容确有需要时才加入精简的“教材校核/释义”；不因讲得少就补成教材详解。明确排除或只需了解的内容按课堂要求处理，不扩充成考试重点；教材未被使用时不为形式完整而强加教材段落。
- 老师明确要求逐字背诵教材/指定来源时，引用可核实的对应原文，标明来源和版本，解释另写；要求记住课堂表述时保留课堂要求，不自动换成教材定义。原文缺失或 OCR 不清时标待核，不能把自己改写的句子当成原文。
- 理工科按“概念/物理意义 → 公式与符号、单位、成立条件 → 使用步骤/课堂例题 → 易错与关联”展开。法条、规范、常数和定义核对版本；课堂案例和已有例题优先，自拟练习明确标注。纯文字学科不强塞公式和图。
- 长讲义按需要加入必背、辨析、题型/答题思路、回听来源索引。索引链接到正文已有条目，避免大段重复；不给短讲义强加固定四附录。

### 课堂轻重与讲义篇幅

- 视频相对教材最有价值的信息是老师如何取舍：先抓明确的掌握/记忆要求，再结合反复解释的难点、推导与例题投入、易错对比和明确的略讲/了解即可/不考说明，判断本讲的复习重心。时长、重复次数只能辅助判断，不能机械换算为重要程度或考试承诺；教材标题、加粗、篇幅和知识的一般重要性都不能代替课堂信号。
- 开头与各单元速览先指出最值得投入时间的内容，并区分重点掌握、理解即可、简要回顾及考试排除项；只使用有课堂依据的层级，不为形式完整强填每一类。重点可前置，并用精简课堂依据解释为什么值得重视。
- 把主要篇幅用于重点的概念关系、推导/答题步骤、典型课堂案例和易错处；次要内容用短段或索引交代，重复口头铺陈可压缩，老师略过的内容不按教材扩写。完整阅读与覆盖核验是为了避免漏掉课堂信号，不要求每段转写都在正文等量复述；不使用固定页数、字数或篇幅比例。
- 区分“教学重点”和“必考承诺”。教师讲得深入、反复解释，可作为重点理解的依据，但不能据此新增“必考/可能考”或“必背”要求；仅从讲解投入归纳的教学重点放入 `key_concepts`，讲义可标“重点理解”，不据此创建 `exam_signals`；老师明确强调“重点掌握”等信号才按任务一输出 `strength=重点`。来源不够时说明轻重尚不能可靠判断，不从教材补造。

### PDF 导航与排版

- 默认生成**可点击目录和章节书签**，标题及目录页码均可跳转。使用 `hyperref`、`linktoc=all`、`\tableofcontents`，保留带编号书签；用户明确要求不显示目录时仍保留章节书签。
- 正文交叉引用用唯一 `\label` + `\ref` / `\eqref` / `\hyperref`，不要手写目标页码。图表 `\label` 放在 `\caption` 后；无编号标题入目录时用 `\phantomsection` + `\addcontentsline`。
- 书签用可读纯文本；标题含公式时写 `\texorpdfstring{$...$}{纯文本}`，避免格式命令或缺字污染书签。设准确 PDF 标题；作者信息仅用用户提供的值。
- 页眉提供当前章节，页脚保留页码；长标题用短标题，防止页眉重叠。沿用 Recap 配色，不硬套旧资料的学校、作者、开卷说明和课程专属颜色。
- 数学使用 LaTeX 数学命令（`\neq`、`\times` 等）；表格优先 `booktabs`/`tabularx`，跨页长表按需 `longtable`，检查列宽和表头续页。大框、图表和标题要检查分页，不把整章塞进不可分页环境。
- 正文中的 `%`、`&`、`#`、`_`、`$`、`{`、`}` 等 LaTeX 特殊字符须按文本语境转义；数学模式保留运算、下标与分组语义，不对整份源码盲目替换。URL 用 `\url{...}`，原话中的百分数不能因 `%` 注释而丢失。

### 标记说明与复习工具

- 使用彩色提示框或强调标记时，在开头加入紧凑的“标记说明 / Marking Guide”，**每个标签直接显示正文对应的实际颜色**。复用同一命名色，不另写相近的 RGB 值，不只写“橙色表示考点”。下面的 `\reviewtag{命名色}{文字标签}` 同时提供彩色字与浅底色；颜色之外保留“考点 / 必背 / 辨析 / 答题”等文字，灰度打印也能区分。只列本讲实际使用的类型。
- `signaltext` 用于考点、关键词与链接的深暖色文字，`signal` 用于图示强调；`completec` 对应必背，`errorc` 对应辨析，`timec` 对应答题步骤和来源。正文大段保持黑色；标记说明里的颜色含义与正文一致，不把“辨析”的颜色同时用于“正确答案”。
- 标记表达内容用途，不自动赋予考试强度。“考点”仍需课堂依据，“必背”仍需老师要求；明确写出“不考”“只需了解”“公式会提供”等条件，不能靠颜色代替这些边界。
- 长讲义可提供一页公式/概念速查表，列“公式或概念、条件、单位或易错处、正文引用”，用 `\eqref` / `\hyperref` 指向推导，避免把推导复制一遍。成组易混点用同维度对照表；例题按“已知与目标 → 适用条件 → 分步推导 → 单位/边界检查”组织。自测题仅在内容需要时加入，答案用链接回查，不凭空增加考试预测。

### 公式、表格与分页技巧

- 连等推导用 `align` / `align*`，一条长公式用 `equation` 内的 `aligned` 或 `split`，分段定义用 `cases`；在等号/运算关系处换行，不把整条公式缩成小字。只给正文会引用的公式编号，`\label` 放在相应公式环境内；用 `\text{...}` 表示数学中的说明、`\mathrm{...}` 表示单位，例如 `\sigma=F/A\quad[\mathrm{MPa}]`，并在邻近正文定义符号和成立条件。
- 对照表优先 `tabularx` 的 `X` 列自动换行，可用 `>{\raggedright\arraybackslash}X` 避免窄列英文过度拉伸；用 `\linewidth` 而非固定页宽，让表格适应当前正文区。文本行用 `booktabs` 分隔，不依赖密集竖线。长表用 `longtable` 的 `\endfirsthead` / `\endhead` 重复表头，置于正文，不放入 `table` 浮动体或提示框；宽表先拆分列/主题，不用整体缩放掩盖不可读字号。
- 提示框保持可跨页的 `framed` 实现，框内不要放浮动体；图表与来源说明尽量相邻。不要用 `minipage` / `samepage` 包住长段落，也不靠大量 `\\`、负间距或每小节 `\newpage` 修补版面。标题或短答题步骤确需与下文同页时，可在确认可用后按需加载 `needspace` 并用 `\Needspace{5\baselineskip}`；不要对整章强制保留空间。
- 需要引用的图保留 `\caption` 和其后的 `\label`。外部图片按需加载 `graphicx`，用 `width=\linewidth`、合理的高度上限和 `keepaspectratio` 保持比例；TikZ 优先调整节点间距、文字换行和图结构，不把所有标注整体缩得过小。将 `Overfull \hbox`、缺字、未定义引用和重复目标警告定位到实际页面修正，不用全局 `\sloppy` 或关闭警告掩盖问题。

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
\newcommand{\reviewtag}[2]{\begingroup
  \setlength{\fboxsep}{3pt}%
  \colorbox{#1!10!white}{\textcolor{#1}{\strut\textbf{#2}}}%
  \endgroup}
\newcommand{\tj}[1]{\textbf{#1}}
\newcommand{\dw}[1]{{\small\color{timec}定位：#1}\par\medskip}
\newenvironment{reviewbox}[2]{%
  \def\FrameCommand{{\color{#1}\vrule width 2.5pt}\hspace{8pt}}%
  \MakeFramed{\advance\hsize-\width\FrameRestore}%
  \noindent{\small\color{#1}\textbf{#2}}\par\smallskip}%
  {\endMakeFramed\medskip}
\newenvironment{kaodian}{\begin{reviewbox}{signaltext}{【考点】老师原话}}{\end{reviewbox}}
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
\subsection*{标记说明}
\begin{description}[style=nextline,leftmargin=0pt,labelwidth=0pt,labelsep=0pt,font=\normalfont]
  \item[\reviewtag{signaltext}{考点}] 有课堂依据的重点；强度和考试条件见正文。
  \item[\reviewtag{completec}{必背}] 老师要求记忆的表述；规范原文附来源。
  \item[\reviewtag{errorc}{辨析}] 易混概念、适用边界与常见错误。
  \item[\reviewtag{timec}{答题}] 解题顺序、踩点术语与检查方法。
\end{description}
\dw{本讲在课程体系中的位置}
\pdfbookmark[0]{\contentsname}{recap-contents}
\tableofcontents
\clearpage
% 正文：\section{主题}\label{sec:topic}，依次补齐章/节
\end{document}
~~~

如需“计算题步骤”等自定义框标题，可直接用 `\begin{reviewbox}{timec}{标题}`，不另造未定义命令。模板用文字标签避免装饰符号缺字；英文版须同时翻译这些标签、`\reviewtitle`、`\dw` 和 `suvlan`。英文标记说明替换为以下段落，沿用模板的 `\reviewtag`，并删除未使用的类型：

~~~latex
\subsection*{Marking Guide}
\begin{description}[style=nextline,leftmargin=0pt,labelwidth=0pt,labelsep=0pt,font=\normalfont]
  \item[\reviewtag{signaltext}{Key Point}] Grounded in the lecture; see the text for exam scope and conditions.
  \item[\reviewtag{completec}{Memorize}] Wording the instructor asks you to retain; exact source text is cited.
  \item[\reviewtag{errorc}{Distinguish}] Confusable concepts, limits of applicability, and common mistakes.
  \item[\reviewtag{timec}{Answer Steps}] Solution order, required terms, and checks.
\end{description}
~~~

以下两个片段仅示范排版，用真实课程内容替换；英文课程同时翻译表头和正文。它们只使用基线已加载的宏包，不需要另加一组宏包：

~~~latex
% 一式多行：解释为何成立，并在公式之后定义符号、单位和条件。
\begin{equation}\label{eq:stress}
  \begin{aligned}
    \sigma &= \frac{F}{A}, & A &= b h,\\
    \sigma &= \frac{F}{b h}.
  \end{aligned}
\end{equation}
% 正文用 \eqref{eq:stress} 回查；此处不是未经来源核实的课程结论。
\begin{tabularx}{\linewidth}{@{}l>{\raggedright\arraybackslash}X>{\raggedright\arraybackslash}X@{}}
  \toprule
  条目 & 适用条件 & 易错与回查 \\
  \midrule
  正应力 & 轴向载荷、截面平均值 & 统一力与面积单位，见式~\eqref{eq:stress}。\\
  \bottomrule
\end{tabularx}
~~~

### 示意图

- 老师明确要求会画的图必须覆盖；标准受力图、流程图、应力应变曲线等按教学需要补充。自行重画标“整理示意”，不能称课堂截图。
- 有明确考试依据的作图题标“考试要求会画”，说明特征点、曲线/受力关系及作答要点；关键部分用 `signal` 色，其余以黑色和 `timec` 灰为主。
- TikZ 图一图一验；线条、坐标、变量与单位清楚，配图解释特征点和适用条件。图宽不超正文区；含坐标轴的函数图可按需加载 `pgfplots`，引用外部图片才加载 `graphicx`。
- API 只返回单个 `.tex`，不能引用未提供的外部图片、章节子文件或临时路径。图用内联 TikZ，无法可靠绘制时说明缺口。
- 连续两次编译失败可简化绘图实现，不能改变受力关系或曲线含义；无法可靠画出的图保留缺口。图片文件交付时与源码一并保留，使用相对路径。

### 编译与验收（CLI）

1. 先确认 `xelatex`（找不到再查 `/Library/TeX/texbin/xelatex`）及实际用到的包：`kpsewhich hyperref.sty` 等。不要把某台电脑的 BasicTeX 包清单当通用事实。轻量 `framed` 为默认；额外包按需检查，不无条件禁止，也不未经授权全局安装依赖。
2. 在工作目录生成候选 `.tex`/PDF，执行 `xelatex -interaction=nonstopmode -halt-on-error -jobname=<目标PDF去掉.pdf的文件名> <讲义源码文件>` 至少两遍。源码和目标 PDF 分别按清单的对应键取路径；部分迁移时两者可能是不同名称，不能由 `.tex` 名推导 PDF 名。把完整 `-jobname=...` 安全引用为单个参数，源码文件名也安全引用并加 `./` 防止前导短横线被当作选项；目录和文件名可能含空格、中文或单引号，不把未转义名称直接拼进 shell 命令。只有目录/引用仍要求重跑才继续；报错读 log 定位，最多三轮修复，不用旧 PDF 冒充编译成功。
3. **内容核验**：对照课堂输入覆盖表，逐单元复核考试信号、原话、推导、案例和范围条件，确认课堂重点已得到充分解释、次要内容没有挤占主线，未遗漏重点或混入未讲的教材主题；教材引用须对应具体课堂疑点或必要释义。再核对数字/公式/定义、同音错字、版本差异、跨单元重复/矛盾与排除范围。有条件由独立审阅者执行；记录具体位置、依据和修正，未解决项明确保留。
4. **文档核验**：检查页数、文本提取、目录/页码、字体缺字和未解析的 `??`；检查所有链接目标有效、书签名称可读、章节齐全。可用 PDF 工具（如 pypdf/PDFKit）检查链接注释、书签和目标页；仅看到目录文字不算通过。确认“标记说明”与正文复用同名颜色、标签含义一致，英文课程没有遗留中文提示框或表头。
5. **页面核验**：渲染最终 PDF 检查全部页面，可先总览再放大目录、标记说明、公式、表格、图和跨页处；解决截断、重叠、缺字、空白异常及影响阅读的溢出。确认颜色标签实际着色、浅底与文字清晰，灰度下仍可凭标签理解；检查长表续页表头和公式编号位置。没有渲染/交互工具时明确报告未做的检查，不宣称视觉验收或实点跳转通过。
6. 验证通过才以正确文件名交付 PDF 和可编辑源码；保留原始输入、旧版备份、必要图像和待续工作记录。辅助文件仅清理本次工作目录中的已知 `.aux/.log/.toc/.out` 等，失败时保留 log 便于恢复，不通配删除课程文件。

无法编译时保留 `.tex`、失败信息和 Markdown 降级稿，报告缺少的工具/包；不要覆盖仍可用的旧 PDF，不把“已写源码”报告成“已生成讲义 PDF”。API 只输出源码，以上落盘/编译/验收是否执行由宿主程序决定。

## 任务四：课程考试重点 → `course.files["review.tex"]` + `course.files["review.pdf"]`

CLI 先按 `lectures.json` 清点各讲分析，明确缺失、过期、无法解析的讲次；不能静默跳过后声称覆盖全课程。API 仅汇总实际提供的讲次，并明确覆盖数量/范围。

默认交付与任务三相同的可导航 LaTeX/PDF；用户明确要 Markdown 或无法编译时写 `course.files["review.md"]` 指定文件（旧版课程写 `review.md`）。API 仍只返回源文档，不自行决定或操作文件路径。内容按课程语言组织：

1. 来源与覆盖范围、已确认的考试形式/题型/排除项。
2. 必考清单（仅明确承诺的项目）；重点清单与有依据的可能考内容。
3. 必背汇总、答题步骤与题型、易混辨析。
4. 各讲/章节索引，必要时加入回听定位和作业复习线索。

跨讲同一知识点可归并并标“多次强调”，保留来源讲次和各自条件；强度不能仅由出现次数升级。重讲、补讲和后来更正要合并核对，不能拼接成虚构引文。按实际课堂主题及有依据的重要程度组织长总表，重点前置，避免各章等量铺开；索引指向已有正文。教材只辅助澄清已有课堂条目，不新增教材考点或按教材目录补齐课程。用户明确要求的教材拓展另列，不把总表扩写成未经请求的整本教材。

## 汇报与续作

说明交付路径、实际覆盖的讲次/章节/文稿块、教材使用情况、纠错或来源冲突、缺失材料及待核项。分别报告“源码已写、编译通过、内容核验、链接结构检查、页面检查、交互点击验证”的实际完成情况。中断时提供工作目录、已完成单元和下一步；保留可用旧成果，不用部分草稿冒充全量交付。

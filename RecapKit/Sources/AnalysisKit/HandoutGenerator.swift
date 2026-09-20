//
//  HandoutGenerator.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// Generates Markdown or LaTeX review documents from the supplied lecture material
public struct HandoutGenerator {

    public init() {}

    // MARK: - Per-lecture handout

    private static let lectureSystemPrompt = """
    你是一名复习讲义撰写者。根据一节课的完整转写稿和已提取的考点信息，为学生写这一讲的复习讲义。

    要求：
    - 只输出 Markdown，不要任何解释或代码块包裹；
    - 结构固定为：
      # <讲次标题>
      ## 本讲概览        （3-5 句话说清这讲讲了什么、重心在哪）
      ## 考点详解        （逐条：知识点讲解 + 老师原话用 > 引用块保留 + 题型提示）
      ## 必背清单
      ## 答题步骤与课堂案例
      ## 易混辨析
      ## 考试范围与条件
      ## 作业与思考题
    - 讲解内容必须基于转写稿实际讲过的东西，不要凭空扩充；
    - 转写稿来自语音识别，专业术语的同音错字请按上下文纠正后书写正确版本；
    - 保留老师原话，考点强度依据老师的明确措辞，不因知识点重要或反复出现就升级为必考；保留不考、了解即可、公式会提供、是否要求推导等范围与条件；
    - 答题步骤、适用题型、公式依据、单位和课堂案例只采用输入中可核实的内容，保留例题条件与易错提醒，不补造数值或答案；
    - 本次只提供转写稿与考点提取结果，没有教材原文或精确时间戳。不要声称已核验教材、页码或视频时间；在讲义内说明资料范围和仍需核实的缺口，不把未提供的教材内容写成逐字必背依据；
    - 语言平实直接，不用比喻；
    - 讲义语言跟随转写稿语言：英文课程写英文讲义（结构标题也用英文），中文课程写中文。
    """

    public func lectureHandout(
        title: String,
        transcript: String,
        analysis: LectureAnalysis,
        client: ChatClient
    ) async throws -> String {
        let analysisJSON = Self.encodeJSON(analysis)
        let user = """
        讲次标题：\(title)

        考点提取结果（JSON）：
        \(analysisJSON)

        完整转写稿：
        \(transcript)
        """
        return try await client.complete(system: Self.lectureSystemPrompt, user: user, temperature: 0.3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Uses the bundled skill's handout specification with only the material supplied to the API
    public func lectureLaTeX(
        title: String,
        transcript: String,
        analysis: LectureAnalysis,
        skill: String,
        client: ChatClient
    ) async throws -> String {
        let system = """
        \(skill)

        现在只执行上面 skill 的任务三「生成本讲讲义」，采用其中共用的 LaTeX 模板、可点击目录、PDF 书签与交叉引用规范。
        你在 API 通道，只能使用下面提供的本讲转写稿和考点提取结果；未提供教材原文、教材图像、分段时间戳或其他讲次资料。不要读写文件、请求读取分章文件或声称已核验教材、页码、视频时间、编译结果和 PDF 版面。原话与考点强度以转写稿为准，保留考试排除项、公式提供等条件，以及有依据的答题步骤和课堂案例，不补造缺失的例题条件或答案。
        在讲义正文中简要说明资料范围和未核实的缺口；没有教材依据时，不声称必背表述已与教材逐字核对。这里只生成可编译的源文档，不执行 skill 中的文件操作、编译、渲染或交付核验步骤。
        返回的单个 .tex 必须自足，不引用未提供的外部图片、章节子文件或临时路径；图用内联 TikZ，无法可靠绘制时在正文列出待核项。
        不要输出 .tex 之外的解释或 markdown 代码块围栏，直接输出完整的 .tex 文件内容（从 \\documentclass 到 \\end{document}）。
        """
        let user = """
        讲次标题：\(title)

        考点提取结果（JSON）：
        \(Self.encodeJSON(analysis))

        完整转写稿：
        \(transcript)
        """
        var tex = try await client.complete(system: system, user: user, temperature: 0.3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tex.hasPrefix("```") {
            tex = tex
                .replacingOccurrences(of: "```latex", with: "")
                .replacingOccurrences(of: "```tex", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tex
    }

    // MARK: - Course-wide exam digest

    private static let courseSystemPrompt = """
    你要把本次提供的各讲考点提取结果汇总成一份「考试重点总表」，供期末复习使用。

    要求：
    - 只输出 Markdown，不要任何解释或代码块包裹；
    - 结构固定为：
      # <课程名>考试重点
      ## 必考清单        （输入中 strength=必考 或 must-know 的信号，按知识点归并，注明出自哪一讲）
      ## 重点清单        （strength=重点 或 key）
      ## 可能考清单      （strength=可能考 或 likely）
      ## 必背汇总
      ## 答题套路汇总
      ## 易混辨析汇总
      ## 考试范围与条件
      ## 各讲要点索引    （每讲一行：讲次名 — 一句话核心内容）
    - 开头声明仅覆盖本次输入的讲次及其数量，不知道课程总讲次，不声称已覆盖全课程；
    - 跨讲重复提到的同一知识点要合并成一条，并标注「多次强调」和各来源讲次；重复不代表必考，强度不得脱离老师明确措辞升级；
    - 保留老师原话的关键表述；
    - 保留不考、了解即可、公式会提供、是否要求推导等考试条件，以及有依据的答题步骤、适用题型和课堂案例；输入中的矛盾分别注明来源，不自行裁定；
    - 只提供了提取结果，没有转写稿、教材或精确时间戳，不声称已核验这些原始资料；资料范围和缺口写进总表，不补造例题条件、答案或教材必背原文；
    - 语言平实直接；
    - 总表语言跟随各讲内容语言：英文课程输出英文。
    """

    // Course digest as LaTeX, spec'd by the same bundled skill as the lecture handout
    public func courseLaTeX(
        courseName: String,
        lectures: [(title: String, analysis: LectureAnalysis)],
        skill: String,
        client: ChatClient
    ) async throws -> String {
        let system = """
        \(skill)

        现在只执行上面 skill 的任务四「课程考试重点总表」，把下面提供的 \(lectures.count) 讲考点提取结果合并成「\(courseName)考试重点」，并采用共用 LaTeX 模板、可点击目录、PDF 书签与交叉引用规范。
        跨讲重复的知识点合并并标注「多次强调」及各来源讲次，保留老师原话的关键表述和各讲要点索引；重复不代表必考，强度不能脱离明确措辞升级。保留不考、了解即可、公式会提供、是否要求推导等考试条件，以及输入中有依据的答题步骤、适用题型和课堂案例；矛盾分别注明来源，不自行裁定或补造例题条件与答案。
        你在 API 通道，只能读取下面提供的提取结果，未提供课程完整讲次清单、转写稿、教材原文、教材图像或精确时间戳。在总表正文开头按课程语言声明「基于本次提供的 \(lectures.count) 讲提取结果」，不声称已覆盖全课程或核验上述原始资料；其他未核实的缺口也写在总表内。
        这里只生成源文档，不读写文件，不执行 skill 中的编译、渲染或交付核验步骤，不声称已通过这些核验。不要输出 .tex 之外的解释或 markdown 代码块围栏，直接输出完整的 .tex 文件内容（从 \\documentclass 到 \\end{document}）。
        返回的单个 .tex 必须自足，不引用未提供的外部图片、章节子文件或临时路径；图用内联 TikZ，无法可靠绘制时在正文列出待核项。
        """
        var user = "课程名：\(courseName)\n本次提供 \(lectures.count) 讲的提取结果，不代表课程全部讲次。\n\n以下是各讲的考点提取结果：\n"
        for lecture in lectures {
            user += "\n### \(lecture.title)\n\(Self.encodeJSON(lecture.analysis))\n"
        }
        var tex = try await client.complete(system: system, user: user, temperature: 0.3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tex.hasPrefix("```") {
            tex = tex
                .replacingOccurrences(of: "```latex", with: "")
                .replacingOccurrences(of: "```tex", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tex
    }

    public func courseDigest(
        courseName: String,
        lectures: [(title: String, analysis: LectureAnalysis)],
        client: ChatClient
    ) async throws -> String {
        var user = "课程名：\(courseName)\n本次提供 \(lectures.count) 讲的提取结果，不代表课程全部讲次。\n\n以下是各讲的考点提取结果：\n"
        for lecture in lectures {
            user += "\n### \(lecture.title)\n\(Self.encodeJSON(lecture.analysis))\n"
        }
        return try await client.complete(system: Self.courseSystemPrompt, user: user, temperature: 0.3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func encodeJSON(_ analysis: LectureAnalysis) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(analysis) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

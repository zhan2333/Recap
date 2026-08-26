//
//  HandoutGenerator.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// Turns extraction results into human-readable review documents (Markdown)
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
      ## 易混辨析
      ## 作业与思考题
    - 讲解内容必须基于转写稿实际讲过的东西，不要凭空扩充；
    - 转写稿来自语音识别，专业术语的同音错字请按上下文纠正后书写正确版本；
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

    // LaTeX channel: the bundled claude skill doubles as the spec; the model only runs its handout task
    public func lectureLaTeX(
        title: String,
        transcript: String,
        analysis: LectureAnalysis,
        skill: String,
        client: ChatClient
    ) async throws -> String {
        let system = """
        \(skill)

        现在只执行上面 skill 中「生成讲义」任务的 LaTeX 排版规范。你不在文件系统环境中：不要读写文件、不要执行其他任务、不要输出解释或 markdown 代码块围栏，直接输出完整的 .tex 文件内容（从 \\documentclass 到 \\end{document}）。
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
    你要把一门课程所有讲次的考点提取结果汇总成一份「考试重点总表」，供期末复习使用。

    要求：
    - 只输出 Markdown，不要任何解释或代码块包裹；
    - 结构固定为：
      # <课程名>考试重点
      ## 必考清单        （全课程 strength=必考 的信号，按知识点归并，注明出自哪一讲）
      ## 重点清单        （strength=重点）
      ## 必背汇总
      ## 答题套路汇总
      ## 易混辨析汇总
      ## 各讲要点索引    （每讲一行：讲次名 — 一句话核心内容）
    - 跨讲重复提到的同一知识点要合并成一条，并标注「多次强调」；
    - 保留老师原话的关键表述；
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

        现在执行考试重点汇总：把下面各讲的考点提取结果合并成一份「\(courseName)考试重点」总表（跨讲重复的知识点合并并标注「多次强调」，保留老师原话的关键表述，附各讲要点索引），并按上面 skill 中「生成讲义」任务的 LaTeX 排版规范排版。你不在文件系统环境中：不要读写文件、不要执行其他任务、不要输出解释或 markdown 代码块围栏，直接输出完整的 .tex 文件内容（从 \\documentclass 到 \\end{document}）。
        """
        var user = "课程名：\(courseName)\n\n以下是各讲的考点提取结果：\n"
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
        var user = "课程名：\(courseName)\n\n以下是各讲的考点提取结果：\n"
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

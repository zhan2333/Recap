//
//  LectureAnalyzer.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// Structured exam-focused extraction from one lecture transcript
public struct LectureAnalysis: Codable, Sendable {

    public struct ExamSignal: Codable, Sendable {
        // The teacher's literal words ("这个必考", "记住有效应力原理").
        public var quote: String
        // 必考 / 重点 / 可能考
        public var strength: String
        // Question type if the teacher hinted one (计算题/简答/论述…).
        public var qtype: String?
        // What the signal is about.
        public var topic: String?
    }

    public var examSignals: [ExamSignal]
    public var mustMemorize: [String]
    public var answerApproaches: [String]
    public var confusablePoints: [String]
    public var keyConcepts: [String]
    public var assignments: [String]

    enum CodingKeys: String, CodingKey {
        case examSignals = "exam_signals"
        case mustMemorize = "must_memorize"
        case answerApproaches = "answer_approaches"
        case confusablePoints = "confusable_points"
        case keyConcepts = "key_concepts"
        case assignments
    }
}

public struct LectureAnalyzer {

    public enum AnalyzeError: Error, LocalizedError {
        case unparsableResponse(raw: String, detail: String)

        public var errorDescription: String? {
            switch self {
            case .unparsableResponse(_, let detail):
                "无法解析模型返回的 JSON（\(detail)）"
            }
        }

        // Full model output, for saving next to the lecture for diagnosis.
        public var rawResponse: String {
            switch self {
            case .unparsableResponse(let raw, _): raw
            }
        }
    }

    private static let systemPrompt = """
    你是一名课程复习助理，任务是从大学课堂录音的转写稿中提取与期末考试相关的信息。

    转写稿的已知缺陷，处理时注意：
    - 来自 whisper 语音识别，专业术语常有同音错字（如"土力学"写成"图的学"、"固结"写成"固解"），请按上下文和专业知识纠正理解；
    - 静音段可能出现"请点赞订阅""优优独播剧场"（英文课程则是 "Thanks for watching" 一类）等幻觉文本，直接忽略；
    - 学生汇报、点名、闲聊段落不要提取。

    转写稿是什么语言，所有输出字段（quote、topic、各清单）就用什么语言：英文课程输出英文，中文课程输出中文。

    只输出一个 JSON 对象，不要 markdown 代码块，不要任何解释文字。字段：
    {
      "exam_signals": [{"quote": "老师的原话", "strength": "必考|重点|可能考（英文课程用 must-know|key|likely）", "qtype": "题型(可选)", "topic": "涉及知识点(可选)"}],
      "must_memorize": ["需要逐字背诵的表述"],
      "answer_approaches": ["老师讲的答题套路/框架"],
      "confusable_points": ["易混易错辨析"],
      "key_concepts": ["本讲核心概念"],
      "assignments": ["布置的作业/思考题"]
    }
    提取规则：
    - exam_signals 里的 quote 保留一处连续的老师原话，只校正上下文能确认的识别错字；不要改写成书面语，不拼接不同位置的句子，不在 quote 中加入时间戳、讲次名、教材页码、校正说明或其他出处信息。
    - strength 依据老师明确措辞：明确说必考、一定考才用必考/must-know；明确强调重点掌握用重点/key；明确提示可能考用可能考/likely。不能仅因概念重要、反复出现或你认为值得考就提升强度；没有考试信号的核心内容放 key_concepts。qtype 只写老师实际说明的题型，不明则省略或为 null。
    - 不考、仅了解、无需背诵、公式会提供、需要或不需要推导等要求，作为带「考试范围与条件」（英文用 Exam scope and conditions）标记的完整条目保留在 key_concepts，不当作正向考试信号；不得丢掉否定词与适用范围，也不能把提供公式等同于不考计算。不同说法矛盾时保留各自条件，不擅自裁定。
    - must_memorize 只收录老师明确要求记住且本段可核实的表述，保留适用条件；本次未提供教材，不声称已经与教材逐字核对，不能把按常识补全的内容伪装成教材原文。
    - answer_approaches 保留老师实际讲过的题型、分步过程、踩点术语、公式依据、单位检查和课堂案例。每条仍为字符串，可在同一条里写清题型、条件、步骤与例题数据；缺失的条件、数值或答案不得补造，必要时注明待核实。
    - confusable_points 保留成对概念、区分依据、错误原因与适用条件，不只列名称；assignments 保留老师实际布置的题号、页码与要求，未说清的部分注明未说明。
    - 只基于本次转写文本和明确提供的参考提取，不虚构教材出处、视频时间或已核验的结论。没有内容的字段给空数组，六个顶层字段都要保留，不新增字段或改变数组/字符串类型。
    """

    // Findings from an earlier pass over the same material, offered as a hint and never as the source
    public struct AnalysisReference: Sendable {
        public var range: ClosedRange<TimeInterval>?
        public var text: String

        public init(range: ClosedRange<TimeInterval>? = nil, text: String) {
            self.range = range
            self.text = text
        }
    }

    public init() {}

    public func extract(
        transcript: String,
        client: ChatClient,
        references: [AnalysisReference] = []
    ) async throws -> LectureAnalysis {
        let response = try await client.complete(
            system: Self.systemPrompt,
            user: "以下是一节课的完整转写稿：\n\n\(transcript)" + Self.referenceBlock(references)
        )
        return try Self.parse(response)
    }

    // A transcript past the budget is read in pieces and the findings merged, since the
    // endpoint only sees what we send it
    public func extract(
        lines: [TranscriptLine],
        client: ChatClient,
        maxTokens: Int = 12_000,
        references: [AnalysisReference] = [],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> LectureAnalysis {
        let chunks = TranscriptChunker.chunks(from: lines, maxTokens: maxTokens)
        guard chunks.count > 1 else {
            onProgress?(0, 1)
            let text = lines.map(\.text).joined(separator: "\n")
            let analysis = try await extract(transcript: text, client: client, references: references)
            onProgress?(1, 1)
            return analysis
        }

        var parts: [LectureAnalysis] = []
        for chunk in chunks {
            onProgress?(chunk.index, chunks.count)
            // Only the references covering this stretch, so a long lecture keeps its prompts small
            let covering = references.filter {
                guard let range = $0.range else { return true }
                return range.overlaps(chunk.start...max(chunk.start, chunk.end))
            }
            let response = try await client.complete(
                system: Self.systemPrompt,
                user: """
                这是一节课转写稿的第 \(chunk.index + 1) / \(chunks.count) 部分，时间范围 \(chunk.timeRange)。
                只针对这一部分提取，不要推测其他部分的内容。

                \(chunk.text)
                """ + Self.referenceBlock(covering)
            )
            parts.append(try Self.parse(response))
        }
        onProgress?(chunks.count, chunks.count)
        return Self.merge(parts)
    }

    private static func referenceBlock(_ references: [AnalysisReference]) -> String {
        let body = references.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !body.isEmpty else { return "" }
        return """


        这些内容此前单独提取过一份重点，供参考。它可能不全也可能有错，一律以转写稿为准，不要照抄：

        \(body)
        """
    }

    // Findings arrive per piece; identical entries are folded and the first wording wins
    static func merge(_ parts: [LectureAnalysis]) -> LectureAnalysis {
        func unique(_ lists: [[String]]) -> [String] {
            var seen = Set<String>()
            return lists.flatMap { $0 }.filter { seen.insert($0.trimmingCharacters(in: .whitespaces)).inserted }
        }
        var signals: [LectureAnalysis.ExamSignal] = []
        var seenQuotes = Set<String>()
        for signal in parts.flatMap(\.examSignals) where seenQuotes.insert(signal.quote).inserted {
            signals.append(signal)
        }
        return LectureAnalysis(
            examSignals: signals,
            mustMemorize: unique(parts.map(\.mustMemorize)),
            answerApproaches: unique(parts.map(\.answerApproaches)),
            confusablePoints: unique(parts.map(\.confusablePoints)),
            keyConcepts: unique(parts.map(\.keyConcepts)),
            assignments: unique(parts.map(\.assignments))
        )
    }

    // Tolerant of code fences, surrounding prose, and the most common LLM JSON defect: raw control characters inside string literals.
    static func parse(_ raw: String) throws -> LectureAnalysis {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }

        var lastError = "empty response"
        for candidate in [text, Self.escapingControlCharacters(in: text)] {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try JSONDecoder().decode(LectureAnalysis.self, from: data)
            } catch {
                lastError = Self.describe(error)
            }
        }
        throw AnalyzeError.unparsableResponse(raw: raw, detail: lastError)
    }

    // Escapes raw newlines/tabs that appear inside JSON string literals
    static func escapingControlCharacters(in text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        for ch in text {
            if escaped {
                out.append(ch)
                escaped = false
                continue
            }
            switch ch {
            case "\\" where inString:
                out.append(ch)
                escaped = true
            case "\"":
                inString.toggle()
                out.append(ch)
            case "\n" where inString: out += "\\n"
            case "\r" where inString: out += "\\r"
            case "\t" where inString: out += "\\t"
            default:
                out.append(ch)
            }
        }
        return out
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .dataCorrupted(let context): return "JSON 语法错误：\(context.debugDescription)"
        case .keyNotFound(let key, _): return "缺少字段 \(key.stringValue)"
        case .typeMismatch(_, let context): return "字段类型不符：\(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context): return "字段值缺失：\(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: return error.localizedDescription
        }
    }
}

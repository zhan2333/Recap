//
//  LectureAnalyzer.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

/// Structured exam-focused extraction from one lecture transcript.
/// Field set carried over from the proven shell-pipeline schema.
public struct LectureAnalysis: Codable, Sendable {

    public struct ExamSignal: Codable, Sendable {
        /// The teacher's literal words ("这个必考", "记住有效应力原理").
        public var quote: String
        /// 必考 / 重点 / 可能考
        public var strength: String
        /// Question type if the teacher hinted one (计算题/简答/论述…).
        public var qtype: String?
        /// What the signal is about.
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
        case unparsableResponse(String)

        public var errorDescription: String? {
            switch self {
            case .unparsableResponse(let text):
                "无法解析模型返回的 JSON：\(text.prefix(200))"
            }
        }
    }

    private static let systemPrompt = """
    你是一名课程复习助理，任务是从大学课堂录音的转写稿中提取与期末考试相关的信息。

    转写稿的已知缺陷，处理时注意：
    - 来自 whisper 语音识别，专业术语常有同音错字（如"土力学"写成"图的学"、"固结"写成"固解"），请按上下文和专业知识纠正理解；
    - 静音段可能出现"请点赞订阅""优优独播剧场"等幻觉文本，直接忽略；
    - 学生汇报、点名、闲聊段落不要提取。

    只输出一个 JSON 对象，不要 markdown 代码块，不要任何解释文字。字段：
    {
      "exam_signals": [{"quote": "老师的原话", "strength": "必考|重点|可能考", "qtype": "题型(可选)", "topic": "涉及知识点(可选)"}],
      "must_memorize": ["需要逐字背诵的表述"],
      "answer_approaches": ["老师讲的答题套路/框架"],
      "confusable_points": ["易混易错辨析"],
      "key_concepts": ["本讲核心概念"],
      "assignments": ["布置的作业/思考题"]
    }
    exam_signals 里的 quote 必须贴近老师原话，不要改写成书面语。没有内容的字段给空数组。
    """

    public init() {}

    public func extract(transcript: String, client: ChatClient) async throws -> LectureAnalysis {
        let response = try await client.complete(
            system: Self.systemPrompt,
            user: "以下是一节课的完整转写稿：\n\n\(transcript)"
        )
        return try Self.parse(response)
    }

    /// Tolerant of models that wrap JSON in a code fence despite instructions.
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
        guard let data = text.data(using: .utf8),
              let analysis = try? JSONDecoder().decode(LectureAnalysis.self, from: data)
        else { throw AnalyzeError.unparsableResponse(raw) }
        return analysis
    }
}

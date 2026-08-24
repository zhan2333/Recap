//
//  ChatClient.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

// Minimal OpenAI-compatible chat-completions client (single turn)
public struct ChatClient {

    public struct Config: Sendable {
        public var baseURL: URL      // e.g. https://openrouter.ai/api/v1
        public var apiKey: String
        public var model: String

        public init(baseURL: URL, apiKey: String, model: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.model = model
        }
    }

    public enum ClientError: Error, LocalizedError {
        case http(Int, String)
        case emptyResponse
        case notJSON(String)
        case truncated

        public var errorDescription: String? {
            switch self {
            case .http(let code, let body): "LLM request failed (HTTP \(code)): \(body.prefix(300))"
            case .emptyResponse: "LLM returned an empty response"
            case .notJSON(let body): "接口返回的不是 JSON（检查 Base URL 是否正确、是否需要 /v1 后缀）：\(body.prefix(200))"
            case .truncated: "模型输出达到长度上限被截断，请重试"
            }
        }
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 180
        sessionConfig.timeoutIntervalForResource = 600
        session = URLSession(configuration: sessionConfig)
    }

    // Normalizes whatever the user pasted into a chat/completions endpoint: bare hosts get /v1
    private var endpoint: URL {
        var base = config.baseURL
        if base.path.isEmpty || base.path == "/" {
            return base.appendingPathComponent("v1/chat/completions")
        }
        if base.path.hasSuffix("/chat/completions") {
            return base
        }
        if base.path.hasSuffix("/messages") {
            base.deleteLastPathComponent()
        }
        return base.appendingPathComponent("chat/completions")
    }

    // One request, one answer
    public func complete(system: String? = nil, user: String, temperature: Double = 0.2) async throws -> String {
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": user])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "messages": messages,
            "temperature": temperature,
            "max_tokens": 16384,
        ]
        if !config.model.isEmpty {
            body["model"] = config.model
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.notJSON(String(data: data, encoding: .utf8) ?? "<binary>")
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty
        else { throw ClientError.emptyResponse }
        if choices.first?["finish_reason"] as? String == "length" {
            throw ClientError.truncated
        }
        return content
    }
}

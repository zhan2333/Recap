//
//  ChatClient.swift
//  AnalysisKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

/// Minimal OpenAI-compatible chat-completions client (single turn).
/// Works with OpenRouter, self-hosted gateways, or Ollama — anything
/// speaking the /v1/chat/completions dialect.
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

        public var errorDescription: String? {
            switch self {
            case .http(let code, let body): "LLM request failed (HTTP \(code)): \(body.prefix(300))"
            case .emptyResponse: "LLM returned an empty response"
            }
        }
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 600
        session = URLSession(configuration: sessionConfig)
    }

    /// One request, one answer. No tools, no streaming, no history.
    public func complete(system: String? = nil, user: String, temperature: Double = 0.2) async throws -> String {
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": user])

        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": messages,
            "temperature": temperature,
        ] as [String: Any])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty
        else { throw ClientError.emptyResponse }
        return content
    }
}

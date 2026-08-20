//
//  Settings.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import Foundation
import AnalysisKit

enum Settings {

    static var modelPath: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: "modelPath"), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("whisper-models/ggml-large-v3-turbo.bin")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: "modelPath") }
    }

    static var llmBaseURL: String {
        get { UserDefaults.standard.string(forKey: "llmBaseURL") ?? "https://openrouter.ai/api/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "llmBaseURL") }
    }

    static var llmModel: String {
        get { UserDefaults.standard.string(forKey: "llmModel") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "llmModel") }
    }

    // UserDefaults for now: ad-hoc re-signing on every debug build breaks
    // Keychain ACLs (items become unreadable/undeletable). Move back to
    // Keychain once the app ships with a stable signing identity.
    static var llmAPIKey: String {
        get { UserDefaults.standard.string(forKey: "llmAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "llmAPIKey") }
    }

    /// nil until base URL + key + model are all configured.
    static var chatConfig: ChatClient.Config? {
        guard let url = URL(string: llmBaseURL), !llmAPIKey.isEmpty, !llmModel.isEmpty else { return nil }
        return ChatClient.Config(baseURL: url, apiKey: llmAPIKey, model: llmModel)
    }
}


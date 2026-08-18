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

    static var llmAPIKey: String {
        get { KeychainStore.get("llmAPIKey") ?? "" }
        set { KeychainStore.set(newValue, for: "llmAPIKey") }
    }

    /// nil until base URL + key + model are all configured.
    static var chatConfig: ChatClient.Config? {
        guard let url = URL(string: llmBaseURL), !llmAPIKey.isEmpty, !llmModel.isEmpty else { return nil }
        return ChatClient.Config(baseURL: url, apiKey: llmAPIKey, model: llmModel)
    }
}

/// Generic-password wrapper; API key never touches UserDefaults.
enum KeychainStore {

    private static let service = "com.rio.Recap"

    static func set(_ value: String, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

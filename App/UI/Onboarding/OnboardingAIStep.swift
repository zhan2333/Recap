//
//  OnboardingAIStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit
import AnalysisKit

// Optional step: connect a service now, or stay on local transcripts
final class OnboardingAIStep: OnboardingStepView {

    private enum Mode {
        case connect, later
    }

    private var mode: Mode = Settings.chatConfig == nil ? .later : .connect
    private var isChecking = false
    private var baseURL = Settings.llmBaseURL
    private var apiKey = Settings.llmAPIKey
    private var model = Settings.llmModel

    private let container = UIStackView()
    private let error = UILabel()

    override var primaryTitle: String {
        if isChecking { return String(localized: "正在检查…") }
        return mode == .connect ? String(localized: "检查并保存") : String(localized: "继续")
    }

    override var isPrimaryEnabled: Bool { !isChecking }

    override func build() {
        container.axis = .vertical
        container.spacing = 10
        let outcomes = UIStackView(arrangedSubviews: [
            OnboardingScene.chip(String(localized: "只要文稿")),
            OnboardingScene.chip(String(localized: "文稿 + 重点"), tinted: true),
        ])
        outcomes.axis = .vertical
        outcomes.spacing = 6
        let scene = OnboardingScene(
            leading: OnboardingScene.chip(String(localized: "文稿")),
            trailing: outcomes
        )
        let wrapper = UIStackView(arrangedSubviews: [scene, container])
        wrapper.axis = .vertical
        wrapper.spacing = 14
        fill(with: wrapper)
        rebuild()
    }

    private func rebuild() {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }
        container.addArrangedSubview(optionCard(
            title: String(localized: "连接 AI 服务"),
            detail: String(localized: "自动整理重点和讲义"),
            selected: mode == .connect
        ) { [weak self] in
            self?.mode = .connect
            self?.rebuild()
        })
        container.addArrangedSubview(optionCard(
            title: String(localized: "暂时不用"),
            detail: String(localized: "先使用本地转写，之后在设置中连接"),
            selected: mode == .later
        ) { [weak self] in
            self?.mode = .later
            self?.rebuild()
        })

        if mode == .connect {
            container.addArrangedSubview(field(
                label: String(localized: "服务地址"), placeholder: "https://api.example.com/v1", value: baseURL
            ) { [weak self] in self?.baseURL = $0 })
            container.addArrangedSubview(field(
                label: String(localized: "API Key"), placeholder: "••••••••••••", secure: true, value: apiKey
            ) { [weak self] in self?.apiKey = $0 })
            container.addArrangedSubview(field(
                label: String(localized: "模型（可留空）"), placeholder: "model-name", value: model
            ) { [weak self] in self?.model = $0 })
            container.addArrangedSubview(note(String(localized: "连接检查只会发送一个很短的测试请求，不会包含课程内容。设置保存在这台 Mac。")))
            error.isHidden = true
            container.addArrangedSubview(error)
        }
        error.font = RecapTheme.body(11, weight: .semibold)
        error.textColor = RecapTheme.error
        error.numberOfLines = 0
        onStateChange?()
    }

    override func performPrimary(_ completion: @escaping (PrimaryResult) -> Void) {
        guard mode == .connect else {
            completion(.next)
            return
        }
        Settings.llmBaseURL = baseURL
        Settings.llmAPIKey = apiKey
        Settings.llmModel = model
        guard let config = Settings.chatConfig else {
            show(error: String(localized: "还缺少服务地址和 API Key。"))
            completion(.stay)
            return
        }
        isChecking = true
        onStateChange?()
        Task {
            do {
                try await ChatClient(config: config).checkConnection()
                isChecking = false
                onStateChange?()
                completion(.next)
            } catch {
                isChecking = false
                show(error: Self.message(for: error))
                completion(.stay)
            }
        }
    }

    // Separate a wrong address from a rejected key so the next action is obvious
    private static func message(for error: Error) -> String {
        if let clientError = error as? ChatClient.ClientError {
            switch clientError {
            case .http(401, _), .http(403, _):
                return String(localized: "API Key 被拒绝，检查一下这个 Key 是否有效。")
            case .http(404, _):
                return String(localized: "找不到这个接口或模型，检查服务地址是否需要 /v1，以及模型名是否正确。")
            case .http(let code, _):
                return String(localized: "服务返回 HTTP \(code)，稍后再试或换一个服务。")
            case .notJSON:
                return String(localized: "这个地址返回的不是接口数据，通常是服务地址少了 /v1。")
            default:
                break
            }
        }
        return String(localized: "连不上这个服务：\(error.localizedDescription)")
    }

    private func show(error message: String) {
        error.text = message
        error.isHidden = false
        onStateChange?()
    }
}

//
//  SettingsViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

/// Simple form: whisper model path + OpenAI-compatible endpoint config.
/// Values save as you type (UserDefaults / Keychain).
final class SettingsViewController: UITableViewController {

    private struct Field {
        let title: String
        let placeholder: String
        let secure: Bool
        let get: () -> String
        let set: (String) -> Void
    }

    private struct Section {
        let header: String
        let footer: String?
        let fields: [Field]
    }

    private lazy var sections: [Section] = [
        Section(
            header: "转写",
            footer: "ggml 格式的 whisper 模型文件路径。",
            fields: [
                Field(title: "模型路径", placeholder: "~/whisper-models/ggml-large-v3-turbo.bin", secure: false,
                      get: { Settings.modelPath.path },
                      set: { Settings.modelPath = URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }),
            ]
        ),
        Section(
            header: "AI 分析",
            footer: "任何 OpenAI-compatible 接口：OpenRouter、自建网关，或本地 Ollama。API Key 保存在本机。",
            fields: [
                Field(title: "Base URL", placeholder: "https://openrouter.ai/api/v1", secure: false,
                      get: { Settings.llmBaseURL }, set: { Settings.llmBaseURL = $0 }),
                Field(title: "API Key", placeholder: "sk-…", secure: true,
                      get: { Settings.llmAPIKey }, set: { Settings.llmAPIKey = $0 }),
                Field(title: "Model", placeholder: "如 anthropic/claude-sonnet-4.5", secure: false,
                      get: { Settings.llmModel }, set: { Settings.llmModel = $0 }),
            ]
        ),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "设置"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(TextFieldCell.self, forCellReuseIdentifier: TextFieldCell.reuseID)
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].fields.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldCell.reuseID, for: indexPath) as! TextFieldCell
        let field = sections[indexPath.section].fields[indexPath.row]
        cell.configure(title: field.title, placeholder: field.placeholder, secure: field.secure,
                       value: field.get(), onChange: field.set)
        return cell
    }
}

private final class TextFieldCell: UITableViewCell, UITextFieldDelegate {

    static let reuseID = "TextFieldCell"

    private let titleLabel = UILabel()
    private let textField = UITextField()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        textField.font = .preferredFont(forTextStyle: .body)
        textField.textColor = .secondaryLabel
        textField.textAlignment = .right
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = self
        textField.addAction(UIAction { [weak self] _ in
            self?.onChange?(self?.textField.text ?? "")
        }, for: .editingChanged)

        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.axis = .horizontal
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, placeholder: String, secure: Bool, value: String, onChange: @escaping (String) -> Void) {
        titleLabel.text = title
        textField.placeholder = placeholder
        textField.isSecureTextEntry = secure
        textField.text = value
        self.onChange = onChange
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

//
//  DetailHeaderView.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

// 52pt detail chrome: lecture title, centered mode tabs, local pill, overflow menu and the primary analyze button.
final class DetailHeaderView: UIView {

    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let modeTabs = ModeTabsView(items: [
        String(localized: "分段"), String(localized: "全文"),
        String(localized: "播放"), String(localized: "重点"),
    ])
    let overflowButton = UIButton(type: .system)
    let analyzeButton = UIButton(type: .system)
    private let analyzeSpinner = UIActivityIndicatorView(style: .medium)
    private let localPill = UIView()

    var isAnalyzing = false {
        didSet {
            analyzeButton.isHidden = isAnalyzing
            analyzeSpinner.isHidden = !isAnalyzing
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RecapTheme.surface.withAlphaComponent(0.83)

        titleLabel.font = RecapTheme.body(13, weight: .semibold)
        titleLabel.textColor = RecapTheme.ink
        subtitleLabel.font = RecapTheme.body(11)
        subtitleLabel.textColor = RecapTheme.quiet
        // Titles truncate first when the column narrows; actions never do.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 1

        // "· 本地" state pill
        let dot = UIView()
        dot.backgroundColor = RecapTheme.complete
        dot.layer.cornerRadius = 3.5
        let localLabel = UILabel()
        localLabel.text = String(localized: "本地")
        localLabel.font = RecapTheme.body(11)
        localLabel.textColor = RecapTheme.muted
        dot.translatesAutoresizingMaskIntoConstraints = false
        localLabel.translatesAutoresizingMaskIntoConstraints = false
        localPill.addSubview(dot)
        localPill.addSubview(localLabel)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: localPill.leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: localPill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            localLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
            localLabel.trailingAnchor.constraint(equalTo: localPill.trailingAnchor),
            localLabel.topAnchor.constraint(equalTo: localPill.topAnchor),
            localLabel.bottomAnchor.constraint(equalTo: localPill.bottomAnchor),
        ])

        overflowButton.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
            for: .normal
        )
        overflowButton.tintColor = RecapTheme.muted
        overflowButton.showsMenuAsPrimaryAction = true

        var analyzeConfig = UIButton.Configuration.filled()
        analyzeConfig.attributedTitle = AttributedString(
            String(localized: "提取重点"), attributes: AttributeContainer([
                .font: RecapTheme.body(12, weight: .semibold), .foregroundColor: RecapTheme.paper,
            ]))
        analyzeConfig.baseBackgroundColor = RecapTheme.ink
        analyzeConfig.baseForegroundColor = RecapTheme.paper
        analyzeConfig.background.cornerRadius = RecapTheme.radiusSM
        analyzeConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        analyzeButton.configuration = analyzeConfig

        analyzeSpinner.hidesWhenStopped = false
        analyzeSpinner.isHidden = true
        analyzeSpinner.startAnimating()

        analyzeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        overflowButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let trailing = UIStackView(arrangedSubviews: [localPill, overflowButton, analyzeButton, analyzeSpinner])
        trailing.axis = .horizontal
        trailing.alignment = .center
        trailing.spacing = 8

        let bottomLine = UIView()
        bottomLine.backgroundColor = RecapTheme.line

        for subview in [titles, modeTabs, trailing, bottomLine] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            titles.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titles.centerYAnchor.constraint(equalTo: centerYAnchor),
            modeTabs.centerXAnchor.constraint(equalTo: centerXAnchor),
            modeTabs.centerYAnchor.constraint(equalTo: centerYAnchor),
            modeTabs.leadingAnchor.constraint(greaterThanOrEqualTo: titles.trailingAnchor, constant: 12),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: modeTabs.trailingAnchor, constant: 12),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Narrow column: drop the decorative local pill to keep actions whole.
        localPill.isHidden = bounds.width < 660
    }
}

// Pill-style segmented tabs: bordered track, paper-colored active thumb.
final class ModeTabsView: UIView {

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0
    private var buttons: [UIButton] = []

    init(items: [String]) {
        super.init(frame: .zero)
        backgroundColor = RecapTheme.ink.withAlphaComponent(0.05)
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = RecapTheme.line.cgColor

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 0
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.setTitle(item, for: .normal)
            button.titleLabel?.font = RecapTheme.body(12)
            button.layer.cornerRadius = 5
            button.layer.cornerCurve = .continuous
            button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            // Width follows each title (e.g. "Full transcript") instead of a fixed CJK-sized slot
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
            if let titleLabel = button.titleLabel {
                button.widthAnchor.constraint(greaterThanOrEqualTo: titleLabel.widthAnchor, constant: 24).isActive = true
            }
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ])
        applySelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ index: Int, notify: Bool = true) {
        guard index != selectedIndex || !notify else {
            onSelect?(index)
            return
        }
        selectedIndex = index
        applySelection()
        if notify { onSelect?(index) }
    }

    private func applySelection() {
        for (index, button) in buttons.enumerated() {
            let active = index == selectedIndex
            button.backgroundColor = active ? RecapTheme.paper : .clear
            button.setTitleColor(active ? RecapTheme.ink : RecapTheme.muted, for: .normal)
            button.layer.shadowOpacity = active ? 0.14 : 0
            button.layer.shadowRadius = 2
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.layer.shadowColor = RecapTheme.ink.cgColor
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = RecapTheme.line.cgColor
    }
}

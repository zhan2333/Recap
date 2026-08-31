//
//  OnboardingLectureStep.swift
//  Recap
//
//  Created by Rio on 2026/8/28.
//

import UIKit
import UniformTypeIdentifiers

final class OnboardingLectureStep: OnboardingStepView, UIDocumentPickerDelegate {

    private enum Source {
        case local, link
    }

    private var source: Source = .local
    private var pickedFile: URL?
    private var linkText = ""
    private let container = UIStackView()
    private let error = UILabel()

    override var primaryTitle: String {
        switch source {
        case .local: pickedFile == nil ? String(localized: "选择文件…") : String(localized: "开始导入")
        case .link: String(localized: "使用这个链接")
        }
    }

    private var localCard: OnboardingChoiceCard?
    private var linkCard: OnboardingChoiceCard?
    private var selectedRow = UIStackView()
    private let selectedLabel = UILabel()
    private var linkSection = UIStackView()
    private var skipAction = UIView()

    override func build() {
        error.font = RecapTheme.body(11, weight: .semibold)
        error.textColor = RecapTheme.error
        error.numberOfLines = 0
        error.isHidden = true
        error.alpha = 0

        container.axis = .vertical
        container.spacing = 10
        let scene = OnboardingScene(pieces: [
            OnboardingMediaChip(label: "MP4"),
            OnboardingThread(distance: 64),
            OnboardingFolder(
                title: host?.recordedCourse?.name ?? String(localized: "课程"),
                detail: String(localized: "第一讲")),
        ])

        let local = optionCard(
            title: String(localized: "选择本地文件"),
            detail: String(localized: "音频或视频 · 最简单"),
            selected: source == .local
        ) { [weak self] in self?.select(.local) }
        let link = optionCard(
            title: String(localized: "粘贴回放直链"),
            detail: String(localized: "来自课程平台的直接下载链接"),
            selected: source == .link
        ) { [weak self] in self?.select(.link) }
        localCard = local
        linkCard = link

        selectedLabel.font = RecapTheme.body(11.5, weight: .semibold)
        selectedLabel.textColor = RecapTheme.complete
        selectedLabel.numberOfLines = 2
        selectedRow = UIStackView(arrangedSubviews: [selectedLabel])
        selectedRow.axis = .vertical
        selectedRow.isHidden = true
        selectedRow.alpha = 0

        linkSection = UIStackView(arrangedSubviews: [
            field(label: String(localized: "回放直链"), placeholder: "https://…", value: linkText) { [weak self] in
                self?.linkText = $0
            },
        ])
        linkSection.axis = .vertical
        linkSection.spacing = 10
        linkSection.isHidden = source != .link
        linkSection.alpha = source == .link ? 1 : 0

        skipAction = textAction(String(localized: "我现在没有文件")) { [weak self] in
            self?.requestAdvance?()
        }

        let choices = UIStackView(arrangedSubviews: [local, link])
        choices.axis = .horizontal
        choices.distribution = .fillEqually
        choices.spacing = 10
        container.addArrangedSubview(choices)
        container.addArrangedSubview(selectedRow)
        container.addArrangedSubview(linkSection)
        container.addArrangedSubview(error)
        container.addArrangedSubview(skipAction)

        let wrapper = UIStackView(arrangedSubviews: [scene, container])
        wrapper.axis = .vertical
        wrapper.spacing = 12
        fill(with: wrapper)
    }

    // Switching source folds one section out and the other in, in place
    private func select(_ next: Source) {
        guard next != source else { return }
        source = next
        localCard?.isChosen = source == .local
        linkCard?.isChosen = source == .link
        animateContentChange {
            linkSection.isHidden = source != .link
            linkSection.alpha = source == .link ? 1 : 0
            let showsFile = source == .local && pickedFile != nil
            selectedRow.isHidden = !showsFile
            selectedRow.alpha = showsFile ? 1 : 0
            error.isHidden = true
            error.alpha = 0
        }
        onStateChange?()
    }

    private func showError(_ message: String) {
        error.text = message
        animateContentChange {
            error.isHidden = false
            error.alpha = 1
        }
    }

    override func performPrimary(_ completion: @escaping (PrimaryResult) -> Void) {
        switch source {
        case .local:
            guard let file = pickedFile else {
                pendingCompletion = completion
                pickFile()
                return
            }
            importLecture(name: file.deletingPathExtension().lastPathComponent, url: file, completion: completion)
        case .link:
            let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), url.host != nil else {
                showError(String(localized: "请粘贴课程回放的直接下载链接。"))
                completion(.stay)
                return
            }
            let name = url.deletingPathExtension().lastPathComponent
            importLecture(name: name.isEmpty ? String(localized: "第 1 讲") : name, url: url, completion: completion)
        }
    }

    private var pendingCompletion: ((PrimaryResult) -> Void)?

    // The course may have been skipped; create one so the lecture has a home
    private func importLecture(name: String, url: URL, completion: @escaping (PrimaryResult) -> Void) {
        let store = LibraryStore.shared
        let course = host?.recordedCourse ?? store.addCourse(named: String(localized: "我的课程"))
        host?.record(course: course)
        let lecture = store.addLecture(named: name, url: url, to: course)
        host?.record(lecture: lecture)
        LectureQueue.shared.enqueue(lecture, in: course)
        completion(.finish)
    }

    private func pickFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audiovisualContent], asCopy: false)
        picker.delegate = self
        host?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        pickedFile = urls.first
        selectedLabel.text = String(localized: "已选择：\(pickedFile?.lastPathComponent ?? "")")
        animateContentChange {
            selectedRow.isHidden = false
            selectedRow.alpha = 1
        }
        onStateChange?()
        pendingCompletion?(.stay)
        pendingCompletion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingCompletion?(.stay)
        pendingCompletion = nil
    }
}

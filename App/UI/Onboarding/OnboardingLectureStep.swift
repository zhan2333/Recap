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
    private var link = ""
    private let container = UIStackView()
    private let error = UILabel()

    override var primaryTitle: String {
        switch source {
        case .local: pickedFile == nil ? String(localized: "选择文件…") : String(localized: "开始导入")
        case .link: String(localized: "使用这个链接")
        }
    }

    private let sceneHost = UIView()

    override func build() {
        error.font = RecapTheme.body(11, weight: .semibold)
        error.textColor = RecapTheme.error
        error.numberOfLines = 0
        error.isHidden = true
        container.axis = .vertical
        container.spacing = 10
        let scene = OnboardingScene(
            leading: OnboardingScene.chip("MP4"),
            trailing: OnboardingScene.chip(
                host?.recordedCourse?.name ?? String(localized: "课程"),
                detail: String(localized: "第一讲"), tinted: true)
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
            title: String(localized: "选择本地文件"),
            detail: String(localized: "音频或视频 · 最简单"),
            selected: source == .local
        ) { [weak self] in
            self?.source = .local
            self?.rebuild()
        })
        container.addArrangedSubview(optionCard(
            title: String(localized: "粘贴回放直链"),
            detail: String(localized: "来自课程平台的直接下载链接"),
            selected: source == .link
        ) { [weak self] in
            self?.source = .link
            self?.rebuild()
        })

        if source == .local, let file = pickedFile {
            let row = UILabel()
            row.text = String(localized: "已选择：\(file.lastPathComponent)")
            row.font = RecapTheme.body(11.5, weight: .semibold)
            row.textColor = RecapTheme.complete
            row.numberOfLines = 2
            container.addArrangedSubview(row)
        }
        if source == .link {
            container.addArrangedSubview(field(
                label: String(localized: "回放直链"), placeholder: "https://…", value: link
            ) { [weak self] in self?.link = $0 })
        }
        error.isHidden = true
        container.addArrangedSubview(error)
        container.addArrangedSubview(textAction(String(localized: "我现在没有文件")) { [weak self] in
            self?.requestAdvance?()
        })
        onStateChange?()
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
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), url.host != nil else {
                error.text = String(localized: "请粘贴课程回放的直接下载链接。")
                error.isHidden = false
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
        rebuild()
        pendingCompletion?(.stay)
        pendingCompletion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingCompletion?(.stay)
        pendingCompletion = nil
    }
}

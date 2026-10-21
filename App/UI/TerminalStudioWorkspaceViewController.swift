//
//  TerminalStudioWorkspaceViewController.swift
//  Recap
//
//  Created by Rio on 10/21/26.
//

import UIKit

/// Owns one terminal for the lifetime of a lecture workspace. Presentation never ends its shell.
final class TerminalStudioWorkspaceViewController: UIViewController {
    enum Presentation { case hidden, companion, expanded }

    let transcript: TranscriptViewController
    let contentNavigation: UINavigationController
    private let lecture: Lecture
    private let course: Course
    private(set) var studio: TerminalStudioViewController?
    private(set) var presentation: Presentation = .hidden
    private let scrollView = UIScrollView()
    private let divider = UIView()
    private var companionWidth: CGFloat = 390
    private var dragStartWidth: CGFloat = 390
    private var previousDisplayMode: UISplitViewController.DisplayMode?

    init(lecture: Lecture, course: Course) {
        self.lecture = lecture
        self.course = course
        transcript = TranscriptViewController(lecture: lecture, course: course)
        contentNavigation = UINavigationController(rootViewController: transcript)
        super.init(nibName: nil, bundle: nil)
        transcript.studioWorkspace = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        addChild(contentNavigation)
        scrollView.addSubview(contentNavigation.view)
        contentNavigation.didMove(toParent: self)
        divider.backgroundColor = RecapTheme.line
        divider.isAccessibilityElement = true
        divider.accessibilityLabel = String(localized: "调整 Studio 宽度")
        divider.accessibilityTraits = .button
        divider.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeCompanion(_:))))
        divider.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: String(localized: "加宽 Studio")) { [weak self] _ in
                self?.adjustWidth(by: 40); return true
            },
            UIAccessibilityCustomAction(name: String(localized: "缩窄 Studio")) { [weak self] _ in
                self?.adjustWidth(by: -40); return true
            },
        ]
        scrollView.addSubview(divider)
    }

    func toggleStudio() {
        if presentation == .hidden { showStudio() } else { setPresentation(.hidden) }
    }

    func showStudio(prompt: String? = nil) {
        loadViewIfNeeded()
        if studio == nil {
            let currentCourse = LibraryStore.shared.course(id: course.id) ?? course
            let currentLecture = LibraryStore.shared.lecture(id: lecture.id, in: currentCourse) ?? lecture
            let controller = TerminalStudioViewController(lecture: currentLecture, course: currentCourse)
            controller.onRequestHide = { [weak self] in self?.setPresentation(.hidden) }
            controller.onRequestExpand = { [weak self] in
                guard let self else { return }
                self.setPresentation(self.presentation == .expanded ? .companion : .expanded)
            }
            controller.onRequestReference = { [weak self] selection in self?.captureReference(selection: selection) }
            controller.onNavigateReference = { [weak self] reference in self?.navigate(to: reference) }
            controller.onOpenHandout = { [weak self] in
                self?.setPresentation(.companion)
                self?.transcript.showHandout()
            }
            studio = controller
            addChild(controller)
            scrollView.addSubview(controller.view)
            controller.didMove(toParent: self)
        }
        if let prompt { studio?.setPrompt(prompt) }
        setPresentation(.companion)
        view.layoutIfNeeded()
        studio?.activateSession()
    }

    func setPresentation(_ value: Presentation) {
        guard studio != nil else { return }
        if presentation == .hidden && value != .hidden {
            previousDisplayMode = splitViewController?.preferredDisplayMode
            splitViewController?.preferredDisplayMode = .secondaryOnly
        } else if value == .hidden, let previousDisplayMode {
            splitViewController?.preferredDisplayMode = previousDisplayMode
            self.previousDisplayMode = nil
        }
        presentation = value
        if value == .hidden { studio?.view.endEditing(true) }
        transcript.setStudioVisible(value != .hidden)
        studio?.setExpanded(value == .expanded)
        scrollView.setContentOffset(.zero, animated: false)
        view.setNeedsLayout()
    }

    private func captureReference(selection: Bool) {
        let reference: TerminalStudioReference?
        if let pdf = contentNavigation.topViewController as? PDFViewController {
            reference = pdf.studioReference(selection: selection)
        } else {
            reference = transcript.studioReference(selection: selection)
        }
        if let reference { studio?.addReference(reference) }
        else { studio?.showReferenceUnavailable(selection: selection) }
    }

    private func navigate(to reference: TerminalStudioReference) {
        setPresentation(.companion)
        switch reference.location {
        case .pdf:
            transcript.showHandout()
            (contentNavigation.topViewController as? PDFViewController)?.navigate(to: reference)
        case .playback:
            contentNavigation.popToRootViewController(animated: false)
            transcript.navigate(to: reference)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds.inset(by: view.safeAreaInsets)
        scrollView.frame = bounds
        let size = bounds.size
        let visible = presentation != .hidden
        contentNavigation.view.isHidden = presentation == .expanded
        studio?.view.isHidden = !visible
        divider.isHidden = presentation != .companion || size.width < 980
        var contentSize = size
        if presentation == .hidden {
            contentNavigation.view.frame = CGRect(origin: .zero, size: size)
        } else if presentation == .expanded {
            studio?.view.frame = CGRect(origin: .zero, size: size)
        } else if size.width >= 980 {
            let width = min(companionWidth, size.width - 580)
            contentNavigation.view.frame = CGRect(x: 0, y: 0, width: size.width - width - 6, height: size.height)
            divider.frame = CGRect(x: size.width - width - 6, y: 0, width: 6, height: size.height)
            studio?.view.frame = CGRect(x: size.width - width, y: 0, width: width, height: size.height)
        } else {
            let contentHeight = max(480, size.height * 0.55)
            let studioHeight = max(500, size.height * 0.45)
            contentNavigation.view.frame = CGRect(x: 0, y: 0, width: size.width, height: contentHeight)
            studio?.view.frame = CGRect(x: 0, y: contentHeight + 1, width: size.width, height: studioHeight)
            contentSize.height = contentHeight + studioHeight + 1
        }
        scrollView.contentSize = contentSize
        scrollView.isScrollEnabled = contentSize.height > size.height
    }

    @objc private func resizeCompanion(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { dragStartWidth = companionWidth }
        companionWidth = min(520, max(340, dragStartWidth - gesture.translation(in: view).x))
        view.setNeedsLayout()
    }

    private func adjustWidth(by delta: CGFloat) {
        companionWidth = min(520, max(340, companionWidth + delta))
        view.setNeedsLayout()
    }
}

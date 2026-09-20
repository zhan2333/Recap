//
//  PDFLinkView.swift
//  Recap
//
//  Created by Rio on 9/20/26.
//

import UIKit
import PDFKit

final class PDFLinkView: PDFView {
    var onActivateLink: ((PDFAnnotation) -> Void)?

    func linkAnnotation(at point: CGPoint) -> PDFAnnotation? {
        guard let document, let page = page(for: point, nearest: false),
              let annotation = page.annotation(at: convert(point, to: page)),
              annotation.type == "Link", annotation.shouldDisplay,
              PDFNavigation.canActivate(annotation, in: document) else { return nil }
        return annotation
    }

    @discardableResult
    func activateLink(at point: CGPoint) -> Bool {
        guard let annotation = linkAnnotation(at: point), let onActivateLink else { return false }
        onActivateLink(annotation)
        return true
    }

    #if targetEnvironment(macCatalyst)
    private var repairedLink: (point: CGPoint, annotation: PDFAnnotation)?
    private var pendingLink: PDFAnnotation?
    private var linkTap: UITapGestureRecognizer?
    private var linkFeedback: PDFLinkFeedbackView?
    private lazy var linkGestureDelegate = PDFLinkGestureDelegate(pdfView: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        installLinkGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installLinkGesture()
    }

    private func installLinkGesture() {
        let tap = PDFLinkTapGestureRecognizer(target: self, action: #selector(activateTappedLink(_:)))
        tap.name = "RecapPDFLink"
        tap.buttonMaskRequired = .primary
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = linkGestureDelegate
        tap.onPressChanged = { [weak self] point in self?.linkFeedback?.updatePressed(at: point) }
        addGestureRecognizer(tap)
        linkTap = tap
        NotificationCenter.default.addObserver(self, selector: #selector(documentChanged), name: .PDFViewDocumentChanged, object: self)
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewVisiblePagesChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(clearLinkFeedback), name: name, object: self)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLinkFeedback), name: .PDFViewScaleChanged, object: self)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard let annotation = linkAnnotation(at: point), let page = annotation.page, let documentView,
              hit.map({ isDetached($0) || $0 === self || $0.isDescendant(of: self) }) == true else {
            return hit
        }
        let feedback = linkFeedback ?? PDFLinkFeedbackView(pdfView: self)
        linkFeedback = feedback
        if feedback.superview !== documentView { documentView.addSubview(feedback) }
        feedback.configure(annotation: annotation, frame: convert(convert(annotation.bounds, from: page), to: documentView))
        repairedLink = (point, annotation)
        return feedback
    }

    fileprivate func needsLinkGesture(at point: CGPoint) -> Bool {
        let repair = repairedLink
        repairedLink = nil
        pendingLink = nil
        guard let annotation = linkAnnotation(at: point) else { return false }
        let wasRepaired = repair.map {
            $0.annotation === annotation && hypot(point.x - $0.point.x, point.y - $0.point.y) < 1
        } ?? false
        let hit = super.hitTest(point, with: nil)
        let isBroken = hit.map(isDetached) ?? false
        guard wasRepaired || isBroken || (hit != nil && hit === linkFeedback) else { return false }
        pendingLink = annotation
        return true
    }

    private func isDetached(_ hit: UIView) -> Bool {
        guard let window else { return false }
        return hit.window !== window || (hit !== self && !hit.isDescendant(of: self))
    }

    @objc private func clearLinkFeedback() {
        linkFeedback?.removeFromSuperview()
        linkFeedback = nil
    }

    @objc private func refreshLinkFeedback() {
        guard let feedback = linkFeedback else { return }
        guard let annotation = feedback.annotation, let page = annotation.page, page.document === document,
              let documentView, feedback.superview === documentView else {
            clearLinkFeedback()
            return
        }
        feedback.configure(annotation: annotation, frame: convert(convert(annotation.bounds, from: page), to: documentView))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshLinkFeedback()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { clearLinkFeedback() }
    }

    @objc private func activateTappedLink(_ tap: UITapGestureRecognizer) {
        defer { pendingLink = nil; repairedLink = nil }
        guard tap.state == .ended, let pendingLink, pendingLink.page?.document === document,
              linkAnnotation(at: tap.location(in: self)) === pendingLink else { return }
        activateLink(at: tap.location(in: self))
    }

    @objc private func documentChanged() {
        clearLinkFeedback()
        repairedLink = nil
        pendingLink = nil
        linkTap?.isEnabled = false
        linkTap?.isEnabled = true
    }
    #endif
}

#if targetEnvironment(macCatalyst)
private final class PDFLinkGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var pdfView: PDFLinkView?

    init(pdfView: PDFLinkView) { self.pdfView = pdfView }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let pdfView else { return false }
        return pdfView.needsLinkGesture(at: touch.location(in: pdfView))
    }

}

// Observe completed link clicks without competing with PDFKit's pointer and text gestures.
private final class PDFLinkTapGestureRecognizer: UITapGestureRecognizer {
    var onPressChanged: ((CGPoint?) -> Void)?

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onPressChanged?(state == .possible ? touches.first?.location(in: view) : nil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        onPressChanged?(state == .possible ? touches.first?.location(in: view) : nil)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onPressChanged?(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onPressChanged?(nil)
    }

    override func reset() {
        super.reset()
        onPressChanged?(nil)
    }
}

// A link-only leaf gives its pointer style precedence over PDFKit's text-selection cursor.
// It stays inside documentView so the existing scroll, selection, and link gestures remain ancestors.
private final class PDFLinkFeedbackView: UIView, UIPointerInteractionDelegate {
    private weak var pdfView: PDFLinkView?
    private(set) weak var annotation: PDFAnnotation?
    private lazy var pointer = UIPointerInteraction(delegate: self)
    private var isHovered = false
    private var isPressed = false

    init(pdfView: PDFLinkView) {
        self.pdfView = pdfView
        super.init(frame: .zero)
        isOpaque = false
        accessibilityElementsHidden = true
        layer.cornerRadius = 2
        addInteraction(pointer)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(annotation: PDFAnnotation, frame: CGRect) {
        let changed = self.annotation !== annotation || self.frame != frame
        if self.annotation !== annotation {
            isHovered = false
            isPressed = false
        }
        self.annotation = annotation
        self.frame = frame
        updateAppearance()
        if changed { pointer.invalidate() }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event), let pdfView, let annotation else { return false }
        return pdfView.linkAnnotation(at: convert(point, to: pdfView)) === annotation
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        guard point(inside: request.location, with: nil), let annotation else { return nil }
        return UIPointerRegion(rect: bounds, identifier: annotation)
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        .system()
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, willEnter region: UIPointerRegion,
                            animator: UIPointerInteractionAnimating) {
        guard (region.identifier as? PDFAnnotation) === annotation else { return }
        isHovered = true
        updateAppearance()
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, willExit region: UIPointerRegion,
                            animator: UIPointerInteractionAnimating) {
        guard (region.identifier as? PDFAnnotation) === annotation else { return }
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    func updatePressed(at point: CGPoint?) {
        isPressed = point.flatMap { point in pdfView?.linkAnnotation(at: point) }.map { $0 === annotation } ?? false
        updateAppearance()
    }

    private func updateAppearance() {
        // The PDF's dark-mode filter also inverts this neutral overlay.
        backgroundColor = UIColor.black.withAlphaComponent(isPressed ? 0.14 : isHovered ? 0.06 : 0)
    }
}
#endif

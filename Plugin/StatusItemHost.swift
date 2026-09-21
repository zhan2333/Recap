//
//  StatusItemHost.swift
//  RecapShellPlugin
//
//  Created by Rio on 2026/9/13.
//

// Catalyst has no status bar API, so the menu bar item is built here in AppKit
import AppKit

// Must mirror the host app's protocol byte-for-byte
@objc(RSPStatusItemHosting)
public protocol StatusItemHosting {
    static func install(_ imageData: Data, tooltip: String,
                        onCommand: @escaping (String) -> Void,
                        onPrimaryClick: @escaping () -> Void)
    static func setMenu(_ items: [[String: String]])
    static func setProgress(_ fraction: Double, active: Bool, tooltip: String)
    static func remove()
    static func terminate()
}

@objc(RSPStatusItemHost)
public final class StatusItemHost: NSObject, StatusItemHosting {

    private static var statusItem: NSStatusItem?
    private static var baseImage: NSImage?
    private static var command: ((String) -> Void)?
    private static var primaryClick: (() -> Void)?
    private static let target = ClickTarget()

    @objc public static func install(_ imageData: Data, tooltip: String,
                                     onCommand: @escaping (String) -> Void,
                                     onPrimaryClick: @escaping () -> Void) {
        DispatchQueue.main.async {
            command = onCommand
            primaryClick = onPrimaryClick
            guard statusItem == nil else { return }

            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let image = NSImage(data: imageData) {
                let height: CGFloat = 16
                image.size = NSSize(width: height * image.size.width / max(image.size.height, 1), height: height)
                image.isTemplate = true
                baseImage = image
                item.button?.image = image
            }
            item.button?.toolTip = tooltip
            item.button?.target = target
            item.button?.action = #selector(ClickTarget.clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        }
    }

    @objc public static func setMenu(_ items: [[String: String]]) {
        DispatchQueue.main.async {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for entry in items {
                switch entry["kind"] {
                case "separator":
                    menu.addItem(.separator())
                case "header":
                    let header = NSMenuItem(title: entry["title"] ?? "", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    menu.addItem(header)
                default:
                    let menuItem = NSMenuItem(title: entry["title"] ?? "",
                                              action: #selector(ClickTarget.pick(_:)),
                                              keyEquivalent: entry["key"] ?? "")
                    menuItem.target = target
                    menuItem.representedObject = entry["id"]
                    menu.addItem(menuItem)
                }
            }
            self.menu = menu
        }
    }

    @objc public static func remove() {
        DispatchQueue.main.async {
            guard let item = statusItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // A bar under the mark while the queue works; alpha carries it, so the template still tints
    @objc public static func setProgress(_ fraction: Double, active: Bool, tooltip: String) {
        DispatchQueue.main.async {
            guard let button = statusItem?.button, let base = baseImage else { return }
            button.toolTip = tooltip
            guard active else {
                button.image = base
                return
            }
            let barHeight: CGFloat = 2
            let gap: CGFloat = 2
            let size = NSSize(width: base.size.width, height: base.size.height + gap + barHeight)
            let composed = NSImage(size: size, flipped: false) { _ in
                base.draw(at: NSPoint(x: 0, y: gap + barHeight), from: .zero, operation: .sourceOver, fraction: 1)
                let track = NSRect(x: 0, y: 0, width: size.width, height: barHeight)
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
                // An unknown-length step fills the whole bar at a lower weight
                let filled = fraction > 0 ? min(max(fraction, 0), 1) : 1
                let alpha: CGFloat = fraction > 0 ? 1 : 0.55
                let fill = NSRect(x: 0, y: 0, width: size.width * filled, height: barHeight)
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
                return true
            }
            composed.isTemplate = true
            button.image = composed
        }
    }

    // UIKit has no way to quit, so the menu's Quit goes through AppKit
    @objc public static func terminate() {
        if Thread.isMainThread {
            NSApp.terminate(nil)
        } else {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // Kept aside so a left click can open the app instead of dropping the menu
    private static var menu: NSMenu?

    fileprivate static func handleClick() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        guard isRightClick, let menu, let item = statusItem else {
            primaryClick?()
            return
        }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    fileprivate static func handlePick(_ identifier: String) {
        command?(identifier)
    }
}

private final class ClickTarget: NSObject {

    @objc func clicked(_ sender: Any?) {
        StatusItemHost.handleClick()
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        StatusItemHost.handlePick(identifier)
    }
}

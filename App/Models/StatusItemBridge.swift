//
//  StatusItemBridge.swift
//  Recap
//
//  Created by Rio on 2026/9/13.
//

import UIKit

// Mirror of the plugin's interface
@objc(RSPStatusItemHosting)
protocol StatusItemHosting {
    static func install(_ imageData: Data, tooltip: String,
                        onCommand: @escaping (String) -> Void,
                        onPrimaryClick: @escaping () -> Void)
    static func setMenu(_ items: [[String: String]])
    static func setProgress(_ fraction: Double, active: Bool, tooltip: String)
    static func remove()
    static func terminate()
}

// The menu bar item lives in the macOS glue bundle; Catalyst has no status bar API
enum StatusItemBridge {

    private static let host: StatusItemHosting.Type? = {
        let candidates = [Bundle.main.builtInPlugInsURL, Bundle.main.resourceURL]
        for base in candidates {
            guard let url = base?.appendingPathComponent("RecapShellPlugin.bundle"),
                  let bundle = Bundle(url: url), bundle.load(),
                  let cls = bundle.classNamed("RSPStatusItemHost") else { continue }
            return cls as? StatusItemHosting.Type
        }
        return nil
    }()

    static var isAvailable: Bool { host != nil }

    static func install(image: Data, tooltip: String,
                        onCommand: @escaping (String) -> Void,
                        onPrimaryClick: @escaping () -> Void) {
        host?.install(image, tooltip: tooltip, onCommand: onCommand, onPrimaryClick: onPrimaryClick)
    }

    static func setMenu(_ items: [[String: String]]) {
        host?.setMenu(items)
    }

    static func setProgress(_ fraction: Double, active: Bool, tooltip: String) {
        host?.setProgress(fraction, active: active, tooltip: tooltip)
    }

    static func remove() {
        host?.remove()
    }

    static func terminate() {
        host?.terminate()
    }
}

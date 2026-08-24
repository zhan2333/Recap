//
//  RecapTheme.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import UIKit

// Visual tokens ported from RecapDesignSite/public/designs/recap-tokens.css (Evidence Thread direction)
enum RecapTheme {

    // MARK: - Core palette (light / dark from tokens css)

    static let canvas = dyn(0xF2F0E9, 0x1F1D1A)
    static let surface = dyn(0xECE9DF, 0x27241F)
    static let paper = dyn(0xFAF9F5, 0x2E2A25)
    static let ink = dyn(0x2F2D29, 0xF1ECE3)
    static let time = dyn(0x6B655C, 0xC4B9AA)
    static let signal = dyn(0xD97757, 0xE78F70)
    static let complete = dyn(0x63715F, 0xA6B19A)
    static let error = dyn(0xB84B43, 0xE17B70)
    static let muted = dyn(0x57534D, 0xD1CABF)
    static let quiet = dyn(0x6B675F, 0xB8B1A7)
    static let signalText = dyn(0x9A452F, 0xF0A487)

    // MARK: - Derived mixes (color-mix equivalents)

    static let line = blend(ink, into: paper, amount: 0.13)
    static let hover = ink.withAlphaComponent(0.06)
    static let selection = ink.withAlphaComponent(0.09)
    static let timeSoft = blend(time, into: paper, amount: 0.09)
    static let signalSoft = blend(signal, into: paper, amount: 0.11)
    static let completeSoft = blend(complete, into: paper, amount: 0.10)
    static let errorSoft = blend(error, into: paper, amount: 0.10)
    static let markedRow = signal.withAlphaComponent(0.07)
    static let markedRowFocused = signal.withAlphaComponent(0.12)
    static let metaBar = blend(surface, into: paper, amount: 0.44)
    static let notesPane = blend(surface, into: paper, amount: 0.54)

    // MARK: - Type

    // Editorial serif: New York for latin, Songti SC cascade for CJK
    static func display(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        let songti = UIFontDescriptor(fontAttributes: [.family: "Songti SC"])
        return UIFont(descriptor: serif.addingAttributes([.cascadeList: [songti]]), size: size)
    }

    // SF Mono, timecodes only.
    static func mono(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func body(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    // MARK: - Metrics

    static let radiusXS: CGFloat = 5
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 8
    static let radiusRow: CGFloat = 10
    static let notesWidth: CGFloat = 260
    static let railWidth: CGFloat = 32
    static let timeColumnWidth: CGFloat = 78

    // MARK: - Helpers

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? Self.hex(dark) : Self.hex(light)
        }
    }

    private static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    // color-mix(in srgb, top amount%, base)
    private static func blend(_ top: UIColor, into base: UIColor, amount: CGFloat) -> UIColor {
        UIColor { traits in
            var (tr, tg, tb, ta): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            top.resolvedColor(with: traits).getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            base.resolvedColor(with: traits).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            return UIColor(
                red: tr * amount + br * (1 - amount),
                green: tg * amount + bg * (1 - amount),
                blue: tb * amount + bb * (1 - amount),
                alpha: 1
            )
        }
    }
}

//
//  BrandToolbarDelegate.swift
//  Recap
//
//  Created by Rio on 9/21/26.
//

#if targetEnvironment(macCatalyst)
import UIKit
import AppKit

// Window toolbar controls the course and lecture columns together.
final class BrandToolbarDelegate: NSObject, NSToolbarDelegate {

    static let brandID = NSToolbarItem.Identifier("recapBrandMark")
    static let sidebarsID = NSToolbarItem.Identifier("recapToggleSidebars")
    weak var splitViewController: UISplitViewController?

    private static var brandImage: UIImage? = {
        guard let image = UIImage(named: "recap-r-mark") else { return nil }
        let height: CGFloat = 19
        let size = CGSize(width: height * image.size.width / image.size.height, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysTemplate)
    }()

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarsID, Self.brandID, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        if itemIdentifier == Self.sidebarsID {
            item.image = UIImage(systemName: "sidebar.left")
            item.label = String(localized: "切换课程与讲次边栏")
            item.toolTip = item.label
            item.target = self
            item.action = #selector(toggleSidebars)
        } else if itemIdentifier == Self.brandID {
            item.image = Self.brandImage
            item.label = "Recap"
            item.isBordered = false
        } else {
            return nil
        }
        item.isNavigational = true
        item.autovalidates = false
        return item
    }

    @objc private func toggleSidebars() {
        guard let split = splitViewController, !split.isCollapsed else { return }
        split.preferredDisplayMode = split.displayMode == .secondaryOnly ? .twoBesideSecondary : .secondaryOnly
    }
}
#endif

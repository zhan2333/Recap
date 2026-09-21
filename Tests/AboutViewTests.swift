//
//  AboutViewTests.swift
//  RecapPDFTests
//
//  Created by Rio on 9/21/26.
//

#if canImport(UIKit)
import UIKit
import XCTest
@testable import RecapPDFTestHost

@MainActor
final class AboutViewTests: XCTestCase {

    override func tearDown() async throws {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.first?.rootViewController = UIViewController()
        }
    }

    func testAboutDisplaysMarketingVersionWithoutBuildNumber() async throws {
        let version = "2.5.1"
        let controller = AboutViewController(version: version, checkForUpdates: { nil }, installUpdate: {})
        try await present(controller)

        let text = labels(in: controller).compactMap(\.text)
        XCTAssertTrue(text.contains(String(localized: "版本 \(version)")))
        XCTAssertFalse(text.contains { $0.contains("(1)") || $0.contains("（1）") })
        XCTAssertTrue(try button(String(localized: "检查更新"), in: controller).isEnabled)
    }

    func testCheckShowsLatestVersionWithoutOfferingInstallation() async throws {
        var checks = 0
        var installations = 0
        let controller = AboutViewController(version: "2.5.1", checkForUpdates: {
            checks += 1
            return nil
        }, installUpdate: { installations += 1 })
        try await present(controller)
        let checkButton = try button(String(localized: "检查更新"), in: controller)

        checkButton.sendActions(for: .touchUpInside)
        XCTAssertFalse(checkButton.isEnabled)
        XCTAssertTrue(hasText(String(localized: "正在检查更新…"), in: controller))
        let finished = await eventually { self.hasText(String(localized: "Recap 已是最新版本。"), in: controller) }

        XCTAssertTrue(finished)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(installations, 0)
        XCTAssertTrue(checkButton.isEnabled)
        XCTAssertTrue(try button(String(localized: "下载并更新"), in: controller).isHidden)
    }

    func testAvailableVersionOffersInstallationAndDismissesBeforeInstalling() async throws {
        let availableVersion = "2.5.2"
        var installations = 0
        var dismissedBeforeInstalling = false
        let presenter = UIViewController()
        let controller = AboutViewController(version: "2.5.1", checkForUpdates: { availableVersion }, installUpdate: {
            installations += 1
            dismissedBeforeInstalling = presenter.presentedViewController == nil
        })
        try await present(controller, from: presenter)

        try button(String(localized: "检查更新"), in: controller).sendActions(for: .touchUpInside)
        let finished = await eventually {
            self.hasText(String(localized: "新版本 \(availableVersion) 已可用。"), in: controller)
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(installations, 0)
        let installButton = try button(String(localized: "下载并更新"), in: controller)
        XCTAssertFalse(installButton.isHidden)
        XCTAssertTrue(installButton.isEnabled)

        installButton.sendActions(for: .touchUpInside)
        let installed = await eventually { installations == 1 }
        XCTAssertTrue(installed)
        XCTAssertTrue(dismissedBeforeInstalling)
        XCTAssertNil(controller.view.window)
    }

    func testFailedCheckCanRetrySuccessfully() async throws {
        var checks = 0
        let controller = AboutViewController(version: "2.5.1", checkForUpdates: {
            checks += 1
            if checks == 1 { throw URLError(.notConnectedToInternet) }
            return nil
        }, installUpdate: { XCTFail("Checking for updates must not install an update.") })
        try await present(controller)

        try button(String(localized: "检查更新"), in: controller).sendActions(for: .touchUpInside)
        let failed = await eventually {
            self.hasText(String(localized: "暂时无法检查更新，请稍后重试。"), in: controller)
        }
        XCTAssertTrue(failed)
        let retryButton = try button(String(localized: "重试"), in: controller)
        XCTAssertTrue(retryButton.isEnabled)
        XCTAssertTrue(try button(String(localized: "下载并更新"), in: controller).isHidden)

        retryButton.sendActions(for: .touchUpInside)
        let recovered = await eventually { self.hasText(String(localized: "Recap 已是最新版本。"), in: controller) }
        XCTAssertTrue(recovered)
        XCTAssertEqual(checks, 2)
        XCTAssertTrue(try button(String(localized: "检查更新"), in: controller).isEnabled)
    }

    func testClosingDuringCheckIgnoresDelayedResultAndDoesNotInstall() async throws {
        var pendingCheck: CheckedContinuation<String?, any Error>?
        defer { pendingCheck?.resume(returning: nil) }
        var checkReturned = false
        var installations = 0
        let controller = AboutViewController(version: "2.5.1", checkForUpdates: {
            let result = try await withCheckedThrowingContinuation { pendingCheck = $0 }
            checkReturned = true
            return result
        }, installUpdate: { installations += 1 })
        try await present(controller)
        try button(String(localized: "检查更新"), in: controller).sendActions(for: .touchUpInside)
        let started = await eventually { pendingCheck != nil }
        XCTAssertTrue(started)
        let pending = try XCTUnwrap(pendingCheck)
        let textBeforeClosing = labels(in: controller).compactMap(\.text)
        let closeButton = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == String(localized: "关闭")
        })

        closeButton.sendActions(for: .touchUpInside)
        let closed = await eventually { controller.view.window == nil }
        XCTAssertTrue(closed)
        pending.resume(returning: "2.5.2")
        pendingCheck = nil
        let returned = await eventually { checkReturned }
        XCTAssertTrue(returned)
        await Task.yield()

        XCTAssertEqual(labels(in: controller).compactMap(\.text), textBeforeClosing)
        XCTAssertTrue(try button(String(localized: "下载并更新"), in: controller).isHidden)
        XCTAssertEqual(installations, 0)
    }

    // MARK: - Helpers

    private func present(_ controller: AboutViewController, from presentingController: UIViewController? = nil) async throws {
        let presenter = presentingController ?? UIViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first)
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.loadViewIfNeeded()
        presenter.view.layoutIfNeeded()
        let ready = await eventually { presenter.view.window != nil }
        XCTAssertTrue(ready)
        presenter.present(controller, animated: false)
        let presented = await eventually { controller.viewIfLoaded?.window != nil }
        XCTAssertTrue(presented)
        controller.view.layoutIfNeeded()
    }

    private func button(_ title: String, in controller: UIViewController) throws -> UIButton {
        try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UIButton }.first {
            $0.configuration?.title == title || $0.title(for: .normal) == title
        }, "Missing button: \(title)")
    }

    private func labels(in controller: UIViewController) -> [UILabel] {
        descendants(of: controller.view).compactMap { $0 as? UILabel }
    }

    private func hasText(_ text: String, in controller: UIViewController) -> Bool {
        labels(in: controller).contains { $0.text == text }
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}
#endif

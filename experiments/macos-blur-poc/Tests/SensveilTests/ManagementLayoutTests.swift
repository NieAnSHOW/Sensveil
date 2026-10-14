import AppKit
import SwiftUI
import XCTest
@testable import Sensveil

final class ManagementLayoutTests: XCTestCase {
    @MainActor
    func testExpandedEnglishSettingsFitNarrowWindowAndScrollWithinIt() throws {
        _ = NSApplication.shared
        let previousLanguage = LanguagePreferences.shared.selection
        LanguagePreferences.shared.selection = .english
        defer { LanguagePreferences.shared.selection = previousLanguage }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        var configuration = ProtectionConfiguration()
        configuration.schedule.mode = .specified
        try store.save(configuration)
        let controller = SensveilController(
            configurationStore: store,
            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }
        let navigation = ManagementNavigation()
        navigation.selection = .settings
        let root = ManagementView(controller: controller, permissions: PermissionCoordinator(), navigation: navigation)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 780, height: 560)
        // The window is never shown. These are actual native layouts produced
        // by SwiftUI, including combined effects and schedule, and sidebar footer.
        for height in [CGFloat(560), CGFloat(700)] {
            window.setContentSize(NSSize(width: 780, height: height))
            settleLayout(window)
            let content = try XCTUnwrap(window.contentView)
            XCTAssertFalse(descendants(of: content).contains { $0 is NSSplitView }, "The fixed sidebar has no draggable split")
            let scrollViews = descendants(of: content).compactMap { $0 as? NSScrollView }
            XCTAssertGreaterThanOrEqual(scrollViews.count, 2, "The sidebar and settings retain their native scrolling")
            XCTAssertTrue(scrollViews.contains { abs($0.bounds.width - 210) <= 1 }, "The sidebar retains its fixed width")
            for scroll in scrollViews {
                XCTAssertLessThanOrEqual(scroll.bounds.height, content.bounds.height + 1)
                let bounds = scroll.convert(scroll.bounds, to: content)
                XCTAssertGreaterThanOrEqual(bounds.minY, content.bounds.minY - 1)
                XCTAssertLessThanOrEqual(bounds.maxY, content.bounds.maxY + 1)
            }
            XCTAssertTrue(scrollViews.contains {
                ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 1
            }, "The expanded settings must scroll inside the available window")
        }
    }

    @MainActor
    func testProductionWindowIsFixedAndTitlebarActionTracksPauseLanguageAndNavigation() throws {
        _ = NSApplication.shared
        let previousLanguage = LanguagePreferences.shared.selection
        LanguagePreferences.shared.selection = .english
        defer { LanguagePreferences.shared.selection = previousLanguage }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        var configuration = ProtectionConfiguration()
        configuration.schedule.mode = .specified
        try store.save(configuration)
        let controller = SensveilController(configurationStore: store,
                                            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }
        let navigation = ManagementNavigation()
        let window = ManagementWindow(controller: controller, permissions: PermissionCoordinator(), navigation: navigation)
        settleLayout(window)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 920, height: 700))
        XCTAssertEqual(window.contentMaxSize, window.contentMinSize)
        XCTAssertEqual(window.contentView?.bounds.size, window.contentMinSize)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)).isEnabled)
        XCTAssertEqual(window.frameAutosaveName, "")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)

        let accessory = try XCTUnwrap(window.titlebarAccessoryViewControllers.first)
        XCTAssertEqual(accessory.layoutAttribute, .right)
        let button = try XCTUnwrap(descendants(of: accessory.view).compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(button.title, "Pause Protection")
        XCTAssertEqual(button.toolTip, "Temporarily stop protection for all apps")
        let bounds = button.convert(button.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(bounds.minY, window.contentLayoutRect.maxY - 1, "The action belongs to the native titlebar")
        XCTAssertLessThanOrEqual(bounds.maxY, window.frame.height + 1)
        XCTAssertGreaterThan(bounds.minX, window.frame.width - 200)
        XCTAssertTrue(button.isEnabled)
        button.performClick(nil)
        XCTAssertTrue(controller.configuration.isGloballyPaused)
        XCTAssertTrue(try store.load().isGloballyPaused)
        XCTAssertEqual(button.title, "Resume Protection")
        controller.setGlobalPause(false)
        XCTAssertEqual(button.title, "Pause Protection", "Updates from the menu/controller also reach the titlebar")
        LanguagePreferences.shared.selection = .chinese
        XCTAssertEqual(button.title, "暂停保护")
        XCTAssertEqual(button.toolTip, "暂时停止所有应用的保护")
        for page in ManagementPage.allCases {
            navigation.selection = page
            settleLayout(window)
            XCTAssertTrue(button.window === window)
            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(window.contentView?.bounds.size, NSSize(width: 920, height: 700))
        }
    }

    @MainActor
    func testTitlebarPauseIsDisabledWhenSavedConfigurationCannotBeRead() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(appSupportDirectory: directory)
        let original = Data("not-json".utf8)
        try original.write(to: store.configURL)
        let controller = SensveilController(configurationStore: store,
                                            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }
        let window = ManagementWindow(controller: controller, permissions: PermissionCoordinator(), navigation: ManagementNavigation())
        let accessory = try XCTUnwrap(window.titlebarAccessoryViewControllers.first)
        let button = try XCTUnwrap(descendants(of: accessory.view).compactMap { $0 as? NSButton }.first)
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.toolTip, L10n.text("无法读取本地配置，当前设置只读。请检查配置文件后重新启动 Sensveil。"))
        button.performClick(nil)
        XCTAssertFalse(controller.configuration.isGloballyPaused)
        XCTAssertEqual(try Data(contentsOf: store.configURL), original)
    }

    @MainActor
    private func settleLayout(_ window: NSWindow) {
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

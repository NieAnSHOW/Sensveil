import AppKit
import SwiftUI
import XCTest
@testable import Sensveil

final class ManagementLayoutTests: XCTestCase {
    @MainActor
    func testExpandedEnglishScheduleFitsNarrowWindowAndScrollsWithinIt() throws {
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
        navigation.selection = .schedule
        let root = ManagementView(controller: controller, permissions: PermissionCoordinator(), navigation: navigation)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 780, height: 560)
        // The window is never shown. These are actual native layouts produced
        // by SwiftUI, including the long English schedule and sidebar footer.
        for height in [CGFloat(560), CGFloat(700)] {
            window.setContentSize(NSSize(width: 780, height: height))
            settleLayout(window)
            let content = try XCTUnwrap(window.contentView)
            let split = try XCTUnwrap(descendants(of: content).compactMap { $0 as? NSSplitView }.first)
            let splitBounds = split.convert(split.bounds, to: content)
            // Before the fix the split extended above and below this viewport,
            // cutting off the page header, pause action, About and save buttons.
            XCTAssertGreaterThanOrEqual(splitBounds.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(splitBounds.maxY, content.bounds.maxY + 1)
            let scrollViews = descendants(of: split).compactMap { $0 as? NSScrollView }
            XCTAssertGreaterThanOrEqual(scrollViews.count, 2, "The sidebar and schedule retain their native scrolling")
            for scroll in scrollViews {
                XCTAssertLessThanOrEqual(scroll.bounds.height, content.bounds.height + 1)
            }
            XCTAssertTrue(scrollViews.contains {
                ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 1
            }, "The expanded schedule must scroll inside the available window rather than enlarge the split")
        }
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

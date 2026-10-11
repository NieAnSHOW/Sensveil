import AppKit
import SwiftUI

@MainActor
public final class SensveilAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    public let controller: SensveilController
    public let permissions: PermissionCoordinator
    private var statusItem: NSStatusItem!
    private var managementWindow: NSWindow?

    public init(controller: SensveilController = SensveilController(), permissions: PermissionCoordinator = PermissionCoordinator()) {
        self.controller = controller; self.permissions = permissions
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Sensveil")
        statusItem.button?.toolTip = "Sensveil"
        rebuildMenu()
        permissions.startPolling()
        openManagementWindow()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        permissions.stopPolling(); controller.stopProtection()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    }

    public func openManagementWindow() {
        let view = ManagementView(controller: controller, permissions: permissions)
        let hosting = NSHostingController(rootView: view)
        let window = managementWindow ?? NSWindow(contentViewController: hosting)
        window.contentViewController = hosting
        window.title = "Sensveil"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 720))
        window.contentMinSize = NSSize(width: 520, height: 660)
        window.center(); window.isReleasedWhenClosed = false
        managementWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "打开 Sensveil", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: controller.pauseActionTitle, action: #selector(togglePauseFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Sensveil", action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(togglePauseFromMenu) })?.title = controller.pauseActionTitle
        menu.items.first(where: { $0.action == #selector(togglePauseFromMenu) })?.isEnabled = !controller.isConfigurationReadOnly
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(togglePauseFromMenu) || !controller.isConfigurationReadOnly
    }

    @objc private func openFromMenu() { openManagementWindow() }
    @objc private func togglePauseFromMenu() { controller.performMenuAction(.togglePause, openManagement: {}, quit: {}); rebuildMenu() }
    @objc private func quitFromMenu() { controller.performMenuAction(.quit, openManagement: {}, quit: { NSApp.terminate(nil) }) }
}

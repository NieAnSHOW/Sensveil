import AppKit
import SwiftUI

@MainActor
public final class SensveilAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    public let controller: SensveilController
    public let permissions: PermissionCoordinator
    private var statusItem: NSStatusItem!
    private var managementWindow: NSWindow?
    private let navigation = ManagementNavigation()

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
        installApplicationMenu()
        permissions.startPolling()
        openManagementWindow()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        permissions.stopPolling(); controller.stopProtection()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    }

    public func openManagementWindow() {
        let window: NSWindow
        if let existing = managementWindow {
            window = existing
        } else {
            let view = ManagementView(controller: controller, permissions: permissions, navigation: navigation)
            window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Sensveil"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 920, height: 700))
            window.contentMinSize = NSSize(width: 780, height: 560)
            window.center()
            window.setFrameAutosaveName("SensveilManagementWindow")
            window.isReleasedWhenClosed = false
            managementWindow = window
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "打开 Sensveil", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(withTitle: "关于 Sensveil", action: #selector(openAboutFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: controller.pauseActionTitle, action: #selector(togglePauseFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Sensveil", action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(title: "Sensveil", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "Sensveil")
        applicationMenu.addItem(withTitle: "关于 Sensveil", action: #selector(openAboutFromMenu), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "退出 Sensveil", action: #selector(quitFromMenu), keyEquivalent: "q")
        applicationMenu.items.forEach { $0.target = self }
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(togglePauseFromMenu) })?.title = controller.pauseActionTitle
        menu.items.first(where: { $0.action == #selector(togglePauseFromMenu) })?.isEnabled = !controller.isConfigurationReadOnly
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(togglePauseFromMenu) || !controller.isConfigurationReadOnly
    }

    @objc private func openSettingsFromMenu() {
        navigation.selection = .general
        openManagementWindow()
    }
    @objc private func openAboutFromMenu() {
        navigation.selection = .about
        openManagementWindow()
    }
    @objc private func openFromMenu() { openManagementWindow() }
    @objc private func togglePauseFromMenu() { controller.performMenuAction(.togglePause, openManagement: {}, quit: {}); rebuildMenu() }
    @objc private func quitFromMenu() { controller.performMenuAction(.quit, openManagement: {}, quit: { NSApp.terminate(nil) }) }
}

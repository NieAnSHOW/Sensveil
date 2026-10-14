import AppKit
import Combine
import SwiftUI

@MainActor
public final class SensveilAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    public let controller: SensveilController
    public let permissions: PermissionCoordinator
    private var statusItem: NSStatusItem!
    private(set) var statusMenu: NSMenu?
    private var languageSubscription: AnyCancellable?
    private var hasApplicationMenu = false
    private var managementWindow: NSWindow?
    private let navigation = ManagementNavigation()

    public init(controller: SensveilController = SensveilController(), permissions: PermissionCoordinator = PermissionCoordinator()) {
        self.controller = controller; self.permissions = permissions
        super.init()
        languageSubscription = LanguagePreferences.shared.changes.dropFirst().sink { [weak self] language in
            guard let self else { return }
            if self.statusMenu != nil { self.rebuildMenu(language: language) }
            if self.hasApplicationMenu { self.installApplicationMenu(language: language) }
        }
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
            window = ManagementWindow(contentViewController: NSHostingController(rootView: view))
            // Retain the title for accessibility and window identity while letting
            // native content/material extend behind the transparent title area.
            window.title = "Sensveil"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unified
            window.collectionBehavior.insert(.fullScreenPrimary)
            // ManagementWindow routes only the system's reserved title area
            // to dragging; the content area keeps its own mouse handling.
            window.isMovableByWindowBackground = false
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

    public func rebuildMenu(language: AppLanguage = L10n.language) {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: L10n.text("打开 Sensveil", language: language), action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("设置…", language: language), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(withTitle: L10n.text("关于 Sensveil", language: language), action: #selector(openAboutFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text(controller.pauseActionTitle, language: language), action: #selector(togglePauseFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("退出 Sensveil", language: language), action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusMenu = menu
        statusItem?.menu = menu
    }

    func installApplicationMenu(language: AppLanguage = L10n.language) {
        hasApplicationMenu = true
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(title: "Sensveil", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "Sensveil")
        applicationMenu.addItem(withTitle: L10n.text("关于 Sensveil", language: language), action: #selector(openAboutFromMenu), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: L10n.text("设置…", language: language), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: L10n.text("退出 Sensveil", language: language), action: #selector(quitFromMenu), keyEquivalent: "q")
        applicationMenu.items.forEach { $0.target = self }
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(title: L10n.text("编辑", language: language), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L10n.text("编辑", language: language))
        editMenu.addItem(withTitle: L10n.text("撤销", language: language), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L10n.text("重做", language: language), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.text("剪切", language: language), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.text("复制", language: language), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("粘贴", language: language), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.text("全选", language: language), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(togglePauseFromMenu) })?.title = controller.localizedPauseActionTitle
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

/// A transparent titlebar forwards clicks into the full-size hosting view.
/// Restore window-server dragging only in AppKit's reserved title area.
@MainActor
private final class ManagementWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           event.clickCount == 1,
           !styleMask.contains(.fullScreen),
           attachedSheet == nil,
           isMovable,
           let contentView {
            let point = event.locationInWindow
            let contentBounds = contentView.convert(contentView.bounds, to: nil)
            // contentLayoutRect is supplied in window coordinates and updates
            // with system titlebar, toolbar, resizing and fullscreen geometry.
            let isTitleArea = contentBounds.contains(point) && point.y >= contentLayoutRect.maxY
            let isWindowButton = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].contains { type in
                guard let button = standardWindowButton(type) else { return false }
                return button.convert(button.bounds, to: nil).contains(point)
            }
            if isTitleArea && !isWindowButton {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }
}

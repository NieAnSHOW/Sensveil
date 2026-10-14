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
            window = ManagementWindow(controller: controller, permissions: permissions, navigation: navigation)
            window.center()
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

@MainActor
final class ManagementWindow: NSWindow {
    static let contentSize = NSSize(width: 920, height: 700)
    private let pauseButton = NSButton()
    private var controller: SensveilController?
    private var pauseSubscription: AnyCancellable?

    convenience init(controller: SensveilController, permissions: PermissionCoordinator, navigation: ManagementNavigation) {
        let root = ManagementView(controller: controller, permissions: permissions, navigation: navigation)
            .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        let hostingController = NSHostingController(rootView: root)
        // Match SwiftUI's generated window constraints to AppKit's fixed size.
        hostingController.sizingOptions = [.minSize, .maxSize]
        self.init(contentViewController: hostingController)
        self.controller = controller
        title = "Sensveil"
        styleMask = [.titled, .closable, .miniaturizable]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        collectionBehavior.insert(.fullScreenNone)
        standardWindowButton(.zoomButton)?.isEnabled = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        contentMinSize = Self.contentSize
        contentMaxSize = Self.contentSize
        setContentSize(Self.contentSize)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 176, height: 28))
        pauseButton.bezelStyle = .rounded
        pauseButton.controlSize = .small
        pauseButton.imagePosition = .imageLeading
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        accessory.view.addSubview(pauseButton)
        NSLayoutConstraint.activate([
            pauseButton.widthAnchor.constraint(equalToConstant: 156),
            pauseButton.trailingAnchor.constraint(equalTo: accessory.view.trailingAnchor, constant: -12),
            pauseButton.centerYAnchor.constraint(equalTo: accessory.view.centerYAnchor)
        ])
        addTitlebarAccessoryViewController(accessory)

        // Use incoming published values: @Published emits before its property changes.
        pauseSubscription = controller.$configuration
            .combineLatest(controller.$configurationLoadFailed, LanguagePreferences.shared.changes)
            .sink { [weak self] configuration, readOnly, language in
                self?.updatePauseAction(paused: configuration.isGloballyPaused, readOnly: readOnly, language: language)
            }
    }

    private func updatePauseAction(paused: Bool, readOnly: Bool, language: AppLanguage) {
        let title = L10n.text(paused ? "恢复保护" : "暂停保护", language: language)
        pauseButton.title = title
        pauseButton.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        pauseButton.setAccessibilityLabel(title)
        pauseButton.isEnabled = !readOnly
        let help = readOnly
            ? "无法读取本地配置，当前设置只读。请检查配置文件后重新启动 Sensveil。"
            : (paused ? "恢复所有应用的保护" : "暂时停止所有应用的保护")
        pauseButton.toolTip = L10n.text(help, language: language)
    }

    @objc private func togglePause() {
        guard let controller else { return }
        controller.setGlobalPause(!controller.configuration.isGloballyPaused)
    }
}

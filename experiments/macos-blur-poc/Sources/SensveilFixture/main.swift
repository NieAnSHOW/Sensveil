import AppKit
import SwiftUI

@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var sheets: [Int: NSWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        reopenWindows()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func reopenWindows() {
        for index in 0..<3 {
            if let existing = windows.first(where: { $0.identifier?.rawValue == "fixture-\(index)" }) {
                existing.deminiaturize(nil)
                existing.makeKeyAndOrderFront(nil)
            } else {
                createWindow(index: index, duplicate: false)
            }
        }
    }

    @objc func createDuplicates() {
        createWindow(index: 3, duplicate: true)
        createWindow(index: 4, duplicate: true)
    }

    private func createWindow(index: Int, duplicate: Bool) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = duplicate ? 100.0 : CGFloat(index) * 55.0
        let origin = NSPoint(x: visible.minX + 60 + offset, y: max(visible.minY + 30, visible.maxY - 620 - offset))
        let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 640, height: 560)),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = duplicate ? "Synthetic Duplicate \(windows.count + 1)" : "Synthetic Fixture \(index + 1)"
        window.identifier = NSUserInterfaceItemIdentifier(duplicate ? "duplicate-\(windows.count)" : "fixture-\(index)")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 520)
        window.contentView = NSHostingView(rootView: FixtureView(
            title: window.title,
            move: { [weak window] in
                guard let window else { return }
                window.setFrameOrigin(NSPoint(x: window.frame.minX + 35, y: window.frame.minY + 25))
            },
            resize: { [weak window] in
                guard let window else { return }
                let size = window.frame.size
                let delta: CGFloat = size.width > 740 ? -100 : 50
                window.setFrame(NSRect(origin: window.frame.origin,
                                       size: NSSize(width: max(window.minSize.width, size.width + delta),
                                                    height: max(window.minSize.height, size.height + delta))), display: true)
            },
            minimize: { [weak window] in window?.miniaturize(nil) },
            sheet: { [weak self, weak window] in
                guard let self, let window else { return }
                self.openSheet(on: window)
            },
            reopen: { [weak self] in self?.reopenWindows() },
            duplicates: { [weak self] in self?.createDuplicates() }))
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func openSheet(on parent: NSWindow) {
        guard parent.attachedSheet == nil else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Synthetic Sheet"
        sheet.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 20) {
            Text("SYNTHETIC TEST DATA").font(.headline).foregroundStyle(.red)
            Text("Sheet sample: 000-0000-0001").font(.title3)
            Button("Close sheet") { [weak self, weak parent, weak sheet] in
                guard let parent, let sheet else { return }
                parent.endSheet(sheet)
                self?.sheets.removeValue(forKey: parent.windowNumber)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        sheets[parent.windowNumber] = sheet
        parent.beginSheet(sheet)
    }

    private func createMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sensveil Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let windowsItem = NSMenuItem()
        let windowsMenu = NSMenu(title: "Fixture")
        let reopen = NSMenuItem(title: "Reopen three windows", action: #selector(reopenWindows), keyEquivalent: "r")
        reopen.target = self
        windowsMenu.addItem(reopen)
        let duplicates = NSMenuItem(title: "Create overlapping duplicates", action: #selector(createDuplicates), keyEquivalent: "d")
        duplicates.target = self
        windowsMenu.addItem(duplicates)
        windowsItem.submenu = windowsMenu
        mainMenu.addItem(windowsItem)
        NSApp.mainMenu = mainMenu
    }
}

private struct FixtureView: View {
    let title: String
    let move: () -> Void
    let resize: () -> Void
    let minimize: () -> Void
    let sheet: () -> Void
    let reopen: () -> Void
    let duplicates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "testtube.2")
                Text("SYNTHETIC TEST DATA").font(.headline)
                Spacer()
            }.foregroundStyle(.red)
            Text(title).font(.title2.weight(.semibold))
            Divider()
            Text("测试用户甲 / SAMPLE ACCOUNT").font(.system(size: 24))
            Text("000-0000-0001 · SAMPLE ONLY").font(.system(size: 12))
            Text("12 pt: Fictional balance, no real account").font(.system(size: 12))
            Text("24 pt: SAMPLE ACCOUNT").font(.system(size: 24))
            Text("48 pt: $12,345").font(.system(size: 48)).lineLimit(1)
            Divider()
            HStack(spacing: 12) {
                Button(action: move) { Label("Move", systemImage: "arrow.up.right") }
                Button(action: resize) { Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right") }
                Button(action: minimize) { Label("Minimize", systemImage: "minus") }
                Button("Open sheet", action: sheet)
            }
            HStack(spacing: 12) {
                Button("Reopen three windows", action: reopen)
                Button("Create overlapping duplicates", action: duplicates)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

let app = NSApplication.shared
let delegate = FixtureAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

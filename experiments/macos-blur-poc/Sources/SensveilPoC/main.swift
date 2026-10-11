import AppKit

@MainActor
final class PoCAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PoCController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PoCController()
        self.controller = controller
        controller.showDiagnostics()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
}

let app = NSApplication.shared
let delegate = PoCAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

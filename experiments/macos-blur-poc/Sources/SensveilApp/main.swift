import AppKit
import Sensveil

let app = NSApplication.shared
if CommandLine.arguments.contains("--validate-guard-label") {
    app.setActivationPolicy(.accessory)
    Task { exit(await GuardLabelValidation.run()) }
    app.run()
} else {
    let delegate = SensveilAppDelegate()
    app.delegate = delegate
    app.run()
}

import AppKit
import PoCCore

struct FocusEvent {
    enum Kind { case startup, activation, launch, termination, screens, space, sleep, wake, windows, permissions }
    let receivedAt: ContinuousClock.Instant
    let frontmostPID: Int32?
    let kind: Kind
    let terminatedPID: Int32?
}

@MainActor
final class FocusMonitor: NSObject {
    private let foregroundPID: () -> Int32?
    private var onEvent: ((FocusEvent) -> Void)?

    init(foregroundPID: @escaping () -> Int32? = {
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else { return nil }
        return app.processIdentifier
    }) { self.foregroundPID = foregroundPID }

    func start(onEvent: @escaping (FocusEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        publish(kind: .startup)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(self, selector: #selector(receive(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(receive(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        onEvent = nil
    }

    /// Focus only requires a live PID. launchDate is optional for system apps
    /// such as Finder and remains required by the separate target tracker.
    func currentFrontmostPID() -> Int32? {
        guard let pid = foregroundPID(), pid > 0 else { return nil }
        return pid
    }

    @objc private func receive(_ notification: Notification) {
        let kind: FocusEvent.Kind
        var terminatedPID: Int32?
        switch notification.name {
        case NSWorkspace.didActivateApplicationNotification: kind = .activation
        case NSWorkspace.didLaunchApplicationNotification: kind = .launch
        case NSWorkspace.didTerminateApplicationNotification:
            kind = .termination
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                terminatedPID = app.processIdentifier
            }
        case NSWorkspace.activeSpaceDidChangeNotification: kind = .space
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification: kind = .sleep
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification: kind = .wake
        default: kind = .screens
        }
        publish(kind: kind, terminatedPID: terminatedPID)
    }

    private func publish(kind: FocusEvent.Kind, terminatedPID: Int32? = nil) {
        onEvent?(FocusEvent(receivedAt: .now, frontmostPID: currentFrontmostPID(), kind: kind, terminatedPID: terminatedPID))
    }
}

@MainActor
protocol FocusMonitoring: AnyObject {
    func start(onEvent: @escaping (FocusEvent) -> Void)
    func stop()
    func currentFrontmostPID() -> Int32?
}

extension FocusMonitor: FocusMonitoring {}

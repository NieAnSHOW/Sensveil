@preconcurrency import ApplicationServices
import PoCCore

@MainActor
final class PermissionCoordinator {
    func accessibilityStatus() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    @discardableResult
    func requestAccessibility() -> PermissionState {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return accessibilityStatus()
    }
}

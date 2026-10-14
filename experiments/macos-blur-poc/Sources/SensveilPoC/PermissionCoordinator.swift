@preconcurrency import ApplicationServices
import CoreGraphics
import PoCCore

@MainActor
final class PermissionCoordinator {
    static var accessibilityIsGranted: Bool { AXIsProcessTrusted() }

    func accessibilityStatus() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    @discardableResult
    func requestAccessibility() -> PermissionState {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return accessibilityStatus()
    }

    func screenCaptureStatus() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    @discardableResult
    func requestScreenCapture() -> PermissionState {
        _ = CGRequestScreenCaptureAccess()
        // Request can return before the user changes settings; always preflight again.
        return screenCaptureStatus()
    }
}

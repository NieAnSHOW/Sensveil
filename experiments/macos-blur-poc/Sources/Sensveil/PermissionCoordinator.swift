@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import PoCCore

@MainActor
public final class PermissionCoordinator: ObservableObject {
    @Published public private(set) var accessibility: PermissionState = .notGranted
    @Published public private(set) var screenRecording: PermissionState = .notGranted
    private var pollTask: Task<Void, Never>?

    public init() { refresh() }
    deinit { pollTask?.cancel() }

    public func refresh() {
        let currentAccessibility: PermissionState = AXIsProcessTrusted() ? .granted : .notGranted
        let currentScreenRecording: PermissionState = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        if accessibility != currentAccessibility { accessibility = currentAccessibility }
        if screenRecording != currentScreenRecording { screenRecording = currentScreenRecording }
    }

    @discardableResult public func requestAccessibility() -> PermissionState {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh(); return accessibility
    }

    @discardableResult public func requestScreenRecording() -> PermissionState {
        _ = CGRequestScreenCaptureAccess()
        refresh(); return screenRecording
    }

    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    public func stopPolling() { pollTask?.cancel(); pollTask = nil }
}

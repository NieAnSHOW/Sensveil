import Foundation
import CoreGraphics

/// A PID is meaningful only within the lifetime observed by the tracker.
public struct ProcessInstance: Hashable, Sendable {
    public let pid: Int32
    public let generation: UInt64

    public init(pid: Int32, generation: UInt64) {
        self.pid = pid
        self.generation = generation
    }
}

public struct WindowKey: Hashable, Sendable {
    public let process: ProcessInstance
    public let cgWindowID: UInt32

    public init(process: ProcessInstance, cgWindowID: UInt32) {
        self.process = process
        self.cgWindowID = cgWindowID
    }
}

public struct WindowCandidate: Equatable, Sendable {
    public let key: WindowKey
    public var bounds: CGRect
    public var isOnScreen: Bool
    public var layer: Int

    public init(key: WindowKey, bounds: CGRect, isOnScreen: Bool, layer: Int) {
        self.key = key
        self.bounds = bounds
        self.isOnScreen = isOnScreen
        self.layer = layer
    }

    var isEligible: Bool {
        isOnScreen && layer == 0 && bounds.isValidWindowRect
    }
}

public struct AXWindowCandidate: Equatable, Sendable {
    /// An index within one enumeration, never a persistent window identifier.
    public let token: Int
    public let process: ProcessInstance
    public let bounds: CGRect
    public let isMinimized: Bool

    public init(token: Int, process: ProcessInstance, bounds: CGRect, isMinimized: Bool) {
        self.token = token
        self.process = process
        self.bounds = bounds
        self.isMinimized = isMinimized
    }
}

public enum WindowMatch: Equatable, Sendable {
    case unique(WindowKey)
    case missing
    case ambiguous
}

public struct ScreenLayout: Equatable, Sendable {
    /// The menu-bar display's AppKit frame in global points.
    public let primaryScreenFrame: CGRect
    public let screenFrames: [CGRect]

    public init(primaryScreenFrame: CGRect, screenFrames: [CGRect]) {
        self.primaryScreenFrame = primaryScreenFrame
        self.screenFrames = screenFrames
    }
}

public enum PermissionState: Equatable, Sendable {
    case unknown
    case notGranted
    case granted
}

public enum OverlayIntent: Equatable, Sendable {
    case remove
    /// A request to the system adapter, not evidence of rendered protection.
    case attemptBlur
    case cannotProtect(reason: String)
}

public struct ProtectionInput: Sendable {
    public var frontmost: ProcessInstance?
    /// Current frontmost PID from NSWorkspace, even when launchDate is unavailable.
    public var frontmostPID: Int32?
    public var selected: Set<ProcessInstance>
    /// Only uniquely matched candidates should be supplied by the tracker.
    public var windows: [WindowCandidate]
    public var previousOverlayKeys: Set<WindowKey>
    /// All required permission preflights, including Accessibility.
    public var permissions: [PermissionState]
    public var isSuspended: Bool
    public var requiresRevalidation: Bool

    public init(frontmost: ProcessInstance?, frontmostPID: Int32? = nil, selected: Set<ProcessInstance>, windows: [WindowCandidate], previousOverlayKeys: Set<WindowKey>, permissions: [PermissionState], isSuspended: Bool, requiresRevalidation: Bool) {
        self.frontmost = frontmost
        self.frontmostPID = frontmostPID
        self.selected = selected
        self.windows = windows
        self.previousOverlayKeys = previousOverlayKeys
        self.permissions = permissions
        self.isSuspended = isSuspended
        self.requiresRevalidation = requiresRevalidation
    }
}

extension CGRect {
    var isValidWindowRect: Bool {
        !isNull && !isInfinite && width > 0 && height > 0 &&
            [origin.x, origin.y, width, height, minX, maxX, minY, maxY].allSatisfy(\.isFinite)
    }
}

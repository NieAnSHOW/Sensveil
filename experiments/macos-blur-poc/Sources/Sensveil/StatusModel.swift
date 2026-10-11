import Foundation

/// The user-visible protection state for one configured application (or the
/// aggregate state when more than one application is configured).
public enum ProtectionStatus: Equatable, Sendable {
    case notRunning
    case foreground
    case protected
    case partialFailure([String])
    case cannotProtect(String)
    case overFreeLimit
    case paused
}

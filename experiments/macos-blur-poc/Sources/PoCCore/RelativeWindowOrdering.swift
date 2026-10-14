import CoreGraphics

/// One front-to-back public CG window-list sample, without titles or owner names.
public struct OrderedWindowMetadata: Equatable, Sendable {
    public let windowID: UInt32
    public let bounds: CGRect?

    public init(windowID: UInt32, bounds: CGRect? = nil) {
        self.windowID = windowID
        self.bounds = bounds
    }
}

/// Metadata can reject a relative placement; an ok result never certifies pixels.
public enum RelativeWindowOrdering {
    public enum Classification: String, Equatable, Sendable {
        case ok, panelMissing, targetMissing, panelAfterTarget
        case protectionGeometryUnknown, interveningGeometryUnknown, unrelatedBetween

        public var failureReason: String? {
            switch self {
            case .ok: nil
            case .unrelatedBetween:
                "An unrelated window overlaps the overlay between overlay and target; relative layering failed"
            case .interveningGeometryUnknown, .protectionGeometryUnknown:
                "Public window geometry is unavailable; relative layering is unverified"
            default:
                "Relative overlay order was lost; cannot protect with this material candidate"
            }
        }
    }

    public enum Intersection: Equatable, Sendable {
        case empty, unknown, overlap(CGRect)
    }

    public struct InterveningWindow: Equatable, Sendable {
        public let metadata: OrderedWindowMetadata
        public let intersection: Intersection
    }

    public struct Result: Equatable, Sendable {
        public let classification: Classification
        public let interveningWindows: [InterveningWindow]
    }

    public static func evaluate(panelID: UInt32, targetID: UInt32, protectionBounds: CGRect,
                                windows: [OrderedWindowMetadata], ownOverlayIDs: Set<UInt32>) -> Result {
        guard let panelIndex = windows.firstIndex(where: { $0.windowID == panelID }) else {
            return Result(classification: .panelMissing, interveningWindows: [])
        }
        guard let targetIndex = windows.firstIndex(where: { $0.windowID == targetID }) else {
            return Result(classification: .targetMissing, interveningWindows: [])
        }
        guard panelIndex < targetIndex else {
            return Result(classification: .panelAfterTarget, interveningWindows: [])
        }
        guard protectionBounds.isValidWindowRect else {
            return Result(classification: .protectionGeometryUnknown, interveningWindows: [])
        }
        let intervening = windows[(panelIndex + 1)..<targetIndex].filter {
            !ownOverlayIDs.contains($0.windowID)
        }.map { item -> InterveningWindow in
            guard let bounds = item.bounds, bounds.isValidWindowRect else {
                return InterveningWindow(metadata: item, intersection: .unknown)
            }
            let overlap = protectionBounds.intersection(bounds)
            return InterveningWindow(metadata: item,
                                     intersection: overlap.isValidWindowRect ? .overlap(overlap) : .empty)
        }
        let classification: Classification
        if intervening.contains(where: { $0.intersection == .unknown }) {
            classification = .interveningGeometryUnknown
        } else {
            classification = intervening.contains {
                if case .overlap = $0.intersection { return true }
                return false
            } ? .unrelatedBetween : .ok
        }
        return Result(classification: classification, interveningWindows: intervening)
    }
}

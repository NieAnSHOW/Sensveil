import CoreGraphics

public struct RoundedOverlayGeometry: Equatable, Sendable {
    public static let padding: CGFloat = 8
    public static let preferredRadius: CGFloat = 20
    public let targetBounds: CGRect
    public let protectionBounds: CGRect
    public let radius: CGFloat

    public init?(targetBounds: CGRect) {
        guard targetBounds.isValidWindowRect else { return nil }
        let expanded = targetBounds.insetBy(dx: -Self.padding, dy: -Self.padding)
        guard expanded.isValidWindowRect,
              expanded.minX < targetBounds.minX, expanded.minY < targetBounds.minY,
              expanded.maxX > targetBounds.maxX, expanded.maxY > targetBounds.maxY else { return nil }
        self.targetBounds = targetBounds
        protectionBounds = expanded
        radius = min(Self.preferredRadius, expanded.width / 2, expanded.height / 2)
    }

    public static func maskPath(in bounds: CGRect) -> CGPath {
        let radius = max(0, min(preferredRadius, bounds.width / 2, bounds.height / 2))
        return CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

import Foundation
import CoreGraphics

public enum CoordinateTransform {
    /// CG/AX and AppKit use points. Display backing scale never enters this conversion.
    public static func appKitRect(from cgRect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(x: cgRect.origin.x,
               y: primaryScreenFrame.maxY - cgRect.maxY,
               width: cgRect.width,
               height: cgRect.height)
    }
}

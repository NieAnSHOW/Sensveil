import CoreGraphics
import XCTest
@testable import PoCCore

final class RoundedOverlayGeometryTests: XCTestCase {
    func testExpandsFullFrameIncludingTitleBarAndTracksMovementAndResize() throws {
        for target in [CGRect(x: 100, y: 50, width: 640, height: 592),
                       CGRect(x: -100.25, y: 75.5, width: 690.5, height: 642.25)] {
            let geometry = try XCTUnwrap(RoundedOverlayGeometry(targetBounds: target))
            XCTAssertEqual(geometry.targetBounds, target)
            XCTAssertEqual(geometry.protectionBounds, target.insetBy(dx: -8, dy: -8))
            XCTAssertEqual(geometry.radius, 20)
        }
    }

    func testInvalidAndUnrepresentableExpansionIsRejected() {
        for target in [CGRect.zero, .null, .infinite,
                       CGRect(x: CGFloat.nan, y: 0, width: 50, height: 50),
                       CGRect(x: 1e20, y: 0, width: 50, height: 50)] {
            XCTAssertNil(RoundedOverlayGeometry(targetBounds: target))
        }
    }

    func testTinyWindowsClampRadiusAndRemainInsideMask() throws {
        let geometry = try XCTUnwrap(RoundedOverlayGeometry(targetBounds: CGRect(x: 0, y: 0, width: 1, height: 2)))
        XCTAssertEqual(geometry.radius, 8.5)
        XCTAssertTrue(RoundedOverlayGeometry.maskPath(in: CGRect(origin: .zero, size: geometry.protectionBounds.size))
            .contains(CGPoint(x: 8, y: 8)))
    }

    func testRoundedMaskHasTransparentOuterCornersAndFullyCoversTargetPixels() throws {
        for size in [CGSize(width: 1, height: 2), CGSize(width: 37.25, height: 51.5), CGSize(width: 640, height: 592)] {
            let geometry = try XCTUnwrap(RoundedOverlayGeometry(targetBounds: CGRect(x: -20.25, y: 0.5, width: size.width, height: size.height)))
            for scale in [CGFloat(1), 2, 3] {
              for phase in [CGFloat(0), 0.5] {
                let bounds = CGRect(origin: .zero, size: geometry.protectionBounds.size)
                let width = Int(ceil(bounds.width * scale)) + 1, height = Int(ceil(bounds.height * scale)) + 1
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                try pixels.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.translateBy(x: phase, y: phase)
                    context.scaleBy(x: scale, y: scale)
                    context.setShouldAntialias(true)
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.addPath(RoundedOverlayGeometry.maskPath(in: bounds))
                    context.fillPath()
                }
                let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
                XCTAssertEqual(alpha[0], 0, "Outer corner must be rounded")
                let start = Int(floor(8 * scale + phase))
                let endX = Int(ceil((8 + size.width) * scale + phase))
                let endY = Int(ceil((8 + size.height) * scale + phase))
                var missing = 0
                for y in start..<endY {
                    for x in start..<endX where alpha[y * width + x] != 255 { missing += 1 }
                }
                XCTAssertEqual(missing, 0, "Target/title-bar pixels must be fully covered at scale \(scale)")
              }
            }
        }
    }
}

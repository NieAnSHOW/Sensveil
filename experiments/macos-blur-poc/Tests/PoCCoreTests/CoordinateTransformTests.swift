import Foundation
import CoreGraphics
import XCTest
@testable import PoCCore

final class CoordinateTransformTests: XCTestCase {
    func testGlobalPointCoordinates() {
        XCTAssertEqual(CoordinateTransform.appKitRect(from: CGRect(x: 100, y: 200, width: 500, height: 300), primaryScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)), CGRect(x: 100, y: 400, width: 500, height: 300))
    }

    func testNegativeAndMixedDisplayCoordinates() {
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), screenFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1280, y: -124, width: 1280, height: 1024)])
        let cgRect = CGRect(x: -1280, y: 0, width: 1280, height: 1024)
        let result = CoordinateTransform.appKitRect(from: cgRect, primaryScreenFrame: layout.primaryScreenFrame)
        XCTAssertEqual(result, CGRect(x: -1280, y: -124, width: 1280, height: 1024))
        XCTAssertEqual(result.size, CGSize(width: 1280, height: 1024))
        XCTAssertEqual(CoordinateTransform.appKitRect(from: CGRect(x: 50, y: -600, width: 400, height: 200), primaryScreenFrame: layout.primaryScreenFrame), CGRect(x: 50, y: 1300, width: 400, height: 200))
    }

    func testPrimaryScreenOriginIsPartOfTheFlipBaseline() {
        XCTAssertEqual(CoordinateTransform.appKitRect(from: CGRect(x: -100, y: 200, width: 500, height: 300), primaryScreenFrame: CGRect(x: 40, y: 50, width: 1440, height: 900)), CGRect(x: -100, y: 450, width: 500, height: 300))
    }
}

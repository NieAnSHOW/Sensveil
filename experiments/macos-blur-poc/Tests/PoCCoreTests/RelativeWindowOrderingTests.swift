import CoreGraphics
import XCTest
@testable import PoCCore

final class RelativeWindowOrderingTests: XCTestCase {
    private let protectedBounds = CGRect(x: 100, y: 100, width: 300, height: 200)

    func testUnrelatedWindowOutsideProtectedBoundsDoesNotReject() {
        let result = evaluate(between: [.init(windowID: 30, bounds: CGRect(x: 450, y: 100, width: 100, height: 100))])
        XCTAssertEqual(result.classification, .ok)
        XCTAssertEqual(result.interveningWindows.first?.intersection, .empty)
    }

    func testPartialOverlapRejectsEvenOnePointOfContent() {
        let result = evaluate(between: [.init(windowID: 30, bounds: CGRect(x: 399, y: 120, width: 100, height: 100))])
        XCTAssertEqual(result.classification, .unrelatedBetween)
        XCTAssertEqual(result.interveningWindows.first?.intersection, .overlap(CGRect(x: 399, y: 120, width: 1, height: 100)))
    }

    func testTouchingEdgesDoNotCountAsContentOverlap() {
        XCTAssertEqual(evaluate(between: [.init(windowID: 30, bounds: CGRect(x: 400, y: 100, width: 100, height: 100))]).classification, .ok)
    }

    func testUnknownAndInvalidInterveningGeometryRejects() {
        for bounds in [nil, CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)] {
            let result = evaluate(between: [.init(windowID: 30, bounds: bounds)])
            XCTAssertEqual(result.classification, .interveningGeometryUnknown)
            XCTAssertEqual(result.interveningWindows.first?.intersection, .unknown)
        }
    }

    func testOtherOwnedOverlayIsNotAnUnrelatedConflict() {
        XCTAssertEqual(evaluate(between: [.init(windowID: 20, bounds: nil)], ownIDs: [10, 20]).classification, .ok)
    }

    func testMissingAndReversedPairRetainsFailure() {
        XCTAssertEqual(check([.init(windowID: 1)]).classification, .panelMissing)
        XCTAssertEqual(check([.init(windowID: 10)]).classification, .targetMissing)
        XCTAssertEqual(check([.init(windowID: 1), .init(windowID: 10)]).classification, .panelAfterTarget)
    }

    func testUnknownGeometryCannotBeHiddenByEarlierNonIntersectingWindow() {
        let result = evaluate(between: [
            .init(windowID: 30, bounds: CGRect(x: -500, y: -400, width: 100, height: 100)),
            .init(windowID: 31, bounds: nil)
        ])
        XCTAssertEqual(result.classification, .interveningGeometryUnknown)
        XCTAssertEqual(result.interveningWindows.count, 2)
    }

    func testInvalidProtectedBoundsRejectsEvenWithoutInterveningWindow() {
        let result = RelativeWindowOrdering.evaluate(panelID: 10, targetID: 1, protectionBounds: .zero,
            windows: [.init(windowID: 10), .init(windowID: 1)], ownOverlayIDs: [10])
        XCTAssertEqual(result.classification, .protectionGeometryUnknown)
    }

    func testNegativeDisplayCoordinatesUseGlobalCGGeometry() {
        let result = RelativeWindowOrdering.evaluate(panelID: 10, targetID: 1,
            protectionBounds: CGRect(x: -600, y: -300, width: 300, height: 200),
            windows: [.init(windowID: 10), .init(windowID: 30, bounds: CGRect(x: -400, y: -200, width: 200, height: 200)), .init(windowID: 1)],
            ownOverlayIDs: [10])
        XCTAssertEqual(result.classification, .unrelatedBetween)
    }

    private func evaluate(between: [OrderedWindowMetadata], ownIDs: Set<UInt32> = [10]) -> RelativeWindowOrdering.Result {
        check([.init(windowID: 10)] + between + [.init(windowID: 1)], ownIDs: ownIDs)
    }

    private func check(_ windows: [OrderedWindowMetadata], ownIDs: Set<UInt32> = [10]) -> RelativeWindowOrdering.Result {
        RelativeWindowOrdering.evaluate(panelID: 10, targetID: 1, protectionBounds: protectedBounds,
                                        windows: windows, ownOverlayIDs: ownIDs)
    }
}

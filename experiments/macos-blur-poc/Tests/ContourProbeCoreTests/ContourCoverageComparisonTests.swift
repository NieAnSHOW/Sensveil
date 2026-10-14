import XCTest
@testable import ContourProbeCore

final class ContourCoverageComparisonTests: XCTestCase {
    func testCountsMissingAndExcessPixelsAgainstIndependentReference() throws {
        let result = try ContourCoverageComparison.compare(
            width: 3, height: 2,
            candidate: [0, 255, 255, 255, 255, 0],
            reference: [1, 128, 0, 255, 255, 0], titleBarRows: 1)
        XCTAssertEqual(result.referencePixelCount, 4)
        XCTAssertEqual(result.missingPixelCount, 1)
        XCTAssertEqual(result.excessPixelCount, 1)
        XCTAssertEqual(result.titleBarReferencePixelCount, 2)
        XCTAssertEqual(result.titleBarMissingPixelCount, 1)
    }

    func testExactCoverageIncludesPartialReferenceWithoutThreshold() throws {
        let result = try ContourCoverageComparison.compare(
            width: 2, height: 2, candidate: [0, 255, 255, 0],
            reference: [0, 1, 254, 0], titleBarRows: 0)
        XCTAssertEqual(result.missingPixelCount, 0)
        XCTAssertEqual(result.excessPixelCount, 0)
        XCTAssertEqual(result.titleBarReferencePixelCount, 0)
    }

    func testRejectsInvalidDimensionsAndMismatchedBuffers() {
        XCTAssertThrowsError(try ContourCoverageComparison.compare(
            width: 0, height: 1, candidate: [], reference: [], titleBarRows: 0))
        XCTAssertThrowsError(try ContourCoverageComparison.compare(
            width: 2, height: 1, candidate: [255], reference: [255, 255], titleBarRows: 0))
        XCTAssertThrowsError(try ContourCoverageComparison.compare(
            width: 1, height: 1, candidate: [255], reference: [], titleBarRows: 0))
        XCTAssertThrowsError(try ContourCoverageComparison.compare(
            width: 1, height: 1, candidate: [255], reference: [255], titleBarRows: 2))
        XCTAssertThrowsError(try ContourCoverageComparison.compare(
            width: Int.max, height: 2, candidate: [], reference: [], titleBarRows: 0))
        XCTAssertThrowsError(try ContourCoverageComparison.compare(
            width: 4_000_001, height: 1, candidate: [], reference: [], titleBarRows: 0))
    }
}

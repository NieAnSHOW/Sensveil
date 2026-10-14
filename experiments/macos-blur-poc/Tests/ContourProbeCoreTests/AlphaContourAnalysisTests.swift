import XCTest
@testable import ContourProbeCore

final class AlphaContourAnalysisTests: XCTestCase {
    private let rounded: [UInt8] = [
        0, 255, 255, 255, 0,
        255, 255, 255, 255, 255,
        255, 255, 255, 255, 255,
        255, 255, 255, 255, 255,
        0, 255, 255, 255, 0
    ]

    func testFourExteriorCornersProduceOnlyDiagnosticCandidate() throws {
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: rounded)
        XCTAssertEqual(result.status, .outerContourCandidate)
        XCTAssertEqual(result.statistics.opaquePixelCount, 21)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4)
        XCTAssertEqual(result.statistics.interiorTransparentPixelCount, 0)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testOpaqueRectangleCannotProvideContour() throws {
        let result = try AlphaContourAnalysis.analyze(
            width: 3, height: 2, alphaBytes: [255, 255, 255, 255, 255, 255]
        )
        XCTAssertEqual(result.status, .opaqueNoContour)
        XCTAssertEqual(result.statistics.opaquePixelCount, 6)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 0)
    }

    func testEntirelyTransparentImageIsAmbiguous() throws {
        let result = try AlphaContourAnalysis.analyze(width: 2, height: 2, alphaBytes: [0, 0, 0, 0])
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4)
        XCTAssertEqual(result.filledSilhouetteAlpha, [0, 0, 0, 0])
    }

    func testInternalTransparentHoleIsFilledAndAmbiguous() throws {
        var input = rounded
        input[12] = 0
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.interiorTransparentPixelCount, 1)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testInteriorPartialAlphaIsNotExposedInPreviewAndIsAmbiguous() throws {
        var input = rounded
        input[12] = 128
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.partialAlphaPixelCount, 1)
        XCTAssertEqual(result.statistics.interiorPartialAlphaPixelCount, 1)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testBoundaryAntialiasRetainsConservativeMass() throws {
        var input = rounded
        input[1] = 60
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .outerContourCandidate)
        XCTAssertEqual(result.statistics.partialAlphaPixelCount, 1)
        XCTAssertEqual(result.statistics.interiorPartialAlphaPixelCount, 0)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testMultipleBoundaryAntialiasLayersAreNotInteriorTransparency() throws {
        var input = rounded
        input[1] = 60
        input[6] = 128
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .outerContourCandidate)
        XCTAssertEqual(result.statistics.opaquePixelCount, 19)
        XCTAssertEqual(result.statistics.partialAlphaPixelCount, 2)
        XCTAssertEqual(result.statistics.boundaryConnectedPartialAlphaPixelCount, 2)
        XCTAssertEqual(result.statistics.interiorPartialAlphaPixelCount, 0)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testEntirelyPartialSilhouetteCannotProvideContourCandidate() throws {
        let input: [UInt8] = [
            0, 128, 128, 128, 0,
            128, 128, 128, 128, 128,
            128, 128, 128, 128, 128,
            128, 128, 128, 128, 128,
            0, 128, 128, 128, 0
        ]
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.opaquePixelCount, 0)
        XCTAssertEqual(result.statistics.partialAlphaPixelCount, 21)
        XCTAssertEqual(result.statistics.boundaryConnectedPartialAlphaPixelCount, 21)
        XCTAssertEqual(result.statistics.interiorPartialAlphaPixelCount, 0)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testPartialBridgeNeverTurnsInternalZeroHoleIntoExterior() throws {
        var input = rounded
        input[1] = 60
        input[6] = 128
        input[11] = 128
        input[12] = 0
        input[13] = 128
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.partialAlphaPixelCount, 4)
        XCTAssertEqual(result.statistics.boundaryConnectedPartialAlphaPixelCount, 3)
        XCTAssertEqual(result.statistics.interiorPartialAlphaPixelCount, 1)
        XCTAssertEqual(result.statistics.interiorTransparentPixelCount, 1)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4)
        XCTAssertEqual(result.filledSilhouetteAlpha, rounded)
    }

    func testDisconnectedPartialClusterRemainsInteriorAndFilled() throws {
        let input: [UInt8] = [
            0, 60, 255, 255, 255, 255, 0,
            255, 128, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 128, 60, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            0, 255, 255, 255, 255, 255, 0
        ]
        let expected: [UInt8] = [
            0, 255, 255, 255, 255, 255, 0,
            255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255,
            0, 255, 255, 255, 255, 255, 0
        ]
        let result = try AlphaContourAnalysis.analyze(width: 7, height: 7, alphaBytes: input)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.partialAlphaPixelCount, 4)
        XCTAssertEqual(result.statistics.boundaryConnectedPartialAlphaPixelCount, 2)
        XCTAssertEqual(result.statistics.interiorPartialAlphaPixelCount, 2)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4)
        XCTAssertEqual(result.filledSilhouetteAlpha, expected)
    }

    func testBorderConnectedNotchIsExteriorButNotCandidate() throws {
        var input = rounded
        input[10] = 0
        input[11] = 0
        let result = try AlphaContourAnalysis.analyze(width: 5, height: 5, alphaBytes: input)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 6)
        XCTAssertEqual(result.statistics.interiorTransparentPixelCount, 0)
        XCTAssertEqual(result.filledSilhouetteAlpha, input)
    }

    func testDimensionsAndByteCountAreValidated() {
        assertError(.invalidDimensions, width: 0, height: 1, alpha: [])
        assertError(.invalidDimensions, width: 1, height: -1, alpha: [])
        assertError(.alphaByteCountMismatch, width: 2, height: 2, alpha: [255])
        assertError(.alphaByteCountMismatch, width: 1, height: 1, alpha: [255, 255])
    }

    func testOverflowAndPixelLimitAreCheckedBeforeByteCount() {
        assertError(.pixelCountOverflow, width: Int.max, height: 2, alpha: [])
        assertError(.pixelLimitExceeded, width: 4_000_001, height: 1, alpha: [])
    }

    func testExactlyFourMillionPixelsAreAccepted() throws {
        let result = try AlphaContourAnalysis.analyze(
            width: 2_000, height: 2_000,
            alphaBytes: [UInt8](repeating: 0, count: 4_000_000)
        )
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.statistics.exteriorTransparentPixelCount, 4_000_000)
        XCTAssertEqual(result.filledSilhouetteAlpha.count, 4_000_000)
        XCTAssertEqual(result.filledSilhouetteAlpha[3_999_999], 0)
    }

    private func assertError(
        _ expected: AlphaContourAnalysisError, width: Int, height: Int, alpha: [UInt8],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try AlphaContourAnalysis.analyze(width: width, height: height, alphaBytes: alpha),
            file: file, line: line
        ) { error in
            XCTAssertEqual(error as? AlphaContourAnalysisError, expected, file: file, line: line)
        }
    }
}

public struct ContourCoverageStatistics: Equatable, Sendable {
    public let referencePixelCount: Int
    public let missingPixelCount: Int
    public let excessPixelCount: Int
    public let titleBarReferencePixelCount: Int
    public let titleBarMissingPixelCount: Int
}

public enum ContourCoverageComparisonError: Error, Equatable {
    case invalidDimensions, pixelLimitExceeded, byteCountMismatch, invalidTitleBarRows
}

public enum ContourCoverageComparison {
    /// Both buffers must use the same pixel grid, with row zero at the top.
    /// Any nonzero reference alpha is content that must be covered.
    public static func compare(
        width: Int, height: Int, candidate: [UInt8], reference: [UInt8], titleBarRows: Int
    ) throws -> ContourCoverageStatistics {
        guard width > 0, height > 0 else { throw ContourCoverageComparisonError.invalidDimensions }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, count <= AlphaContourAnalysis.maximumPixelCount else {
            throw ContourCoverageComparisonError.pixelLimitExceeded
        }
        guard candidate.count == count, reference.count == count else {
            throw ContourCoverageComparisonError.byteCountMismatch
        }
        guard (0...height).contains(titleBarRows) else {
            throw ContourCoverageComparisonError.invalidTitleBarRows
        }
        var referenceCount = 0, missing = 0, excess = 0, titleCount = 0, titleMissing = 0
        for index in 0..<count {
            if reference[index] > 0 {
                referenceCount += 1
                if candidate[index] == 0 { missing += 1 }
                if index / width < titleBarRows {
                    titleCount += 1
                    if candidate[index] == 0 { titleMissing += 1 }
                }
            } else if candidate[index] > 0 {
                excess += 1
            }
        }
        return ContourCoverageStatistics(referencePixelCount: referenceCount,
            missingPixelCount: missing, excessPixelCount: excess,
            titleBarReferencePixelCount: titleCount, titleBarMissingPixelCount: titleMissing)
    }
}

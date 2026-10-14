public enum AlphaContourStatus: String, Sendable {
    case opaqueNoContour
    case ambiguous
    case outerContourCandidate
}

public enum AlphaContourAnalysisError: Error, Equatable {
    case invalidDimensions
    case pixelCountOverflow
    case pixelLimitExceeded
    case alphaByteCountMismatch
}

public struct AlphaContourStatistics: Equatable, Sendable {
    public let opaquePixelCount: Int
    public let partialAlphaPixelCount: Int
    public let boundaryConnectedPartialAlphaPixelCount: Int
    public let interiorPartialAlphaPixelCount: Int
    public let interiorTransparentPixelCount: Int
    public let exteriorTransparentPixelCount: Int
}

public struct AlphaContourResult: Sendable {
    public let width: Int
    public let height: Int
    public let status: AlphaContourStatus
    public let statistics: AlphaContourStatistics
    public let filledSilhouetteAlpha: [UInt8]
}

public enum AlphaContourAnalysis {
    public static let maximumPixelCount = 4_000_000

    public static func analyze(
        width: Int, height: Int, alphaBytes: [UInt8]
    ) throws -> AlphaContourResult {
        guard width > 0, height > 0 else { throw AlphaContourAnalysisError.invalidDimensions }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { throw AlphaContourAnalysisError.pixelCountOverflow }
        guard pixelCount <= maximumPixelCount else { throw AlphaContourAnalysisError.pixelLimitExceeded }
        guard alphaBytes.count == pixelCount else {
            throw AlphaContourAnalysisError.alphaByteCountMismatch
        }

        // This binary buffer doubles as flood visitation; source alpha never becomes preview alpha.
        var silhouette = [UInt8](repeating: 255, count: pixelCount)
        var queue: [Int32] = []
        queue.reserveCapacity(pixelCount)
        func enqueue(_ index: Int) {
            guard alphaBytes[index] == 0, silhouette[index] != 0 else { return }
            silhouette[index] = 0
            queue.append(Int32(index))
        }
        for x in 0..<width {
            enqueue(x)
            enqueue((height - 1) * width + x)
        }
        for y in 0..<height {
            enqueue(y * width)
            enqueue(y * width + width - 1)
        }
        var head = 0
        while head < queue.count {
            let index = Int(queue[head])
            head += 1
            let x = index % width
            if x > 0 { enqueue(index - 1) }
            if x + 1 < width { enqueue(index + 1) }
            if index >= width { enqueue(index - width) }
            if index < pixelCount - width { enqueue(index + width) }
        }

        let exteriorTransparent = queue.count
        queue.removeAll(keepingCapacity: true)
        var visitedPartial = [UInt8](repeating: 0, count: pixelCount)
        func enqueuePartial(_ index: Int) {
            guard alphaBytes[index] > 0, alphaBytes[index] < 255,
                  visitedPartial[index] == 0 else { return }
            visitedPartial[index] = 1
            queue.append(Int32(index))
        }

        var opaque = 0
        var partial = 0
        var interiorTransparent = 0
        for index in 0..<pixelCount {
            switch alphaBytes[index] {
            case 255:
                opaque += 1
            case 0:
                if silhouette[index] != 0 { interiorTransparent += 1 }
            default:
                partial += 1
                let x = index % width
                let touchesBoundary = x == 0 || x == width - 1
                    || index < width || index >= pixelCount - width
                    || silhouette[index - 1] == 0 || silhouette[index + 1] == 0
                    || silhouette[index - width] == 0 || silhouette[index + width] == 0
                if touchesBoundary { enqueuePartial(index) }
            }
        }

        // Traverse partial alpha only. Internal zero holes cannot connect partial regions,
        // and this diagnostic traversal never changes the exact-zero exterior or preview.
        head = 0
        while head < queue.count {
            let index = Int(queue[head])
            head += 1
            let x = index % width
            if x > 0 { enqueuePartial(index - 1) }
            if x + 1 < width { enqueuePartial(index + 1) }
            if index >= width { enqueuePartial(index - width) }
            if index < pixelCount - width { enqueuePartial(index + width) }
        }
        let boundaryConnectedPartial = queue.count
        let interiorPartial = partial - boundaryConnectedPartial

        // Orthogonal contiguity rejects notches and separated masses without fitting a radius.
        // A candidate is still diagnostic: these conditions cannot establish an authoritative contour.
        func hasContiguousFilledLines(lineCount: Int, length: Int, rowMajor: Bool) -> Bool {
            for line in 0..<lineCount {
                var foundFilled = false
                var endedFilled = false
                for offset in 0..<length {
                    let index = rowMajor ? line * width + offset : offset * width + line
                    if silhouette[index] != 0 {
                        if endedFilled { return false }
                        foundFilled = true
                    } else if foundFilled {
                        endedFilled = true
                    }
                }
                if !foundFilled { return false }
            }
            return true
        }
        let cornersAreExterior = silhouette[0] == 0 && silhouette[width - 1] == 0
            && silhouette[(height - 1) * width] == 0 && silhouette[pixelCount - 1] == 0
        let status: AlphaContourStatus
        if opaque == pixelCount {
            status = .opaqueNoContour
        } else if opaque > 0, interiorTransparent == 0, interiorPartial == 0,
                  cornersAreExterior,
                  hasContiguousFilledLines(lineCount: height, length: width, rowMajor: true),
                  hasContiguousFilledLines(lineCount: width, length: height, rowMajor: false) {
            status = .outerContourCandidate
        } else {
            status = .ambiguous
        }
        return AlphaContourResult(
            width: width, height: height, status: status,
            statistics: AlphaContourStatistics(
                opaquePixelCount: opaque, partialAlphaPixelCount: partial,
                boundaryConnectedPartialAlphaPixelCount: boundaryConnectedPartial,
                interiorPartialAlphaPixelCount: interiorPartial,
                interiorTransparentPixelCount: interiorTransparent,
                exteriorTransparentPixelCount: exteriorTransparent
            ),
            filledSilhouetteAlpha: silhouette
        )
    }
}

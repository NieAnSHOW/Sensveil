import AppKit
import ScreenCaptureKit
import CoreVideo
import PoCCore
import ContourProbeCore

struct ContourProbeArtifact: Sendable {
    let silhouette: CGImage?
    let summary: String
}

enum ContourProbeFailure: Error {
    case staleTarget, permissionUnavailable, metadataUnavailable, geometryMismatch
    case pixelLimit, captureUnavailable, conversionUnavailable

    var message: String {
        switch self {
        case .staleTarget: "Discarded: fixture, selection or display evidence changed"
        case .permissionUnavailable: "Cannot capture: Accessibility and Screen Recording must be granted"
        case .metadataUnavailable: "Cannot capture: unique fixture capture metadata is unavailable"
        case .geometryMismatch: "Cannot determine contour: capture geometry is inconsistent"
        case .pixelLimit: "Cannot capture: dimensions exceed the 4 million pixel limit"
        case .captureUnavailable: "Cannot capture: the single-window screenshot API failed"
        case .conversionUnavailable: "Cannot determine contour: alpha conversion failed"
        }
    }
}

@MainActor
enum ContourProbe {
    static func capture(window: WindowCandidate, validate: @MainActor () -> Bool) async throws -> ContourProbeArtifact {
        try check(validate)
        let source = try await captureWindow(window)
        try check(validate)
        let filter = SCContentFilter(desktopIndependentWindow: source)
        let contentRect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let dimensions = try dimensions(contentRect: contentRect, scale: scale, bounds: window.bounds)
        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        if #available(macOS 14.2, *) { configuration.includeChildWindows = false }
        // Only fully contained windows are accepted by the controller. Keep the SDK's
        // global-clipping behavior rather than treating offscreen clipping as a contour.
        try check(validate)
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch { throw ContourProbeFailure.captureUnavailable }
        try check(validate)
        guard image.width == dimensions.width, image.height == dimensions.height,
              image.width <= AlphaContourAnalysis.maximumPixelCount / image.height else {
            throw ContourProbeFailure.geometryMismatch
        }
        // Re-enumerate metadata after capture; it never reads other windows' pixels or titles.
        let currentSource = try await captureWindow(window)
        try check(validate)
        let currentFilter = SCContentFilter(desktopIndependentWindow: currentSource)
        guard currentFilter.contentRect == contentRect, CGFloat(currentFilter.pointPixelScale) == scale else {
            throw ContourProbeFailure.geometryMismatch
        }
        let artifact = try await Task.detached(priority: .userInitiated) {
            try analyze(image: image, contentRect: contentRect, scale: scale)
        }.value
        try check(validate)
        return artifact
    }

    private static func check(_ validate: @MainActor () -> Bool) throws {
        try Task.checkCancellation()
        guard validate() else { throw ContourProbeFailure.staleTarget }
    }

    private static func captureWindow(_ window: WindowCandidate) async throws -> SCWindow {
        guard CGPreflightScreenCaptureAccess(), PermissionCoordinator.accessibilityIsGranted else {
            throw ContourProbeFailure.permissionUnavailable
        }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        catch { throw ContourProbeFailure.metadataUnavailable }
        let matches = content.windows.filter {
            $0.windowID == window.key.cgWindowID &&
            $0.owningApplication?.processID == window.key.process.pid &&
            $0.owningApplication?.bundleIdentifier == PoCController.fixtureBundleIdentifier &&
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
        }
        guard matches.count == 1, let source = matches.first, source.isOnScreen, source.windowLayer == 0 else {
            throw ContourProbeFailure.metadataUnavailable
        }
        guard sameBounds(source.frame, window.bounds) else { throw ContourProbeFailure.geometryMismatch }
        return source
    }

    private static func sameBounds(_ first: CGRect, _ second: CGRect) -> Bool {
        valid(first) && valid(second) && abs(first.minX - second.minX) <= 1 &&
            abs(first.minY - second.minY) <= 1 && abs(first.maxX - second.maxX) <= 1 &&
            abs(first.maxY - second.maxY) <= 1
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0 &&
            [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.width, rect.height].allSatisfy(\.isFinite)
    }

    private static func dimensions(contentRect: CGRect, scale: CGFloat, bounds: CGRect) throws -> (width: Int, height: Int) {
        guard valid(contentRect), scale.isFinite, scale > 0,
              abs(contentRect.width - bounds.width) <= 1, abs(contentRect.height - bounds.height) <= 1 else {
            throw ContourProbeFailure.geometryMismatch
        }
        // contentRect's origin belongs to the filter's content domain; SCWindow.frame
        // above is the global geometry check. Do not equate these coordinate origins.
        let width = ceil(contentRect.width * scale)
        let height = ceil(contentRect.height * scale)
        let limit = AlphaContourAnalysis.maximumPixelCount
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= CGFloat(limit), height <= CGFloat(limit), width * height <= CGFloat(limit) else {
            throw ContourProbeFailure.pixelLimit
        }
        return (Int(width), Int(height))
    }

    nonisolated private static func analyze(image: CGImage, contentRect: CGRect, scale: CGFloat) throws -> ContourProbeArtifact {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= AlphaContourAnalysis.maximumPixelCount / height else {
            throw ContourProbeFailure.pixelLimit
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let converted = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard converted else { throw ContourProbeFailure.conversionUnavailable }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in alpha.indices { alpha[index] = rgba[index * 4 + 3] }
        // RGB is never included in the result, diagnostic state, logs or a rendered view.
        rgba = []
        let result = try AlphaContourAnalysis.analyze(width: width, height: height, alphaBytes: alpha)
        let stats = result.statistics
        let status: String
        switch result.status {
        case .opaqueNoContour: status = "FAILED: opaque image provides no outer contour"
        case .ambiguous: status = "UNKNOWN: alpha boundary is ambiguous"
        case .outerContourCandidate: status = "UNKNOWN: experimental outer contour candidate; unvalidated"
        }
        let summary = "\(status)\n\(width) x \(height) pixels; content \(contentRect.width) x \(contentRect.height) points; scale \(scale)\n"
            + "Opaque \(stats.opaquePixelCount); partial \(stats.partialAlphaPixelCount); exterior transparent \(stats.exteriorTransparentPixelCount)\n"
            + "Boundary partial \(stats.boundaryConnectedPartialAlphaPixelCount); interior transparent \(stats.interiorTransparentPixelCount); interior partial \(stats.interiorPartialAlphaPixelCount)"
        let silhouette = result.status == .outerContourCandidate
            ? neutralSilhouette(width: width, height: height, alpha: result.filledSilhouetteAlpha) : nil
        return ContourProbeArtifact(silhouette: silhouette, summary: summary)
    }

    nonisolated private static func neutralSilhouette(width: Int, height: Int, alpha: [UInt8]) -> CGImage? {
        guard alpha.count == width * height else { return nil }
        var pixels = [UInt8](repeating: 0, count: alpha.count * 4)
        for index in alpha.indices where alpha[index] == 255 {
            pixels[index * 4] = 120
            pixels[index * 4 + 1] = 120
            pixels[index * 4 + 2] = 120
            pixels[index * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

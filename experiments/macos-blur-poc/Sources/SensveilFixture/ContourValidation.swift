import AppKit
import ScreenCaptureKit
import CoreVideo
import ContourProbeCore

/// Explicit, finite fixture-only experiment. Never installs a protection mask.
@MainActor
enum FixtureContourValidation {
    private enum Failure: Error { case geometry, conversion, limit }

    static func run() async {
        let visible = NSScreen.main?.visibleFrame ?? .zero
        guard visible.width >= 700, visible.height >= 600 else {
            print("CONTOUR unavailable: insufficient single-display test area")
            NSApp.terminate(nil)
            return
        }
        let titled = NSWindow(contentRect: NSRect(x: visible.minX + 60, y: visible.minY + 60,
            width: 480, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        titled.title = "SYNTHETIC CONTOUR VALIDATION"
        titled.contentView = ValidationShapeView(frame: .zero, rounded: false)
        let rounded = NSWindow(contentRect: NSRect(x: visible.minX + 90, y: visible.minY + 90,
            width: 480, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
        rounded.isOpaque = false
        rounded.backgroundColor = .clear
        rounded.hasShadow = false
        rounded.contentView = ValidationShapeView(frame: .zero, rounded: true)
        let windows = [("titled", titled), ("known-rounded-borderless", rounded)]
        defer {
            for (_, window) in windows { window.orderOut(nil) }
            NSApp.terminate(nil)
        }
        print("CONTOUR finite fixture-only validation; images remain in memory; no product approval")
        for (kind, window) in windows {
            window.makeKeyAndOrderFront(nil)
            for pose in ["initial", "moved", "resized"] {
                if pose == "moved" {
                    window.setFrameOrigin(NSPoint(x: window.frame.minX + 35, y: window.frame.minY + 25))
                } else if pose == "resized" {
                    window.setFrame(NSRect(origin: window.frame.origin,
                        size: NSSize(width: window.frame.width + 70, height: window.frame.height + 50)), display: true)
                }
                window.displayIfNeeded()
                do {
                    // Allow the finite geometry change to reach the compositor before sampling.
                    try await Task.sleep(for: .milliseconds(250))
                    try await sample(window, kind: kind, pose: pose)
                } catch {
                    print("CONTOUR \(kind) \(pose) unavailable: \(error)")
                }
            }
            window.orderOut(nil)
        }
        print("CONTOUR standard titled compositor outline remains UNVALIDATED; Task 8 remains gated")
    }

    private static func sample(_ window: NSWindow, kind: String, pose: String) async throws {
        let frame = window.frame
        guard let screen = window.screen, screen.frame.contains(frame),
              let view = window.contentView?.superview,
              abs(view.bounds.width - frame.width) < 0.01,
              abs(view.bounds.height - frame.height) < 0.01 else { throw Failure.geometry }
        let screenFrame = screen.frame
        let screenScale = screen.backingScaleFactor
        let expectedWidth = ceil(view.bounds.width * screenScale)
        let expectedHeight = ceil(view.bounds.height * screenScale)
        guard screenScale.isFinite, screenScale > 0,
              expectedWidth.isFinite, expectedHeight.isFinite,
              expectedWidth >= 1, expectedHeight >= 1,
              expectedWidth * expectedHeight <= CGFloat(AlphaContourAnalysis.maximumPixelCount) else { throw Failure.limit }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.conversion }
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              bitmap.pixelsWide <= AlphaContourAnalysis.maximumPixelCount / bitmap.pixelsHigh else { throw Failure.limit }
        // Apple documents cacheDisplay as view drawing, not compositor clipping.
        // In particular an opaque rectangular result is not an outline oracle.
        if let data = bitmap.bitmapData { memset(data, 0, bitmap.bytesPerRow * bitmap.pixelsHigh) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let referenceImage = bitmap.cgImage else { throw Failure.conversion }
        let reference = try alpha(referenceImage)
        let cornerIndices = [0, referenceImage.width - 1,
            (referenceImage.height - 1) * referenceImage.width, reference.count - 1]
        let clearCorners = cornerIndices.filter { reference[$0] == 0 }.count
        print("CONTOUR \(kind) \(pose) reference=cacheDisplay \(referenceImage.width)x\(referenceImage.height) clearCorners=\(clearCorners)/4 opaque=\(reference.filter { $0 == 255 }.count)")
        guard CGPreflightScreenCaptureAccess() else {
            print("CONTOUR \(kind) \(pose) capture skipped: Screen Recording not granted; no permission requested")
            return
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let matches = content.windows.filter {
            $0.windowID == CGWindowID(window.windowNumber)
                && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                && $0.isOnScreen && $0.windowLayer == 0
        }
        guard let desktopTop = NSScreen.screens.first?.frame.maxY else { throw Failure.geometry }
        let expectedGlobalFrame = CGRect(x: frame.minX, y: desktopTop - frame.maxY,
            width: frame.width, height: frame.height)
        guard matches.count == 1, let source = matches.first,
              window.screen === screen, screen.frame == screenFrame,
              screen.backingScaleFactor == screenScale,
              abs(source.frame.minX - expectedGlobalFrame.minX) < 0.01,
              abs(source.frame.minY - expectedGlobalFrame.minY) < 0.01,
              abs(source.frame.width - expectedGlobalFrame.width) < 0.01,
              abs(source.frame.height - expectedGlobalFrame.height) < 0.01 else { throw Failure.geometry }
        let filter = SCContentFilter(desktopIndependentWindow: source)
        let scale = CGFloat(filter.pointPixelScale)
        guard scale.isFinite, scale > 0,
              abs(filter.contentRect.width - frame.width) < 0.01,
              abs(filter.contentRect.height - frame.height) < 0.01 else { throw Failure.geometry }
        let width = ceil(filter.contentRect.width * scale), height = ceil(filter.contentRect.height * scale)
        guard width >= 1, height >= 1, width * height <= CGFloat(AlphaContourAnalysis.maximumPixelCount),
              width == CGFloat(referenceImage.width), height == CGFloat(referenceImage.height) else { throw Failure.geometry }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(width)
        configuration.height = Int(height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        if #available(macOS 14.2, *) { configuration.includeChildWindows = false }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard CGPreflightScreenCaptureAccess(), frame == window.frame, window.isVisible,
              window.screen === screen, screen.frame == screenFrame,
              screen.backingScaleFactor == screenScale,
              image.width == referenceImage.width, image.height == referenceImage.height else { throw Failure.geometry }
        let latest = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard latest.windows.contains(where: {
            $0.windowID == source.windowID && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                && $0.frame == source.frame && $0.isOnScreen
        }), CGPreflightScreenCaptureAccess(), frame == window.frame,
            window.screen === screen, screen.frame == screenFrame,
            screen.backingScaleFactor == screenScale else { throw Failure.geometry }
        let result = try AlphaContourAnalysis.analyze(width: image.width, height: image.height, alphaBytes: alpha(image))
        let titleHeight = max(0, frame.height - window.contentLayoutRect.height)
        let comparison = try ContourCoverageComparison.compare(width: image.width, height: image.height,
            candidate: result.filledSilhouetteAlpha, reference: reference,
            titleBarRows: min(image.height, Int(ceil(titleHeight * scale))))
        let missingReferenceAlpha = reference.indices.compactMap { index -> UInt8? in
            reference[index] > 0 && result.filledSilhouetteAlpha[index] == 0 ? reference[index] : nil
        }
        let oracle = kind == "titled" ? "INVALID_FOR_COMPOSITOR_OUTLINE" : "known-local-drawing"
        print("CONTOUR \(kind) \(pose) status=\(result.status.rawValue) oracle=\(oracle) referencePixels=\(comparison.referencePixelCount) missing=\(comparison.missingPixelCount) excess=\(comparison.excessPixelCount) titlePixels=\(comparison.titleBarReferencePixelCount) titleMissing=\(comparison.titleBarMissingPixelCount) missingOpaque=\(missingReferenceAlpha.filter { $0 == 255 }.count) missingAlphaMax=\(missingReferenceAlpha.max() ?? 0)")
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw Failure.geometry
        }
        let displays = latest.displays.filter { $0.displayID == displayNumber.uint32Value }
        guard displays.count == 1, let display = displays.first,
              display.frame.contains(source.frame) else { throw Failure.geometry }
        // This includes only our one window, never the desktop, dock, or other apps.
        // It is a second SCK path, not an independent authority for compositor shape.
        let displayFilter = SCContentFilter(display: display, including: [source])
        if #available(macOS 14.2, *) { displayFilter.includeMenuBar = false }
        guard CGFloat(displayFilter.pointPixelScale) == scale else { throw Failure.geometry }
        let displayConfiguration = SCStreamConfiguration()
        displayConfiguration.width = Int(width)
        displayConfiguration.height = Int(height)
        displayConfiguration.sourceRect = source.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        displayConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        displayConfiguration.shouldBeOpaque = false
        let clearBackground = CGColor(gray: 0, alpha: 0)
        displayConfiguration.backgroundColor = clearBackground
        displayConfiguration.ignoreShadowsDisplay = true
        displayConfiguration.showsCursor = false
        displayConfiguration.capturesAudio = false
        if #available(macOS 14.2, *) { displayConfiguration.includeChildWindows = false }
        guard CGPreflightScreenCaptureAccess(), frame == window.frame, window.isVisible,
              window.screen === screen, screen.frame == screenFrame,
              screen.backingScaleFactor == screenScale else { throw Failure.geometry }
        let displayImage = try await SCScreenshotManager.captureImage(
            contentFilter: displayFilter, configuration: displayConfiguration)
        withExtendedLifetime(clearBackground) {}
        let afterDisplay = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard CGPreflightScreenCaptureAccess(), frame == window.frame, window.isVisible,
              window.screen === screen, screen.frame == screenFrame, screen.backingScaleFactor == screenScale,
              displayImage.width == image.width, displayImage.height == image.height,
              afterDisplay.displays.contains(where: { $0.displayID == display.displayID && $0.frame == display.frame }),
              afterDisplay.windows.contains(where: {
                  $0.windowID == source.windowID && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                      && $0.frame == source.frame && $0.isOnScreen
              }) else { throw Failure.geometry }
        let displayAlpha = try alpha(displayImage)
        let displayCorners = cornerIndices.filter { displayAlpha[$0] == 0 }.count
        guard displayCorners == 4, displayAlpha.contains(255) else {
            print("CONTOUR \(kind) \(pose) display-path=INVALID_REFERENCE clearCorners=\(displayCorners)/4")
            return
        }
        let crosscheck = try ContourCoverageComparison.compare(width: image.width, height: image.height,
            candidate: result.filledSilhouetteAlpha, reference: displayAlpha,
            titleBarRows: min(image.height, Int(ceil(titleHeight * scale))))
        print("CONTOUR \(kind) \(pose) display-path=CROSSCHECK_ONLY clearCorners=\(displayCorners)/4 referencePixels=\(crosscheck.referencePixelCount) missing=\(crosscheck.missingPixelCount) excess=\(crosscheck.excessPixelCount) titlePixels=\(crosscheck.titleBarReferencePixelCount) titleMissing=\(crosscheck.titleBarMissingPixelCount)")
    }

    private static func alpha(_ image: CGImage) throws -> [UInt8] {
        guard image.width > 0, image.height > 0,
              image.width <= AlphaContourAnalysis.maximumPixelCount / image.height else { throw Failure.limit }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard success else { throw Failure.conversion }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}

@MainActor
private final class ValidationShapeView: NSView {
    private let rounded: Bool
    init(frame: NSRect, rounded: Bool) { self.rounded = rounded; super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { !rounded }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        if rounded {
            NSBezierPath(roundedRect: bounds, xRadius: 32, yRadius: 20).fill()
        } else {
            bounds.fill()
        }
    }
}

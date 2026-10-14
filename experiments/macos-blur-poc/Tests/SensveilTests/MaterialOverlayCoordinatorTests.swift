import AppKit
import QuartzCore
import XCTest
@testable import PoCCore
@testable import Sensveil

@MainActor
final class MaterialOverlayCoordinatorTests: XCTestCase {
    func testMaterialMaskFullyCoversTargetAfterLayoutAndResize() throws {
        let effect = RoundedMaterialEffect(frame: CGRect(x: 0, y: 0, width: 116, height: 96))
        for size in [CGSize(width: 116, height: 96), CGSize(width: 656.25, height: 608.5)] {
            effect.setFrameSize(size)
            effect.needsLayout = true
            effect.layoutSubtreeIfNeeded()
            let mask = try XCTUnwrap(effect.layer?.mask)
            XCTAssertEqual(mask.frame.size, size)
            for scale in [CGFloat(1), 2, 3] {
                let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                try pixels.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.scaleBy(x: scale, y: scale)
                    mask.render(in: context)
                }
                XCTAssertEqual(pixels[3], 0)
                var missing = 0
                for y in Int(8 * scale)..<Int(ceil((size.height - 8) * scale)) {
                    for x in Int(8 * scale)..<Int(ceil((size.width - 8) * scale)) {
                        if pixels[(y * width + x) * 4 + 3] != 255 { missing += 1 }
                    }
                }
                XCTAssertEqual(missing, 0, "Installed material mask must not cut target/title-bar pixels")
            }
        }
    }

    func testOffscreenExpansionKeepsGeometryButRemainsUnaccepted() {
        let target = CGRect(x: -4.25, y: 30.5, width: 240, height: 180)
        let window = WindowCandidate(key: WindowKey(process: ProcessInstance(pid: 100, generation: 1), cgWindowID: 10), bounds: target, isOnScreen: true, layer: 0)
        let panel = FakeMaterialPanel(id: 101)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: { [] }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])

        guard case .failed = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)[window.key] else {
            return XCTFail("Offscreen placements remain outside local acceptance")
        }
        XCTAssertTrue(panel.wasClosed)
        XCTAssertEqual(panel.submittedFrame, CGRect(x: -12.25, y: 381.5, width: 256, height: 196))
    }

    func testThirdWindowTouchingOnlyExpansionBandRejectsPlacement() {
        let target = CGRect(x: 10, y: 10, width: 100, height: 100)
        let third = CGRect(x: 112, y: 30, width: 4, height: 20)
        XCTAssertFalse(target.intersects(third))
        let window = WindowCandidate(key: WindowKey(process: ProcessInstance(pid: 100, generation: 1), cgWindowID: 10), bounds: target, isOnScreen: true, layer: 0)
        let panel = FakeMaterialPanel(id: 101)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 101, bounds: target), .init(windowID: 30, bounds: third), .init(windowID: 10, bounds: target)]
        }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        _ = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)

        guard case .failed = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)[window.key] else {
            return XCTFail("an unrelated window intersecting only the expansion band must reject placement")
        }
        XCTAssertTrue(panel.wasClosed)
    }

    func testOrderingFailureRemovesOnlyRejectedWindowAndExpiresAfterRemoval() {
        let process = ProcessInstance(pid: 100, generation: 1)
        let first = WindowCandidate(key: WindowKey(process: process, cgWindowID: 10), bounds: CGRect(x: 10, y: 10, width: 100, height: 100), isOnScreen: true, layer: 0)
        let second = WindowCandidate(key: WindowKey(process: process, cgWindowID: 20), bounds: CGRect(x: 200, y: 10, width: 100, height: 100), isOnScreen: true, layer: 0)
        var panels: [FakeMaterialPanel] = []
        var order: [UInt32]? = []
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in
            let panel = FakeMaterialPanel(id: UInt32(100 + panels.count))
            panels.append(panel)
            return panel
        }, orderedWindowMetadata: {
            order?.map { id in
                let target = id == first.key.cgWindowID || id == panels.first(where: { $0.targetID == first.key.cgWindowID })?.windowID ? first.bounds : second.bounds
                return OrderedWindowMetadata(windowID: id, bounds: id == 10 || id == 20 ? target : target.insetBy(dx: -8, dy: -8))
            }
        }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        let intents: [WindowKey: OverlayIntent] = [first.key: .attemptBlur, second.key: .attemptBlur]
        let initial = coordinator.reconcile(intents, windows: [first, second], screenLayout: layout)
        XCTAssertEqual(initial[first.key], .requestSubmitted)
        XCTAssertEqual(initial[second.key], .requestSubmitted)
        let firstPanel = panels.first { $0.targetID == first.key.cgWindowID }!
        let secondPanel = panels.first { $0.targetID == second.key.cgWindowID }!
        order = [secondPanel.windowID, 20, 10, firstPanel.windowID]

        let rejected = coordinator.reconcile(intents, windows: [first, second], screenLayout: layout)

        guard case .failed = rejected[first.key] else { return XCTFail("lost ordering must reject affected key") }
        guard case .protected = rejected[second.key] else { return XCTFail("Unchanged accepted pair should stay protected") }
        XCTAssertEqual(coordinator.overlayKeys, [second.key])
        XCTAssertTrue(firstPanel.wasClosed)
        XCTAssertFalse(secondPanel.wasClosed)
        _ = coordinator.reconcile([second.key: .attemptBlur], windows: [second], screenLayout: layout)
        order = [secondPanel.windowID, 20]

        let rebuilt = coordinator.reconcile(intents, windows: [first, second], screenLayout: layout)

        XCTAssertEqual(rebuilt[first.key], .requestSubmitted)
        coordinator.removeAll()
    }

    func testUnavailableOrderMetadataFailsAllExistingRequests() {
        let process = ProcessInstance(pid: 100, generation: 1)
        let window = WindowCandidate(key: WindowKey(process: process, cgWindowID: 10), bounds: CGRect(x: 10, y: 10, width: 100, height: 100), isOnScreen: true, layer: 0)
        let panel = FakeMaterialPanel(id: 101)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: { nil }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        _ = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)

        let observations = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)

        guard case .failed = observations[window.key] else { return XCTFail("missing metadata must fail closed") }
        XCTAssertTrue(coordinator.overlayKeys.isEmpty)
        let repeated = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)
        guard case .failed = repeated[window.key] else { return XCTFail("metadata failure must remain latched during the same attempt") }
        XCTAssertTrue(coordinator.overlayKeys.isEmpty)
        _ = coordinator.reconcile([:], windows: [], screenLayout: layout)
        XCTAssertEqual(coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)[window.key], .requestSubmitted)
    }

    func testInterveningWindowUsesGeometryAndRetainsConflictFailure() {
        let bounds = CGRect(x: 10, y: 10, width: 100, height: 100)
        let window = WindowCandidate(key: WindowKey(process: ProcessInstance(pid: 100, generation: 1), cgWindowID: 10), bounds: bounds, isOnScreen: true, layer: 0)
        let panel = FakeMaterialPanel(id: 101)
        var thirdBounds = CGRect(x: 300, y: 10, width: 100, height: 100)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 101, bounds: bounds.insetBy(dx: -8, dy: -8)), .init(windowID: 30, bounds: thirdBounds), .init(windowID: 10, bounds: bounds)]
        }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        let intents: [WindowKey: OverlayIntent] = [window.key: .attemptBlur]
        _ = coordinator.reconcile(intents, windows: [window], screenLayout: layout)
        guard case .protected = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else { return XCTFail("Nonoverlapping third window should permit accepted placement") }
        XCTAssertFalse(panel.wasClosed)

        thirdBounds = CGRect(x: 109, y: 10, width: 100, height: 100)
        guard case .failed = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else {
            return XCTFail("overlapping third window must reject placement")
        }
        XCTAssertTrue(panel.wasClosed)
        thirdBounds = CGRect(x: 300, y: 10, width: 100, height: 100)
        coordinator.setSettings(OverlaySettings(blurLevel: .strongest, showsProtectionLabel: false))
        guard case .failed = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else {
            return XCTFail("conflict must remain latched until the attempt ends")
        }
    }

    func testUnknownInterveningBoundsRejectsExistingPanel() {
        let bounds = CGRect(x: 10, y: 10, width: 100, height: 100)
        let window = WindowCandidate(key: WindowKey(process: ProcessInstance(pid: 100, generation: 1), cgWindowID: 10), bounds: bounds, isOnScreen: true, layer: 0)
        let panel = FakeMaterialPanel(id: 101)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 101, bounds: bounds), .init(windowID: 30), .init(windowID: 10, bounds: bounds)]
        }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        _ = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)
        guard case .failed = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)[window.key] else {
            return XCTFail("unknown geometry must fail closed")
        }
        XCTAssertTrue(panel.wasClosed)
    }
    func testExpandedFrameTracksTargetAndRejectsThirdWindowOnlyInMargin() throws {
        let bounds = CGRect(x: 100, y: 100, width: 100, height: 100)
        let key = WindowKey(process: ProcessInstance(pid: 100, generation: 1), cgWindowID: 10)
        var window = WindowCandidate(key: key, bounds: bounds, isOnScreen: true, layer: 0)
        var panels: [FakeMaterialPanel] = []
        var thirdBounds = CGRect(x: 250, y: 120, width: 20, height: 20)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in
            let panel = FakeMaterialPanel(id: UInt32(101 + panels.count))
            panels.append(panel)
            return panel
        }, orderedWindowMetadata: {
            [.init(windowID: panels.last!.windowID), .init(windowID: 30, bounds: thirdBounds), .init(windowID: 10, bounds: window.bounds)]
        }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        let intents: [WindowKey: OverlayIntent] = [key: .attemptBlur]
        XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key], .requestSubmitted)
        XCTAssertEqual(panels.last?.submittedFrame, CGRect(x: 92, y: 392, width: 116, height: 116))
        let original = try XCTUnwrap(panels.last)
        window.bounds = CGRect(x: 110, y: 110, width: 90, height: 80)
        XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key], .requestSubmitted)
        XCTAssertTrue(original.wasClosed)
        XCTAssertEqual(panels.last?.submittedFrame, CGRect(x: 102, y: 402, width: 106, height: 96))
        thirdBounds = CGRect(x: 203, y: 120, width: 20, height: 20)
        XCTAssertFalse(window.bounds.intersects(thirdBounds))
        guard case .failed = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key] else {
            return XCTFail("Third window in expanded margin must reject the overlay")
        }
        XCTAssertTrue(coordinator.overlayKeys.isEmpty)
    }

    func testSettingsReachNewAndExistingPanelsWithoutRemovingThem() {
        let bounds = CGRect(x: 100, y: 100, width: 100, height: 100)
        let window = WindowCandidate(key: WindowKey(process: ProcessInstance(pid: 100, generation: 1), cgWindowID: 10), bounds: bounds, isOnScreen: true, layer: 0)
        let panel = FakeMaterialPanel(id: 101)
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 101), .init(windowID: 10, bounds: bounds)]
        }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        let initial = OverlaySettings(blurLevel: .enhanced, showsProtectionLabel: true)
        coordinator.setSettings(initial)
        _ = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)
        XCTAssertEqual(panel.settings, initial)
        let updated = OverlaySettings(blurLevel: .strongest, showsProtectionLabel: false)
        coordinator.setSettings(updated)
        XCTAssertEqual(panel.settings, updated)
        XCTAssertFalse(panel.wasClosed)
        XCTAssertEqual(coordinator.overlayKeys, [window.key])
    }
}

@MainActor
private final class FakeMaterialPanel: MaterialPanelPresenting {
    let windowID: UInt32
    var targetID: UInt32?
    var wasClosed = false
    var submittedFrame: CGRect?
    var settings: OverlaySettings?
    var evidence: OverlayProtectionEvidence?
    var backingScale: CGFloat = 2
    var presentationFrame: CGRect? { submittedFrame }
    init(id: UInt32) { windowID = id }
    func submit(frame: CGRect, above targetID: UInt32) {
        self.targetID = targetID
        submittedFrame = frame
    }
    func remove() { wasClosed = true }
    func fadeOut(completion: @escaping @MainActor () -> Void) { remove(); completion() }
    func setSettings(_ settings: OverlaySettings) { self.settings = settings }
    func setProtectionEvidence(_ evidence: OverlayProtectionEvidence?) { self.evidence = evidence }
}

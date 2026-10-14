import AppKit
import XCTest
@testable import Sensveil
@testable import PoCCore

@MainActor
final class MaterialAcceptanceTests: XCTestCase {
    private var accepted: MaterialAcceptanceEnvironment {
        .init(version: .init(majorVersion: 27, minorVersion: 0, patchVersion: 1), build: "26A434", architecture: "arm64", increasedContrast: false)
    }

    func testOnlyLocallyAcceptedSystemAndSettingsAreAllowed() {
        XCTAssertTrue(accepted.isAccepted)
        XCTAssertFalse(MaterialAcceptanceEnvironment(version: accepted.version, build: "other", architecture: "arm64", increasedContrast: false).isAccepted)
        XCTAssertFalse(MaterialAcceptanceEnvironment(version: .init(majorVersion: 14, minorVersion: 0, patchVersion: 0), build: "26A434", architecture: "arm64", increasedContrast: false).isAccepted)
        XCTAssertFalse(MaterialAcceptanceEnvironment(version: accepted.version, build: accepted.build, architecture: "x86_64", increasedContrast: false).isAccepted)
        XCTAssertFalse(MaterialAcceptanceEnvironment(version: accepted.version, build: accepted.build, architecture: accepted.architecture, increasedContrast: true).isAccepted)
    }

    func testFirstRequestWaitsForMatchingNaturalSnapshotAndTierChangeExpiresEvidence() {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        let coverage = target.insetBy(dx: -8, dy: -8)
        let panel = AcceptedTestPanel()
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), screenFrames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 11, bounds: coverage), .init(windowID: 10, bounds: target)]
        }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
        let intents: [WindowKey: OverlayIntent] = [key: .attemptBlur]
        XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key], .requestSubmitted)
        XCTAssertNil(panel.evidence)
        let observation = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key]
        guard case .protected(let evidence) = observation else { return XCTFail("Accepted material requires current matching placement") }
        XCTAssertEqual(evidence.key, key)
        XCTAssertEqual(evidence.bounds, target)
        XCTAssertEqual(evidence.blurLevel, .standard)
        XCTAssertEqual(panel.evidence, evidence)
        coordinator.setSettings(.init(blurLevel: .strongest, showsProtectionLabel: true))
        XCTAssertNil(panel.evidence)
        XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key], .requestSubmitted)
        guard case .protected(let changed) = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[key] else { return XCTFail("New tier must be rechecked") }
        XCTAssertEqual(changed.blurLevel, .strongest)
        coordinator.removeAll()
        XCTAssertTrue(panel.removed)
    }

    func testSupportedScalesProtectWindowsOnEveryDisplayUsingPrimaryCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let secondaryFrames = [primary.offsetBy(dx: 1000, dy: 41),
            primary.offsetBy(dx: -1000, dy: 0), primary.offsetBy(dx: 0, dy: 800),
            primary.offsetBy(dx: 0, dy: -800)]
        for secondary in secondaryFrames {
            let layout = ScreenLayout(primaryScreenFrame: primary, screenFrames: [primary, secondary])
            for screen in layout.screenFrames {
                for scale in [CGFloat(1), CGFloat(2)] {
                    let appKitTarget = CGRect(x: screen.minX + 100, y: screen.minY + 100, width: 300, height: 200)
                    let target = CoordinateTransform.appKitRect(from: appKitTarget, primaryScreenFrame: primary)
                    let window = WindowCandidate(key: WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10),
                        bounds: target, isOnScreen: true, layer: 0)
                    let panel = AcceptedTestPanel()
                    panel.backingScale = scale
                    let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
                        [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
                    }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
                    let intents: [WindowKey: OverlayIntent] = [window.key: .attemptBlur]
                    XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key], .requestSubmitted)
                    XCTAssertNil(panel.evidence)
                    guard case .protected = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else {
                        return XCTFail("A complete placement on either display must protect at 1x or 2x")
                    }
                    XCTAssertEqual(panel.presentationFrame, appKitTarget.insetBy(dx: -8, dy: -8))
                    XCTAssertNotNil(panel.evidence)
                    coordinator.removeAll()
                }
            }
        }
    }

    func testUnsupportedScaleNeverIssuesEvidence() {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let window = WindowCandidate(key: WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10), bounds: target, isOnScreen: true, layer: 0)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for scale in [CGFloat(0), -1, 1.5, 3, .infinity, .nan] {
            let panel = AcceptedTestPanel()
            panel.backingScale = scale
            let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: { [] },
                reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
            guard case .failed = coordinator.reconcile([window.key: .attemptBlur], windows: [window],
                screenLayout: .init(primaryScreenFrame: screen, screenFrames: [screen]))[window.key] else {
                return XCTFail("Unaccepted display conditions must fail closed")
            }
            XCTAssertNil(panel.evidence)
            XCTAssertTrue(panel.removed)
        }
    }

    func testCrossDisplayEdgeAndAmbiguousCoverageNeverIssueEvidence() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let secondary = primary.offsetBy(dx: 1000, dy: 0)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let placements = [(CGRect(x: 900, y: 100, width: 300, height: 200), [primary, secondary]),
            (CGRect(x: 0, y: 100, width: 300, height: 200), [primary, secondary]),
            (CGRect(x: 700, y: 100, width: 300, height: 200), [primary, secondary]),
            (CGRect(x: 100, y: 100, width: 300, height: 200), [primary, primary])]
        for (target, screens) in placements {
            let panel = AcceptedTestPanel()
            let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
            let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: { [] },
                reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
            guard case .failed = coordinator.reconcile([key: .attemptBlur], windows: [window],
                screenLayout: .init(primaryScreenFrame: primary, screenFrames: screens))[key] else {
                return XCTFail("The complete expanded coverage must belong to exactly one display")
            }
            XCTAssertNil(panel.evidence)
            XCTAssertTrue(coordinator.overlayKeys.isEmpty)
        }
    }

    func testLayoutChangeRebuildsAndRequiresFreshNaturalSnapshot() throws {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let oldLayout = ScreenLayout(primaryScreenFrame: primary, screenFrames: [primary])
        let newLayout = ScreenLayout(primaryScreenFrame: primary, screenFrames: [primary, primary.offsetBy(dx: -1000, dy: 0)])
        var panels: [AcceptedTestPanel] = []
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in
            let panel = AcceptedTestPanel()
            panels.append(panel)
            return panel
        }, orderedWindowMetadata: {
            [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
        }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
        let intents: [WindowKey: OverlayIntent] = [key: .attemptBlur]
        _ = coordinator.reconcile(intents, windows: [window], screenLayout: oldLayout)
        guard case .protected = coordinator.reconcile(intents, windows: [window], screenLayout: oldLayout)[key] else {
            return XCTFail("Expected accepted baseline")
        }
        let old = try XCTUnwrap(panels.first)
        XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: newLayout)[key], .requestSubmitted)
        XCTAssertTrue(old.removed)
        XCTAssertNil(old.evidence)
        XCTAssertEqual(panels.count, 2)
        XCTAssertNil(panels.last?.evidence)
        guard case .protected = coordinator.reconcile(intents, windows: [window], screenLayout: newLayout)[key] else {
            return XCTFail("New layout requires a fresh matching natural snapshot")
        }
        coordinator.removeAll()
    }

    func testLayoutChangeBeforeExitRemovesImmediately() {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let oldLayout = ScreenLayout(primaryScreenFrame: primary, screenFrames: [primary])
        let newLayout = ScreenLayout(primaryScreenFrame: primary.offsetBy(dx: 0, dy: 50),
            screenFrames: [primary.offsetBy(dx: 0, dy: 50)])
        let panel = AcceptedTestPanel()
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
        }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted }, reduceMotion: { false })
        _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: oldLayout)
        _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: oldLayout)
        _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: newLayout, foregroundPID: 42)
        XCTAssertTrue(panel.removed)
        XCTAssertNil(panel.fadeCompletion)
        XCTAssertTrue(coordinator.retiringKeys.isEmpty)
    }

    func testMultiDisplayExitRetiresAndChangedLayoutOrScaleRemovesIt() {
        let target = CGRect(x: 1100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = ScreenLayout(primaryScreenFrame: primary, screenFrames: [primary, primary.offsetBy(dx: 1000, dy: 0)])
        for changesScale in [false, true] {
            let panel = AcceptedTestPanel()
            panel.backingScale = 1
            let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
                [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
            }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted }, reduceMotion: { false })
            _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
            guard case .protected = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)[key] else {
                return XCTFail("Expected accepted secondary display baseline")
            }
            _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: layout, foregroundPID: 42)
            XCTAssertEqual(coordinator.retiringKeys, [key])
            XCTAssertNotNil(panel.fadeCompletion)
            XCTAssertFalse(panel.removed)
            let changed = changesScale ? layout : ScreenLayout(primaryScreenFrame: primary, screenFrames: [primary])
            if changesScale { panel.backingScale = 3 }
            _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: changed, foregroundPID: 42)
            XCTAssertTrue(panel.removed)
            XCTAssertTrue(coordinator.retiringKeys.isEmpty)
        }
    }

    func testUnknownOrChangedNaturalGeometryRemovesProtectedEvidence() {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let window = WindowCandidate(key: WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10), bounds: target, isOnScreen: true, layer: 0)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for changed in [CGRect?.none, target.insetBy(dx: -7, dy: -8)] {
            let panel = AcceptedTestPanel()
            var bounds: CGRect? = target.insetBy(dx: -8, dy: -8)
            let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
                [.init(windowID: 11, bounds: bounds), .init(windowID: 10, bounds: target)]
            }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
            let intents: [WindowKey: OverlayIntent] = [window.key: .attemptBlur]
            let layout = ScreenLayout(primaryScreenFrame: screen, screenFrames: [screen])
            _ = coordinator.reconcile(intents, windows: [window], screenLayout: layout)
            guard case .protected = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else { return XCTFail("Expected accepted baseline") }
            bounds = changed
            guard case .failed = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else { return XCTFail("Stale placement must fail") }
            XCTAssertTrue(panel.removed)
            XCTAssertNil(panel.evidence)
        }
    }

    func testCGMovesBeforeCandidateDoesNotLatchGeometryFailure() {
        let old = CGRect(x: 100, y: 100, width: 300, height: 200)
        var observedTarget = old
        var window = WindowCandidate(key: WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10), bounds: old, isOnScreen: true, layer: 0)
        let panel = AcceptedTestPanel()
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
            [.init(windowID: 11, bounds: observedTarget.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: observedTarget)]
        }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted })
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = ScreenLayout(primaryScreenFrame: screen, screenFrames: [screen])
        let intents: [WindowKey: OverlayIntent] = [window.key: .attemptBlur]
        _ = coordinator.reconcile(intents, windows: [window], screenLayout: layout)
        _ = coordinator.reconcile(intents, windows: [window], screenLayout: layout)
        observedTarget = old.offsetBy(dx: 25, dy: 15)
        guard case .failed = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else { return XCTFail("Mismatched metadata cannot approve") }
        XCTAssertNil(panel.evidence)
        window.bounds = observedTarget
        XCTAssertEqual(coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key], .requestSubmitted)
        guard case .protected = coordinator.reconcile(intents, windows: [window], screenLayout: layout)[window.key] else { return XCTFail("Fresh matching placement must recover") }
    }

    func testForegroundExitRetiresButRapidReentryCancelsOldCompletion() throws {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        var panels: [AcceptedTestPanel] = []
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in
            let panel = AcceptedTestPanel()
            panels.append(panel)
            return panel
        }, orderedWindowMetadata: {
            [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
        }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted }, reduceMotion: { false })
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = ScreenLayout(primaryScreenFrame: screen, screenFrames: [screen])
        _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
        _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
        let old = try XCTUnwrap(panels.first)
        _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: layout, foregroundPID: 42)
        XCTAssertTrue(coordinator.overlayKeys.isEmpty)
        XCTAssertEqual(coordinator.retiringKeys, [key])
        XCTAssertNil(old.evidence)
        XCTAssertFalse(old.removed)
        let late = try XCTUnwrap(old.fadeCompletion)
        XCTAssertEqual(coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)[key], .requestSubmitted)
        XCTAssertTrue(old.removed)
        XCTAssertTrue(coordinator.retiringKeys.isEmpty)
        XCTAssertEqual(panels.count, 2)
        late()
        XCTAssertFalse(panels[1].removed)
        XCTAssertEqual(coordinator.overlayKeys, [key])
        coordinator.removeAll()
        XCTAssertTrue(panels[1].removed)
    }

    func testChangingDurationClearsRetiringPanelsAndOffRemovesImmediately() {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = ScreenLayout(primaryScreenFrame: screen, screenFrames: [screen])
        for initial in ProtectionTransition.allCases {
            let panel = AcceptedTestPanel()
            let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
                [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
            }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted }, reduceMotion: { false })
            coordinator.setSettings(.init(blurLevel: .standard, showsProtectionLabel: true, protectionTransition: initial))
            _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
            _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
            _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: layout, foregroundPID: 42)
            if initial == .off {
                XCTAssertTrue(panel.removed)
                XCTAssertNil(panel.fadeCompletion)
                XCTAssertTrue(coordinator.retiringKeys.isEmpty)
            } else {
                XCTAssertFalse(panel.removed)
                XCTAssertEqual(coordinator.retiringKeys, [key])
                coordinator.setSettings(.init(blurLevel: .standard, showsProtectionLabel: true, protectionTransition: .off))
                XCTAssertTrue(panel.removed)
                XCTAssertTrue(coordinator.retiringKeys.isEmpty)
                panel.fadeCompletion?()
                XCTAssertTrue(coordinator.retiringKeys.isEmpty)
            }
        }
    }

    func testReducedMotionAndFailureNeverLeaveRetiringPanels() {
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let key = WindowKey(process: .init(pid: 42, generation: 1), cgWindowID: 10)
        let window = WindowCandidate(key: key, bounds: target, isOnScreen: true, layer: 0)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = ScreenLayout(primaryScreenFrame: screen, screenFrames: [screen])
        for reduce in [true, false] {
            let panel = AcceptedTestPanel()
            let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowMetadata: {
                [.init(windowID: 11, bounds: target.insetBy(dx: -8, dy: -8)), .init(windowID: 10, bounds: target)]
            }, reduceTransparency: { false }, acceptedEnvironment: { self.accepted }, reduceMotion: { reduce })
            _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
            _ = coordinator.reconcile([key: .attemptBlur], windows: [window], screenLayout: layout)
            if reduce {
                _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: layout, foregroundPID: 42)
                XCTAssertNil(panel.fadeCompletion)
            } else {
                _ = coordinator.reconcile([key: .remove], windows: [window], screenLayout: layout, foregroundPID: 42)
                XCTAssertNotNil(panel.fadeCompletion)
                var moved = window
                moved.bounds = moved.bounds.offsetBy(dx: 20, dy: 10)
                _ = coordinator.reconcile([key: .remove], windows: [moved], screenLayout: layout, foregroundPID: 42)
                XCTAssertTrue(panel.removed)
                XCTAssertTrue(coordinator.retiringKeys.isEmpty)
                _ = coordinator.reconcile([key: .cannotProtect(reason: "Permission lost")], windows: [window], screenLayout: layout)
            }
            XCTAssertTrue(panel.removed)
            XCTAssertTrue(coordinator.retiringKeys.isEmpty)
        }
    }
}

@MainActor
private final class AcceptedTestPanel: MaterialPanelPresenting {
    let windowID: UInt32 = 11
    var presentationFrame: CGRect?
    var backingScale: CGFloat = 2
    var evidence: OverlayProtectionEvidence?
    var removed = false
    var fadeCompletion: (@MainActor () -> Void)?
    func submit(frame: CGRect, above targetID: UInt32) { presentationFrame = frame }
    func remove() { removed = true; evidence = nil }
    func fadeOut(completion: @escaping @MainActor () -> Void) { fadeCompletion = completion }
    func setSettings(_ settings: OverlaySettings) {}
    func setProtectionEvidence(_ evidence: OverlayProtectionEvidence?) { self.evidence = evidence }
}

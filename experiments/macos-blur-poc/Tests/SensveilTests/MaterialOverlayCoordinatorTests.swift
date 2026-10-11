import AppKit
import XCTest
@testable import PoCCore
@testable import Sensveil

@MainActor
final class MaterialOverlayCoordinatorTests: XCTestCase {
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
        }, orderedWindowIDs: { order }, reduceTransparency: { false })
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
        XCTAssertEqual(rejected[second.key], .requestSubmitted)
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
        let coordinator = MaterialOverlayCoordinator(makePanel: { _ in panel }, orderedWindowIDs: { nil }, reduceTransparency: { false })
        let layout = ScreenLayout(primaryScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), screenFrames: [CGRect(x: 0, y: 0, width: 800, height: 600)])
        _ = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)

        let observations = coordinator.reconcile([window.key: .attemptBlur], windows: [window], screenLayout: layout)

        guard case .failed = observations[window.key] else { return XCTFail("missing metadata must fail closed") }
        XCTAssertTrue(coordinator.overlayKeys.isEmpty)
    }
}

@MainActor
private final class FakeMaterialPanel: MaterialPanelPresenting {
    let windowID: UInt32
    var targetID: UInt32?
    var wasClosed = false
    init(id: UInt32) { windowID = id }
    func submit(frame: CGRect, above targetID: UInt32) { self.targetID = targetID }
    func remove() { wasClosed = true }
}

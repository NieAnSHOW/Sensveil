import AppKit
import XCTest
@testable import PoCCore
@testable import Sensveil

@MainActor
final class WindowProtectionCoordinatorTests: XCTestCase {
    private let bundleID = "com.example.editor"

    func testForegroundClearsEveryWindowForApplication() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let windows = [candidate(instance, id: 1), candidate(instance, id: 2)]
        let runtime = FakeProtectionRuntime()
        runtime.instances[bundleID] = [instance]
        runtime.snapshots[instance] = snapshot(instance, windows: windows)
        runtime.frontmost = instance
        let coordinator = WindowProtectionCoordinator(runtime: runtime)

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        XCTAssertEqual(coordinator.status(for: bundleID), .foreground)
        XCTAssertTrue(runtime.reconciles.contains { intents, _ in
            intents.values.filter { $0 == .remove }.count == 2
        })
    }

    func testBackgroundRequestsBlurButNeverReportsProtected() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = FakeProtectionRuntime()
        runtime.instances[bundleID] = [instance]
        runtime.snapshots[instance] = snapshot(instance, windows: [candidate(instance, id: 3)])
        runtime.frontmost = ProcessInstance(pid: 200, generation: 2)
        runtime.observationResult = { intents, _ in
            Dictionary(uniqueKeysWithValues: intents.compactMap { key, intent in
                intent == .attemptBlur ? (key, .requestSubmitted) : nil
            })
        }
        let coordinator = WindowProtectionCoordinator(runtime: runtime)

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        XCTAssertTrue(runtime.reconciles.contains { intents, _ in intents.values.contains(.attemptBlur) })
        guard case .cannotProtect(let reason) = coordinator.status(for: bundleID) else {
            return XCTFail("submitted material must remain unverified")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("unverified"))
    }

    func testPauseRemovesOverlaysAndReportsPaused() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        coordinator.setGlobalPause(true)

        XCTAssertEqual(coordinator.status(for: bundleID), .paused)
        XCTAssertGreaterThanOrEqual(runtime.removeAllCount, 1)
        XCTAssertTrue(runtime.reconciles.last?.0.values.allSatisfy { $0 == .remove } ?? false)
    }

    func testMissingAccessibilityPermissionCannotProtect() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        runtime.permissions = [.notGranted]
        let coordinator = WindowProtectionCoordinator(runtime: runtime)

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        guard case .cannotProtect(let reason) = coordinator.status(for: bundleID) else {
            return XCTFail("missing permission must fail closed")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("permission"))
    }

    func testUnsupportedWindowProducesPartialFailureWhenAnotherWindowSubmits() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let supported = candidate(instance, id: 1)
        let runtime = configuredRuntime(instance: instance)
        runtime.snapshots[instance] = snapshot(instance, windows: [supported], issues: [WindowIssue(kind: .ambiguous, reason: "duplicate geometry")])
        runtime.observationResult = { intents, _ in
            Dictionary(uniqueKeysWithValues: intents.compactMap { key, intent in
                intent == .attemptBlur ? (key, .requestSubmitted) : nil
            })
        }
        let coordinator = WindowProtectionCoordinator(runtime: runtime)

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        guard case .partialFailure(let summaries) = coordinator.status(for: bundleID) else {
            return XCTFail("mixed supported and unsupported windows must be partial failure")
        }
        XCTAssertTrue(summaries.contains { $0.localizedCaseInsensitiveContains("ambiguous") })
        XCTAssertTrue(summaries.allSatisfy { !$0.contains("duplicate geometry") })
    }

    func testPIDGenerationChangeRemovesOldOverlayAndRebuildsForNewInstance() {
        let old = ProcessInstance(pid: 100, generation: 1)
        let replacement = ProcessInstance(pid: 100, generation: 2)
        let runtime = configuredRuntime(instance: old)
        runtime.observationResult = { intents, _ in
            Dictionary(uniqueKeysWithValues: intents.compactMap { key, intent in
                intent == .attemptBlur ? (key, .requestSubmitted) : nil
            })
        }
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        runtime.instances[bundleID] = [replacement]
        runtime.snapshots[replacement] = snapshot(replacement, windows: [candidate(replacement, id: 9)])
        runtime.emit(.launch)

        XCTAssertTrue(runtime.reconciles.contains { intents, _ in
            intents.contains { key, intent in key.process == old && intent == .remove }
        })
        XCTAssertTrue(runtime.reconciles.contains { intents, _ in
            intents.keys.contains { $0.process == replacement } && intents.values.contains(.attemptBlur)
        })
    }

    func testTerminationRemovesAllOverlaysAndClearsStatus() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        runtime.instances[bundleID] = []
        runtime.emit(.termination, terminatedPID: instance.pid)

        XCTAssertEqual(coordinator.status(for: bundleID), .notRunning)
        XCTAssertGreaterThanOrEqual(runtime.removeAllCount, 1)
    }

    private func configuredRuntime(instance: ProcessInstance) -> FakeProtectionRuntime {
        let runtime = FakeProtectionRuntime()
        runtime.instances[bundleID] = [instance]
        runtime.snapshots[instance] = snapshot(instance, windows: [candidate(instance, id: 1)])
        runtime.frontmost = ProcessInstance(pid: 200, generation: 2)
        return runtime
    }

    private func application() -> ProtectedApplication {
        ProtectedApplication(bundleIdentifier: bundleID, displayName: "Editor")
    }

    private func candidate(_ instance: ProcessInstance, id: UInt32) -> WindowCandidate {
        WindowCandidate(key: WindowKey(process: instance, cgWindowID: id), bounds: CGRect(x: 10, y: 10, width: 400, height: 300), isOnScreen: true, layer: 0)
    }

    private func snapshot(_ instance: ProcessInstance, windows: [WindowCandidate], issues: [WindowIssue] = []) -> WindowSnapshot {
        WindowSnapshot(target: instance, receivedAt: .now, windows: windows, issues: issues, minimizedCount: 0, cgCount: windows.count, axCount: windows.count, notificationFallback: false)
    }
}

@MainActor
private final class FakeProtectionRuntime: WindowProtectionCoordinator.Runtime {
    var callback: ((FocusEvent) -> Void)?
    var frontmost: ProcessInstance?
    var instances: [String: [ProcessInstance]] = [:]
    var snapshots: [ProcessInstance: WindowSnapshot] = [:]
    var permissions: [PermissionState] = [.granted]
    var observationResult: (([WindowKey: OverlayIntent], [WindowCandidate]) -> [WindowKey: OverlayObservation])?
    var reconciles: [([WindowKey: OverlayIntent], [WindowCandidate])] = []
    var removeAllCount = 0
    var overlayKeys = Set<WindowKey>()

    func start(onEvent: @escaping (FocusEvent) -> Void) { callback = onEvent; onEvent(FocusEvent(receivedAt: .now, frontmost: frontmost, kind: .startup, terminatedPID: nil)) }
    func stop() { callback = nil }
    func currentFrontmost() -> ProcessInstance? { frontmost }
    func runningInstances(for bundleIdentifier: String) -> [ProcessInstance] { instances[bundleIdentifier] ?? [] }
    func snapshot(for instance: ProcessInstance) -> WindowSnapshot? { snapshots[instance] }
    func permissionStates() -> [PermissionState] { permissions }
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate]) -> [WindowKey: OverlayObservation] {
        reconciles.append((intents, windows))
        let result = observationResult?(intents, windows) ?? [:]
        overlayKeys = Set(result.compactMap { key, observation in
            if observation == .requestSubmitted { return key }
            return nil
        })
        return result
    }
    func removeAllOverlays() { removeAllCount += 1; overlayKeys.removeAll() }
    func emit(_ kind: FocusEvent.Kind, terminatedPID: Int32? = nil) { callback?(FocusEvent(receivedAt: .now, frontmost: frontmost, kind: kind, terminatedPID: terminatedPID)) }
}

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

    func testStartupWithKnownForegroundPIDWithoutProcessInstanceRequestsBlur() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        runtime.frontmost = nil
        runtime.rawFrontmostPID = 200
        let coordinator = WindowProtectionCoordinator(runtime: runtime)

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        XCTAssertEqual(runtime.reconciles.last?.0[candidate(instance, id: 1).key], .attemptBlur)
    }

    func testTargetToKnownDesktopPIDAndBackClearsOnlyWhenTargetIsFocused() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        runtime.frontmost = instance
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        let key = candidate(instance, id: 1).key
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        XCTAssertEqual(runtime.reconciles.last?.0[key], .remove)

        runtime.frontmost = nil
        runtime.rawFrontmostPID = 200
        runtime.emit(.activation)

        XCTAssertEqual(runtime.reconciles.last?.0[key], .attemptBlur)
        runtime.frontmost = instance
        runtime.rawFrontmostPID = nil
        runtime.emit(.activation)
        XCTAssertEqual(runtime.reconciles.last?.0[key], .remove)
        XCTAssertEqual(coordinator.status(for: bundleID), .foreground)
    }

    func testUnknownForegroundAfterKnownForegroundDoesNotReuseStaleFocus() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        runtime.frontmost = nil
        runtime.emit(.activation)

        guard case .cannotProtect = runtime.reconciles.last?.0[candidate(instance, id: 1).key] else {
            return XCTFail("unknown foreground must not be treated as a known background application")
        }
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

    func testIndependentOverlayFailureProducesPartialFailure() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let windows = [candidate(instance, id: 1), candidate(instance, id: 2)]
        let runtime = configuredRuntime(instance: instance)
        runtime.snapshots[instance] = snapshot(instance, windows: windows)
        runtime.observationResult = { _, _ in [windows[0].key: .requestSubmitted, windows[1].key: .failed(reason: "Relative overlay order was lost")] }
        let coordinator = WindowProtectionCoordinator(runtime: runtime)

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        XCTAssertEqual(coordinator.status(for: bundleID), .partialFailure(["Relative overlay order was lost"]))
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

    func testUnavailableSnapshotClearsPriorWindowEvidence() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        runtime.snapshots[instance] = nil

        runtime.emit(.activation)

        XCTAssertTrue(runtime.reconciles.last?.1.isEmpty ?? false)
        XCTAssertFalse(runtime.reconciles.last?.0.values.contains(.attemptBlur) ?? true)
    }

    func testIneligibleTargetsNeverReachOverlayAttempts() {
        for bundle in ["com.nieanshow.sensveil", "com.nieanshow.sensveil.fixture", "invalid identifier"] {
            let instance = ProcessInstance(pid: 100, generation: 1)
            let runtime = configuredRuntime(instance: instance)
            runtime.instances[bundle] = [instance]
            let coordinator = WindowProtectionCoordinator(runtime: runtime)

            coordinator.start(configuration: ProtectionConfiguration(applications: [ProtectedApplication(bundleIdentifier: bundle, displayName: "Rejected")]))

            XCTAssertFalse(runtime.reconciles.contains { $0.0.values.contains(.attemptBlur) }, bundle)
            guard case .cannotProtect = coordinator.status(for: bundle) else { return XCTFail("ineligible target must fail closed") }
        }
    }

    func testOverFreeLimitConfigurationNeverAttemptsProtection() {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        let apps = [application(), ProtectedApplication(bundleIdentifier: "com.example.second", displayName: "Second"), ProtectedApplication(bundleIdentifier: "com.example.third", displayName: "Third")]

        coordinator.start(configuration: ProtectionConfiguration(applications: apps))

        XCTAssertTrue(apps.allSatisfy { coordinator.status(for: $0) == .overFreeLimit })
        XCTAssertFalse(runtime.reconciles.contains { $0.0.values.contains(.attemptBlur) })
        XCTAssertGreaterThan(runtime.removeAllCount, 0)
    }

    func testProductionRuntimeReconcilesTrackerUpdatesWithoutStartupRecursion() async throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]))
        defer { fixture.remove() }
        let coordinator = WindowProtectionCoordinator(runtime: fixture.runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        XCTAssertEqual(fixture.tracker.startCount, 1)
        let initialCount = fixture.overlays.calls.count
        fixture.tracker.current = snapshot(instance, windows: [candidate(instance, id: 2)])

        fixture.tracker.emit()
        await Task.yield()
        await Task.yield()

        XCTAssertGreaterThan(fixture.overlays.calls.count, initialCount)
        XCTAssertEqual(fixture.overlays.calls.last?.1.map(\.key.cgWindowID), [2])
        coordinator.stop()
    }

    func testProductionRuntimePollsPermissionRevocation() async throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]))
        defer { fixture.remove() }
        let coordinator = WindowProtectionCoordinator(runtime: fixture.runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        fixture.permission = .notGranted

        try await Task.sleep(for: .milliseconds(40))

        XCTAssertFalse(fixture.overlays.calls.last?.0.values.contains(.attemptBlur) ?? true)
        guard case .cannotProtect(let reason) = coordinator.status(for: bundleID) else { return XCTFail("revoked permission must fail closed") }
        XCTAssertTrue(reason.contains("permission"))
        coordinator.stop()
    }

    func testProductionRuntimeRejectsHelpersBeforeTracking() async throws {
        for (policy, flags) in [(NSApplication.ActivationPolicy.accessory, [:]), (.regular, ["LSBackgroundOnly": true]), (.regular, ["LSUIElement": true])] {
            let instance = ProcessInstance(pid: 100, generation: 1)
            let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]), policy: policy, flags: flags)
            defer { fixture.remove() }
            let coordinator = WindowProtectionCoordinator(runtime: fixture.runtime)
            coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

            XCTAssertEqual(fixture.tracker.startCount, 0)
            XCTAssertFalse(fixture.overlays.calls.contains { $0.0.values.contains(.attemptBlur) })
            guard case .cannotProtect = coordinator.status(for: bundleID) else { return XCTFail("helper must fail closed") }
            coordinator.stop()
        }
    }

    func testProductionRuntimePrunesTrackersOnRemovalExitAndPIDReplacement() throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]))
        defer { fixture.remove() }
        let coordinator = WindowProtectionCoordinator(runtime: fixture.runtime)
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        fixture.launchDate = fixture.launchDate?.addingTimeInterval(10)
        fixture.focus.emit(.launch)
        XCTAssertEqual(fixture.tracker.stopCount, 1)
        coordinator.setConfiguration(ProtectionConfiguration())
        XCTAssertEqual(fixture.tracker.stopCount, 2)
        coordinator.setConfiguration(ProtectionConfiguration(applications: [application()]))
        fixture.isRunning = false
        fixture.focus.emit(.termination, terminatedPID: instance.pid)
        XCTAssertEqual(fixture.tracker.stopCount, 3)
        coordinator.stop()
    }

    func testControllerStartsAndUpdatesInjectedCoordinator() throws {
        let runtime = FakeProtectionRuntime()
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(fileURL: directory.appendingPathComponent("configuration.json"))
        let controller = SensveilController(configurationStore: store, catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false), protectionCoordinator: coordinator)
        XCTAssertNotNil(runtime.callback)
        controller.addApplication(ApplicationDescriptor(bundleIdentifier: bundleID, displayName: "Editor", url: directory.appendingPathComponent("Editor.app")))
        // Differential configuration: a plain settings change reconciles but
        // must not tear down unrelated overlays.
        XCTAssertGreaterThan(runtime.reconciles.count, 1)
        controller.setGlobalPause(true)
        XCTAssertEqual(controller.status(for: application()), .paused)
        controller.removeApplication(application())
        XCTAssertTrue(controller.configuration.applications.isEmpty)
        controller.stopProtection()
        XCTAssertNil(runtime.callback)
    }

    func testControllerReleaseStopsInjectedCoordinator() async {
        let runtime = FakeProtectionRuntime()
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var controller: SensveilController? = SensveilController(configurationStore: ConfigurationStore(fileURL: directory.appendingPathComponent("configuration.json")), catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false), protectionCoordinator: coordinator)
        XCTAssertNotNil(controller)
        XCTAssertNotNil(runtime.callback)

        controller = nil
        await Task.yield()
        await Task.yield()

        XCTAssertNil(runtime.callback)
    }

    func testProductionFocusAdapterReconcilesDesktopActivationWithoutLaunchIdentity() throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]))
        defer { fixture.remove() }
        // The focus provider represents NSWorkspace's current PID; it has no
        // launchDate requirement. Target tracking still uses the dated instance.
        var foregroundPID: Int32? = 200
        let focus = FocusMonitor(foregroundPID: { foregroundPID })
        let runtime = AdapterRuntime(focus: focus, overlays: fixture.overlays, registry: ProcessRegistry(), applications: {
            [AdapterRuntime.RunningApplication(bundleIdentifier: self.bundleID, bundleURL: fixture.directory.appendingPathComponent("Editor.app"), activationPolicy: .regular, pid: 100, launchDate: Date(timeIntervalSince1970: 1), isTerminated: false)]
        }, makeTracker: { fixture.tracker }, permissions: { [.granted] })
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        defer { coordinator.stop() }
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        let key = candidate(instance, id: 1).key
        XCTAssertEqual(fixture.overlays.calls.last?.0[key], .attemptBlur)

        foregroundPID = 100
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(fixture.overlays.calls.last?.0[key], .remove)
        XCTAssertEqual(coordinator.status(for: bundleID), .foreground)

        foregroundPID = 200
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(fixture.overlays.calls.last?.0[key], .attemptBlur)
        XCTAssertTrue(fixture.overlays.overlayKeys.contains(key))

        // Calibration/AX reconciliation must read current focus, not keep the
        // last activation's PID when the system can no longer supply focus.
        foregroundPID = nil
        coordinator.setConfiguration(ProtectionConfiguration(applications: [application()]))
        guard case .cannotProtect = fixture.overlays.calls.last?.0[key] else {
            return XCTFail("unknown current focus must clear the submitted overlay")
        }
        XCTAssertFalse(fixture.overlays.overlayKeys.contains(key))
    }

    func testProductionFocusAdapterRejectsUnknownAndInvalidPIDs() {
        var foregroundPID: Int32?
        let focus = FocusMonitor(foregroundPID: { foregroundPID })
        var events: [FocusEvent] = []
        for pid: Int32? in [nil, -1, 0, 200] {
            foregroundPID = pid
            focus.start { events.append($0) }
        }
        focus.stop()
        XCTAssertEqual(events.map(\.frontmostPID), [nil, nil, nil, 200])
    }

    func testTerminationInvalidatesTargetGenerationEvenWhenLaunchDateIsUnchanged() throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]))
        defer { fixture.remove() }
        let runtime = fixture.runtime
        runtime.start { _ in }
        defer { runtime.stop() }
        let before = try XCTUnwrap(runtime.runningInstances(for: bundleID).first)

        fixture.focus.emit(.termination, terminatedPID: 100)
        let after = try XCTUnwrap(runtime.runningInstances(for: bundleID).first)

        XCTAssertNotEqual(before, after)
    }

    func testTargetWithoutLaunchDateStillNeverStartsTracker() throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let fixture = try RuntimeFixture(bundleID: bundleID, instance: instance, snapshot: snapshot(instance, windows: [candidate(instance, id: 1)]))
        fixture.launchDate = nil
        defer { fixture.remove() }
        let coordinator = WindowProtectionCoordinator(runtime: fixture.runtime)
        defer { coordinator.stop() }

        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))

        XCTAssertEqual(coordinator.status(for: bundleID), .notRunning)
        XCTAssertEqual(fixture.tracker.startCount, 0)
        XCTAssertFalse(fixture.overlays.calls.contains { $0.0.values.contains(.attemptBlur) })
    }

    func testScheduleBoundaryRemovesOverlaysAndRestoresProtection() throws {
        var current = try date("2026-10-12T10:00:00Z") // Monday inside 09:00–18:00
        let runtime = configuredRuntime(instance: ProcessInstance(pid: 100, generation: 1))
        let coordinator = WindowProtectionCoordinator(runtime: runtime, now: { current }, calendar: { Self.gregorianGMT() }, holidays: .empty)
        defer { coordinator.stop() }
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()], schedule: Self.specifiedSchedule()))

        let key = candidate(ProcessInstance(pid: 100, generation: 1), id: 1).key
        XCTAssertEqual(runtime.reconciles.last?.0[key], .attemptBlur)

        current = try date("2026-10-12T18:00:00Z") // end is exclusive
        coordinator.processScheduleTimerFired()
        XCTAssertEqual(coordinator.status(for: bundleID), .outsideSchedule)
        XCTAssertGreaterThanOrEqual(runtime.removeAllCount, 1)

        current = try date("2026-10-13T09:00:00Z") // next weekday window start
        coordinator.processScheduleTimerFired()
        XCTAssertEqual(runtime.reconciles.last?.0[key], .attemptBlur)
    }

    func testPauseResumeFollowsSchedule() throws {
        var current = try date("2026-10-12T10:00:00Z")
        let runtime = configuredRuntime(instance: ProcessInstance(pid: 100, generation: 1))
        let coordinator = WindowProtectionCoordinator(runtime: runtime, now: { current }, calendar: { Self.gregorianGMT() }, holidays: .empty)
        defer { coordinator.stop() }
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()], schedule: Self.specifiedSchedule()))

        coordinator.setGlobalPause(true)
        XCTAssertEqual(coordinator.status(for: bundleID), .paused)
        coordinator.setGlobalPause(false)
        XCTAssertEqual(runtime.reconciles.last?.0.values.contains(.attemptBlur), true)

        current = try date("2026-10-12T18:30:00Z")
        coordinator.setGlobalPause(true)
        coordinator.setGlobalPause(false)
        XCTAssertEqual(coordinator.status(for: bundleID), .outsideSchedule)
    }

    func testDisabledApplicationKeepsDisabledAcrossPauseAndSchedule() throws {
        var current = try date("2026-10-12T10:00:00Z")
        let runtime = configuredRuntime(instance: ProcessInstance(pid: 100, generation: 1))
        runtime.observationResult = { _, _ in [:] }
        let coordinator = WindowProtectionCoordinator(runtime: runtime, now: { current }, calendar: { Self.gregorianGMT() }, holidays: .empty)
        defer { coordinator.stop() }
        let disabled = ProtectedApplication(bundleIdentifier: bundleID, displayName: "Editor", isEnabled: false)
        coordinator.start(configuration: ProtectionConfiguration(applications: [disabled], schedule: Self.specifiedSchedule()))

        XCTAssertEqual(coordinator.status(for: bundleID), .disabled)
        coordinator.setGlobalPause(true)
        XCTAssertEqual(coordinator.status(for: bundleID), .disabled)

        current = try date("2026-10-12T20:00:00Z")
        coordinator.setGlobalPause(false)
        coordinator.processScheduleTimerFired()
        XCTAssertEqual(coordinator.status(for: bundleID), .disabled)
        XCTAssertFalse(runtime.reconciles.contains { $0.0.values.contains(.attemptBlur) })
    }

    func testRunningAppWithoutVisibleWindowsReportsNoVisibleWindows() throws {
        let instance = ProcessInstance(pid: 100, generation: 1)
        let runtime = configuredRuntime(instance: instance)
        runtime.snapshots[instance] = snapshot(instance, windows: [])
        let coordinator = WindowProtectionCoordinator(runtime: runtime)
        defer { coordinator.stop() }
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()]))
        XCTAssertEqual(coordinator.status(for: bundleID), .noVisibleWindows)

        runtime.snapshots[instance] = snapshot(instance, windows: [], issues: [WindowIssue(kind: .ambiguous, reason: "duplicate geometry")])
        runtime.emit(.windows)
        guard case .cannotProtect = coordinator.status(for: bundleID) else {
            return XCTFail("snapshot issues must keep the failure path")
        }
    }

    func testCalendarMissingYearWarnsIndependentlyOfStatus() throws {
        let runtime = configuredRuntime(instance: ProcessInstance(pid: 100, generation: 1))
        let coordinator = WindowProtectionCoordinator(runtime: runtime, calendar: { Self.gregorianGMT() }, holidays: .empty)
        defer { coordinator.stop() }
        var schedule = Self.specifiedSchedule()
        schedule.followsMainlandHolidays = true
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()], schedule: schedule))

        XCTAssertTrue(coordinator.scheduleEvaluation?.missingHolidayYears.contains(2026) ?? false)
        XCTAssertEqual(coordinator.scheduleEvaluation?.isActive, true)
        // The calendar warning must not masquerade as a protection failure.
        XCTAssertEqual(runtime.reconciles.last?.0.values.contains(.attemptBlur), true)
    }

    func testTimeChangedEventReconcilesSchedule() throws {
        var current = try date("2026-10-12T10:00:00Z")
        let runtime = configuredRuntime(instance: ProcessInstance(pid: 100, generation: 1))
        let coordinator = WindowProtectionCoordinator(runtime: runtime, now: { current }, calendar: { Self.gregorianGMT() }, holidays: .empty)
        defer { coordinator.stop() }
        coordinator.start(configuration: ProtectionConfiguration(applications: [application()], schedule: Self.specifiedSchedule()))
        let before = runtime.removeAllCount

        current = try date("2026-10-12T19:00:00Z")
        runtime.emit(.timeChanged)

        XCTAssertEqual(coordinator.status(for: bundleID), .outsideSchedule)
        XCTAssertGreaterThan(runtime.removeAllCount, before)
    }

    private static func specifiedSchedule() -> ProtectionSchedule {
        var schedule = ProtectionSchedule.defaultConfiguration
        schedule.mode = .specified
        schedule.followsMainlandHolidays = false
        return schedule
    }

    private static func gregorianGMT() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value), value)
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
private final class RuntimeFixture {
    let tracker: FakeWindowTracker
    let focus = FakeFocusMonitor()
    let overlays = FakeOverlayCoordinator()
    let directory: URL
    var launchDate: Date? = Date(timeIntervalSince1970: 1)
    var isRunning = true
    var permission: PermissionState = .granted
    private let bundleID: String
    private let instance: ProcessInstance
    private let policy: NSApplication.ActivationPolicy
    lazy var runtime = AdapterRuntime(focus: focus, overlays: overlays, registry: ProcessRegistry(), applications: { [weak self] in
        guard let self, self.isRunning else { return [] }
        return [AdapterRuntime.RunningApplication(bundleIdentifier: self.bundleID, bundleURL: self.directory.appendingPathComponent("Editor.app"), activationPolicy: self.policy, pid: self.instance.pid, launchDate: self.launchDate, isTerminated: false)]
    }, makeTracker: { [tracker] in tracker }, permissions: { [weak self] in [self?.permission ?? .unknown] }, pollInterval: .milliseconds(5))

    init(bundleID: String, instance: ProcessInstance, snapshot: WindowSnapshot, policy: NSApplication.ActivationPolicy = .regular, flags: [String: Bool] = [:]) throws {
        self.bundleID = bundleID; self.instance = instance; self.policy = policy
        self.tracker = FakeWindowTracker(snapshot)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = directory.appendingPathComponent("Editor.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": "Editor"]
        for (key, value) in flags { info[key] = value }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class FakeWindowTracker: WindowTracking {
    var current: WindowSnapshot
    var callback: ((WindowSnapshot) -> Void)?
    var startCount = 0
    var stopCount = 0
    init(_ current: WindowSnapshot) { self.current = current }
    func start(for target: ProcessInstance, onChange: @escaping (WindowSnapshot) -> Void) { startCount += 1; callback = onChange; onChange(current) }
    func stop() { stopCount += 1; callback = nil }
    func snapshot(for target: ProcessInstance) -> WindowSnapshot { current }
    func emit() { callback?(current) }
}

@MainActor
private final class FakeFocusMonitor: FocusMonitoring {
    var callback: ((FocusEvent) -> Void)?
    func start(onEvent: @escaping (FocusEvent) -> Void) { callback = onEvent; emit(.startup) }
    func stop() { callback = nil }
    func currentFrontmostPID() -> Int32? { 200 }
    func emit(_ kind: FocusEvent.Kind, terminatedPID: Int32? = nil) { callback?(FocusEvent(receivedAt: .now, frontmostPID: currentFrontmostPID(), kind: kind, terminatedPID: terminatedPID)) }
}

@MainActor
private final class FakeOverlayCoordinator: OverlayCoordinating {
    var overlayKeys = Set<WindowKey>()
    var calls: [([WindowKey: OverlayIntent], [WindowCandidate])] = []
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate], screenLayout: ScreenLayout) -> [WindowKey: OverlayObservation] {
        calls.append((intents, windows))
        overlayKeys = Set(intents.compactMap { $0.value == .attemptBlur ? $0.key : nil })
        return Dictionary(uniqueKeysWithValues: intents.compactMap { key, intent in
            switch intent { case .attemptBlur: return (key, .requestSubmitted); case .cannotProtect(let reason): return (key, .failed(reason: reason)); case .remove: return nil }
        })
    }
    func removeAll() { overlayKeys.removeAll() }
}

@MainActor
private final class FakeProtectionRuntime: WindowProtectionCoordinator.Runtime {
    var callback: ((FocusEvent) -> Void)?
    var frontmost: ProcessInstance?
    var rawFrontmostPID: Int32?
    var instances: [String: [ProcessInstance]] = [:]
    var snapshots: [ProcessInstance: WindowSnapshot] = [:]
    var permissions: [PermissionState] = [.granted]
    var observationResult: (([WindowKey: OverlayIntent], [WindowCandidate]) -> [WindowKey: OverlayObservation])?
    var reconciles: [([WindowKey: OverlayIntent], [WindowCandidate])] = []
    var removeAllCount = 0
    var overlayKeys = Set<WindowKey>()

    func start(onEvent: @escaping (FocusEvent) -> Void) { callback = onEvent; onEvent(FocusEvent(receivedAt: .now, frontmostPID: currentFrontmostPID(), kind: .startup, terminatedPID: nil)) }
    func stop() { callback = nil }
    func currentFrontmostPID() -> Int32? { rawFrontmostPID ?? frontmost?.pid }
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
    func emit(_ kind: FocusEvent.Kind, terminatedPID: Int32? = nil) { callback?(FocusEvent(receivedAt: .now, frontmostPID: currentFrontmostPID(), kind: kind, terminatedPID: terminatedPID)) }
}

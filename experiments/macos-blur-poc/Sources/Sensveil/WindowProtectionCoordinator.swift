import AppKit
import Foundation
import PoCCore

/// Main-actor bridge between application focus, conservative window identity and
/// the material adapter. Scoped evidence must match the current window and
/// settings; a submitted request alone remains unverified.
@MainActor
public final class WindowProtectionCoordinator {
    public var onStatusChange: (() -> Void)?
    struct RunningTarget: Equatable {
        let bundleIdentifier: String
        let instance: ProcessInstance
    }

    /// Latest schedule judgment for the current configuration. Holiday
    /// availability warnings live here, never inside ProtectionStatus.
    public private(set) var scheduleEvaluation: ProtectionScheduleEvaluation?

    @MainActor
    protocol Runtime: AnyObject {
        func start(onEvent: @escaping (FocusEvent) -> Void)
        func stop()
        func currentFrontmostPID() -> Int32?
        func runningInstances(for bundleIdentifier: String) -> [ProcessInstance]
        func eligibilityFailure(for bundleIdentifier: String) -> String?
        func retainTrackers(for instances: Set<ProcessInstance>)
        func snapshot(for instance: ProcessInstance) -> WindowSnapshot?
        func permissionStates() -> [PermissionState]
        func setSettings(_ settings: OverlaySettings)
        var overlayKeys: Set<WindowKey> { get }
        func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate], animateForegroundRemoval: Bool) -> [WindowKey: OverlayObservation]
        func removeAllOverlays()
    }

    private let runtime: Runtime
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let holidays: MainlandHolidayCalendar
    private var configuration = ProtectionConfiguration()
    private var statuses: [String: ProtectionStatus] = [:]
    private var snapshots: [ProcessInstance: WindowSnapshot] = [:]
    private var selectedInstances: [String: Set<ProcessInstance>] = [:]
    private var frontmostPID: Int32?
    private var isStarted = false
    private var isPaused = false
    private var lifecycleSuspended = false
    private var overlayKeys = Set<WindowKey>()
    private var scheduleTimer: Timer?

    init(
        runtime: Runtime,
        now: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { Calendar.current },
        holidays: MainlandHolidayCalendar = .empty
    ) {
        self.runtime = runtime
        self.now = now
        self.calendar = calendar
        self.holidays = holidays
    }

    /// Convenience production runtime. All adapters are initialized on the main
    /// actor and share one ProcessRegistry to prevent PID reuse confusion.
    /// A failed calendar load degrades to an empty calendar; weekly rules keep
    /// running and the missing-year warning surfaces independently.
    public convenience init() {
        let registry = ProcessRegistry()
        let focus = FocusMonitor()
        let overlays = MaterialOverlayCoordinator()
        let holidays = (try? MainlandHolidayCalendar.loadBundled()) ?? .empty
        self.init(runtime: AdapterRuntime(focus: focus, overlays: overlays, registry: registry), holidays: holidays)
    }

    public func start(configuration: ProtectionConfiguration) {
        stop()
        self.configuration = configuration
        isPaused = configuration.isGloballyPaused
        lifecycleSuspended = false
        isStarted = true
        runtime.setSettings(OverlaySettings(
            blurLevel: configuration.blurLevel, showsProtectionLabel: configuration.showsProtectionLabel,
            protectionTransition: configuration.effectiveProtectionTransition))
        // The production focus monitor emits startup synchronously. Reconcile
        // once after runtime setup, including runtimes without that callback.
        var starting = true
        runtime.start { [weak self] event in
            if starting, case .startup = event.kind { return }
            self?.handle(event)
        }
        starting = false
        reconcile()
    }

    public func stop() {
        guard isStarted else { return }
        let previousStatuses = statuses
        scheduleTimer?.invalidate(); scheduleTimer = nil
        runtime.stop()
        runtime.removeAllOverlays()
        snapshots.removeAll()
        overlayKeys.removeAll()
        selectedInstances.removeAll()
        statuses = Dictionary(uniqueKeysWithValues: configuration.applications.map { ($0.bundleIdentifier, .notRunning) })
        frontmostPID = nil
        isStarted = false
        if statuses != previousStatuses { onStatusChange?() }
    }

    /// Differential configuration update: overlays the new configuration no
    /// longer protects are removed by the next reconcile (previous overlay keys
    /// become .remove intents). A plain settings change must not tear down
    /// overlays for windows that remain protected.
    public func setConfiguration(_ configuration: ProtectionConfiguration) {
        self.configuration = configuration
        isPaused = configuration.isGloballyPaused
        runtime.setSettings(OverlaySettings(
            blurLevel: configuration.blurLevel, showsProtectionLabel: configuration.showsProtectionLabel,
            protectionTransition: configuration.effectiveProtectionTransition))
        guard isStarted else { return }
        reconcile()
    }

    public func setGlobalPause(_ paused: Bool) {
        isPaused = paused
        configuration.isGloballyPaused = paused
        guard isStarted else { return }
        if paused { runtime.removeAllOverlays() }
        reconcile()
    }

    public func status(for application: ProtectedApplication) -> ProtectionStatus {
        status(for: application.bundleIdentifier)
    }

    public func status(for bundleIdentifier: String) -> ProtectionStatus {
        statuses[bundleIdentifier] ?? .notRunning
    }

    /// Human-readable bundled holiday coverage for display.
    public var holidayCoverageDescription: String {
        holidays.coverageDescription()
    }

    public func removeAllOverlays() {
        runtime.removeAllOverlays()
    }

    private func handle(_ event: FocusEvent) {
        guard isStarted else { return }
        switch event.kind {
        case .sleep:
            lifecycleSuspended = true
            runtime.removeAllOverlays()
            overlayKeys.removeAll()
            snapshots.removeAll()
        case .wake:
            lifecycleSuspended = false
            runtime.removeAllOverlays()
            overlayKeys.removeAll()
            snapshots.removeAll()
        case .screens, .space:
            runtime.removeAllOverlays()
            overlayKeys.removeAll()
            snapshots.removeAll()
        case .termination:
            if let pid = event.terminatedPID {
                snapshots = snapshots.filter { $0.key.pid != pid }
                selectedInstances = selectedInstances.mapValues { $0.filter { $0.pid != pid } }
                runtime.removeAllOverlays()
            }
        case .launch, .activation, .startup, .windows, .permissions, .timeChanged:
            break
        }
        reconcile()
    }

    /// Fired by the single one-shot boundary timer. Internal so tests can
    /// advance an injected clock and drive it deterministically.
    func processScheduleTimerFired() {
        reconcile()
    }

    /// Re-evaluates the schedule and rearms the unique one-shot boundary timer
    /// on the main RunLoop common modes, so menu interaction or dragging cannot
    /// postpone a schedule boundary indefinitely.
    private func refreshScheduleEvaluationAndRearmTimer() {
        scheduleEvaluation = evaluateProtectionSchedule(
            configuration.schedule, at: now(), calendar: calendar(), holidays: holidays)
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard isStarted, !lifecycleSuspended else { return }
        let interval = scheduleEvaluation?.nextEvaluation.timeIntervalSince(now()) ?? 0
        guard interval > 0 else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.processScheduleTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    /// True when the current configuration's protection schedule is inactive
    /// right now. All-day mode is always active.
    private var isOutsideSchedule: Bool {
        guard configuration.schedule.mode == .specified else { return false }
        return !(scheduleEvaluation?.isActive ?? true)
    }

    private func reconcile() {
        guard isStarted else { return }
        let previousStatuses = statuses
        let previousScheduleEvaluation = scheduleEvaluation
        defer {
            if statuses != previousStatuses || scheduleEvaluation != previousScheduleEvaluation {
                onStatusChange?()
            }
        }
        statuses.removeAll()
        refreshScheduleEvaluationAndRearmTimer()
        let apps = configuration.applications.filter(\.isEnabled)
        // Outside the configured schedule: remove layers and stop window
        // tracking, but keep launch/focus listeners so entering the schedule
        // re-enumerates current state instead of reusing stale geometry.
        if isOutsideSchedule {
            runtime.removeAllOverlays()
            runtime.retainTrackers(for: [])
            overlayKeys.removeAll()
            snapshots.removeAll()
            selectedInstances.removeAll()
            for app in configuration.applications {
                guard app.isEnabled else { statuses[app.bundleIdentifier] = .disabled; continue }
                if isPaused || lifecycleSuspended { statuses[app.bundleIdentifier] = .paused; continue }
                let running = !runtime.runningInstances(for: app.bundleIdentifier).isEmpty
                statuses[app.bundleIdentifier] = running ? .outsideSchedule : .notRunning
            }
            return
        }
        var targets: [(bundle: String, instance: ProcessInstance)] = []
        selectedInstances.removeAll()
        for application in apps {
            guard isEligible(bundleIdentifier: application.bundleIdentifier) else {
                statuses[application.bundleIdentifier] = .cannotProtect("Configured application identity is not eligible.")
                continue
            }
            let instances = runtime.runningInstances(for: application.bundleIdentifier)
            if let failure = runtime.eligibilityFailure(for: application.bundleIdentifier) {
                statuses[application.bundleIdentifier] = .cannotProtect(failure)
                continue
            }
            selectedInstances[application.bundleIdentifier] = Set(instances)
            targets.append(contentsOf: instances.map { (application.bundleIdentifier, $0) })
            for instance in instances {
                snapshots[instance] = runtime.snapshot(for: instance)
            }
        }
        let live = Set(targets.map(\.instance))
        runtime.retainTrackers(for: live)
        snapshots = snapshots.filter { live.contains($0.key) }

        var allWindows: [WindowCandidate] = []
        for snapshot in snapshots.values { allWindows.append(contentsOf: snapshot.windows) }
        let selected = Set(targets.map(\.instance))
        // Read current focus for every reconciliation, including AX callbacks.
        // Unknown focus must never fall back to a previously focused app.
        frontmostPID = runtime.currentFrontmostPID()
        let input = ProtectionInput(
            frontmost: nil,
            frontmostPID: frontmostPID,
            selected: selected,
            windows: allWindows,
            previousOverlayKeys: overlayKeys,
            permissions: runtime.permissionStates(),
            isSuspended: isPaused || lifecycleSuspended,
            requiresRevalidation: false
        )
        var intents = ProtectionReducer.reduce(input)
        // Focus is application-level: every process instance for a configured
        // bundle is foreground while any one of its instances is frontmost.
        if let focusedPID = input.frontmostPID,
           let focusedBundle = targets.first(where: { $0.instance.pid == focusedPID })?.bundle {
            for target in targets where target.bundle == focusedBundle {
                for key in snapshots[target.instance]?.windows.map(\.key) ?? [] { intents[key] = .remove }
            }
        }
        let allowFocusTransition = !input.isSuspended && !input.permissions.isEmpty
            && input.permissions.allSatisfy { $0 == .granted }
        let observations = runtime.reconcile(intents, windows: allWindows, animateForegroundRemoval: allowFocusTransition)
        overlayKeys = runtime.overlayKeys.union(Set(observations.compactMap { key, value in
            switch value {
            case .requestSubmitted, .protected: return key
            case .failed: return nil
            }
        }))
        updateStatuses(apps: apps, targets: targets, snapshots: snapshots, intents: intents, observations: observations)
    }

    private func updateStatuses(apps: [ProtectedApplication], targets: [(bundle: String, instance: ProcessInstance)], snapshots: [ProcessInstance: WindowSnapshot], intents: [WindowKey: OverlayIntent], observations: [WindowKey: OverlayObservation]) {
        for app in apps {
            if statuses[app.bundleIdentifier] != nil { continue }
            let appTargets = targets.filter { $0.bundle == app.bundleIdentifier }
            if isPaused || lifecycleSuspended { statuses[app.bundleIdentifier] = .paused; continue }
            guard !appTargets.isEmpty else { statuses[app.bundleIdentifier] = .notRunning; continue }
            if appTargets.contains(where: { $0.instance.pid == frontmostPID }) { statuses[app.bundleIdentifier] = .foreground; continue }
            let appSnapshotValues = snapshotsFor(appTargets, snapshots: snapshots)
            // A running app with no visible, issue-free window has nothing to
            // protect; this is not a blur failure.
            if appSnapshotValues.count == appTargets.count,
               appSnapshotValues.allSatisfy({ $0.windows.isEmpty && $0.issues.isEmpty }) {
                statuses[app.bundleIdentifier] = .noVisibleWindows
                continue
            }
            let windowsByKey = Dictionary(grouping: appSnapshotValues.flatMap(\.windows), by: \.key)
            let appKeys = Set(windowsByKey.keys)
            let appIntents = intents.filter { appKeys.contains($0.key) }
            let appObservations = observations.filter { appKeys.contains($0.key) }
            var failures = appSnapshotValues.flatMap { $0.issues.map { issueSummary($0) } }
                + appObservations.compactMap { _, value in if case .failed(let reason) = value { return sanitize(reason) }; return nil }
                + appIntents.compactMap { _, value in if case .cannotProtect(let reason) = value { return sanitize(reason) }; return nil }
            if appSnapshotValues.count != appTargets.count {
                failures.append("Current window snapshot is unavailable.")
            }
            var verifiedKeys = Set<WindowKey>()
            for key in appKeys {
                guard let windows = windowsByKey[key], windows.count == 1 else {
                    failures.append("ambiguous window mapping")
                    continue
                }
                switch appObservations[key] {
                case .protected(let evidence):
                    guard appIntents[key] == .attemptBlur,
                          evidence.key == key,
                          evidence.bounds == windows[0].bounds,
                          evidence.blurLevel == configuration.blurLevel,
                          evidence.validationRevision == OverlayProtectionEvidence.acceptedRevision else {
                        failures.append("Current protection evidence does not match the window or settings.")
                        continue
                    }
                    verifiedKeys.insert(key)
                case .requestSubmitted:
                    failures.append("Material request submitted; visual protection is unverified.")
                case .failed:
                    break
                case nil:
                    failures.append("Required protection evidence is unavailable.")
                }
            }
            if !appKeys.isEmpty, verifiedKeys == appKeys, failures.isEmpty {
                statuses[app.bundleIdentifier] = .protected
            } else if !verifiedKeys.isEmpty {
                statuses[app.bundleIdentifier] = .partialFailure(unique(failures))
            } else if !failures.isEmpty {
                statuses[app.bundleIdentifier] = .cannotProtect(unique(failures).joined(separator: "; "))
            } else {
                statuses[app.bundleIdentifier] = .cannotProtect("No validated blur evidence is available.")
            }
        }
        for app in configuration.applications where !apps.contains(app) { statuses[app.bundleIdentifier] = .disabled }
    }


    private func isEligible(bundleIdentifier: String) -> Bool {
        let own = Bundle.main.bundleIdentifier
        return BundleIdentifierValidator.isValid(bundleIdentifier) && bundleIdentifier != own && bundleIdentifier != "com.nieanshow.sensveil" && bundleIdentifier != "com.nieanshow.sensveil.fixture" && !bundleIdentifier.lowercased().contains("sensveilfixture")
    }

    private func issueSummary(_ issue: WindowIssue) -> String {
        switch issue.kind {
        case .missing: return "missing window mapping"
        case .ambiguous: return "ambiguous window mapping"
        case .unsupported: return "unsupported window"
        case .accessibilityUnavailable: return "accessibility permission unavailable"
        case .processUnavailable: return "process identity unavailable"
        case .metadataUnavailable: return "window metadata unavailable"
        }
    }
    private func snapshotsFor(_ targets: [(bundle: String, instance: ProcessInstance)], snapshots: [ProcessInstance: WindowSnapshot]) -> [WindowSnapshot] {
        targets.compactMap { snapshots[$0.instance] }
    }

    private func unique(_ values: [String]) -> [String] {
        Array(NSOrderedSet(array: values).compactMap { $0 as? String })
    }

    private func sanitize(_ reason: String) -> String {
        let value = reason.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Protection evidence unavailable." }
        return String(value.prefix(160))
    }
}

@MainActor
final class AdapterRuntime: WindowProtectionCoordinator.Runtime {
    struct RunningApplication {
        let bundleIdentifier: String?
        let bundleURL: URL?
        let activationPolicy: NSApplication.ActivationPolicy
        let pid: Int32
        let launchDate: Date?
        let isTerminated: Bool
    }

    let focus: any FocusMonitoring
    private var trackers: [ProcessInstance: any WindowTracking] = [:]
    let overlays: any OverlayCoordinating
    var overlayKeys: Set<WindowKey> { overlays.overlayKeys }
    let registry: ProcessRegistry
    private let applications: () -> [RunningApplication]
    private let makeTracker: () -> any WindowTracking
    private let permissions: () -> [PermissionState]
    private let pollInterval: Duration
    private var onEvent: ((FocusEvent) -> Void)?
    private var permissionPoll: Task<Void, Never>?
    private var pendingWindowEvent: Task<Void, Never>?
    private var session = UUID()
    private var eligibilityFailures: [String: String] = [:]

    init(focus: any FocusMonitoring, overlays: any OverlayCoordinating, registry: ProcessRegistry,
         applications: @escaping () -> [RunningApplication] = {
             NSWorkspace.shared.runningApplications.map { RunningApplication(bundleIdentifier: $0.bundleIdentifier, bundleURL: $0.bundleURL, activationPolicy: $0.activationPolicy, pid: $0.processIdentifier, launchDate: $0.launchDate, isTerminated: $0.isTerminated) }
         }, makeTracker: (() -> any WindowTracking)? = nil,
         permissions: @escaping () -> [PermissionState] = { [AXIsProcessTrusted() ? .granted : .notGranted] },
         pollInterval: Duration = .seconds(1)) {
        self.focus = focus; self.overlays = overlays; self.registry = registry
        self.applications = applications
        self.makeTracker = makeTracker ?? { WindowTracker(registry: registry) }
        self.permissions = permissions; self.pollInterval = pollInterval
    }
    func start(onEvent: @escaping (FocusEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        focus.start { [weak self] event in
            guard let self else { return }
            if let pid = event.terminatedPID {
                self.registry.remove(pid: pid)
                self.retainTrackers(for: Set(self.trackers.keys.filter { $0.pid != pid }))
            }
            self.onEvent?(event)
        }
        let activeSession = session
        var previous = permissionStates()
        permissionPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.session == activeSession else { return }
                let current = self.permissionStates()
                if previous != current {
                    previous = current
                    self.publish(.permissions)
                }
            }
        }
    }
    public func stop() {
        session = UUID()
        permissionPoll?.cancel(); permissionPoll = nil
        pendingWindowEvent?.cancel(); pendingWindowEvent = nil
        onEvent = nil
        focus.stop(); trackers.values.forEach { $0.stop() }; trackers.removeAll()
    }
    func currentFrontmostPID() -> Int32? { focus.currentFrontmostPID() }
    func runningInstances(for bundleIdentifier: String) -> [ProcessInstance] {
        eligibilityFailures[bundleIdentifier] = nil
        return applications().compactMap { app in
            guard app.bundleIdentifier == bundleIdentifier, !app.isTerminated else { return nil }
            guard let url = app.bundleURL,
                  ApplicationCatalog.descriptor(at: url, activationPolicy: app.activationPolicy, ownBundleIdentifier: Bundle.main.bundleIdentifier)?.bundleIdentifier == bundleIdentifier else {
                eligibilityFailures[bundleIdentifier] = "Running application is not an eligible regular application."
                return nil
            }
            guard let launchDate = app.launchDate else { return nil }
            return registry.observe(pid: app.pid, launchDate: launchDate)
        }
    }
    func eligibilityFailure(for bundleIdentifier: String) -> String? { eligibilityFailures[bundleIdentifier] }
    func retainTrackers(for instances: Set<ProcessInstance>) {
        for key in Set(trackers.keys).subtracting(instances) { trackers.removeValue(forKey: key)?.stop() }
    }
    func snapshot(for instance: ProcessInstance) -> WindowSnapshot? {
        let tracker: any WindowTracking
        if let existing = trackers[instance] {
            tracker = existing
        } else {
            tracker = makeTracker()
            trackers[instance] = tracker
            // start emits its first snapshot synchronously. The caller is already
            // reconciling it; only later AX/calibration callbacks schedule rebuilds.
            var starting = true
            let activeSession = session
            tracker.start(for: instance) { [weak self] _ in
                guard !starting, let self, self.session == activeSession,
                      self.trackers[instance] != nil else { return }
                self.scheduleWindowEvent()
            }
            starting = false
        }
        return tracker.snapshot(for: instance)
    }
    func permissionStates() -> [PermissionState] { permissions() }
    func setSettings(_ settings: OverlaySettings) { overlays.setSettings(settings) }
    private func scheduleWindowEvent() {
        guard onEvent != nil, pendingWindowEvent == nil else { return }
        let activeSession = session
        pendingWindowEvent = Task { @MainActor [weak self] in
            guard let self, self.session == activeSession, !Task.isCancelled else { return }
            self.pendingWindowEvent = nil
            self.publish(.windows)
        }
    }
    private func publish(_ kind: FocusEvent.Kind) {
        onEvent?(FocusEvent(receivedAt: .now, frontmostPID: currentFrontmostPID(), kind: kind, terminatedPID: nil))
    }
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate], animateForegroundRemoval: Bool) -> [WindowKey: OverlayObservation] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return intents.reduce(into: [:]) { result, entry in if case .cannotProtect(let reason) = entry.value { result[entry.key] = .failed(reason: reason) } } }
        let layout = ScreenLayout(primaryScreenFrame: primary.frame, screenFrames: screens.map(\.frame))
        return overlays.reconcile(intents, windows: windows, screenLayout: layout,
            foregroundPID: animateForegroundRemoval ? currentFrontmostPID() : nil)
    }
    public func removeAllOverlays() { overlays.removeAll() }
}

extension WindowProtectionCoordinator.Runtime {
    func eligibilityFailure(for bundleIdentifier: String) -> String? { nil }
    func retainTrackers(for instances: Set<ProcessInstance>) {}
}

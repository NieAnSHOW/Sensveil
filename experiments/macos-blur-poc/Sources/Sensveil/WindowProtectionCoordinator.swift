import AppKit
import Foundation
import PoCCore

/// Main-actor bridge between application focus, conservative window identity and
/// the material adapter. The adapter's requestSubmitted result is deliberately
/// kept unverified; no public AppKit API proves composited pixels are private.
@MainActor
public final class WindowProtectionCoordinator {
    public var onStatusChange: (() -> Void)?
    struct RunningTarget: Equatable {
        let bundleIdentifier: String
        let instance: ProcessInstance
    }

    @MainActor
    protocol Runtime: AnyObject {
        func start(onEvent: @escaping (FocusEvent) -> Void)
        func stop()
        func currentFrontmost() -> ProcessInstance?
        func runningInstances(for bundleIdentifier: String) -> [ProcessInstance]
        func eligibilityFailure(for bundleIdentifier: String) -> String?
        func retainTrackers(for instances: Set<ProcessInstance>)
        func snapshot(for instance: ProcessInstance) -> WindowSnapshot?
        func permissionStates() -> [PermissionState]
        var overlayKeys: Set<WindowKey> { get }
        func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate]) -> [WindowKey: OverlayObservation]
        func removeAllOverlays()
    }

    private let runtime: Runtime
    private var configuration = ProtectionConfiguration()
    private var statuses: [String: ProtectionStatus] = [:]
    private var snapshots: [ProcessInstance: WindowSnapshot] = [:]
    private var selectedInstances: [String: Set<ProcessInstance>] = [:]
    private var frontmost: ProcessInstance?
    private var isStarted = false
    private var isPaused = false
    private var lifecycleSuspended = false
    private var overlayKeys = Set<WindowKey>()

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    /// Convenience production runtime. All adapters are initialized on the main
    /// actor and share one ProcessRegistry to prevent PID reuse confusion.
    public convenience init() {
        let registry = ProcessRegistry()
        let focus = FocusMonitor(registry: registry)
        let overlays = MaterialOverlayCoordinator()
        self.init(runtime: AdapterRuntime(focus: focus, overlays: overlays, registry: registry))
    }

    public func start(configuration: ProtectionConfiguration) {
        stop()
        self.configuration = configuration
        isPaused = configuration.isGloballyPaused
        lifecycleSuspended = false
        isStarted = true
        runtime.start { [weak self] event in
            self?.handle(event)
        }
        reconcile()
    }

    public func stop() {
        guard isStarted else { return }
        runtime.stop()
        runtime.removeAllOverlays()
        snapshots.removeAll()
        overlayKeys.removeAll()
        selectedInstances.removeAll()
        statuses = Dictionary(uniqueKeysWithValues: configuration.applications.map { ($0.bundleIdentifier, .notRunning) })
        frontmost = nil
        isStarted = false
        onStatusChange?()
    }

    public func setConfiguration(_ configuration: ProtectionConfiguration) {
        self.configuration = configuration
        isPaused = configuration.isGloballyPaused
        guard isStarted else { return }
        runtime.removeAllOverlays()
        overlayKeys.removeAll()
        snapshots.removeAll()
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

    public func removeAllOverlays() {
        runtime.removeAllOverlays()
    }

    private func handle(_ event: FocusEvent) {
        guard isStarted else { return }
        frontmost = event.frontmost
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
        case .launch, .activation, .startup, .windows, .permissions:
            break
        }
        reconcile()
    }

    private func reconcile() {
        guard isStarted else { return }
        defer { onStatusChange?() }
        statuses.removeAll()
        let apps = configuration.applications.filter(\.isEnabled)
        if configuration.applications.count > ConfigurationStore.freeApplicationLimit {
            statuses = Dictionary(uniqueKeysWithValues: configuration.applications.map { ($0.bundleIdentifier, .overFreeLimit) })
            runtime.removeAllOverlays()
            runtime.retainTrackers(for: [])
            overlayKeys.removeAll()
            snapshots.removeAll()
            selectedInstances.removeAll()
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
        let input = ProtectionInput(
            frontmost: frontmost ?? runtime.currentFrontmost(),
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
        if let focused = input.frontmost, let focusedBundle = targets.first(where: { $0.instance == focused })?.bundle {
            for target in targets where target.bundle == focusedBundle {
                for key in snapshots[target.instance]?.windows.map(\.key) ?? [] { intents[key] = .remove }
            }
        }
        let observations = runtime.reconcile(intents, windows: allWindows)
        overlayKeys = runtime.overlayKeys.union(Set(observations.compactMap { key, value in value == .requestSubmitted ? key : nil }))
        updateStatuses(apps: apps, targets: targets, snapshots: snapshots, intents: intents, observations: observations)
    }

    private func updateStatuses(apps: [ProtectedApplication], targets: [(bundle: String, instance: ProcessInstance)], snapshots: [ProcessInstance: WindowSnapshot], intents: [WindowKey: OverlayIntent], observations: [WindowKey: OverlayObservation]) {
        for app in apps {
            if statuses[app.bundleIdentifier] != nil { continue }
            let appTargets = targets.filter { $0.bundle == app.bundleIdentifier }
            if isPaused || lifecycleSuspended { statuses[app.bundleIdentifier] = .paused; continue }
            guard !appTargets.isEmpty else { statuses[app.bundleIdentifier] = .notRunning; continue }
            if appTargets.contains(where: { $0.instance == frontmost }) { statuses[app.bundleIdentifier] = .foreground; continue }
            let appKeys = Set(appTargets.flatMap { instance in snapshots[instance.instance]?.windows.map(\.key) ?? [] })
            let appIntents = intents.filter { appKeys.contains($0.key) }
            let appObservations = observations.filter { appKeys.contains($0.key) }
            let failures = snapshotsFor(appTargets, snapshots: snapshots).flatMap { $0.issues.map { issueSummary($0) } }
                + appObservations.compactMap { _, value in if case .failed(let reason) = value { return sanitize(reason) }; return nil }
                + appIntents.compactMap { _, value in if case .cannotProtect(let reason) = value { return sanitize(reason) }; return nil }
            let submitted = appObservations.values.contains { $0 == OverlayObservation.requestSubmitted }
            if submitted && failures.isEmpty {
                statuses[app.bundleIdentifier] = .cannotProtect("Material request submitted; visual protection is unverified.")
            } else if submitted {
                statuses[app.bundleIdentifier] = .partialFailure(unique(failures))
            } else if !failures.isEmpty {
                statuses[app.bundleIdentifier] = .cannotProtect(unique(failures).joined(separator: "; "))
            } else if appIntents.values.contains(where: { if case .cannotProtect = $0 { return true }; return false }) {
                statuses[app.bundleIdentifier] = .cannotProtect("Required protection evidence is unavailable.")
            } else {
                statuses[app.bundleIdentifier] = .cannotProtect("No validated blur evidence is available.")
            }
        }
        for app in configuration.applications where !apps.contains(app) { statuses[app.bundleIdentifier] = .notRunning }
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
    func currentFrontmost() -> ProcessInstance? { focus.currentInstance() }
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
        onEvent?(FocusEvent(receivedAt: .now, frontmost: currentFrontmost(), kind: kind, terminatedPID: nil))
    }
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate]) -> [WindowKey: OverlayObservation] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return intents.reduce(into: [:]) { result, entry in if case .cannotProtect(let reason) = entry.value { result[entry.key] = .failed(reason: reason) } } }
        let layout = ScreenLayout(primaryScreenFrame: primary.frame, screenFrames: screens.map(\.frame))
        return overlays.reconcile(intents, windows: windows, screenLayout: layout)
    }
    public func removeAllOverlays() { overlays.removeAll() }
}

extension WindowProtectionCoordinator.Runtime {
    func eligibilityFailure(for bundleIdentifier: String) -> String? { nil }
    func retainTrackers(for instances: Set<ProcessInstance>) {}
}

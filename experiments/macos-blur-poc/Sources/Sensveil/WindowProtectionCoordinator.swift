import AppKit
import Foundation
import PoCCore

/// Main-actor bridge between application focus, conservative window identity and
/// the material adapter. The adapter's requestSubmitted result is deliberately
/// kept unverified; no public AppKit API proves composited pixels are private.
@MainActor
final class WindowProtectionCoordinator {
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
    convenience init() {
        let registry = ProcessRegistry()
        let focus = FocusMonitor(registry: registry)
        let tracker = WindowTracker(registry: registry)
        let overlays = MaterialOverlayCoordinator()
        self.init(runtime: AdapterRuntime(focus: focus, tracker: tracker, overlays: overlays, registry: registry))
    }

    func start(configuration: ProtectionConfiguration) {
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

    func stop() {
        guard isStarted else { return }
        runtime.stop()
        runtime.removeAllOverlays()
        snapshots.removeAll()
        overlayKeys.removeAll()
        selectedInstances.removeAll()
        statuses = Dictionary(uniqueKeysWithValues: configuration.applications.map { ($0.bundleIdentifier, .notRunning) })
        frontmost = nil
        isStarted = false
    }

    func setConfiguration(_ configuration: ProtectionConfiguration) {
        self.configuration = configuration
        isPaused = configuration.isGloballyPaused
        guard isStarted else { return }
        runtime.removeAllOverlays()
        overlayKeys.removeAll()
        snapshots.removeAll()
        reconcile()
    }

    func setGlobalPause(_ paused: Bool) {
        isPaused = paused
        configuration.isGloballyPaused = paused
        guard isStarted else { return }
        if paused { runtime.removeAllOverlays() }
        reconcile()
    }

    func status(for application: ProtectedApplication) -> ProtectionStatus {
        status(for: application.bundleIdentifier)
    }

    func status(for bundleIdentifier: String) -> ProtectionStatus {
        statuses[bundleIdentifier] ?? .notRunning
    }

    func removeAllOverlays() {
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
        case .launch, .activation, .startup:
            break
        }
        reconcile()
    }

    private func reconcile() {
        guard isStarted else { return }
        let apps = configuration.applications.filter(\.isEnabled)
        if configuration.applications.count > ConfigurationStore.freeApplicationLimit {
            statuses = Dictionary(uniqueKeysWithValues: configuration.applications.map { ($0.bundleIdentifier, .overFreeLimit) })
        }
        var targets: [(bundle: String, instance: ProcessInstance)] = []
        for application in apps {
            let instances = runtime.runningInstances(for: application.bundleIdentifier)
            selectedInstances[application.bundleIdentifier] = Set(instances)
            targets.append(contentsOf: instances.map { (application.bundleIdentifier, $0) })
            for instance in instances {
                if let snapshot = runtime.snapshot(for: instance) { snapshots[instance] = snapshot }
            }
        }
        let live = Set(targets.map(\.instance))
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
            if !isEligible(bundleIdentifier: app.bundleIdentifier) { statuses[app.bundleIdentifier] = .cannotProtect("Configured application identity is not eligible."); continue }
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
        return bundleIdentifier != own && bundleIdentifier != "com.nieanshow.sensveil.fixture" && !bundleIdentifier.lowercased().contains("sensveilfixture")
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
private final class AdapterRuntime: WindowProtectionCoordinator.Runtime {
    let focus: FocusMonitor
    var trackers: [ProcessInstance: WindowTracker] = [:]
    let overlays: MaterialOverlayCoordinator
    var overlayKeys: Set<WindowKey> { overlays.overlayKeys }
    let registry: ProcessRegistry
    init(focus: FocusMonitor, tracker: WindowTracker, overlays: MaterialOverlayCoordinator, registry: ProcessRegistry) { self.focus = focus; self.trackers = [:]; self.overlays = overlays; self.registry = registry }
    func start(onEvent: @escaping (FocusEvent) -> Void) { focus.start(onEvent: onEvent) }
    func stop() { focus.stop(); trackers.values.forEach { $0.stop() }; trackers.removeAll() }
    func currentFrontmost() -> ProcessInstance? { focus.currentInstance() }
    func runningInstances(for bundleIdentifier: String) -> [ProcessInstance] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier == bundleIdentifier, !app.isTerminated, let launchDate = app.launchDate else { return nil }
            return registry.observe(pid: app.processIdentifier, launchDate: launchDate)
        }
    }
    func snapshot(for instance: ProcessInstance) -> WindowSnapshot? {
        let tracker: WindowTracker
        if let existing = trackers[instance] {
            tracker = existing
        } else {
            tracker = WindowTracker(registry: registry)
            trackers[instance] = tracker
            tracker.start(for: instance) { _ in }
        }
        return tracker.snapshot(for: instance)
    }
    func permissionStates() -> [PermissionState] { [AXIsProcessTrusted() ? .granted : .notGranted] }
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate]) -> [WindowKey: OverlayObservation] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return intents.reduce(into: [:]) { result, entry in if case .cannotProtect(let reason) = entry.value { result[entry.key] = .failed(reason: reason) } } }
        let layout = ScreenLayout(primaryScreenFrame: primary.frame, screenFrames: screens.map(\.frame))
        return overlays.reconcile(intents, windows: windows, screenLayout: layout)
    }
    func removeAllOverlays() { overlays.removeAll() }
}

import AppKit
import Combine
import PoCCore

@MainActor
final class PoCController: ObservableObject {
    static let bundleIdentifier = "com.nieanshow.sensveil.poc"
    static let fixtureBundleIdentifier = "com.nieanshow.sensveil.fixture"

    @Published private(set) var selectedBundleIdentifier: String?
    @Published private(set) var selectedApplication: NSRunningApplication?
    @Published private(set) var isExperimentEnabled = false
    @Published private(set) var accessibilityPermission: PermissionState = .unknown
    @Published private(set) var screenCapturePermission: PermissionState = .unknown
    @Published private(set) var targetMessage = "No target selected"
    @Published private(set) var experimentMessage = "Experiment not validated"
    @Published private(set) var windowMessage = "No window snapshot"
    @Published private(set) var measurementMessage = "No measurements"
    @Published private(set) var latestSnapshot: WindowSnapshot?
    @Published private(set) var frontmostInstance: ProcessInstance?
    @Published private(set) var isSuspended = false
    @Published private(set) var requiresRevalidation = true
    @Published private(set) var selectedInstance: ProcessInstance?

    var onStateChange: (@MainActor () -> Void)?
    private let permissions = PermissionCoordinator()
    private let registry = ProcessRegistry()
    private lazy var focusMonitor = FocusMonitor(registry: registry)
    private lazy var windowTracker = WindowTracker(registry: registry)
    let measurements = MeasurementRecorder()
    private lazy var overlayCoordinator = MaterialOverlayCoordinator(measurements: measurements)
    private var diagnosticWindow: DiagnosticWindow?
    private var permissionPoll: Task<Void, Never>?
    private var displayOptionsObserver: NSObjectProtocol?
    private var appearanceObserver: NSKeyValueObservation?

    init() {
        refreshPermissions()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.materialSettingsChanged() }
        }
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.materialSettingsChanged() }
        }
        focusMonitor.start { [weak self] event in
            guard let self else { return }
            self.frontmostInstance = event.frontmost
            self.measurements.record(MeasurementEvent(phase: .focusReceived, receivedAt: event.receivedAt))
            // Activation removes foreground overlays before enumeration. Lifecycle/layout
            // events must invalidate their stale snapshot before attempting reconciliation.
            if case .activation = event.kind { self.notifyStateChange() }
            switch event.kind {
            case .sleep:
                self.isSuspended = true
                self.invalidateSnapshot()
                self.windowTracker.stop()
            case .wake:
                self.isSuspended = false
                self.invalidateSnapshot()
                self.restartTracking()
            case .termination:
                if event.terminatedPID == self.selectedInstance?.pid {
                    self.clearTarget(message: "Selected fixture exited; select its new instance after relaunch")
                } else { self.windowTracker.refresh() }
            case .screens, .space:
                self.invalidateSnapshot()
                self.windowTracker.refresh()
            default: self.windowTracker.refresh()
            }
            self.updateMeasurementMessage()
            self.notifyStateChange()
        }
        permissionPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                self.refreshPermissions()
            }
        }
    }

    func showDiagnostics() {
        if diagnosticWindow == nil { diagnosticWindow = DiagnosticWindow(controller: self) }
        diagnosticWindow?.showWindow(nil)
    }

    func stop() {
        permissionPoll?.cancel()
        permissionPoll = nil
        focusMonitor.stop()
        windowTracker.stop()
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
        displayOptionsObserver = nil
        appearanceObserver?.invalidate()
        appearanceObserver = nil
        isExperimentEnabled = false
        invalidateSnapshot()
        onStateChange = nil
    }

    func selectTarget(bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty,
              bundleIdentifier != Self.bundleIdentifier,
              bundleIdentifier == Self.fixtureBundleIdentifier else {
            clearTarget(message: "Only the verified Sensveil Fixture can be selected")
            return
        }

        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter(Self.isVerifiedFixture)
        guard candidates.count == 1, let application = candidates.first,
              let launchDate = application.launchDate else {
            clearTarget(message: "Start one Sensveil Fixture app, then select it")
            return
        }

        selectedBundleIdentifier = bundleIdentifier
        selectedApplication = application
        selectedInstance = registry.observe(pid: application.processIdentifier, launchDate: launchDate)
        targetMessage = "Sensveil Fixture (verified running instance)"
        invalidateSnapshot()
        restartTracking()
        notifyStateChange()
    }

    private func restartTracking() {
        guard let selectedInstance, !isSuspended else { return }
        windowTracker.start(for: selectedInstance) { [weak self] snapshot in
            guard let self, self.selectedInstance == snapshot.target else { return }
            self.latestSnapshot = snapshot
            self.requiresRevalidation = !snapshot.issues.isEmpty
            let accepted = snapshot.windows.count
            let rejected = snapshot.issues.count
            let reasons = Set(snapshot.issues.map(\.reason)).sorted().joined(separator: "; ")
            self.windowMessage = "Matched \(accepted) / CG \(snapshot.cgCount) / AX \(snapshot.axCount); issues \(rejected); minimized \(snapshot.minimizedCount)"
            if !reasons.isEmpty { self.windowMessage += "\n" + reasons }
            self.accessibilityPermission = self.permissions.accessibilityStatus()
            self.measurements.record(MeasurementEvent(phase: .snapshotReady, windowCount: accepted,
                                                       failures: snapshot.issues.map(\.kind)))
            self.updateMeasurementMessage()
            self.notifyStateChange()
        }
    }

    func setExperimentEnabled(_ enabled: Bool) {
        if enabled {
            guard let application = selectedApplication, Self.isVerifiedFixture(application) else {
                clearTarget(message: "A verified running fixture is required")
                return
            }
        }
        isExperimentEnabled = enabled
        overlayCoordinator.removeAll()
        experimentMessage = enabled ? "Experiment enabled; protection not validated" : "Experiment not validated"
        notifyStateChange()
    }

    func refreshPermissions() {
        let previousPermission = accessibilityPermission
        accessibilityPermission = permissions.accessibilityStatus()
        screenCapturePermission = permissions.screenCaptureStatus()
        if let application = selectedApplication {
            guard Self.isVerifiedFixture(application), let launchDate = application.launchDate,
                  registry.observe(pid: application.processIdentifier, launchDate: launchDate) == selectedInstance else {
                clearTarget(message: "Selected fixture lifetime can no longer be verified")
                return
            }
        }
        if accessibilityPermission != previousPermission {
            invalidateSnapshot()
            windowTracker.refresh()
        }
        notifyStateChange()
    }

    func requestAccessibility() {
        _ = permissions.requestAccessibility()
        refreshPermissions()
    }

    func requestScreenCapture() {
        _ = permissions.requestScreenCapture()
        refreshPermissions()
    }

    private func clearTarget(message: String) {
        selectedApplication = nil
        selectedBundleIdentifier = nil
        selectedInstance = nil
        windowTracker.stop()
        isExperimentEnabled = false
        targetMessage = message
        windowMessage = "No window snapshot"
        experimentMessage = "Experiment not validated"
        invalidateSnapshot()
        notifyStateChange()
    }

    private func invalidateSnapshot() {
        overlayCoordinator.removeAll()
        latestSnapshot = nil
        requiresRevalidation = true
        measurements.record(MeasurementEvent(phase: .invalidated))
        updateMeasurementMessage()
        notifyStateChange()
    }

    private func materialSettingsChanged() {
        invalidateSnapshot()
        windowTracker.refresh()
    }

    private func notifyStateChange() {
        reconcileOverlays()
        onStateChange?()
    }

    private func reconcileOverlays() {
        guard isExperimentEnabled else {
            overlayCoordinator.removeAll()
            experimentMessage = "Experiment not validated"
            return
        }
        let windows = latestSnapshot?.windows ?? []
        let selected = Set(selectedInstance.map { [$0] } ?? [])
        let intents = ProtectionReducer.reduce(ProtectionInput(
            frontmost: frontmostInstance, selected: selected, windows: windows,
            previousOverlayKeys: overlayCoordinator.overlayKeys, permissions: [accessibilityPermission],
            isSuspended: isSuspended, requiresRevalidation: requiresRevalidation))
        guard let primaryScreen = NSScreen.screens.first else {
            overlayCoordinator.removeAll()
            experimentMessage = "Cannot protect: display layout is unavailable"
            return
        }
        let observations = overlayCoordinator.reconcile(intents, windows: windows,
            screenLayout: ScreenLayout(primaryScreenFrame: primaryScreen.frame,
                                       screenFrames: NSScreen.screens.map(\.frame)))
        let failures = observations.values.compactMap { observation -> String? in
            if case .failed(let reason) = observation { return reason }
            return nil
        }
        if !failures.isEmpty {
            experimentMessage = "Cannot protect: " + Set(failures).sorted().joined(separator: "; ")
        } else if observations.values.contains(.requestSubmitted) {
            experimentMessage = "Experimental overlay active (unverified)"
        } else if frontmostInstance == selectedInstance, selectedInstance != nil {
            experimentMessage = "Fixture foreground; overlays removed (experiment unverified)"
        } else if requiresRevalidation {
            experimentMessage = "Cannot protect: window or material evidence requires revalidation"
        } else {
            experimentMessage = "Cannot protect: no eligible visible fixture windows"
        }
        updateMeasurementMessage()
    }

    private func updateMeasurementMessage() {
        let matched = measurements.phaseCounts[.snapshotReady, default: 0]
        let invalidated = measurements.phaseCounts[.invalidated, default: 0]
        let requested = measurements.phaseCounts[.overlayRequested, default: 0]
        let removed = measurements.phaseCounts[.overlayRemoved, default: 0]
        measurementMessage = "In-memory phases: \(measurements.entries.count) · snapshots \(matched) · invalidations \(invalidated)\nOverlay API requests \(requested) · removals \(removed); presentation timing unmeasured"
    }

    private static func isVerifiedFixture(_ application: NSRunningApplication) -> Bool {
        guard !application.isTerminated, application.processIdentifier > 0,
              application.launchDate != nil,
              application.activationPolicy == .regular,
              application.bundleIdentifier == fixtureBundleIdentifier,
              let bundleURL = application.bundleURL,
              let bundle = Bundle(url: bundleURL),
              bundle.bundleIdentifier == fixtureBundleIdentifier,
              let executableURL = application.executableURL,
              let declaredExecutable = bundle.executableURL else { return false }
        return executableURL.standardizedFileURL.resolvingSymlinksInPath() ==
            declaredExecutable.standardizedFileURL.resolvingSymlinksInPath()
    }
}

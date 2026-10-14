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
    @Published private(set) var materialTier: MaterialTier = .standard
    @Published private(set) var accessibilityPermission: PermissionState = .unknown
    @Published private(set) var screenCapturePermission: PermissionState = .unknown
    @Published private(set) var targetMessage = "No target selected"
    @Published private(set) var experimentMessage = "Experiment not validated"
    @Published private(set) var windowMessage = "No window snapshot"
    @Published private(set) var measurementMessage = "No measurements"
    @Published private(set) var orderingDiagnosticMessage = "No ordering metadata snapshot"
    @Published private(set) var latestSnapshot: WindowSnapshot?
    @Published private(set) var frontmostInstance: ProcessInstance?
    @Published private(set) var isSuspended = false
    @Published private(set) var requiresRevalidation = true
    @Published private(set) var selectedInstance: ProcessInstance?
    @Published private(set) var contourWindowID: UInt32?
    @Published private(set) var isContourCaptureRunning = false
    @Published private(set) var contourMessage = "Contour study stopped; no capture"
    @Published private(set) var contourSilhouette: CGImage?

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
    private var contourRevision = UUID()
    private var contourTask: Task<Void, Never>?
    private var contourTrackedWindow: WindowCandidate?
    private var contourDisplaySignature: [ContourDisplay]?
    private struct ContourDisplay: Equatable {
        let frame: CGRect
        let scale: CGFloat
        let identifier: NSNumber?
    }
    private enum ReconcileSource: String {
        case explicit, snapshot, focusWithdrawal, permissionPoll, experiment, materialTier, invalidation
    }
    private var lastReconcileSource: ReconcileSource = .explicit
    private var reconcileCount: UInt64 = 0
    private var snapshotReconcileCount: UInt64 = 0

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
            // Foreground or unknown activation withdraws overlays before enumeration.
            // Background activation reconciles only through the fresh snapshot callback.
            if case .activation = event.kind,
               self.frontmostInstance == nil || self.frontmostInstance == self.selectedInstance {
                self.notifyStateChange(source: .focusWithdrawal)
            }
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
            self.publishStateChange()
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
        publishStateChange()
    }

    private func restartTracking() {
        guard let selectedInstance, !isSuspended else { return }
        windowTracker.start(for: selectedInstance) { [weak self] snapshot in
            guard let self, self.selectedInstance == snapshot.target else { return }
            self.validateContourSnapshot(snapshot)
            self.latestSnapshot = snapshot
            self.requiresRevalidation = !snapshot.issues.isEmpty
            let accepted = snapshot.windows.count
            let rejected = snapshot.issues.count
            let reasons = Set(snapshot.issues.map(\.reason)).sorted().joined(separator: "; ")
            let excluded = Set(snapshot.exclusions.map(\.kind.rawValue)).sorted().joined(separator: ", ")
            self.windowMessage = "Matched \(accepted) / CG \(snapshot.cgCount) / AX \(snapshot.axCount); issues \(rejected); excluded \(snapshot.exclusions.count); minimized \(snapshot.minimizedCount)"
            if !reasons.isEmpty { self.windowMessage += "\n" + reasons }
            if !excluded.isEmpty { self.windowMessage += "\nExcluded (never protected): " + excluded }
            self.accessibilityPermission = self.permissions.accessibilityStatus()
            self.measurements.record(MeasurementEvent(phase: .snapshotReady, windowCount: accepted,
                                                       failures: snapshot.issues.map(\.kind)))
            self.updateMeasurementMessage()
            self.notifyStateChange(source: .snapshot)
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
        overlayCoordinator.removeAll(clearOrderingDiagnostics: true)
        experimentMessage = enabled ? "Experiment enabled; protection not validated" : "Experiment not validated"
        notifyStateChange(source: .experiment)
    }

    /// Operator-selected material candidate. An existing overlay re-anchors before it re-crossfades.
    func setMaterialTier(_ tier: MaterialTier) {
        guard tier != materialTier else { return }
        materialTier = tier
        overlayCoordinator.setTier(tier)
        notifyStateChange(source: .materialTier)
    }

    var materialParameterSummary: String { overlayCoordinator.parameterSummary }

    var transitionSummary: String { overlayCoordinator.transitionSummary }

    func refreshPermissions() {
        let previousPermission = accessibilityPermission
        let previousScreenCapturePermission = screenCapturePermission
        accessibilityPermission = permissions.accessibilityStatus()
        screenCapturePermission = permissions.screenCaptureStatus()
        if (accessibilityPermission != .granted || screenCapturePermission != .granted),
           contourTrackedWindow != nil || previousPermission != accessibilityPermission ||
           previousScreenCapturePermission != screenCapturePermission {
            invalidateContour(message: "Contour study requires Accessibility and Screen Recording")
        } else if previousScreenCapturePermission != screenCapturePermission {
            invalidateContour(message: "Screen Recording changed; capture manually after revalidation")
        }
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
            publishStateChange()
        } else {
            notifyStateChange(source: .permissionPoll)
        }
    }

    func requestAccessibility() {
        _ = permissions.requestAccessibility()
        refreshPermissions()
    }

    func requestScreenCapture() {
        _ = permissions.requestScreenCapture()
        refreshPermissions()
    }

    var contourWindows: [WindowCandidate] { latestSnapshot?.windows ?? [] }

    var canCaptureContour: Bool {
        !isContourCaptureRunning && !isSuspended && accessibilityPermission == .granted &&
            screenCapturePermission == .granted && selectedContourWindow != nil
    }

    private var selectedContourWindow: WindowCandidate? {
        guard let contourWindowID, let selectedInstance else { return nil }
        let matches = contourWindows.filter { $0.key.process == selectedInstance && $0.key.cgWindowID == contourWindowID }
        return matches.count == 1 ? matches.first : nil
    }

    func selectContourWindow(_ windowID: UInt32?) {
        guard windowID != contourWindowID else { return }
        invalidateContour(message: "Window selection changed; no contour result")
        contourWindowID = windowID
    }

    func stopContourStudy() {
        invalidateContour(message: "Contour study stopped; result discarded")
    }

    func captureContourOnce() {
        guard canCaptureContour, let window = selectedContourWindow else { return }
        invalidateContour(message: "Capturing one synthetic fixture window")
        let revision = contourRevision
        let displays = currentContourDisplays()
        guard contourTargetIsCurrent(window, displays: displays) else {
            contourMessage = "Cannot capture: current fixture geometry, display or permission is unavailable"
            return
        }
        contourTrackedWindow = window
        contourDisplaySignature = displays
        isContourCaptureRunning = true
        contourTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Cancellation expires the ticket but does not release the in-flight slot:
            // SCK may finish its callback later and a second request must not overlap it.
            defer {
                self.contourTask = nil
                self.isContourCaptureRunning = false
            }
            do {
                let artifact = try await ContourProbe.capture(window: window) { [weak self] in
                    guard let self, self.contourRevision == revision else { return false }
                    return self.contourTargetIsCurrent(window, displays: displays)
                }
                guard self.contourRevision == revision,
                      self.contourTargetIsCurrent(window, displays: displays) else { return }
                self.contourSilhouette = artifact.silhouette
                self.contourMessage = "Synthetic CG window \(window.key.cgWindowID)\n" + artifact.summary
            } catch {
                guard self.contourRevision == revision else { return }
                self.contourSilhouette = nil
                self.contourMessage = (error as? ContourProbeFailure)?.message
                    ?? "Cannot determine contour: alpha analysis failed"
            }
        }
    }

    private func contourTargetIsCurrent(_ window: WindowCandidate, displays: [ContourDisplay]) -> Bool {
        guard !isSuspended, contourWindowID == window.key.cgWindowID,
              selectedInstance == window.key.process,
              permissions.accessibilityStatus() == .granted, permissions.screenCaptureStatus() == .granted,
              let application = selectedApplication, Self.isVerifiedFixture(application),
              let launchDate = application.launchDate,
              registry.observe(pid: application.processIdentifier, launchDate: launchDate) == window.key.process,
              displays == currentContourDisplays(), let primary = NSScreen.screens.first else { return false }
        let rect = CoordinateTransform.appKitRect(from: window.bounds, primaryScreenFrame: primary.frame)
        // This initial spike excludes offscreen and cross-display captures to avoid
        // interpreting clipping or mixed backing scales as an outer window boundary.
        guard displays.contains(where: { $0.frame.contains(rect) && $0.scale.isFinite && $0.scale > 0 }) else { return false }
        let snapshot = windowTracker.snapshot(for: window.key.process)
        let matches = snapshot.windows.filter { $0.key == window.key }
        return matches.count == 1 && matches.first == window
    }

    private func currentContourDisplays() -> [ContourDisplay] {
        NSScreen.screens.map { ContourDisplay(frame: $0.frame, scale: $0.backingScaleFactor,
            identifier: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) }
    }

    private func validateContourSnapshot(_ snapshot: WindowSnapshot) {
        guard let tracked = contourTrackedWindow else { return }
        let matches = snapshot.windows.filter { $0.key == tracked.key }
        guard matches.count == 1, matches.first == tracked,
              contourDisplaySignature == currentContourDisplays() else {
            invalidateContour(message: "Discarded: fixture window geometry or display changed")
            return
        }
    }

    private func invalidateContour(message: String) {
        contourRevision = UUID()
        contourTask?.cancel()
        contourTrackedWindow = nil
        contourDisplaySignature = nil
        contourSilhouette = nil
        contourMessage = message
    }

    private func clearTarget(message: String) {
        contourWindowID = nil
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
        invalidateContour(message: "Contour evidence invalidated; capture manually after revalidation")
        overlayCoordinator.removeAll()
        latestSnapshot = nil
        requiresRevalidation = true
        measurements.record(MeasurementEvent(phase: .invalidated))
        updateMeasurementMessage()
        notifyStateChange(source: .invalidation)
    }

    private func materialSettingsChanged() {
        invalidateSnapshot()
        windowTracker.refresh()
    }

    private func notifyStateChange(source: ReconcileSource = .explicit) {
        lastReconcileSource = source
        reconcileCount &+= 1
        if source == .snapshot { snapshotReconcileCount &+= 1 }
        reconcileOverlays()
        publishStateChange()
    }

    // Publishing after a synchronous tracker callback must not repeat ordering requests.
    private func publishStateChange() {
        orderingDiagnosticMessage = "Reconciles \(reconcileCount); snapshots \(snapshotReconcileCount); last \(lastReconcileSource.rawValue)\n"
            + overlayCoordinator.orderingDiagnosticSummary
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
        let requestCount = observations.values.filter { $0 == .requestSubmitted }.count
        if !failures.isEmpty, requestCount > 0 {
            experimentMessage = "Partial experimental requests (unverified): \(requestCount) submitted; \(failures.count) windows cannot protect. "
                + Set(failures).sorted().joined(separator: "; ")
        } else if !failures.isEmpty {
            experimentMessage = "Cannot protect: " + Set(failures).sorted().joined(separator: "; ")
        } else if requestCount > 0 {
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

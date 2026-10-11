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
    @Published private(set) var targetMessage = "No target selected"
    @Published private(set) var experimentMessage = "Experiment not validated"

    var onStateChange: (@MainActor () -> Void)?
    private let permissions = PermissionCoordinator()
    private var diagnosticWindow: DiagnosticWindow?

    init() {
        refreshPermissions()
    }

    func showDiagnostics() {
        if diagnosticWindow == nil { diagnosticWindow = DiagnosticWindow(controller: self) }
        diagnosticWindow?.showWindow(nil)
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
        guard candidates.count == 1, let application = candidates.first else {
            clearTarget(message: "Start one Sensveil Fixture app, then select it")
            return
        }

        selectedBundleIdentifier = bundleIdentifier
        selectedApplication = application
        targetMessage = "Sensveil Fixture (PID \(application.processIdentifier))"
        onStateChange?()
    }

    func setExperimentEnabled(_ enabled: Bool) {
        if enabled {
            guard let application = selectedApplication, Self.isVerifiedFixture(application) else {
                clearTarget(message: "A verified running fixture is required")
                return
            }
        }
        isExperimentEnabled = enabled
        experimentMessage = enabled ? "Experiment enabled; protection not validated" : "Experiment not validated"
        onStateChange?()
    }

    func refreshPermissions() {
        accessibilityPermission = permissions.accessibilityStatus()
        if let application = selectedApplication, !Self.isVerifiedFixture(application) {
            clearTarget(message: "Selected fixture is no longer running")
        }
        onStateChange?()
    }

    func requestAccessibility() {
        accessibilityPermission = permissions.requestAccessibility()
        refreshPermissions()
    }

    private func clearTarget(message: String) {
        selectedApplication = nil
        selectedBundleIdentifier = nil
        isExperimentEnabled = false
        targetMessage = message
        experimentMessage = "Experiment not validated"
        onStateChange?()
    }

    private static func isVerifiedFixture(_ application: NSRunningApplication) -> Bool {
        guard !application.isTerminated, application.processIdentifier > 0,
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

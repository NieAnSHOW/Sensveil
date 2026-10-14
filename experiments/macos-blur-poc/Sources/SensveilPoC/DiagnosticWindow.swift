import AppKit
import SwiftUI
import PoCCore

@MainActor
final class DiagnosticWindow: NSWindowController {
    init(controller: PoCController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 530),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sensveil PoC Diagnostics"
        window.minSize = NSSize(width: 580, height: 500)
        window.contentView = NSHostingView(rootView: DiagnosticView(controller: controller))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

private struct DiagnosticView: View {
    @ObservedObject var controller: PoCController

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Sensveil PoC", systemImage: "eye.slash")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Sensveil PoC")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Target").font(.headline)
                Text(controller.targetMessage).textSelection(.enabled)
                Button("Select Sensveil Fixture") {
                    controller.selectTarget(bundleIdentifier: PoCController.fixtureBundleIdentifier)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                permissionRow("Accessibility", state: controller.accessibilityPermission) {
                    controller.requestAccessibility()
                }
                permissionRow("Screen Recording", state: controller.screenCapturePermission) {
                    controller.requestScreenCapture()
                }
            }
            Text("Screen Recording: authorized for this manual synthetic-window contour study. Permission does not validate protection.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Synthetic window contour (experimental)").font(.headline)
                Picker("Fixture window", selection: Binding(
                    get: { controller.contourWindowID },
                    set: { controller.selectContourWindow($0) })) {
                        Text("Select a fixture CG window").tag(UInt32?.none)
                        ForEach(controller.contourWindows, id: \.key) { window in
                            Text("CG \(window.key.cgWindowID) · \(Double(window.bounds.width).formatted(.number.precision(.fractionLength(0)))) x \(Double(window.bounds.height).formatted(.number.precision(.fractionLength(0)))) points")
                                .tag(Optional(window.key.cgWindowID))
                        }
                }
                HStack {
                    Button {
                        controller.captureContourOnce()
                    } label: {
                        Label(controller.isContourCaptureRunning ? "Capture pending" : "Capture once", systemImage: "camera")
                    }
                    .disabled(!controller.canCaptureContour)
                    Button { controller.stopContourStudy() } label: {
                        Label("Stop study", systemImage: "stop.fill")
                    }
                }
                Text(controller.contourMessage)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let silhouette = controller.contourSilhouette {
                    Image(decorative: silhouette, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .accessibilityLabel("Neutral experimental outer silhouette; unvalidated")
                }
            }
            HStack {
                Spacer()
                Toggle("Experiment", isOn: Binding(
                    get: { controller.isExperimentEnabled },
                    set: { controller.setExperimentEnabled($0) }))
                    .toggleStyle(.switch)
                    .disabled(controller.selectedApplication == nil)
            }
            Divider()
            Text(controller.windowMessage)
                .font(.system(.body, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(controller.measurementMessage).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Ordering metadata (unverified)").font(.headline)
                Text(controller.orderingDiagnosticMessage)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Material candidate").font(.headline)
                Picker("Material candidate", selection: Binding(
                    get: { controller.materialTier },
                    set: { controller.setMaterialTier($0) })) {
                        ForEach(MaterialTier.allCases, id: \.self) { tier in
                            Text(tier.summary).tag(tier)
                        }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(controller.materialParameterSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Transition: " + controller.transitionSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Calibration: 1 second. Continuous-drag timing, crossfade presentation timing and sheet protection are unvalidated.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(controller.experimentMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func permissionRow(_ title: String, state: PermissionState, request: @escaping () -> Void) -> some View {
        GridRow {
            Text(title)
            Text(permissionLabel(state)).foregroundStyle(state == .granted ? Color.green : Color.secondary)
            Button(title == "Screen Recording" ? "Request Recording" : "Request", action: request)
                .disabled(state == .granted)
            Button { controller.refreshPermissions() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh \(title) permission")
            .accessibilityLabel("Refresh \(title) permission")
        }
    }

    private func permissionLabel(_ state: PermissionState) -> String {
        switch state {
        case .unknown: "Not checked"
        case .notGranted: "Not granted"
        case .granted: "Granted"
        }
    }
}

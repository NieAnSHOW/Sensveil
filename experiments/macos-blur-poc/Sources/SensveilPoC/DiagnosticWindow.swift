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
            }
            HStack {
                Button { controller.refreshPermissions() } label: {
                    Label("Refresh permissions", systemImage: "arrow.clockwise")
                }
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
            Text("Material: hudWindow / active / behindWindow")
                .font(.caption).foregroundStyle(.secondary)
            Text("Calibration: 1 second. Continuous-drag timing and sheet protection are unvalidated.")
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
            Button("Request", action: request).disabled(state == .granted)
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

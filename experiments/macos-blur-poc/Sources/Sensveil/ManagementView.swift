import AppKit
import SwiftUI

public struct ManagementView: View {
    @ObservedObject private var controller: SensveilController
    @ObservedObject private var permissions: PermissionCoordinator
    @State private var showDiagnosticPermissions = false

    public init(controller: SensveilController, permissions: PermissionCoordinator) {
        self.controller = controller; self.permissions = permissions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "eye.slash.fill").font(.system(size: 28)).foregroundStyle(.tint)
                Text("Sensveil").font(.title.bold())
                Spacer()
                Toggle("暂停保护", isOn: Binding(get: { controller.configuration.isGloballyPaused }, set: { controller.setGlobalPause($0) }))
                    .toggleStyle(.switch).fixedSize().disabled(controller.isConfigurationReadOnly)
            }
            Divider()
            HStack {
                Text("防窥应用").font(.headline)
                Spacer()
                Text("\(controller.configuration.applications.count) / 2").monospacedDigit().foregroundStyle(.secondary)
            }
            if controller.configuration.applications.isEmpty {
                Text("尚未添加应用").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            } else {
                ForEach(controller.configuration.applications) { application in configuredRow(application) }
            }
            HStack {
                Button { Task { await controller.addApplication() } } label: { Label("添加应用…", systemImage: "plus") }
                    .disabled(!controller.canAddApplication)
                Text(controller.freeLimitMessage).font(.caption).foregroundStyle(.secondary)
            }
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text("可添加应用").font(.headline)
                Spacer()
                Button { controller.refreshApplications() } label: { Image(systemName: "arrow.clockwise") }.help("刷新应用列表")
            }
            TextField("搜索名称或应用标识", text: $controller.searchText).textFieldStyle(.roundedBorder)
            List(controller.applications) { application in
                HStack(spacing: 10) {
                    appIcon(application.iconData)
                    appIdentity(application.displayName, bundleIdentifier: application.bundleIdentifier)
                    Spacer()
                    if controller.configuration.applications.contains(where: { $0.id == application.id }) {
                        Image(systemName: "checkmark").foregroundStyle(.secondary).help("已添加")
                    } else {
                        Button { controller.addApplication(application) } label: { Image(systemName: "plus") }
                            .help("添加 \(application.displayName)").disabled(!controller.canAddApplication)
                    }
                }.padding(.vertical, 3)
            }.frame(minHeight: 100)
            Divider()
            HStack {
                Label("辅助功能", systemImage: "accessibility")
                Spacer()
                Text(permissions.accessibility == .granted ? "已授予" : "未授予").foregroundStyle(.secondary)
                Button("请求权限") { permissions.requestAccessibility(); controller.refreshApplications() }
                    .disabled(permissions.accessibility == .granted)
            }
            DisclosureGroup("可选诊断权限", isExpanded: $showDiagnosticPermissions) {
                HStack {
                    Text("屏幕录制（仅诊断）")
                    Spacer()
                    Text(permissions.screenRecording == .granted ? "已授予" : "未授予").foregroundStyle(.secondary)
                    Button("请求权限") { permissions.requestScreenRecording(); controller.refreshApplications() }
                        .disabled(permissions.screenRecording == .granted)
                }.padding(.top, 6)
            }
            Toggle("登录启动（首期暂未实现）", isOn: .constant(false)).disabled(true)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 600)
        .onChange(of: permissions.accessibility) { _, _ in controller.refreshApplications() }
        .onChange(of: permissions.screenRecording) { _, _ in controller.refreshApplications() }
    }

    private func configuredRow(_ application: ProtectedApplication) -> some View {
        let status = StatusPresentation(controller.status(for: application))
        return HStack(alignment: .top, spacing: 10) {
            appIcon(application.iconData)
            VStack(alignment: .leading, spacing: 4) {
                appIdentity(application.displayName, bundleIdentifier: application.bundleIdentifier)
                Label(status.title, systemImage: status.symbol).font(.callout)
                Text(status.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("保护 \(application.displayName)", isOn: Binding(get: {
                controller.configuration.applications.first(where: { $0.id == application.id })?.isEnabled ?? false
            }, set: { controller.setApplicationEnabled(application, enabled: $0) }))
                .labelsHidden().toggleStyle(.switch).disabled(controller.isConfigurationReadOnly)
            Button { controller.removeApplication(application) } label: { Image(systemName: "trash") }
                .help("移除 \(application.displayName)").disabled(controller.isConfigurationReadOnly)
        }.padding(.vertical, 4)
    }

    private func appIdentity(_ name: String, bundleIdentifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).lineLimit(2)
            Text(bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        }
    }

    private func appIcon(_ data: Data?) -> some View {
        Group {
            if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable() }
            else { Image(systemName: "app").resizable().foregroundStyle(.secondary) }
        }.scaledToFit().frame(width: 28, height: 28)
    }
}

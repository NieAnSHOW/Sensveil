import AppKit
import SwiftUI

enum ManagementPage: String, CaseIterable, Identifiable {
    case applications, effects, schedule, permissions, general, about

    var id: Self { self }
    var title: String {
        switch self {
        case .applications: "防窥应用"
        case .effects: "保护效果"
        case .schedule: "保护时段"
        case .permissions: "权限"
        case .general: "通用"
        case .about: "关于"
        }
    }
    var symbol: String {
        switch self {
        case .applications: "app.badge.checkmark"
        case .effects: "eye.slash"
        case .schedule: "clock"
        case .permissions: "lock.shield"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .applications: "选择需要保护的应用，并查看当前保护状态。"
        case .effects: "调整窗口模糊强度与守护提示。"
        case .schedule: "按每周安排和节假日规则设置保护时间。"
        case .permissions: "管理窗口保护所需的系统授权。"
        case .general: "管理 Sensveil 的应用偏好。"
        case .about: "版本信息与项目链接。"
        }
    }
}

@MainActor
final class ManagementNavigation: ObservableObject {
    @Published var selection: ManagementPage? = .applications
}

public struct ManagementView: View {
    @ObservedObject private var controller: SensveilController
    @ObservedObject private var permissions: PermissionCoordinator
    @ObservedObject private var navigation: ManagementNavigation
    @StateObject private var settings: ProtectionSettingsSession
    @State private var showApplicationPicker = false

    public init(controller: SensveilController, permissions: PermissionCoordinator) {
        self.init(controller: controller, permissions: permissions, navigation: ManagementNavigation())
    }

    init(controller: SensveilController, permissions: PermissionCoordinator, navigation: ManagementNavigation) {
        self.controller = controller
        self.permissions = permissions
        self.navigation = navigation
        _settings = StateObject(wrappedValue: ProtectionSettingsSession(configuration: controller.configuration))
    }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(ManagementPage.allCases, selection: $navigation.selection) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
                .listStyle(.sidebar)
                Divider()
                Toggle("暂停保护", isOn: Binding(
                    get: { controller.configuration.isGloballyPaused },
                    set: { controller.setGlobalPause($0) }))
                    .toggleStyle(.switch)
                    .disabled(controller.isConfigurationReadOnly)
                    .padding(16)
                    .help("暂时停止所有应用的保护")
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let page = navigation.selection ?? .applications
            VStack(alignment: .leading, spacing: 0) {
                pageHeader(page)
                switch page {
                case .applications: applicationsPage
                case .effects:
                    ProtectionSettingsView(controller: controller, session: settings, page: .effects)
                        .id(ManagementPage.effects)
                case .schedule:
                    ProtectionSettingsView(controller: controller, session: settings, page: .schedule)
                        .id(ManagementPage.schedule)
                case .permissions: permissionsPage
                case .general: generalPage
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 560)
        .sheet(isPresented: $showApplicationPicker) {
            ApplicationPickerView(controller: controller)
        }
    }

    private func pageHeader(_ page: ManagementPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(page.title).font(.title2.bold())
                Spacer()
                if page == .applications {
                    Button { showApplicationPicker = true } label: {
                        Label("添加应用…", systemImage: "plus")
                    }
                    .disabled(!controller.canAddApplication)
                }
            }
            Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.isConfigurationReadOnly {
                Label("无法读取本地配置，当前设置只读。请检查配置文件后重新启动 Sensveil。", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.errorMessage { errorLabel(error) }
        }
        .padding(24)
    }

    private var applicationsPage: some View {
        Group {
            if controller.configuration.applications.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView {
                        Label("添加第一个防窥应用", systemImage: "eye.slash")
                    } description: {
                        Text("选择本机应用，为其窗口启用模糊保护。")
                    } actions: {
                        Button("添加应用…") { showApplicationPicker = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(!controller.canAddApplication)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        ForEach(controller.configuration.applications) { application in configuredRow(application) }
                    } header: {
                        Text("已配置 \(controller.configuration.applications.count) 个应用")
                    }
                }.formStyle(.grouped)
            }
        }
    }

    private var permissionsPage: some View {
        Form {
            Section("辅助功能") {
                LabeledContent("授权状态", value: permissions.accessibility == .granted ? "已授予" : "未授予")
                Text("用于识别目标应用窗口并跟随窗口位置。启用窗口保护需要此权限。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("请求辅助功能权限") { permissions.requestAccessibility() }
                    .disabled(permissions.accessibility == .granted)
            }
            Section("屏幕录制 · 可选诊断") {
                LabeledContent("授权状态", value: permissions.screenRecording == .granted ? "已授予" : "未授予")
                Text("仅用于可选诊断；日常窗口保护不依赖此权限。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("请求屏幕录制权限") { permissions.requestScreenRecording() }
                    .disabled(permissions.screenRecording == .granted)
            }
            Section {
                Button("刷新权限状态") { permissions.refresh() }
            }
        }.formStyle(.grouped)
    }

    private var generalPage: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动 Sensveil", isOn: .constant(false)).disabled(true)
                Text("登录启动暂未实现。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func configuredRow(_ application: ProtectedApplication) -> some View {
        let status = StatusPresentation(controller.status(for: application))
        return HStack(alignment: .top, spacing: 12) {
            appIcon(application.iconData)
            VStack(alignment: .leading, spacing: 6) {
                Text(application.displayName).font(.headline).lineLimit(2)
                Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
                Label(status.title, systemImage: status.symbol).font(.callout)
                Text(status.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("保护 \(application.displayName)", isOn: Binding(get: {
                controller.configuration.applications.first(where: { $0.id == application.id })?.isEnabled ?? false
            }, set: { controller.setApplicationEnabled(application, enabled: $0) }))
                .labelsHidden().toggleStyle(.switch).disabled(controller.isConfigurationReadOnly)
            Button { controller.removeApplication(application) } label: { Image(systemName: "trash") }
                .help("移除 \(application.displayName)")
                .accessibilityLabel("移除 \(application.displayName)")
                .disabled(controller.isConfigurationReadOnly)
        }.padding(.vertical, 8)
    }

    private func errorLabel(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func appIcon(_ data: Data?) -> some View {
        Group {
            if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable() }
            else { Image(systemName: "app").resizable().foregroundStyle(.secondary) }
        }.scaledToFit().frame(width: 32, height: 32)
    }
}

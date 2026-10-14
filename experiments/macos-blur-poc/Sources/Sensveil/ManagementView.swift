import AppKit
import SwiftUI

enum ManagementPage: String, CaseIterable, Identifiable {
    case applications, effects, schedule, permissions, general, about

    var id: Self { self }
    @MainActor var title: String {
        switch self {
        case .applications: L10n.text("防窥应用")
        case .effects: L10n.text("保护效果")
        case .schedule: L10n.text("保护时段")
        case .permissions: L10n.text("权限")
        case .general: L10n.text("通用")
        case .about: L10n.text("关于")
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
    @MainActor var subtitle: String {
        switch self {
        case .applications: L10n.text("选择需要保护的应用，并查看当前保护状态。")
        case .effects: L10n.text("调整窗口模糊强度与守护提示。")
        case .schedule: L10n.text("按每周安排和节假日规则设置保护时间。")
        case .permissions: L10n.text("管理窗口保护所需的系统授权。")
        case .general: L10n.text("管理 Sensveil 的应用偏好。")
        case .about: L10n.text("版本信息与项目链接。")
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
    @ObservedObject private var languagePreferences = LanguagePreferences.shared
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
                List(ManagementPage.allCases.filter { $0 != .about }, selection: $navigation.selection) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
                .listStyle(.sidebar)
                Divider()
                Button { navigation.selection = .about } label: {
                    Label(ManagementPage.about.title, systemImage: ManagementPage.about.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .foregroundStyle(navigation.selection == .about ? Color.white : Color.primary)
                        .background(navigation.selection == .about ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(navigation.selection == .about ? [.isSelected] : [])
                .padding(8)
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
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 560)
        .environment(\.locale, languagePreferences.locale)
        .sheet(isPresented: $showApplicationPicker) {
            ApplicationPickerView(controller: controller)
        }
    }

    private func pageHeader(_ page: ManagementPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(page.title).font(.title2.bold())
                Spacer()
                Button {
                    controller.setGlobalPause(!controller.configuration.isGloballyPaused)
                } label: {
                    Label(L10n.text(controller.configuration.isGloballyPaused ? "恢复保护" : "暂停保护"),
                          systemImage: controller.configuration.isGloballyPaused ? "play.fill" : "pause.fill")
                        .fixedSize(horizontal: true, vertical: false)
                }
                .disabled(controller.isConfigurationReadOnly)
                .help(L10n.text(controller.configuration.isGloballyPaused ? "恢复所有应用的保护" : "暂时停止所有应用的保护"))
            }
            Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if page == .applications {
                Button { showApplicationPicker = true } label: {
                    Label(L10n.text("添加应用…"), systemImage: "plus")
                }
                .disabled(!controller.canAddApplication)
                .padding(.top, 8)
            }
            if controller.isConfigurationReadOnly {
                Label(L10n.text("无法读取本地配置，当前设置只读。请检查配置文件后重新启动 Sensveil。"), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.localizedErrorMessage { errorLabel(error) }
        }
        .padding(24)
    }

    private var applicationsPage: some View {
        Group {
            if controller.configuration.applications.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView {
                        Label(L10n.text("添加第一个防窥应用"), systemImage: "eye.slash")
                    } description: {
                        Text(L10n.text("选择本机应用，为其窗口启用模糊保护。"))
                    } actions: {
                        Button(L10n.text("添加应用…")) { showApplicationPicker = true }
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
                        Text(L10n.format("已配置 %d 个应用", controller.configuration.applications.count))
                    }
                }.formStyle(.grouped)
            }
        }
    }

    private var permissionsPage: some View {
        Form {
            Section(L10n.text("辅助功能")) {
                LabeledContent(L10n.text("授权状态"), value: L10n.text(permissions.accessibility == .granted ? "已授予" : "未授予"))
                Text(L10n.text("用于识别目标应用窗口并跟随窗口位置。启用窗口保护需要此权限。"))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L10n.text("请求辅助功能权限")) { permissions.requestAccessibility() }
                    .disabled(permissions.accessibility == .granted)
            }
            Section(L10n.text("屏幕录制 · 可选诊断")) {
                LabeledContent(L10n.text("授权状态"), value: L10n.text(permissions.screenRecording == .granted ? "已授予" : "未授予"))
                Text(L10n.text("仅用于可选诊断；日常窗口保护不依赖此权限。"))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L10n.text("请求屏幕录制权限")) { permissions.requestScreenRecording() }
                    .disabled(permissions.screenRecording == .granted)
            }
            Section {
                Button(L10n.text("刷新权限状态")) { permissions.refresh() }
            }
        }.formStyle(.grouped)
    }

    private var generalPage: some View {
        Form {
            Section(L10n.text("语言")) {
                Picker(L10n.text("应用语言"), selection: $languagePreferences.selection) {
                    Text(L10n.text("跟随系统")).tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }
                Text(L10n.text("语言切换立即生效，未保存的保护设置会保留。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(L10n.text("启动")) {
                Toggle(L10n.text("登录时启动 Sensveil"), isOn: .constant(false)).disabled(true)
                Text(L10n.text("登录启动暂未实现。"))
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
                Label(status.localizedTitle, systemImage: status.symbol).font(.callout)
                Text(status.localizedDetail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(L10n.format("保护 %@", application.displayName), isOn: Binding(get: {
                controller.configuration.applications.first(where: { $0.id == application.id })?.isEnabled ?? false
            }, set: { controller.setApplicationEnabled(application, enabled: $0) }))
                .labelsHidden().toggleStyle(.switch).disabled(controller.isConfigurationReadOnly)
            Button { controller.removeApplication(application) } label: { Image(systemName: "trash") }
                .help(L10n.format("移除 %@", application.displayName))
                .accessibilityLabel(L10n.format("移除 %@", application.displayName))
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

import AppKit
import SwiftUI

/// A bounded native picker keeps the management page focused on protected apps.
struct ApplicationPickerView: View {
    @ObservedObject var controller: SensveilController
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isBrowsing = false
    @State private var selectionError: String?
    @FocusState private var searchIsFocused: Bool

    private var applications: [ApplicationDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return controller.availableApplications.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("添加应用").font(.title2.bold())
                Spacer()
                Button { controller.refreshApplications() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(controller.isLoadingApplications || isBrowsing)
                .help("刷新本机应用列表")
            }
            TextField("搜索名称或应用标识", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .accessibilityLabel("搜索应用")

            Group {
                if controller.isLoadingApplications && controller.availableApplications.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在查找本机应用…").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if applications.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "没有找到应用" : "没有匹配的应用", systemImage: "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty ? "刷新列表，或浏览本机选择应用。" : "试试其他名称或应用标识，也可以浏览本机选择。")
                    }
                } else {
                    List {
                        let running = applications.filter(\.isRunning)
                        let installed = applications.filter { !$0.isRunning }
                        if !running.isEmpty {
                            Section("运行中") {
                                ForEach(running) { application in applicationRow(application) }
                            }
                        }
                        if !installed.isEmpty {
                            Section("已安装") {
                                ForEach(installed) { application in applicationRow(application) }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = selectionError ?? controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("浏览…") { Task { await browseApplication() } }
                    .disabled(!controller.canAddApplication || isBrowsing)
                Text(controller.freeLimitMessage).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isBrowsing)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .onAppear { searchIsFocused = true }
    }

    private func applicationRow(_ application: ApplicationDescriptor) -> some View {
        let isAdded = controller.configuration.applications.contains { $0.id == application.id }
        return Button {
            selectionError = nil
            controller.addApplication(application)
            if controller.configuration.applications.contains(where: { $0.id == application.id }) { dismiss() }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let data = application.iconData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable()
                    } else {
                        Image(systemName: "app").resizable().foregroundStyle(.secondary)
                    }
                }.scaledToFit().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.displayName).lineLimit(1)
                    Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isAdded {
                    Label("已添加", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded || !controller.canAddApplication || isBrowsing)
        .accessibilityLabel(isAdded ? "\(application.displayName)，已添加" : "添加 \(application.displayName)，\(application.bundleIdentifier)")
    }

    private func browseApplication() async {
        isBrowsing = true
        defer { isBrowsing = false }
        selectionError = nil
        guard let application = await controller.catalog.chooseApplication() else {
            if let error = controller.catalog.lastError, error != .noApplicationSelected {
                selectionError = "无法添加所选应用。请选择具有有效标识的普通 macOS 应用。"
            }
            return
        }
        controller.addApplication(application)
        if controller.errorMessage == nil,
           controller.configuration.applications.contains(where: { $0.id == application.id }) { dismiss() }
    }
}

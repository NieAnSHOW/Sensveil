import Combine
import Foundation

@MainActor
public final class SensveilController: ObservableObject {
    @Published public private(set) var configuration: ProtectionConfiguration
    @Published public var searchText = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var configurationLoadFailed = false
    @Published public private(set) var availableApplications: [ApplicationDescriptor] = []
    @Published public private(set) var isLoadingApplications = false
    public var isConfigurationReadOnly: Bool { configurationLoadFailed }
    /// Errors are kept as canonical keys so switching language never retains
    /// a translated error from an earlier operation.
    public var localizedErrorMessage: String? { errorMessage.map(L10n.text) }
    public var localizedPauseActionTitle: String { L10n.text(pauseActionTitle) }

    public let catalog: ApplicationCatalog
    public let configurationStore: ConfigurationStore
    public let protectionCoordinator: WindowProtectionCoordinator
    private var applicationRefreshTask: Task<Void, Never>?

    public init(configurationStore: ConfigurationStore = ConfigurationStore(), catalog: ApplicationCatalog = ApplicationCatalog(), protectionCoordinator: WindowProtectionCoordinator = WindowProtectionCoordinator()) {
        self.configurationStore = configurationStore
        self.catalog = catalog
        self.protectionCoordinator = protectionCoordinator
        do {
            self.configuration = try configurationStore.load()
        } catch {
            self.configuration = ProtectionConfiguration()
            self.configurationLoadFailed = true
            self.errorMessage = "无法读取已保存的配置。为避免覆盖原文件，配置修改已锁定。"
        }
        protectionCoordinator.onStatusChange = { [weak self] in self?.objectWillChange.send() }
        protectionCoordinator.start(configuration: configuration)
        refreshApplications()
    }

    deinit {
        applicationRefreshTask?.cancel()
        let coordinator = protectionCoordinator
        Task { @MainActor in coordinator.stop() }
    }

    public func status(for application: ProtectedApplication) -> ProtectionStatus {
        protectionCoordinator.status(for: application)
    }

    /// Current schedule judgment for display; holiday availability warnings
    /// surface here independently of per-app protection statuses.
    public var scheduleEvaluation: ProtectionScheduleEvaluation? {
        protectionCoordinator.scheduleEvaluation
    }

    /// Bundled holiday calendar coverage (years and versions) for display.
    public var holidayCoverageDescription: String {
        protectionCoordinator.holidayCoverageDescription
    }

    public func setGlobalPause(_ paused: Bool) {
        guard !configurationLoadFailed else { return }
        var updated = configuration
        updated.isGloballyPaused = paused
        do {
            try configurationStore.save(updated)
            configuration = updated
            protectionCoordinator.setGlobalPause(paused)
            errorMessage = nil
        } catch { errorMessage = "无法保存配置，请检查本地文件的访问权限。" }
    }

    public func stopProtection() { protectionCoordinator.stop() }

    public var applications: [ApplicationDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableApplications.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) }
    }
    public func refreshApplications() {
        guard applicationRefreshTask == nil else { return }
        isLoadingApplications = true
        let catalog = catalog
        applicationRefreshTask = Task { [weak self] in
            let applications = await catalog.list()
            guard !Task.isCancelled, let self else { return }
            self.availableApplications = applications
            self.isLoadingApplications = false
            self.applicationRefreshTask = nil
        }
    }
    public var canAddApplication: Bool { !configurationLoadFailed }
    public var pauseActionTitle: String { configuration.isGloballyPaused ? "恢复保护" : "暂停保护" }

    public func performMenuAction(_ action: SensveilMenuAction, openManagement: () -> Void, quit: () -> Void) {
        switch action {
        case .openManagement: openManagement()
        case .togglePause: setGlobalPause(!configuration.isGloballyPaused)
        case .quit: stopProtection(); quit()
        }
    }

    /// Persists the global protection settings and publishes them only after
    /// the store accepted the write, so a failed save leaves the running
    /// configuration untouched.
    public func saveProtectionSettings(
        blurLevel: BlurLevel,
        showsProtectionLabel: Bool,
        schedule: ProtectionSchedule,
        protectionTransition: ProtectionTransition? = nil
    ) throws {
        guard !configurationLoadFailed else { throw ConfigurationError.readFailed }
        var updated = configuration
        do {
            updated.schedule = try schedule.normalized()
        } catch {
            errorMessage = "保护时段无效，请检查开始和结束时间。"
            throw error
        }
        updated.blurLevel = blurLevel
        updated.showsProtectionLabel = showsProtectionLabel
        if let protectionTransition {
            updated.protectionTransition = protectionTransition
        }
        do {
            try configurationStore.save(updated)
        } catch {
            errorMessage = "无法保存配置，请检查本地文件的访问权限。"
            throw error
        }
        configuration = updated
        protectionCoordinator.setConfiguration(updated)
        errorMessage = nil
    }

    public func setApplicationEnabled(_ application: ProtectedApplication, enabled: Bool) {
        guard !configurationLoadFailed,
              let index = configuration.applications.firstIndex(where: { $0.id == application.id }) else { return }
        var updated = configuration
        updated.applications[index].isEnabled = enabled
        do {
            try configurationStore.save(updated)
            configuration = updated
            protectionCoordinator.setConfiguration(updated)
            errorMessage = nil
        } catch { errorMessage = "无法保存配置，请检查本地文件的访问权限。" }
    }

    public func addApplication() async {
        guard !configurationLoadFailed else { return }
        guard let descriptor = await catalog.chooseApplication() else {
            if let error = catalog.lastError, error != .noApplicationSelected {
                errorMessage = "无法添加所选应用。请选择具有有效标识的普通 macOS 应用。"
            }
            return
        }
        addApplication(descriptor)
    }

    public func addApplication(_ descriptor: ApplicationDescriptor) {
        guard !configurationLoadFailed else { return }
        do {
            let protected = ProtectedApplication(bundleIdentifier: descriptor.bundleIdentifier, displayName: descriptor.displayName, iconData: descriptor.iconData)
            let updated = try configurationStore.add(protected, to: configuration)
            try configurationStore.save(updated)
            configuration = updated
            protectionCoordinator.setConfiguration(updated)
            errorMessage = nil
        } catch {
            errorMessage = "无法保存配置，请检查应用标识和本地文件的访问权限。"
        }
    }

    public func removeApplication(_ application: ProtectedApplication) {
        guard !configurationLoadFailed else { return }
        let updated = configurationStore.remove(bundleIdentifier: application.bundleIdentifier, from: configuration)
        do {
            try configurationStore.save(updated)
            configuration = updated
            protectionCoordinator.setConfiguration(updated)
            errorMessage = nil
        } catch { errorMessage = "无法保存配置，请检查本地文件的访问权限。" }
    }
}

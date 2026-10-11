import Combine
import Foundation

@MainActor
public final class SensveilController: ObservableObject {
    @Published public private(set) var configuration: ProtectionConfiguration
    @Published public var searchText = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var configurationLoadFailed = false
    public var isConfigurationReadOnly: Bool { configurationLoadFailed }

    public let catalog: ApplicationCatalog
    public let configurationStore: ConfigurationStore
    public let protectionCoordinator: WindowProtectionCoordinator

    public init(configurationStore: ConfigurationStore = ConfigurationStore(), catalog: ApplicationCatalog = ApplicationCatalog(), protectionCoordinator: WindowProtectionCoordinator = WindowProtectionCoordinator()) {
        self.configurationStore = configurationStore
        self.catalog = catalog
        self.protectionCoordinator = protectionCoordinator
        do {
            self.configuration = try configurationStore.load()
        } catch {
            self.configuration = ProtectionConfiguration()
            self.configurationLoadFailed = true
            self.errorMessage = "Cannot load saved configuration: \(error)"
        }
        protectionCoordinator.onStatusChange = { [weak self] in self?.objectWillChange.send() }
        protectionCoordinator.start(configuration: configuration)
    }

    deinit {
        let coordinator = protectionCoordinator
        Task { @MainActor in coordinator.stop() }
    }

    public func status(for application: ProtectedApplication) -> ProtectionStatus {
        protectionCoordinator.status(for: application)
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
        } catch { errorMessage = "Cannot save configuration: \(error)" }
    }

    public func stopProtection() { protectionCoordinator.stop() }

    public var applications: [ApplicationDescriptor] { catalog.list(search: searchText) }
    public var canAddApplication: Bool { !configurationLoadFailed && configuration.applications.count < ConfigurationStore.freeApplicationLimit }
    public var freeLimitMessage: String { "Free plan: up to \(ConfigurationStore.freeApplicationLimit) applications" }

    public func addApplication() async {
        guard !configurationLoadFailed else { return }
        guard let descriptor = await catalog.chooseApplication() else {
            if let error = catalog.lastError, error != .noApplicationSelected {
                errorMessage = "Cannot add selected application: \(error)"
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
            errorMessage = error as? ConfigurationError == .freeLimitReached ? freeLimitMessage : "Cannot save configuration: \(error)"
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
        } catch { errorMessage = "Cannot save configuration: \(error)" }
    }
}

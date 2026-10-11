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

    public init(configurationStore: ConfigurationStore = ConfigurationStore(), catalog: ApplicationCatalog = ApplicationCatalog()) {
        self.configurationStore = configurationStore
        self.catalog = catalog
        do {
            self.configuration = try configurationStore.load()
        } catch {
            self.configuration = ProtectionConfiguration()
            self.configurationLoadFailed = true
            self.errorMessage = "Cannot load saved configuration: \(error)"
        }
    }

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
            errorMessage = nil
        } catch { errorMessage = "Cannot save configuration: \(error)" }
    }
}

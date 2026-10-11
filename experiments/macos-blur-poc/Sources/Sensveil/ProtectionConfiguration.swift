import Foundation

public enum ConfigurationError: Error, Equatable, Sendable {
    case freeLimitReached
    case invalidBundleIdentifier
    case unsupportedSchema
    case readFailed
    case writeFailed
}

public struct ProtectedApplication: Codable, Equatable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public var displayName: String
    public var iconData: Data?
    public var isEnabled: Bool
    public var sortIndex: Int

    public var id: String { bundleIdentifier }

    public init(
        bundleIdentifier: String,
        displayName: String,
        iconData: Data? = nil,
        isEnabled: Bool = true,
        sortIndex: Int = 0
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.iconData = iconData
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
    }
}

public struct ProtectionConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var applications: [ProtectedApplication]
    public var isGloballyPaused: Bool

    public init(
        schemaVersion: Int = ProtectionConfiguration.currentSchemaVersion,
        applications: [ProtectedApplication] = [],
        isGloballyPaused: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.applications = applications
        self.isGloballyPaused = isGloballyPaused
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case applications
        case isGloballyPaused
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchema
        }
        schemaVersion = version
        applications = try container.decode([ProtectedApplication].self, forKey: .applications)
        isGloballyPaused = try container.decode(Bool.self, forKey: .isGloballyPaused)
    }
}

/// Persistence and free-tier policy for the local protection configuration.
@MainActor
public final class ConfigurationStore {
    public static let freeApplicationLimit = 2

    public let configURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        appSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let directory = appSupportDirectory ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
        self.configURL = directory.appendingPathComponent("config.json", isDirectory: false)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.configURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> ProtectionConfiguration {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return ProtectionConfiguration()
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw ConfigurationError.readFailed
        }

        do {
            var configuration = try decoder.decode(ProtectionConfiguration.self, from: data)
            // Older files may contain duplicate entries. Keep the first one,
            // then make the in-memory representation conform to the quota.
            configuration.applications = deduplicated(configuration.applications)
            return configuration
        } catch let error as ConfigurationError {
            if error == .unsupportedSchema {
                throw error
            }
            preserveCorruptFile(data)
            throw ConfigurationError.readFailed
        } catch {
            preserveCorruptFile(data)
            throw ConfigurationError.readFailed
        }
    }

    public func save(_ configuration: ProtectionConfiguration) throws {
        guard configuration.schemaVersion == ProtectionConfiguration.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchema
        }

        var normalized = configuration
        normalized.applications = deduplicated(normalized.applications)
        let data: Data
        do {
            data = try encoder.encode(normalized)
        } catch {
            throw ConfigurationError.writeFailed
        }

        let directory = configURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporaryURL = directory.appendingPathComponent(".config.json.tmp-\(UUID().uuidString)")
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? fileManager.removeItem(at: temporaryURL) }

            if fileManager.fileExists(atPath: configURL.path) {
                _ = try fileManager.replaceItemAt(configURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: configURL)
            }
        } catch {
            throw ConfigurationError.writeFailed
        }
    }

    /// Adds an application to a caller-owned configuration. Duplicate bundle
    /// identifiers are idempotent and do not consume another free slot.
    public func add(_ application: ProtectedApplication, to configuration: inout ProtectionConfiguration) throws {
        guard Self.isValidBundleIdentifier(application.bundleIdentifier) else {
            throw ConfigurationError.invalidBundleIdentifier
        }

        configuration.applications = deduplicated(configuration.applications)
        guard !configuration.applications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            return
        }
        guard configuration.applications.count < Self.freeApplicationLimit else {
            throw ConfigurationError.freeLimitReached
        }
        configuration.applications.append(application)
    }

    /// Value-returning convenience for callers that keep configuration as an
    /// immutable value while assembling a new snapshot.
    public func add(_ application: ProtectedApplication, to configuration: ProtectionConfiguration) throws -> ProtectionConfiguration {
        var updated = configuration
        try add(application, to: &updated)
        return updated
    }

    public func remove(bundleIdentifier: String, from configuration: inout ProtectionConfiguration) {
        configuration.applications.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    public func remove(bundleIdentifier: String, from configuration: ProtectionConfiguration) -> ProtectionConfiguration {
        var updated = configuration
        remove(bundleIdentifier: bundleIdentifier, from: &updated)
        return updated
    }

    private func deduplicated(_ applications: [ProtectedApplication]) -> [ProtectedApplication] {
        var seen = Set<String>()
        return applications.filter { seen.insert($0.bundleIdentifier).inserted }
    }

    private func preserveCorruptFile(_ data: Data) {
        let directory = configURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copyURL = directory.appendingPathComponent("config.json.corrupt-\(suffix)-\(UUID().uuidString)")
        try? data.write(to: copyURL, options: .atomic)
    }

    private static func defaultApplicationSupportDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Sensveil", isDirectory: true)
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return components.allSatisfy { component in
            !component.isEmpty && component.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

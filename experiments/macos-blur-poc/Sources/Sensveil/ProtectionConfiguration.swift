import Foundation

public enum ConfigurationError: Error, Equatable, Sendable {
    case freeLimitReached
    case invalidBundleIdentifier
    case unsupportedSchema
    case readFailed
    case writeFailed
    case invalidSchedule
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

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case displayName
        case iconData
        case isEnabled
        case sortIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        guard BundleIdentifierValidator.isValid(bundleIdentifier) else {
            throw ConfigurationError.invalidBundleIdentifier
        }
        self.init(
            bundleIdentifier: bundleIdentifier,
            displayName: try container.decode(String.self, forKey: .displayName),
            iconData: try container.decodeIfPresent(Data.self, forKey: .iconData),
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            sortIndex: try container.decode(Int.self, forKey: .sortIndex)
        )
    }
}

public struct ProtectionConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    /// Schema 1 files predate the global protection settings; they are decoded
    /// with defaults for the new fields and stay untouched on disk until the
    /// next user save writes them back as schema 2.
    public static let minimumSchemaVersion = 1

    public var schemaVersion: Int
    public var applications: [ProtectedApplication]
    public var isGloballyPaused: Bool
    public var blurLevel: BlurLevel
    public var showsProtectionLabel: Bool
    public var schedule: ProtectionSchedule

    public init(
        schemaVersion: Int = ProtectionConfiguration.currentSchemaVersion,
        applications: [ProtectedApplication] = [],
        isGloballyPaused: Bool = false,
        blurLevel: BlurLevel = .standard,
        showsProtectionLabel: Bool = true,
        schedule: ProtectionSchedule = .defaultConfiguration
    ) {
        self.schemaVersion = schemaVersion
        self.applications = applications
        self.isGloballyPaused = isGloballyPaused
        self.blurLevel = blurLevel
        self.showsProtectionLabel = showsProtectionLabel
        self.schedule = schedule
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case applications
        case isGloballyPaused
        case blurLevel
        case showsProtectionLabel
        case schedule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard (Self.minimumSchemaVersion...Self.currentSchemaVersion).contains(version) else {
            throw ConfigurationError.unsupportedSchema
        }
        schemaVersion = version
        applications = try container.decode([ProtectedApplication].self, forKey: .applications)
        isGloballyPaused = try container.decode(Bool.self, forKey: .isGloballyPaused)
        if version >= 2 {
            // Schema 2 requires the global protection settings: a file that is
            // missing them is corrupt, not a legacy file to default.
            blurLevel = try container.decode(BlurLevel.self, forKey: .blurLevel)
            showsProtectionLabel = try container.decode(Bool.self, forKey: .showsProtectionLabel)
            schedule = try container.decode(ProtectionSchedule.self, forKey: .schedule)
        } else {
            blurLevel = .standard
            showsProtectionLabel = true
            schedule = .defaultConfiguration
        }
    }

    /// Always encodes the current schema version so that a configuration
    /// migrated in memory is written back as schema 2 on the next save.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(applications, forKey: .applications)
        try container.encode(isGloballyPaused, forKey: .isGloballyPaused)
        try container.encode(blurLevel, forKey: .blurLevel)
        try container.encode(showsProtectionLabel, forKey: .showsProtectionLabel)
        try container.encode(schedule, forKey: .schedule)
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
            if error == .invalidBundleIdentifier {
                throw error
            }
            throw ConfigurationError.readFailed
        } catch {
            preserveCorruptFile(data)
            throw ConfigurationError.readFailed
        }
    }

    public func save(_ configuration: ProtectionConfiguration) throws {
        guard (ProtectionConfiguration.minimumSchemaVersion...ProtectionConfiguration.currentSchemaVersion)
            .contains(configuration.schemaVersion) else {
            throw ConfigurationError.unsupportedSchema
        }

        var normalized = configuration
        guard normalized.applications.allSatisfy({ BundleIdentifierValidator.isValid($0.bundleIdentifier) }) else {
            throw ConfigurationError.invalidBundleIdentifier
        }
        normalized.applications = deduplicated(normalized.applications)
        // Encoding always writes currentSchemaVersion, so a configuration
        // migrated from schema 1 is persisted as schema 2 here.
        normalized.schemaVersion = ProtectionConfiguration.currentSchemaVersion
        normalized.schedule = try normalized.schedule.normalized()
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
        BundleIdentifierValidator.isValid(value)
    }
}

enum BundleIdentifierValidator {
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component.unicodeScalars.allSatisfy(isAllowedASCII)
        }
    }

    private static func isAllowedASCII(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122, 45:
            return true
        default:
            return false
        }
    }
}

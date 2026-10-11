import AppKit
import Foundation

public struct ApplicationDescriptor: Identifiable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let url: URL
    public let iconData: Data?
    public let isRunning: Bool

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, displayName: String, url: URL, iconData: Data? = nil, isRunning: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.url = url
        self.iconData = iconData
        self.isRunning = isRunning
    }
}

public enum ApplicationCatalogError: Error, Equatable, Sendable {
    case noApplicationSelected
    case unsupportedSelection
    case unreadableInfoPlist
    case missingBundleIdentifier
}

/// Discovers regular, user-selectable macOS applications.
@MainActor
public final class ApplicationCatalog {
    public private(set) var lastError: ApplicationCatalogError?

    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let ownBundleIdentifier: String?
    private let applicationDirectories: [URL]
    private let includesRunningApplications: Bool

    public init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationDirectories: [URL]? = nil,
        includesRunningApplications: Bool = true
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.ownBundleIdentifier = ownBundleIdentifier
        self.applicationDirectories = applicationDirectories ?? Self.defaultApplicationDirectories(fileManager: fileManager)
        self.includesRunningApplications = includesRunningApplications
    }

    public func list(search: String = "") -> [ApplicationDescriptor] {
        var byBundleID: [String: ApplicationDescriptor] = [:]
        let running = (includesRunningApplications ? workspace.runningApplications : []).compactMap { application -> ApplicationDescriptor? in
            guard let url = application.bundleURL else { return nil }
            return Self.descriptor(
                at: url,
                isRunning: true,
                activationPolicy: application.activationPolicy,
                ownBundleIdentifier: ownBundleIdentifier
            )
        }
        for descriptor in running { byBundleID[descriptor.bundleIdentifier] = descriptor }

        for root in applicationDirectories {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let descriptor = Self.descriptor(at: url, isRunning: false, ownBundleIdentifier: ownBundleIdentifier) else { continue }
                if let existing = byBundleID[descriptor.bundleIdentifier], existing.isRunning { continue }
                byBundleID[descriptor.bundleIdentifier] = descriptor
                enumerator.skipDescendants()
            }
        }

        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return byBundleID.values
            .filter { normalizedSearch.isEmpty || $0.displayName.lowercased().contains(normalizedSearch) || $0.bundleIdentifier.lowercased().contains(normalizedSearch) }
            .sorted {
                let comparison = $0.displayName.localizedStandardCompare($1.displayName)
                return comparison == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : comparison == .orderedAscending
            }
            .map(withIcon)
    }

    public func descriptor(for url: URL) -> ApplicationDescriptor? {
        Self.descriptor(at: url, isRunning: workspace.runningApplications.contains { $0.bundleURL == url && $0.activationPolicy == .regular }, ownBundleIdentifier: ownBundleIdentifier).map(withIcon)
    }

    private func withIcon(_ descriptor: ApplicationDescriptor) -> ApplicationDescriptor {
        // Only the UI-facing catalog touches AppKit image data; plist parsing stays pure.
        let icon = workspace.icon(forFile: descriptor.url.path)
        icon.size = NSSize(width: 32, height: 32)
        let data = icon.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        return ApplicationDescriptor(bundleIdentifier: descriptor.bundleIdentifier, displayName: descriptor.displayName, url: descriptor.url, iconData: data, isRunning: descriptor.isRunning)
    }

    public func chooseApplication() async -> ApplicationDescriptor? {
        lastError = nil
        let selectedURL: URL? = await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.applicationBundle]
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        guard let selectedURL else {
            lastError = .noApplicationSelected
            return nil
        }
        guard selectedURL.pathExtension.lowercased() == "app" else {
            lastError = .unsupportedSelection
            return nil
        }
        guard let descriptor = descriptor(for: selectedURL) else {
            lastError = Self.infoError(at: selectedURL)
            return nil
        }
        return descriptor
    }

    /// Pure plist-backed descriptor construction used by tests and callers with a known app URL.
    nonisolated public static func descriptor(
        at url: URL,
        isRunning: Bool = false,
        activationPolicy: NSApplication.ActivationPolicy = .regular,
        ownBundleIdentifier: String? = nil
    ) -> ApplicationDescriptor? {
        guard url.pathExtension.lowercased() == "app", activationPolicy == .regular else { return nil }
        guard let info = infoDictionary(at: url) else { return nil }
        guard let bundleIdentifier = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !bundleIdentifier.isEmpty else { return nil }
        guard BundleIdentifierValidator.isValid(bundleIdentifier) else { return nil }
        guard bundleIdentifier != ownBundleIdentifier, bundleIdentifier != "com.nieanshow.sensveil.fixture",
              !bundleIdentifier.lowercased().contains("sensveilfixture") else { return nil }
        if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSUIElement"] as? Bool) == true { return nil }
        let displayName = ((info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent)
        return ApplicationDescriptor(bundleIdentifier: bundleIdentifier, displayName: displayName, url: url, isRunning: isRunning)
    }

    nonisolated private static func infoDictionary(at url: URL) -> [String: Any]? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary
    }

    private static func infoError(at url: URL) -> ApplicationCatalogError {
        guard let info = infoDictionary(at: url) else { return .unreadableInfoPlist }
        guard let identifier = info["CFBundleIdentifier"] as? String, !identifier.isEmpty else { return .missingBundleIdentifier }
        return .unsupportedSelection
    }

    private static func defaultApplicationDirectories(fileManager: FileManager) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications")]
    }
}

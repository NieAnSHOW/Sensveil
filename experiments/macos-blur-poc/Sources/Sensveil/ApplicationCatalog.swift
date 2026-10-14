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
    private let ownBundleIdentifier: String?
    private let applicationDirectories: [URL]
    private let includesRunningApplications: Bool
    private var iconCache: [URL: Data] = [:]

    public init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationDirectories: [URL]? = nil,
        includesRunningApplications: Bool = true
    ) {
        self.workspace = workspace
        self.ownBundleIdentifier = ownBundleIdentifier
        self.applicationDirectories = applicationDirectories ?? Self.defaultApplicationDirectories(fileManager: fileManager)
        self.includesRunningApplications = includesRunningApplications
    }

    public func list(search: String = "") async -> [ApplicationDescriptor] {
        let runningURLs = (includesRunningApplications ? workspace.runningApplications : []).compactMap { application -> URL? in
            guard application.activationPolicy == .regular else { return nil }
            return application.bundleURL
        }
        let directories = applicationDirectories
        let ownIdentifier = ownBundleIdentifier
        // Directory traversal and plist decoding do not need AppKit or the UI actor.
        let descriptors = await Task.detached(priority: .userInitiated) {
            Self.discover(directories: directories, runningURLs: runningURLs, ownBundleIdentifier: ownIdentifier, search: search)
        }.value
        var result: [ApplicationDescriptor] = []
        for (index, descriptor) in descriptors.enumerated() {
            guard !Task.isCancelled else { return [] }
            result.append(withIcon(descriptor))
            // AppKit image drawing stays on the main actor, with bounded work
            // between yields so a large catalog cannot monopolize interaction.
            if index % 8 == 7 { await Task.yield() }
        }
        return result
    }

    nonisolated private static func discover(
        directories: [URL], runningURLs: [URL], ownBundleIdentifier: String?, search: String
    ) -> [ApplicationDescriptor] {
        let fileManager = FileManager()
        var byBundleID: [String: ApplicationDescriptor] = [:]
        let running = runningURLs.compactMap { url -> ApplicationDescriptor? in
            return Self.descriptor(
                at: url,
                isRunning: true,
                ownBundleIdentifier: ownBundleIdentifier
            )
        }
        for descriptor in running { byBundleID[descriptor.bundleIdentifier] = descriptor }

        for root in directories {
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
    }

    public func descriptor(for url: URL) -> ApplicationDescriptor? {
        Self.descriptor(at: url, isRunning: workspace.runningApplications.contains { $0.bundleURL == url && $0.activationPolicy == .regular }, ownBundleIdentifier: ownBundleIdentifier).map(withIcon)
    }

    private func withIcon(_ descriptor: ApplicationDescriptor) -> ApplicationDescriptor {
        let data: Data?
        if let cached = iconCache[descriptor.url] {
            data = cached
        } else {
            data = thumbnailData(for: workspace.icon(forFile: descriptor.url.path))
            if let data { iconCache[descriptor.url] = data }
        }
        return ApplicationDescriptor(bundleIdentifier: descriptor.bundleIdentifier, displayName: descriptor.displayName, url: descriptor.url, iconData: data, isRunning: descriptor.isRunning)
    }

    private func thumbnailData(for image: NSImage) -> Data? {
        // NSImage.size only changes logical points. Draw into a new bitmap to
        // discard large source representations before encoding or persistence.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: 32, height: 32)
        return bitmap.representation(using: .png, properties: [:])
    }

    public func chooseApplication() async -> ApplicationDescriptor? {
        lastError = nil
        let selectedURL: URL? = await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = L10n.text("选择应用")
            panel.prompt = L10n.text("添加")
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
        guard let bundleIdentifier = info["CFBundleIdentifier"] as? String, !bundleIdentifier.isEmpty else { return nil }
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

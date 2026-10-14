import AppKit
import XCTest
@testable import Sensveil

final class ApplicationCatalogTests: XCTestCase {
    @MainActor
    func testCatalogIconIsRasterizedToThumbnailPixels() throws {
        let app = try makeApp(id: "com.example.thumbnail", name: "Thumbnail")
        let catalog = ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false)
        let descriptor = try XCTUnwrap(catalog.descriptor(for: app))
        let data = try XCTUnwrap(descriptor.iconData)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        // Changing the logical NSImage size must not leave a full-resolution
        // bitmap in every row or in persisted protection configuration.
        XCTAssertLessThanOrEqual(bitmap.pixelsWide, 64)
        XCTAssertLessThanOrEqual(bitmap.pixelsHigh, 64)
        XCTAssertLessThan(data.count, 64 * 64 * 4)
    }

    @MainActor
    func testControllerDefersApplicationDiscoveryUntilAfterInitialization() async throws {
        let app = try makeApp(id: "com.example.deferred", name: "Deferred")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = ApplicationCatalog(applicationDirectories: [app.deletingLastPathComponent()], includesRunningApplications: false)
        let controller = SensveilController(configurationStore: ConfigurationStore(appSupportDirectory: directory), catalog: catalog)
        defer { controller.stopProtection() }
        XCTAssertTrue(controller.availableApplications.isEmpty, "Construction must return before scanning installed applications and decoding their icons")
        controller.refreshApplications()
        XCTAssertTrue(controller.availableApplications.isEmpty, "Refresh must schedule discovery without blocking the caller")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while controller.availableApplications.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.availableApplications.map(\.bundleIdentifier), ["com.example.deferred"])
    }

    @MainActor
    func testControllerCannotOverwriteConfigurationAfterLoadFailure() throws {
        for contents in [#"{"schemaVersion":999,"applications":[],"isGloballyPaused":false}"#, "not-json"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = ConfigurationStore(appSupportDirectory: directory)
            let original = Data(contents.utf8)
            try original.write(to: store.configURL)
            let controller = SensveilController(configurationStore: store, catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
            XCTAssertTrue(controller.configurationLoadFailed)
            XCTAssertFalse(controller.canAddApplication)
            controller.addApplication(ApplicationDescriptor(bundleIdentifier: "com.example.one", displayName: "One", url: directory.appendingPathComponent("One.app")))
            controller.removeApplication(ProtectedApplication(bundleIdentifier: "com.example.one", displayName: "One"))
            XCTAssertEqual(try Data(contentsOf: store.configURL), original)
            XCTAssertNotNil(controller.errorMessage)
        }
    }

    @MainActor
    func testControllerAddsAndReloadsApplicationsBeyondTwo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        try store.save(ProtectionConfiguration(applications: [
            ProtectedApplication(bundleIdentifier: "com.example.one", displayName: "One", isEnabled: false),
            ProtectedApplication(bundleIdentifier: "com.example.two", displayName: "Two"),
        ]))
        let catalog = ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false)
        let controller = SensveilController(configurationStore: store, catalog: catalog)
        defer { controller.stopProtection() }
        XCTAssertTrue(controller.canAddApplication)

        for name in ["three", "four", "five", "three"] {
            controller.addApplication(ApplicationDescriptor(bundleIdentifier: "com.example.\(name)", displayName: name, url: directory.appendingPathComponent("\(name).app")))
            XCTAssertNil(controller.errorMessage)
            XCTAssertTrue(controller.canAddApplication)
        }

        let reloaded = SensveilController(configurationStore: store, catalog: catalog)
        defer { reloaded.stopProtection() }
        XCTAssertEqual(reloaded.configuration.applications.map(\.bundleIdentifier), [
            "com.example.one", "com.example.two", "com.example.three", "com.example.four", "com.example.five",
        ])
        XCTAssertFalse(reloaded.configuration.applications[0].isEnabled)
        XCTAssertEqual(reloaded.configuration, controller.configuration)
        XCTAssertTrue(reloaded.canAddApplication)
        XCTAssertNil(reloaded.errorMessage)
    }

    @MainActor
    func testCatalogSearchDeduplicatesAndSortsInstalledApplications() async throws {
        let first = try makeApp(id: "com.example.writer", name: "Writer")
        let second = try makeApp(id: "com.example.writer", name: "Writer Copy")
        let third = try makeApp(id: "com.example.reader", name: "Reader")
        let catalog = ApplicationCatalog(applicationDirectories: [first.deletingLastPathComponent(), second.deletingLastPathComponent(), third.deletingLastPathComponent()], includesRunningApplications: false)
        let matches = await catalog.list(search: "com.example.")
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map(\.displayName), ["Reader", "Writer Copy"])
        let readerMatches = await catalog.list(search: "rEaDeR")
        XCTAssertEqual(readerMatches.map(\.bundleIdentifier), ["com.example.reader"])
    }

    func testDescriptorReadsTemporaryInfoPlistAndFiltersSearchFields() throws {
        let url = try makeApp(id: "com.example.Writer", name: "Writer")
        let descriptor = ApplicationCatalog.descriptor(at: url)
        XCTAssertEqual(descriptor?.bundleIdentifier, "com.example.Writer")
        XCTAssertEqual(descriptor?.displayName, "Writer")
        XCTAssertFalse(descriptor?.isRunning ?? true)
    }

    func testDescriptorFiltersFixtureSelfHelpersAndMissingIdentifier() throws {
        let fixture = try makeApp(id: "com.nieanshow.sensveil.fixture", name: "Fixture")
        let helper = try makeApp(id: "com.example.Helper", name: "Helper", extra: ["LSBackgroundOnly": true])
        let own = try makeApp(id: "com.example.Sensveil", name: "Sensveil")
        let missing = try makeApp(id: nil, name: "Missing")
        XCTAssertNil(ApplicationCatalog.descriptor(at: fixture))
        XCTAssertNil(ApplicationCatalog.descriptor(at: helper))
        XCTAssertNil(ApplicationCatalog.descriptor(at: own, ownBundleIdentifier: "com.example.Sensveil"))
        XCTAssertNil(ApplicationCatalog.descriptor(at: missing))
        let padded = try makeApp(id: " com.example.padded ", name: "Padded")
        XCTAssertNil(ApplicationCatalog.descriptor(at: padded))
    }

    private func makeApp(id: String?, name: String, extra: [String: Any] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name + ".app")
        let infoURL = root.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: infoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleName": name]
        if let id { info["CFBundleIdentifier"] = id }
        extra.forEach { info[$0.key] = $0.value }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)
        return root
    }
}

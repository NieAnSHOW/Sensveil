import AppKit
import XCTest
@testable import Sensveil

final class ApplicationCatalogTests: XCTestCase {
    @MainActor
    func testCatalogSearchDeduplicatesAndSortsInstalledApplications() throws {
        let first = try makeApp(id: "com.example.writer", name: "Writer")
        let second = try makeApp(id: "com.example.writer", name: "Writer Copy")
        let third = try makeApp(id: "com.example.reader", name: "Reader")
        let catalog = ApplicationCatalog(applicationDirectories: [first.deletingLastPathComponent(), second.deletingLastPathComponent(), third.deletingLastPathComponent()])
        let matches = catalog.list(search: "com.example.")
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map(\.displayName), ["Reader", "Writer Copy"])
        XCTAssertEqual(catalog.list(search: "rEaDeR").map(\.bundleIdentifier), ["com.example.reader"])
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

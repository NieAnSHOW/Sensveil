import Foundation
import XCTest
@testable import Sensveil

final class ProtectionConfigurationTests: XCTestCase {
    @MainActor
    func testMissingFileLoadsDefaultConfiguration() throws {
        let store = ConfigurationStore(appSupportDirectory: temporaryDirectory())
        XCTAssertEqual(try store.load(), ProtectionConfiguration())
    }

    @MainActor
    func testDuplicateBundleIdentifiersAreDeduplicated() throws {
        let store = ConfigurationStore(appSupportDirectory: temporaryDirectory())
        var configuration = ProtectionConfiguration(applications: [
            app("com.example.one", sortIndex: 0),
            app("com.example.one", sortIndex: 1),
        ])
        try store.add(app("com.example.one", sortIndex: 2), to: &configuration)
        XCTAssertEqual(configuration.applications.map(\.bundleIdentifier), ["com.example.one"])
    }

    @MainActor
    func testDisabledApplicationsStillConsumeFreeLimit() throws {
        let store = ConfigurationStore(appSupportDirectory: temporaryDirectory())
        var configuration = ProtectionConfiguration(applications: [
            app("com.example.one", enabled: false),
            app("com.example.two"),
        ])
        XCTAssertThrowsError(try store.add(app("com.example.three"), to: &configuration)) { error in
            XCTAssertEqual(error as? ConfigurationError, .freeLimitReached)
        }
    }

    @MainActor
    func testRemovingAnApplicationFreesCapacity() throws {
        let store = ConfigurationStore(appSupportDirectory: temporaryDirectory())
        var configuration = ProtectionConfiguration(applications: [
            app("com.example.one"), app("com.example.two"),
        ])
        store.remove(bundleIdentifier: "com.example.one", from: &configuration)
        XCTAssertNoThrow(try store.add(app("com.example.three"), to: &configuration))
        XCTAssertEqual(configuration.applications.map(\.bundleIdentifier), ["com.example.two", "com.example.three"])
    }

    @MainActor
    func testUnknownSchemaDoesNotOverwriteOriginalFile() throws {
        let directory = temporaryDirectory()
        let store = ConfigurationStore(appSupportDirectory: directory)
        let url = directory.appendingPathComponent("config.json")
        let original = Data(#"{"schemaVersion":999,"applications":[],"isGloballyPaused":false}"#.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: url)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ConfigurationError, .unsupportedSchema)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testCorruptFileIsPreservedAsACopy() throws {
        let directory = temporaryDirectory()
        let store = ConfigurationStore(appSupportDirectory: directory)
        let url = directory.appendingPathComponent("config.json")
        let original = Data("not-json".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: url)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ConfigurationError, .readFailed)
        }
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("config.json.corrupt-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: copies[0]), original)
    }

    @MainActor
    func testAddingRejectsMalformedOrNonASCIIIdentifiers() throws {
        let store = ConfigurationStore(appSupportDirectory: temporaryDirectory())
        for identifier in ["", "example", ".com.example", "com.example.", "com..example", "com.example_bad", "com.\u{00e9}xample", "com.example bad"] {
            var configuration = ProtectionConfiguration()
            XCTAssertThrowsError(try store.add(app(identifier), to: &configuration), identifier) { error in
                XCTAssertEqual(error as? ConfigurationError, .invalidBundleIdentifier)
            }
            XCTAssertEqual(configuration, ProtectionConfiguration())
        }
        var configuration = ProtectionConfiguration()
        XCTAssertNoThrow(try store.add(app("com.Example-1.application"), to: &configuration))
    }

    func testDecodingRejectsInvalidBundleIdentifier() throws {
        let original = try JSONEncoder().encode(ProtectionConfiguration(applications: [app("com.invalid_id")]))
        XCTAssertThrowsError(try JSONDecoder().decode(ProtectionConfiguration.self, from: original)) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidBundleIdentifier)
        }
    }

    @MainActor
    func testLoadingInvalidIdentifierPreservesOriginalAndReturnsError() throws {
        let directory = temporaryDirectory()
        let store = ConfigurationStore(appSupportDirectory: directory)
        let original = try JSONEncoder().encode(ProtectionConfiguration(applications: [app("com.invalid_id")]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: store.configURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidBundleIdentifier)
        }
        XCTAssertEqual(try Data(contentsOf: store.configURL), original)
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("config.json.corrupt-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: copies[0]), original)
    }

    @MainActor
    func testSavingInvalidIdentifierPreservesExistingConfiguration() throws {
        let store = ConfigurationStore(appSupportDirectory: temporaryDirectory())
        let valid = ProtectionConfiguration(applications: [app("com.example.valid")])
        try store.save(valid)
        let original = try Data(contentsOf: store.configURL)
        XCTAssertThrowsError(try store.save(ProtectionConfiguration(applications: [app("com.invalid_id")]))) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidBundleIdentifier)
        }
        XCTAssertEqual(try Data(contentsOf: store.configURL), original)
        XCTAssertEqual(try store.load(), valid)
    }

    private func app(_ bundleIdentifier: String, enabled: Bool = true, sortIndex: Int = 0) -> ProtectedApplication {
        ProtectedApplication(bundleIdentifier: bundleIdentifier, displayName: bundleIdentifier, iconData: nil, isEnabled: enabled, sortIndex: sortIndex)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

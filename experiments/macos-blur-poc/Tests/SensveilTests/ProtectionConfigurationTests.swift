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

    // MARK: - Schema migration

    func testSchemaOneFileIsMigratedWithDefaults() throws {
        let original = Data(#"""
        {"schemaVersion":1,"applications":[
        {"bundleIdentifier":"com.example.one","displayName":"One","isEnabled":true,"sortIndex":3},
        {"bundleIdentifier":"com.example.two","displayName":"Two","isEnabled":false,"sortIndex":1}],
        "isGloballyPaused":true}
        """#.utf8)
        let migrated = try JSONDecoder().decode(ProtectionConfiguration.self, from: original)

        XCTAssertEqual(migrated.schemaVersion, 1)
        XCTAssertEqual(migrated.applications.map(\.bundleIdentifier), ["com.example.one", "com.example.two"])
        XCTAssertEqual(migrated.applications.map(\.sortIndex), [3, 1])
        XCTAssertEqual(migrated.applications.last?.isEnabled, false)
        XCTAssertTrue(migrated.isGloballyPaused)
        XCTAssertEqual(migrated.blurLevel, .standard)
        XCTAssertTrue(migrated.showsProtectionLabel)

        // The weekly ranges are pre-stored even though the default mode is all
        // day, so switching modes never resets saved data.
        let schedule = migrated.schedule
        XCTAssertEqual(schedule.mode, .allDay)
        XCTAssertEqual(schedule.weeklyRanges.count, 7)
        XCTAssertEqual(schedule.weeklyRanges[0], [ProtectionTimeRange(startMinute: 540, endMinute: 1080)])
        XCTAssertEqual(schedule.weeklyRanges[4], [ProtectionTimeRange(startMinute: 540, endMinute: 1080)])
        XCTAssertEqual(schedule.weeklyRanges[5], [])
        XCTAssertEqual(schedule.weeklyRanges[6], [])
        XCTAssertEqual(schedule.holidayRanges, [])
        XCTAssertEqual(schedule.makeupWorkdayRanges, [ProtectionTimeRange(startMinute: 540, endMinute: 1080)])
        XCTAssertFalse(schedule.followsMainlandHolidays)
    }

    @MainActor
    func testLoadingSchemaOneFileLeavesItUntouchedUntilTheNextSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        let original = Data(#"{"schemaVersion":1,"applications":[],"isGloballyPaused":true}"#.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: store.configURL)

        var migrated = try store.load()
        XCTAssertTrue(migrated.isGloballyPaused)
        XCTAssertEqual(try Data(contentsOf: store.configURL), original)

        migrated.showsProtectionLabel = false
        try store.save(migrated)
        let upgraded = try store.load()
        XCTAssertEqual(upgraded.schemaVersion, ProtectionConfiguration.currentSchemaVersion)
        XCTAssertFalse(upgraded.showsProtectionLabel)
        XCTAssertTrue(upgraded.isGloballyPaused)
    }

    func testEditedConfigurationRoundTripsGlobalSettings() throws {
        let original = Data(#"{"schemaVersion":1,"applications":[],"isGloballyPaused":true}"#.utf8)
        let migrated = try JSONDecoder().decode(ProtectionConfiguration.self, from: original)
        XCTAssertTrue(migrated.isGloballyPaused)

        var edited = migrated
        edited.showsProtectionLabel = false
        edited.blurLevel = .strongest
        edited.schedule.mode = .specified
        edited.schedule.weeklyRanges[6] = [ProtectionTimeRange(startMinute: 1320, endMinute: 1800)]
        let decoded = try JSONDecoder().decode(ProtectionConfiguration.self, from: JSONEncoder().encode(edited))

        XCTAssertFalse(decoded.showsProtectionLabel)
        XCTAssertTrue(decoded.isGloballyPaused)
        XCTAssertEqual(decoded.blurLevel, .strongest)
        XCTAssertEqual(decoded.schedule.mode, .specified)
        XCTAssertEqual(decoded.schedule.weeklyRanges[6], [ProtectionTimeRange(startMinute: 1320, endMinute: 1800)])
        XCTAssertEqual(decoded.schedule.weeklyRanges[0], edited.schedule.weeklyRanges[0])
    }

    func testSchemaTwoFileMissingNewFieldIsNotDefaulted() throws {
        let encoded = try JSONEncoder().encode(ProtectionConfiguration())
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "showsProtectionLabel"))
        let incomplete = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(ProtectionConfiguration.self, from: incomplete))
    }

    // MARK: - Schedule validation and normalization

    func testNormalizationMergesAndKeepsCrossDaySpans() throws {
        var schedule = ProtectionSchedule.defaultConfiguration
        schedule.mode = .specified
        schedule.weeklyRanges[0] = [
            ProtectionTimeRange(startMinute: 780, endMinute: 2160),
            ProtectionTimeRange(startMinute: 0, endMinute: 840),
            ProtectionTimeRange(startMinute: 540, endMinute: 600),
        ]
        let normalized = try schedule.normalized()

        // Sorted, merged (adjacent 540-600 sits inside 0-840), and the merged
        // span keeps the largest end offset instead of wrapping past 1440.
        XCTAssertEqual(normalized.weeklyRanges[0], [ProtectionTimeRange(startMinute: 0, endMinute: 2160)])
        XCTAssertEqual(normalized.weeklyRanges[1], schedule.weeklyRanges[1])
        XCTAssertEqual(normalized.mode, .specified)
        XCTAssertNoThrow(try ProtectionSchedule.defaultConfiguration.normalized())
        XCTAssertEqual(try ProtectionSchedule.defaultConfiguration.normalized(), .defaultConfiguration)
    }

    func testNormalizationRejectsInvalidRanges() {
        var zeroLength = ProtectionSchedule.defaultConfiguration
        zeroLength.weeklyRanges[0] = [ProtectionTimeRange(startMinute: 1080, endMinute: 1080)]
        XCTAssertThrowsError(try zeroLength.normalized()) {
            XCTAssertEqual($0 as? ConfigurationError, .invalidSchedule)
        }

        var outOfRange = ProtectionSchedule.defaultConfiguration
        outOfRange.holidayRanges = [ProtectionTimeRange(startMinute: 1500, endMinute: 1600)]
        XCTAssertThrowsError(try outOfRange.normalized())

        var wrongWeekCount = ProtectionSchedule.defaultConfiguration
        wrongWeekCount.weeklyRanges = [[], [], []]
        XCTAssertThrowsError(try wrongWeekCount.normalized()) {
            XCTAssertEqual($0 as? ConfigurationError, .invalidSchedule)
        }
    }

    // MARK: - Invalid schema 2 input

    @MainActor
    func testInvalidSchemaTwoInputThrowsAndLeavesFileUntouched() throws {
        let outOfRange = schemaTwoJSON(weeklyRanges: #"[[{"startMinute":1500,"endMinute":1600}],[],[],[],[],[],[]]"#)
        let outOfRangeEnd = schemaTwoJSON(weeklyRanges: #"[[{"startMinute":10,"endMinute":2880}],[],[],[],[],[],[]]"#)
        let zeroLength = schemaTwoJSON(weeklyRanges: #"[[{"startMinute":1080,"endMinute":1080}],[],[],[],[],[],[]]"#)
        let reversed = schemaTwoJSON(weeklyRanges: #"[[{"startMinute":600,"endMinute":300}],[],[],[],[],[],[]]"#)
        let wrongWeekCount = schemaTwoJSON(weeklyRanges: "[[],[],[]]")
        let unknownBlurLevel = schemaTwoJSON(blurLevel: "extreme")
        let unknownMode = schemaTwoJSON(mode: "sometimes")
        for json in [outOfRange, outOfRangeEnd, zeroLength, reversed, wrongWeekCount, unknownBlurLevel, unknownMode] {
            try assertLoadingRejectsPreservingBytes(json)
        }
    }

    @MainActor
    func testSavingInvalidScheduleLeavesFileUntouched() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        try store.save(ProtectionConfiguration())
        let original = try Data(contentsOf: store.configURL)

        var invalid = ProtectionConfiguration()
        invalid.schedule.weeklyRanges = [[], []]
        XCTAssertThrowsError(try store.save(invalid)) {
            XCTAssertEqual($0 as? ConfigurationError, .invalidSchedule)
        }
        XCTAssertEqual(try Data(contentsOf: store.configURL), original)
    }

    // MARK: - Store round trip

    @MainActor
    func testStoreRoundTripsGlobalSettingsIncludingCrossMidnightRange() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var schedule = ProtectionSchedule.defaultConfiguration
        schedule.mode = .specified
        schedule.followsMainlandHolidays = true
        schedule.weeklyRanges[0] = [ProtectionTimeRange(startMinute: 1320, endMinute: 1800)]
        schedule.holidayRanges = [ProtectionTimeRange(startMinute: 0, endMinute: 2160)]

        try ConfigurationStore(appSupportDirectory: directory).save(ProtectionConfiguration(
            applications: [app("com.example.one"), app("com.example.two", enabled: false, sortIndex: 1)],
            isGloballyPaused: true,
            blurLevel: .strongest,
            showsProtectionLabel: false,
            schedule: schedule
        ))

        let reloaded = try ConfigurationStore(appSupportDirectory: directory).load()
        XCTAssertEqual(reloaded.schemaVersion, ProtectionConfiguration.currentSchemaVersion)
        XCTAssertEqual(reloaded.applications.map(\.bundleIdentifier), ["com.example.one", "com.example.two"])
        XCTAssertEqual(reloaded.applications.last?.isEnabled, false)
        XCTAssertTrue(reloaded.isGloballyPaused)
        XCTAssertEqual(reloaded.blurLevel, .strongest)
        XCTAssertFalse(reloaded.showsProtectionLabel)
        XCTAssertEqual(reloaded.schedule, schedule)
        XCTAssertEqual(reloaded.schedule.weeklyRanges[0], [ProtectionTimeRange(startMinute: 1320, endMinute: 1800)])
    }

    @MainActor
    func testSaveProtectionSettingsPublishesOnlyAfterASuccessfulSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        let controller = SensveilController(
            configurationStore: store,
            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false)
        )

        var schedule = ProtectionSchedule.defaultConfiguration
        schedule.mode = .specified
        try controller.saveProtectionSettings(blurLevel: .enhanced, showsProtectionLabel: false, schedule: schedule)
        XCTAssertEqual(controller.configuration.blurLevel, .enhanced)
        XCTAssertFalse(controller.configuration.showsProtectionLabel)
        XCTAssertEqual(controller.configuration.schedule.mode, .specified)
        XCTAssertNil(controller.errorMessage)

        var invalid = schedule
        invalid.weeklyRanges[0] = [ProtectionTimeRange(startMinute: 1080, endMinute: 1080)]
        XCTAssertThrowsError(try controller.saveProtectionSettings(blurLevel: .strongest, showsProtectionLabel: true, schedule: invalid))
        XCTAssertEqual(controller.configuration.blurLevel, .enhanced)
        XCTAssertTrue(controller.configuration.showsProtectionLabel == false)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(try store.load().blurLevel, .enhanced)
    }

    private func schemaTwoJSON(blurLevel: String = "standard", mode: String = "allDay", weeklyRanges: String = "[[],[],[],[],[],[],[]]") -> String {
        #"""
        {"schemaVersion":2,"applications":[],"isGloballyPaused":false,"blurLevel":"\#(blurLevel)","showsProtectionLabel":true,
        "schedule":{"mode":"\#(mode)","weeklyRanges":\#(weeklyRanges),"followsMainlandHolidays":false,"holidayRanges":[],
        "makeupWorkdayRanges":[]}}
        """#
    }

    @MainActor
    private func assertLoadingRejectsPreservingBytes(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        let original = Data(json.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: store.configURL)

        XCTAssertThrowsError(try store.load(), file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: store.configURL), original, file: file, line: line)
    }

    private func app(_ bundleIdentifier: String, enabled: Bool = true, sortIndex: Int = 0) -> ProtectedApplication {
        ProtectedApplication(bundleIdentifier: bundleIdentifier, displayName: bundleIdentifier, iconData: nil, isEnabled: enabled, sortIndex: sortIndex)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

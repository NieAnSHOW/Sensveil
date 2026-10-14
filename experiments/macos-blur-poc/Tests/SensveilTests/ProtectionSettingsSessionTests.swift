import Foundation
import XCTest
@testable import Sensveil

final class ProtectionSettingsSessionTests: XCTestCase {
    @MainActor
    func testSavingCommitsEffectsAndScheduleTogether() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            session.scheduleDraft.mode = .specified
            session.scheduleDraft.setWeekday(0, selected: true)
            session.scheduleDraft.weeklyRanges[0] = [ProtectionRangeDraft(startMinute: 600, endMinute: 900)]
            session.scheduleDraft.followsMainlandHolidays = true
            session.scheduleDraft.holidayRanges = [ProtectionRangeDraft(startMinute: 660, endMinute: 780)]
            session.blurLevel = .enhanced
            session.showsLabel = false

            session.save(controller: controller)

            let saved = try store.load()
            XCTAssertEqual(saved.blurLevel, .enhanced)
            XCTAssertFalse(saved.showsProtectionLabel)
            XCTAssertEqual(saved.schedule.mode, .specified)
            XCTAssertEqual(saved.schedule.weeklyRanges[0], [ProtectionTimeRange(startMinute: 600, endMinute: 900)])
            XCTAssertTrue(saved.schedule.followsMainlandHolidays)
            XCTAssertEqual(saved.schedule.holidayRanges, [ProtectionTimeRange(startMinute: 660, endMinute: 780)])
            XCTAssertFalse(session.hasChanges(comparedTo: saved))
        }
    }

    @MainActor
    func testSavingPreservesLatestSavedHiddenTransition() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            session.blurLevel = .strongest
            session.showsLabel = false
            session.scheduleDraft.mode = .specified
            session.transition = .off
            try controller.saveProtectionSettings(
                blurLevel: .standard, showsProtectionLabel: true,
                schedule: controller.configuration.schedule, protectionTransition: .ms800)

            session.save(controller: controller)

            let saved = try store.load()
            XCTAssertEqual(saved.blurLevel, .strongest)
            XCTAssertFalse(saved.showsProtectionLabel)
            XCTAssertEqual(saved.schedule.mode, .specified)
            XCTAssertEqual(saved.protectionTransition, .ms800)
            XCTAssertEqual(session.transition, .ms800)
        }
    }

    @MainActor
    func testInvalidScheduleKeepsAllDraftsAndSavedConfigurationForRecovery() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            let original = controller.configuration
            session.blurLevel = .strongest
            session.showsLabel = false
            session.scheduleDraft.mode = .specified
            session.scheduleDraft.weeklyRanges[0] = [ProtectionRangeDraft(startMinute: 600, endMinute: 600)]
            let invalidDraft = session.scheduleDraft

            session.save(controller: controller)

            XCTAssertNotNil(session.errorMessage)
            XCTAssertEqual(session.scheduleDraft, invalidDraft)
            XCTAssertEqual(session.blurLevel, .strongest)
            XCTAssertFalse(session.showsLabel)
            XCTAssertEqual(controller.configuration, original)
            XCTAssertEqual(try store.load(), original)
        }
    }

    @MainActor
    func testDiscardRestoresAllSettingsFromLatestConfiguration() throws {
        try withController { controller, _ in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            session.blurLevel = .strongest
            session.showsLabel = false
            session.scheduleDraft.mode = .specified
            session.scheduleDraft.setWeekday(1, selected: true)
            session.scheduleDraft.weeklyRanges[1].removeAll()
            session.errorMessage = "Unable to save"
            var latestSchedule = controller.configuration.schedule
            latestSchedule.mode = .specified
            latestSchedule.weeklyRanges[2] = [ProtectionTimeRange(startMinute: 480, endMinute: 720)]
            try controller.saveProtectionSettings(
                blurLevel: .enhanced, showsProtectionLabel: true,
                schedule: latestSchedule, protectionTransition: .ms800)

            session.discard(configuration: controller.configuration)

            XCTAssertEqual(session.blurLevel, .enhanced)
            XCTAssertTrue(session.showsLabel)
            XCTAssertEqual(session.transition, .ms800)
            XCTAssertEqual(session.scheduleDraft.scheduleValue, latestSchedule)
            XCTAssertEqual(session.scheduleDraft.selectedWeekdays, [0, 1, 2, 3, 4])
            XCTAssertNil(session.errorMessage)
            XCTAssertFalse(session.hasChanges(comparedTo: controller.configuration))
        }
    }

    @MainActor
    func testWriteFailureRetainsAllDraftsUntilRetrySucceeds() throws {
        try withController { controller, store in
            let original = controller.configuration
            let originalBytes = try Data(contentsOf: store.configURL)
            let session = ProtectionSettingsSession(configuration: original)
            session.blurLevel = .strongest
            session.showsLabel = false
            session.scheduleDraft.mode = .specified
            session.scheduleDraft.weeklyRanges[0] = [ProtectionRangeDraft(startMinute: 600, endMinute: 900)]
            let editedSchedule = session.scheduleDraft
            let directory = store.configURL.deletingLastPathComponent()
            let backup = directory.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: directory, to: backup)
            defer { try? FileManager.default.removeItem(at: backup) }
            try Data("blocked".utf8).write(to: directory)

            session.save(controller: controller)

            XCTAssertNotNil(session.errorMessage)
            XCTAssertEqual(controller.configuration, original)
            XCTAssertEqual(session.blurLevel, .strongest)
            XCTAssertFalse(session.showsLabel)
            XCTAssertEqual(session.scheduleDraft, editedSchedule)
            XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("config.json")), originalBytes)
            XCTAssertTrue(session.hasChanges(comparedTo: original))

            try FileManager.default.removeItem(at: directory)
            try FileManager.default.moveItem(at: backup, to: directory)
            session.save(controller: controller)

            let saved = try store.load()
            XCTAssertNil(session.errorMessage)
            XCTAssertEqual(saved.blurLevel, .strongest)
            XCTAssertFalse(saved.showsProtectionLabel)
            XCTAssertEqual(saved.schedule.weeklyRanges[0], [ProtectionTimeRange(startMinute: 600, endMinute: 900)])
            XCTAssertFalse(session.hasChanges(comparedTo: saved))
        }
    }

    @MainActor
    private func withController(_ body: (SensveilController, ConfigurationStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        try store.save(ProtectionConfiguration())
        let controller = SensveilController(
            configurationStore: store,
            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }
        try body(controller, store)
    }
}

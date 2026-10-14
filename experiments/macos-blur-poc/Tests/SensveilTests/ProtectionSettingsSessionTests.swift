import Foundation
import XCTest
@testable import Sensveil

final class ProtectionSettingsSessionTests: XCTestCase {
    @MainActor
    func testSavingEffectsPreservesUncommittedScheduleUntilScheduleIsSaved() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            let originalSchedule = controller.configuration.schedule
            session.scheduleDraft.mode = .specified
            session.scheduleDraft.weeklyRanges[0] = [ProtectionRangeDraft(startMinute: 600, endMinute: 900)]
            let editedSchedule = session.scheduleDraft.scheduleValue
            session.blurLevel = .enhanced
            session.showsLabel = false

            session.saveEffects(controller: controller)

            XCTAssertNil(session.effectsError)
            XCTAssertEqual(try store.load().schedule, originalSchedule)
            XCTAssertEqual(session.scheduleDraft.scheduleValue, editedSchedule)
            XCTAssertTrue(session.hasScheduleChanges(comparedTo: controller.configuration))
            XCTAssertFalse(session.hasEffectChanges(comparedTo: controller.configuration))

            session.saveSchedule(controller: controller)

            XCTAssertNil(session.scheduleError)
            XCTAssertEqual(try store.load().schedule, editedSchedule)
            XCTAssertEqual(try store.load().blurLevel, .enhanced)
            XCTAssertFalse(try store.load().showsProtectionLabel)
        }
    }

    @MainActor
    func testSavingSchedulePreservesUncommittedEffectsAndLatestSavedTransition() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            session.blurLevel = .strongest
            session.showsLabel = false
            session.scheduleDraft.mode = .specified
            try controller.saveProtectionSettings(
                blurLevel: .enhanced, showsProtectionLabel: true,
                schedule: controller.configuration.schedule, protectionTransition: .ms800)

            session.saveSchedule(controller: controller)

            XCTAssertNil(session.scheduleError)
            let saved = try store.load()
            XCTAssertEqual(saved.blurLevel, .enhanced)
            XCTAssertTrue(saved.showsProtectionLabel)
            XCTAssertEqual(saved.protectionTransition, .ms800)
            XCTAssertEqual(session.blurLevel, .strongest)
            XCTAssertFalse(session.showsLabel)
            XCTAssertTrue(session.hasEffectChanges(comparedTo: controller.configuration))
        }
    }

    @MainActor
    func testSavingEffectsUsesLatestSavedScheduleAndDiscardOnlyAffectsItsPage() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            session.blurLevel = .strongest
            var latestSchedule = controller.configuration.schedule
            latestSchedule.mode = .specified
            latestSchedule.weeklyRanges[2] = [ProtectionTimeRange(startMinute: 480, endMinute: 720)]
            try controller.saveProtectionSettings(
                blurLevel: .standard, showsProtectionLabel: true, schedule: latestSchedule)
            session.scheduleDraft.weeklyRanges[1] = [ProtectionRangeDraft(startMinute: 660, endMinute: 780)]
            let unfinishedSchedule = session.scheduleDraft

            session.saveEffects(controller: controller)

            XCTAssertEqual(try store.load().schedule, latestSchedule)
            XCTAssertEqual(session.scheduleDraft, unfinishedSchedule)
            session.blurLevel = .enhanced
            session.discardSchedule(configuration: controller.configuration)
            XCTAssertEqual(session.blurLevel, .enhanced)
            XCTAssertEqual(session.scheduleDraft.scheduleValue, latestSchedule)
            session.scheduleDraft.mode = .allDay
            session.discardEffects(configuration: controller.configuration)
            XCTAssertEqual(session.scheduleDraft.mode, .allDay)
            XCTAssertEqual(session.blurLevel, .strongest)
        }
    }

    @MainActor
    func testInvalidScheduleKeepsDraftAndSavedConfigurationForRecovery() throws {
        try withController { controller, store in
            let session = ProtectionSettingsSession(configuration: controller.configuration)
            let original = controller.configuration
            session.scheduleDraft.mode = .specified
            session.scheduleDraft.weeklyRanges[0] = [ProtectionRangeDraft(startMinute: 600, endMinute: 600)]
            let invalidDraft = session.scheduleDraft

            session.saveSchedule(controller: controller)

            XCTAssertNotNil(session.scheduleError)
            XCTAssertEqual(session.scheduleDraft, invalidDraft)
            XCTAssertEqual(controller.configuration, original)
            XCTAssertEqual(try store.load(), original)
            session.discardSchedule(configuration: controller.configuration)
            XCTAssertNil(session.scheduleError)
            XCTAssertFalse(session.hasScheduleChanges(comparedTo: controller.configuration))
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

import XCTest
@testable import Sensveil

final class ProtectionSettingsDraftTests: XCTestCase {
    func testSelectionRestoresSavedDaysWithoutSeedingEmptyDays() {
        let defaults = ProtectionSettingsDraft(schedule: .defaultConfiguration)
        XCTAssertEqual(defaults.selectedWeekdays, [0, 1, 2, 3, 4])

        let saved = customSchedule()
        let draft = ProtectionSettingsDraft(schedule: saved)
        XCTAssertEqual(draft.selectedWeekdays, [0, 2])
        XCTAssertEqual(draft.scheduleValue, saved)
        XCTAssertTrue(draft.weeklyRanges[1].isEmpty)
    }

    func testSelectingNewDaySeedsOnlyThatDayAndKeepsCustomRanges() throws {
        var draft = ProtectionSettingsDraft(schedule: customSchedule())
        draft.setWeekday(5, selected: true)

        XCTAssertEqual(draft.selectedWeekdays, [0, 2, 5])
        XCTAssertEqual(draft.scheduleValue.weeklyRanges, [
            [range(1320, 1800)], [], [range(480, 600), range(840, 960)], [], [],
            [range(540, 1080)], []
        ])
        // Re-selecting an already selected day must not replace its edits.
        _ = try XCTUnwrap(draft.weeklyRanges[5].first)
        draft.weeklyRanges[5][0].startMinute = 600
        draft.setWeekday(5, selected: true)
        XCTAssertEqual(draft.scheduleValue.weeklyRanges[5], [range(600, 1080)])
    }

    func testDeselectingClearsOnlyDraftDayUntilSaved() {
        let saved = customSchedule()
        var draft = ProtectionSettingsDraft(schedule: saved)
        draft.setWeekday(0, selected: false)

        XCTAssertEqual(draft.selectedWeekdays, [2])
        XCTAssertEqual(draft.scheduleValue.weeklyRanges, [
            [], [], [range(480, 600), range(840, 960)], [], [], [], []
        ])
        XCTAssertEqual(saved.weeklyRanges[0], [range(1320, 1800)])
        XCTAssertEqual(draft.scheduleValue.holidayRanges, [range(1380, 1740)])
        XCTAssertEqual(draft.scheduleValue.makeupWorkdayRanges, [range(600, 900)])
    }

    func testDeletingLastRangeKeepsDayEditableUntilReload() {
        var draft = ProtectionSettingsDraft(schedule: customSchedule())
        draft.weeklyRanges[0].removeAll()

        XCTAssertTrue(draft.selectedWeekdays.contains(0))
        XCTAssertTrue(draft.scheduleValue.weeklyRanges[0].isEmpty)
        let reloaded = ProtectionSettingsDraft(schedule: draft.scheduleValue)
        XCTAssertEqual(reloaded.selectedWeekdays, [2])
        XCTAssertTrue(reloaded.weeklyRanges[0].isEmpty)
    }

    func testChangingModeKeepsWeeklyAndHolidayEdits() {
        var draft = ProtectionSettingsDraft(schedule: customSchedule())
        draft.setWeekday(6, selected: true)
        draft.weeklyRanges[6] = [ProtectionRangeDraft(startMinute: 1200, endMinute: 1560)]
        draft.followsMainlandHolidays = false
        draft.mode = .allDay
        draft.mode = .specified
        draft.followsMainlandHolidays = true

        XCTAssertEqual(draft.selectedWeekdays, [0, 2, 6])
        XCTAssertEqual(draft.scheduleValue.weeklyRanges[6], [range(1200, 1560)])
        XCTAssertEqual(draft.scheduleValue.holidayRanges, [range(1380, 1740)])
        XCTAssertEqual(draft.scheduleValue.makeupWorkdayRanges, [range(600, 900)])
        XCTAssertTrue(draft.scheduleValue.followsMainlandHolidays)
    }

    func testDiscardReinitializesSelectionAndRangesFromSavedSchedule() {
        let saved = customSchedule()
        var draft = ProtectionSettingsDraft(schedule: saved)
        draft.setWeekday(0, selected: false)
        draft.setWeekday(4, selected: true)
        draft.holidayRanges.removeAll()
        draft.mode = .allDay

        draft = ProtectionSettingsDraft(schedule: saved)

        XCTAssertEqual(draft.selectedWeekdays, [0, 2])
        XCTAssertEqual(draft.scheduleValue, saved)
    }

    private func customSchedule() -> ProtectionSchedule {
        ProtectionSchedule(
            mode: .specified,
            weeklyRanges: [
                [range(1320, 1800)], [], [range(480, 600), range(840, 960)], [], [], [], []
            ],
            followsMainlandHolidays: true,
            holidayRanges: [range(1380, 1740)],
            makeupWorkdayRanges: [range(600, 900)]
        )
    }

    private func range(_ start: Int, _ end: Int) -> ProtectionTimeRange {
        ProtectionTimeRange(startMinute: start, endMinute: end)
    }
}

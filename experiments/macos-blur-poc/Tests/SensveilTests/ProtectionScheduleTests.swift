import Foundation
import XCTest

@testable import Sensveil

final class ProtectionScheduleTests: XCTestCase {
    // Every calendar is injected and fixed; no test reads the machine time zone.

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func range(_ startMinute: Int, _ endMinute: Int) -> ProtectionTimeRange {
        ProtectionTimeRange(startMinute: startMinute, endMinute: endMinute)
    }

    /// Seven days with the same ranges, unless a Monday-first index overrides one.
    private func weekly(
        _ ranges: [ProtectionTimeRange],
        overrides: [Int: [ProtectionTimeRange]] = [:]
    ) -> [[ProtectionTimeRange]] {
        (0..<7).map { overrides[$0] ?? ranges }
    }

    private func schedule(
        weekly: [[ProtectionTimeRange]],
        followsHolidays: Bool = false,
        holiday: [ProtectionTimeRange] = [],
        makeupWorkday: [ProtectionTimeRange] = []
    ) -> ProtectionSchedule {
        ProtectionSchedule(
            mode: .specified,
            weeklyRanges: weekly,
            followsMainlandHolidays: followsHolidays,
            holidayRanges: holiday,
            makeupWorkdayRanges: makeupWorkday
        )
    }

    private func holidays(days: [String: String] = [:], year: Int = 2026) throws -> MainlandHolidayCalendar {
        let entries = days.map { "\"\($0.key)\":\"\($0.value)\"" }.sorted().joined(separator: ",")
        let json = """
        {"years":[{"year":\(year),"version":"test","sourceURLs":["https://example.invalid/notice"],\
        "days":{\(entries)}}]}
        """
        return try MainlandHolidayCalendar(data: Data(json.utf8))
    }

    private func holidaysWithoutData() throws -> MainlandHolidayCalendar {
        try MainlandHolidayCalendar(data: Data("{\"years\":[]}".utf8))
    }

    private func eval(
        _ schedule: ProtectionSchedule,
        at iso: String,
        calendar: Calendar? = nil,
        holidays: MainlandHolidayCalendar
    ) -> ProtectionScheduleEvaluation {
        evaluateProtectionSchedule(
            schedule,
            at: instant(iso),
            calendar: calendar ?? utcCalendar(),
            holidays: holidays
        )
    }

    // MARK: - Weekly boundaries

    func testWeeklyIntervalIsStartInclusiveEndExclusive() throws {
        var schedule = ProtectionSchedule.defaultConfiguration
        schedule.mode = .specified
        schedule.followsMainlandHolidays = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = ISO8601DateFormatter().date(from: "2026-10-12T08:59:59Z")!
        let start = ISO8601DateFormatter().date(from: "2026-10-12T09:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-10-12T18:00:00Z")!
        let holidays = try MainlandHolidayCalendar(data: Data("{\"years\":[]}".utf8))
        XCTAssertFalse(evaluateProtectionSchedule(schedule, at: before, calendar: calendar, holidays: holidays).isActive)
        XCTAssertTrue(evaluateProtectionSchedule(schedule, at: start, calendar: calendar, holidays: holidays).isActive)
        XCTAssertFalse(evaluateProtectionSchedule(schedule, at: end, calendar: calendar, holidays: holidays).isActive)

        let evaluation = evaluateProtectionSchedule(schedule, at: before, calendar: calendar, holidays: holidays)
        XCTAssertEqual(evaluation.nextTransition, start)
        XCTAssertEqual(evaluation.nextEvaluation, start)
        XCTAssertNil(evaluation.activeSource)
        XCTAssertTrue(evaluation.missingHolidayYears.isEmpty)

        let active = evaluateProtectionSchedule(schedule, at: start, calendar: calendar, holidays: holidays)
        XCTAssertEqual(active.activeSource, "每周·周一")
        XCTAssertEqual(active.nextTransition, end)
    }

    func testEmptyWeekendHasNoIntervalsAndWakesAtTheNextBoundary() throws {
        let schedule = schedule(weekly: ProtectionSchedule.defaultConfiguration.weeklyRanges)
        let holidays = try holidaysWithoutData()

        let saturday = eval(schedule, at: "2026-10-17T12:00:00Z", holidays: holidays)
        XCTAssertFalse(saturday.isActive)
        XCTAssertNil(saturday.nextTransition)
        XCTAssertEqual(saturday.nextEvaluation, instant("2026-10-18T00:00:00Z"))

        let sunday = eval(schedule, at: "2026-10-18T23:59:00Z", holidays: holidays)
        XCTAssertFalse(sunday.isActive)
        XCTAssertNil(sunday.nextTransition)
        XCTAssertEqual(sunday.nextEvaluation, instant("2026-10-19T00:00:00Z"))

        let monday = eval(schedule, at: "2026-10-19T00:30:00Z", holidays: holidays)
        XCTAssertFalse(monday.isActive)
        XCTAssertEqual(monday.nextTransition, instant("2026-10-19T09:00:00Z"))
        XCTAssertEqual(monday.nextEvaluation, instant("2026-10-19T09:00:00Z"))
    }

    func testCrossMidnightIntervalBelongsToItsStartDay() throws {
        // Monday 22:00 -> Tuesday 06:00, expressed as an offset from Monday.
        let schedule = schedule(weekly: weekly([], overrides: [0: [range(1320, 1800)]]))
        let holidays = try holidaysWithoutData()

        XCTAssertTrue(eval(schedule, at: "2026-10-12T23:00:00Z", holidays: holidays).isActive)
        let tuesday = eval(schedule, at: "2026-10-13T03:00:00Z", holidays: holidays)
        XCTAssertTrue(tuesday.isActive)
        XCTAssertEqual(tuesday.activeSource, "每周·周一")
        XCTAssertEqual(tuesday.nextTransition, instant("2026-10-13T06:00:00Z"))
        XCTAssertEqual(tuesday.nextEvaluation, instant("2026-10-13T06:00:00Z"))
        XCTAssertFalse(eval(schedule, at: "2026-10-13T06:00:00Z", holidays: holidays).isActive)
    }

    func testHolidayWithoutRangesDoesNotTruncateThePreviousDaysInterval() throws {
        let schedule = schedule(
            weekly: weekly([], overrides: [0: [range(1320, 1800)]]),
            followsHolidays: true,
            holiday: []
        )
        // Tuesday is an official rest day with no holiday intervals: Monday's
        // interval still protects until its own end.
        let holidays = try holidays(days: ["2026-10-13": "rest"])
        let evaluation = eval(schedule, at: "2026-10-13T03:00:00Z", holidays: holidays)
        XCTAssertTrue(evaluation.isActive)
        XCTAssertEqual(evaluation.activeSource, "每周·周一")
        XCTAssertTrue(evaluation.missingHolidayYears.isEmpty)
    }

    func testHolidayOnTheStartDayReplacesTheWeeklyInterval() throws {
        let schedule = schedule(
            weekly: weekly([], overrides: [0: [range(1320, 1800)]]),
            followsHolidays: true,
            holiday: []
        )
        // Monday is a rest day with no holiday intervals: the weekly 22:00 start
        // is replaced, so nothing protects Tuesday early morning.
        let holidays = try holidays(days: ["2026-10-12": "rest"])
        let evaluation = eval(schedule, at: "2026-10-13T03:00:00Z", holidays: holidays)
        XCTAssertFalse(evaluation.isActive)
        XCTAssertNil(evaluation.activeSource)
    }

    func testHolidayRangesApplyOnARestDay() throws {
        let schedule = schedule(
            weekly: weekly([range(540, 1080)]),
            followsHolidays: true,
            holiday: [range(600, 720)]
        )
        let holidays = try holidays(days: ["2026-10-13": "rest"])
        let active = eval(schedule, at: "2026-10-13T11:00:00Z", holidays: holidays)
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.activeSource, "节假日")
        // The weekly 09:00 start no longer applies on a rest day.
        XCTAssertFalse(eval(schedule, at: "2026-10-13T09:30:00Z", holidays: holidays).isActive)
    }

    func testMakeupWorkdayUsesItsOwnRangesOnTheWeekend() throws {
        let schedule = schedule(
            weekly: weekly([]),
            followsHolidays: true,
            makeupWorkday: [range(540, 1080)]
        )
        let makeup = try holidays(days: ["2026-10-17": "makeupWorkday"])
        let active = eval(schedule, at: "2026-10-17T10:00:00Z", holidays: makeup)
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.activeSource, "调休上班")
        let end = eval(schedule, at: "2026-10-17T18:00:00Z", holidays: makeup)
        XCTAssertFalse(end.isActive)
        XCTAssertNil(end.nextTransition)

        // A regular Saturday without an arrangement stays on the weekly rules.
        let regular = eval(schedule, at: "2026-10-17T10:00:00Z", holidays: try holidaysWithoutData())
        XCTAssertFalse(regular.isActive)
    }

    func testMissingHolidayYearFallsBackToWeeklyRulesAndWarns() throws {
        let following = schedule(weekly: weekly([range(540, 1080)]), followsHolidays: true)
        let only2026 = try holidays(days: ["2026-10-01": "rest"])

        let missing = eval(following, at: "2027-06-15T10:00:00Z", holidays: only2026)
        XCTAssertTrue(missing.isActive)
        XCTAssertEqual(missing.missingHolidayYears, [2027])
        XCTAssertEqual(missing.activeSource, "每周·周二")

        let covered = eval(following, at: "2026-06-16T10:00:00Z", holidays: only2026)
        XCTAssertTrue(covered.isActive)
        XCTAssertTrue(covered.missingHolidayYears.isEmpty)

        let notFollowing = schedule(
            weekly: weekly([range(540, 1080)]),
            followsHolidays: false
        )
        XCTAssertTrue(
            eval(notFollowing, at: "2027-06-15T10:00:00Z", holidays: only2026).missingHolidayYears.isEmpty
        )

        let allDay = ProtectionSchedule.defaultConfiguration
        let allDayEvaluation = eval(allDay, at: "2027-06-15T10:00:00Z", holidays: only2026)
        XCTAssertTrue(allDayEvaluation.isActive)
        XCTAssertNil(allDayEvaluation.nextTransition)
        XCTAssertEqual(allDayEvaluation.activeSource, "全天")
        XCTAssertEqual(allDayEvaluation.nextEvaluation, instant("2027-06-16T00:00:00Z"))
        XCTAssertTrue(allDayEvaluation.missingHolidayYears.isEmpty)
    }

    func testOverlappingAndAdjacentRangesBehaveLikeOneSpan() throws {
        let holidays = try holidaysWithoutData()
        let merged = schedule(weekly: weekly([range(540, 900)]))  // 09:00-15:00
        let fragmented = schedule(weekly: weekly([range(540, 720), range(660, 780), range(780, 900)]))
        let adjacent = schedule(weekly: weekly([range(540, 720), range(720, 900)]))

        let probes = ["2026-10-12T08:59:00Z", "2026-10-12T09:00:00Z", "2026-10-12T12:30:00Z",
                      "2026-10-12T14:59:00Z", "2026-10-12T15:00:00Z"]
        for probe in probes {
            let expected = eval(merged, at: probe, holidays: holidays).isActive
            XCTAssertEqual(eval(fragmented, at: probe, holidays: holidays).isActive, expected, probe)
            XCTAssertEqual(eval(adjacent, at: probe, holidays: holidays).isActive, expected, probe)
        }
        // The adjacent halves are one continuous span: no gap at their seam.
        XCTAssertTrue(eval(adjacent, at: "2026-10-12T12:00:00Z", holidays: holidays).isActive)
        // Merging happens for evaluation only; the stored schedule is untouched.
        XCTAssertEqual(fragmented.weeklyRanges[0].count, 3)
        // The seam between adjacent ranges is not a state change.
        for schedule in [fragmented, adjacent] {
            XCTAssertEqual(
                eval(schedule, at: "2026-10-12T08:00:00Z", holidays: holidays).nextTransition,
                instant("2026-10-12T09:00:00Z")
            )
        }
    }

    // MARK: - Daylight saving time

    func testSpringForwardSkippedMinutesHaveNoInstant() throws {
        let losAngeles = calendar("America/Los_Angeles")
        let holidays = try holidaysWithoutData()
        // 2026-03-08: 02:00 PST jumps to 03:00 PDT (10:00Z).
        let spanning = schedule(weekly: weekly([range(60, 240)]))  // 01:00-04:00 local

        XCTAssertTrue(eval(spanning, at: "2026-03-08T09:00:00Z", calendar: losAngeles, holidays: holidays).isActive)
        XCTAssertTrue(eval(spanning, at: "2026-03-08T09:59:00Z", calendar: losAngeles, holidays: holidays).isActive)
        XCTAssertTrue(eval(spanning, at: "2026-03-08T10:00:00Z", calendar: losAngeles, holidays: holidays).isActive)
        XCTAssertFalse(eval(spanning, at: "2026-03-08T11:00:00Z", calendar: losAngeles, holidays: holidays).isActive)
        // The offset change itself does not flip the state; the interval end does.
        XCTAssertEqual(
            eval(spanning, at: "2026-03-08T09:30:00Z", calendar: losAngeles, holidays: holidays).nextTransition,
            instant("2026-03-08T11:00:00Z")
        )

        // An interval made only of skipped minutes has no instant at all.
        let skipped = schedule(weekly: weekly([range(135, 165)]))  // 02:15-02:45 local
        for probe in ["2026-03-08T09:59:00Z", "2026-03-08T10:00:00Z",
                      "2026-03-08T10:30:00Z", "2026-03-08T11:00:00Z"] {
            XCTAssertFalse(eval(skipped, at: probe, calendar: losAngeles, holidays: holidays).isActive, probe)
        }

        // An interval ending inside the gap ends when the clock jumps over it,
        // which is exactly the offset-transition instant.
        let toGap = schedule(weekly: weekly([range(60, 120)]))  // 01:00-02:00 local
        let evaluation = eval(toGap, at: "2026-03-08T09:30:00Z", calendar: losAngeles, holidays: holidays)
        XCTAssertTrue(evaluation.isActive)
        XCTAssertEqual(evaluation.nextTransition, instant("2026-03-08T10:00:00Z"))
        XCTAssertEqual(evaluation.nextEvaluation, instant("2026-03-08T10:00:00Z"))
        XCTAssertFalse(eval(toGap, at: "2026-03-08T10:00:00Z", calendar: losAngeles, holidays: holidays).isActive)
    }

    func testFallBackRepeatedWallclockResolvesToItsFirstOccurrence() throws {
        let losAngeles = calendar("America/Los_Angeles")
        let holidays = try holidaysWithoutData()
        // 2026-11-01: 02:00 PDT falls back to 01:00 PST (09:00Z).
        let early = schedule(weekly: weekly([range(60, 90)]))  // 01:00-01:30 local

        XCTAssertTrue(eval(early, at: "2026-11-01T08:00:00Z", calendar: losAngeles, holidays: holidays).isActive)
        XCTAssertTrue(eval(early, at: "2026-11-01T08:29:00Z", calendar: losAngeles, holidays: holidays).isActive)
        XCTAssertFalse(eval(early, at: "2026-11-01T08:30:00Z", calendar: losAngeles, holidays: holidays).isActive)
        // The repeated 01:15 is the second occurrence, after the first 01:30 end.
        XCTAssertFalse(eval(early, at: "2026-11-01T09:15:00Z", calendar: losAngeles, holidays: holidays).isActive)
        // Probed from the same local day: 07:30Z is 00:30 PDT on the 1st.
        XCTAssertEqual(
            eval(early, at: "2026-11-01T07:30:00Z", calendar: losAngeles, holidays: holidays).nextTransition,
            instant("2026-11-01T08:00:00Z")
        )

        let late = schedule(weekly: weekly([range(90, 120)]))  // 01:30-02:00 local
        XCTAssertTrue(eval(late, at: "2026-11-01T08:30:00Z", calendar: losAngeles, holidays: holidays).isActive)
        // Still inside: the start resolved to the first 01:30 and the end to 02:00 PST.
        XCTAssertTrue(eval(late, at: "2026-11-01T09:30:00Z", calendar: losAngeles, holidays: holidays).isActive)
        XCTAssertFalse(eval(late, at: "2026-11-01T10:00:00Z", calendar: losAngeles, holidays: holidays).isActive)
        // Re-evaluation follows the non-flipping offset change, transition does not.
        let lateMidday = eval(late, at: "2026-11-01T08:45:00Z", calendar: losAngeles, holidays: holidays)
        XCTAssertEqual(lateMidday.nextEvaluation, instant("2026-11-01T09:00:00Z"))
        XCTAssertEqual(lateMidday.nextTransition, instant("2026-11-01T10:00:00Z"))
    }

    // MARK: - Calendar years and local days

    func testIntervalCrossingNewYearUsesItsStartDayRule() throws {
        // 2026-12-31 is a Thursday: 23:00 -> 2027-01-01 06:00.
        let schedule = schedule(
            weekly: weekly([], overrides: [3: [range(1380, 1800)]]),
            followsHolidays: true
        )
        let only2026 = try holidays(days: ["2026-10-01": "rest"])
        let evaluation = eval(schedule, at: "2027-01-01T03:00:00Z", holidays: only2026)
        XCTAssertTrue(evaluation.isActive)
        XCTAssertEqual(evaluation.activeSource, "每周·周四")
        // Only the current day's year is missing; the start day still has data.
        XCTAssertEqual(evaluation.missingHolidayYears, [2027])
        XCTAssertEqual(evaluation.nextTransition, instant("2027-01-01T06:00:00Z"))
    }

    func testEvaluationUsesTheInjectedLocalDay() throws {
        let newYork = calendar("America/New_York")
        let holidays = try holidaysWithoutData()
        let schedule = schedule(weekly: ProtectionSchedule.defaultConfiguration.weeklyRanges)

        // 2026-10-12 is a Monday; 13:00Z is its 09:00 EDT start.
        XCTAssertFalse(eval(schedule, at: "2026-10-12T12:59:00Z", calendar: newYork, holidays: holidays).isActive)
        let active = eval(schedule, at: "2026-10-12T13:00:00Z", calendar: newYork, holidays: holidays)
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.activeSource, "每周·周一")

        // 02:00Z on the 13th is still Monday evening locally: the local day, its
        // midnight and its weekday all come from the injected time zone.
        let mondayEvening = eval(schedule, at: "2026-10-13T02:00:00Z", calendar: newYork, holidays: holidays)
        XCTAssertFalse(mondayEvening.isActive)
        XCTAssertNil(mondayEvening.nextTransition)
        XCTAssertEqual(mondayEvening.nextEvaluation, instant("2026-10-13T04:00:00Z"))
    }

    func testEmptyWeeklyRangesWakeOnlyAtLocalMidnight() throws {
        var schedule = ProtectionSchedule.defaultConfiguration
        schedule.mode = .specified
        schedule.weeklyRanges = Array(repeating: [], count: 7)
        let evaluation = eval(schedule, at: "2026-10-12T12:00:00Z", holidays: try holidaysWithoutData())
        XCTAssertFalse(evaluation.isActive)
        XCTAssertNil(evaluation.nextTransition)
        XCTAssertEqual(evaluation.nextEvaluation, instant("2026-10-13T00:00:00Z"))
        XCTAssertNil(evaluation.activeSource)
        XCTAssertTrue(evaluation.missingHolidayYears.isEmpty)
    }
}

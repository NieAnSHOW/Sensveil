import Foundation
import XCTest
@testable import Sensveil

final class MainlandHolidayCalendarTests: XCTestCase {
    // Synthetic data only: the production table is verified against the official
    // notice by hand, never by asserting its days here.
    private static let syntheticNotice = """
    {"years":[{
        "year":2026,
        "version":"国办发明电〔2026〕1号",
        "sourceURLs":["https://example.invalid/notice"],
        "days":{
            "2026-01-04":"makeupWorkday",
            "2026-02-17":"rest"
        }
    }]}
    """

    private func calendar(_ timeZone: TimeZone = TimeZone(secondsFromGMT: 8 * 3600)!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func calendar(from json: String) throws -> MainlandHolidayCalendar {
        try MainlandHolidayCalendar(data: Data(json.utf8))
    }

    func testMakeupWorkdayIsFoundOnTheWeekend() throws {
        let holidays = try calendar(from: Self.syntheticNotice)
        let local = calendar()
        XCTAssertEqual(local.component(.weekday, from: day(2026, 1, 4, in: local)), 1) // Sunday
        XCTAssertEqual(holidays.kind(on: day(2026, 1, 4, in: local), calendar: local), .makeupWorkday)
    }

    func testRestDayIsFoundOnAWeekday() throws {
        let holidays = try calendar(from: Self.syntheticNotice)
        XCTAssertEqual(holidays.kind(on: day(2026, 2, 17, in: calendar()), calendar: calendar()), .rest)
    }

    func testNonExceptionDaysReturnNil() throws {
        let holidays = try calendar(from: Self.syntheticNotice)
        XCTAssertNil(holidays.kind(on: day(2026, 2, 18, in: calendar()), calendar: calendar()))
        XCTAssertNil(holidays.kind(on: day(2026, 1, 3, in: calendar()), calendar: calendar()))
    }

    func testLookupUsesTheInjectedCalendarTimeZone() throws {
        let holidays = try calendar(from: Self.syntheticNotice)
        // 2026-02-17 00:00 +08:00 is still 2026-02-16 in UTC, so the UTC calendar
        // must not report the rest day for the same instant.
        let instant = day(2026, 2, 17, in: calendar())
        XCTAssertEqual(holidays.kind(on: instant, calendar: calendar()), .rest)
        XCTAssertNil(holidays.kind(on: instant, calendar: calendar(TimeZone(secondsFromGMT: 0)!)))
    }

    func testHasYearReportsCoverage() throws {
        let holidays = try calendar(from: Self.syntheticNotice)
        XCTAssertTrue(holidays.hasYear(2026))
        XCTAssertFalse(holidays.hasYear(2027))
        XCTAssertEqual(holidays.coveredYears, [2026])
        XCTAssertEqual(holidays.coverageDescription(), "2026（国办发明电〔2026〕1号）")
    }

    func testDuplicateYearIsRejected() throws {
        let json = """
        {"years":[
            {"year":2026,"version":"a","sourceURLs":["https://example.invalid/a"],"days":{}},
            {"year":2026,"version":"b","sourceURLs":["https://example.invalid/b"],"days":{}}
        ]}
        """
        XCTAssertThrowsError(try calendar(from: json)) { error in
            XCTAssertEqual(error as? HolidayCalendarError, .duplicateYear(2026))
        }
    }

    func testMalformedAndImpossibleDatesAreRejected() throws {
        for key in ["not-a-date", "2026-2-17", "2026-13-01", "2026-02-30", "2026-01-00", "20260101"] {
            let json = """
            {"years":[{"year":2026,"version":"v","sourceURLs":["https://example.invalid/a"],"days":{"\(key)":"rest"}}]}
            """
            XCTAssertThrowsError(try calendar(from: json), key) { error in
                XCTAssertEqual(error as? HolidayCalendarError, .invalidDate(key))
            }
        }
    }

    func testDateOutsideTheYearIsRejected() throws {
        let json = """
        {"years":[{"year":2026,"version":"v","sourceURLs":["https://example.invalid/a"],"days":{"2025-12-31":"rest"}}]}
        """
        XCTAssertThrowsError(try calendar(from: json)) { error in
            XCTAssertEqual(error as? HolidayCalendarError, .dateOutsideYear(date: "2025-12-31", year: 2026))
        }
    }

    func testMissingVersionIsRejected() throws {
        let json = """
        {"years":[{"year":2026,"version":"  ","sourceURLs":["https://example.invalid/a"],"days":{}}]}
        """
        XCTAssertThrowsError(try calendar(from: json)) { error in
            XCTAssertEqual(error as? HolidayCalendarError, .missingVersion(year: 2026))
        }
    }

    func testMissingSourcesAreRejected() throws {
        let json = """
        {"years":[{"year":2026,"version":"v","sourceURLs":[],"days":{}}]}
        """
        XCTAssertThrowsError(try calendar(from: json)) { error in
            XCTAssertEqual(error as? HolidayCalendarError, .missingSources(year: 2026))
        }
    }

    func testEmptyYearsLoadsWithNoCoverage() throws {
        let holidays = try calendar(from: #"{"years":[]}"#)
        XCTAssertTrue(holidays.years.isEmpty)
        XCTAssertTrue(holidays.coveredYears.isEmpty)
        XCTAssertFalse(holidays.hasYear(2026))
        XCTAssertEqual(holidays.coverageDescription(), "无内置年度安排")
        XCTAssertNil(holidays.kind(on: day(2026, 1, 1, in: calendar()), calendar: calendar()))
    }

    func testBundledResourceLoads() throws {
        let holidays = try MainlandHolidayCalendar.loadBundled()
        XCTAssertTrue(
            holidays.hasYear(2026),
            "bundled calendar should cover the authored year, got: \(holidays.coverageDescription())"
        )
        XCTAssertFalse(try XCTUnwrap(holidays.years[2026]).version.isEmpty)
    }
}

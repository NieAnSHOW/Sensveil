import Foundation

/// A single day's classification inside an officially published annual arrangement.
public enum HolidayDayKind: String, Codable, Sendable {
    /// Official rest day (放假): protection follows the holiday intervals.
    case rest
    /// Official makeup workday (调休上班): a weekend day that follows the workday rules.
    case makeupWorkday
}

public enum HolidayCalendarError: Error, Equatable, Sendable {
    case duplicateYear(Int)
    case missingVersion(year: Int)
    case missingSources(year: Int)
    case invalidDate(String)
    case dateOutsideYear(date: String, year: Int)
    case resourceMissing
}

/// Read-only, offline calendar of the State Council's annual holiday arrangements.
///
/// The bundled JSON records exception days only — official rest days and makeup
/// workdays (调休). Every other day is handled by the weekly schedule.
public struct MainlandHolidayCalendar: Sendable {
    public struct YearData: Codable, Sendable {
        public let year: Int
        public let version: String
        public let sourceURLs: [URL]
        /// ISO `yyyy-MM-dd` keys, exception days only.
        public let days: [String: HolidayDayKind]

        public init(
            year: Int,
            version: String,
            sourceURLs: [URL],
            days: [String: HolidayDayKind]
        ) {
            self.year = year
            self.version = version
            self.sourceURLs = sourceURLs
            self.days = days
        }
    }

    /// Covered years keyed by `YearData.year`.
    public let years: [Int: YearData]

    private struct Document: Codable {
        let years: [YearData]
    }

    /// SwiftPM names the resource bundle `<Package>_<Target>.bundle`.
    static let resourceBundleName = "SensveilBlurPoC_Sensveil.bundle"
    private static let resourceName = "mainland-holidays"

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var years: [Int: YearData] = [:]
        for yearData in document.years {
            // One entry per year keeps every date key unambiguous: a key may only be
            // looked up in its own year, and validation requires that year to match,
            // so the same date can never appear under two entries.
            guard years[yearData.year] == nil else {
                throw HolidayCalendarError.duplicateYear(yearData.year)
            }
            guard !yearData.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HolidayCalendarError.missingVersion(year: yearData.year)
            }
            guard !yearData.sourceURLs.isEmpty else {
                throw HolidayCalendarError.missingSources(year: yearData.year)
            }
            for key in yearData.days.keys {
                guard let date = Self.parseISO8601Day(key) else {
                    throw HolidayCalendarError.invalidDate(key)
                }
                guard Self.utcCalendar.component(.year, from: date) == yearData.year else {
                    throw HolidayCalendarError.dateOutsideYear(date: key, year: yearData.year)
                }
            }
            years[yearData.year] = yearData
        }
        // An empty years array is valid: the caller falls back to the weekly rules.
        self.years = years
    }

    /// Loads the arrangement bundled with the current product build.
    public static func loadBundled() throws -> MainlandHolidayCalendar {
        // Installed .app: build-apps.sh copies the SwiftPM bundle into Contents/Resources.
        if let url = Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
           let bundle = Bundle(url: url) {
            return try load(from: bundle)
        }
        // swift test / swift run: SwiftPM's generated accessor resolves the built bundle.
        return try load(from: Bundle.module)
    }

    private static func load(from bundle: Bundle) throws -> MainlandHolidayCalendar {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw HolidayCalendarError.resourceMissing
        }
        return try MainlandHolidayCalendar(data: Data(contentsOf: url))
    }

    /// The classification of `date`, or `nil` when it is not an exception day.
    public func kind(on date: Date, calendar: Calendar) -> HolidayDayKind? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        return years[year]?.days[key]
    }

    public func hasYear(_ year: Int) -> Bool {
        years[year] != nil
    }

    public var coveredYears: [Int] {
        years.keys.sorted()
    }

    /// Human-readable coverage, e.g. `2026（国办发明电〔2025〕7号）`.
    public func coverageDescription() -> String {
        guard !coveredYears.isEmpty else { return "无内置年度安排" }
        return coveredYears
            .compactMap { years[$0] }
            .map { "\($0.year)（\($0.version)）" }
            .joined(separator: "、")
    }

    /// Strict `yyyy-MM-dd` parse; rejects malformed keys and non-existent dates.
    private static func parseISO8601Day(_ key: String) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = utcCalendar.date(from: components) else { return nil }
        // `Calendar` normalizes overflow (e.g. 2026-02-30 -> 2026-03-02); round-trip to reject it.
        let resolved = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        return date
    }
}

extension MainlandHolidayCalendar {
    /// Fixed, known-valid JSON; the initializer only throws on malformed data.
    /// Used when the bundled resource cannot be read so weekly rules and the
    /// independent missing-year warning keep working.
    static let empty = try! MainlandHolidayCalendar(data: Data("{\"years\":[]}".utf8))
}

import Foundation

public enum BlurLevel: String, Codable, CaseIterable, Sendable {
    case standard, enhanced, strongest
}

public enum ProtectionScheduleMode: String, Codable, Sendable {
    case allDay, specified
}

/// A protection interval expressed in minutes relative to its start day.
/// `endMinute` is an offset from midnight of the start day, so an interval that
/// crosses midnight carries an end above 1440 instead of wrapping to 00:00.
public struct ProtectionTimeRange: Codable, Equatable, Sendable {
    public var startMinute: Int  // 0...1439
    public var endMinute: Int    // 1...2879, must be greater than startMinute

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    private enum CodingKeys: String, CodingKey {
        case startMinute
        case endMinute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startMinute = try container.decode(Int.self, forKey: .startMinute)
        let endMinute = try container.decode(Int.self, forKey: .endMinute)
        try Self.validate(startMinute: startMinute, endMinute: endMinute)
        self.init(startMinute: startMinute, endMinute: endMinute)
    }

    static func validate(startMinute: Int, endMinute: Int) throws {
        guard (0...1439).contains(startMinute),
              (1...2879).contains(endMinute),
              endMinute > startMinute else {
            throw ConfigurationError.invalidSchedule
        }
    }
}

/// Weekly protection intervals plus the holiday/makeup-workday rules that
/// replace a day's weekly intervals when mainland holiday following is on.
public struct ProtectionSchedule: Codable, Equatable, Sendable {
    public static let weekdayCount = 7

    public var mode: ProtectionScheduleMode
    public var weeklyRanges: [[ProtectionTimeRange]]  // 7 entries, Monday at index 0
    public var followsMainlandHolidays: Bool
    public var holidayRanges: [ProtectionTimeRange]
    public var makeupWorkdayRanges: [ProtectionTimeRange]

    public init(
        mode: ProtectionScheduleMode,
        weeklyRanges: [[ProtectionTimeRange]],
        followsMainlandHolidays: Bool = false,
        holidayRanges: [ProtectionTimeRange] = [],
        makeupWorkdayRanges: [ProtectionTimeRange] = []
    ) {
        self.mode = mode
        self.weeklyRanges = weeklyRanges
        self.followsMainlandHolidays = followsMainlandHolidays
        self.holidayRanges = holidayRanges
        self.makeupWorkdayRanges = makeupWorkdayRanges
    }

    /// The weekly ranges are pre-stored even though the default mode is all
    /// day, so switching modes never resets data and no first-init flag exists.
    public static let defaultConfiguration = ProtectionSchedule(
        mode: .allDay,
        weeklyRanges: Array(
            repeating: [ProtectionTimeRange(startMinute: 540, endMinute: 1080)],
            count: 5
        ) + [[], []],
        followsMainlandHolidays: false,
        holidayRanges: [],
        makeupWorkdayRanges: [ProtectionTimeRange(startMinute: 540, endMinute: 1080)]
    )

    private enum CodingKeys: String, CodingKey {
        case mode
        case weeklyRanges
        case followsMainlandHolidays
        case holidayRanges
        case makeupWorkdayRanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = ProtectionSchedule(
            mode: try container.decode(ProtectionScheduleMode.self, forKey: .mode),
            weeklyRanges: try container.decode([[ProtectionTimeRange]].self, forKey: .weeklyRanges),
            followsMainlandHolidays: try container.decode(Bool.self, forKey: .followsMainlandHolidays),
            holidayRanges: try container.decode([ProtectionTimeRange].self, forKey: .holidayRanges),
            makeupWorkdayRanges: try container.decode([ProtectionTimeRange].self, forKey: .makeupWorkdayRanges)
        )
        guard decoded.weeklyRanges.count == Self.weekdayCount else {
            throw ConfigurationError.invalidSchedule
        }
        self = decoded
    }

    /// Validates every range and returns the schedule with each day's ranges
    /// sorted by start minute and merged when overlapping or adjacent.
    /// Attribution stays on the start day and a merged span keeps the largest
    /// end offset, so a span may exceed 1440 minutes and is never wrapped.
    public func normalized() throws -> ProtectionSchedule {
        guard weeklyRanges.count == Self.weekdayCount else {
            throw ConfigurationError.invalidSchedule
        }
        var result = self
        result.weeklyRanges = try weeklyRanges.map(Self.normalized)
        result.holidayRanges = try Self.normalized(holidayRanges)
        result.makeupWorkdayRanges = try Self.normalized(makeupWorkdayRanges)
        return result
    }

    private static func normalized(_ ranges: [ProtectionTimeRange]) throws -> [ProtectionTimeRange] {
        for range in ranges {
            try ProtectionTimeRange.validate(startMinute: range.startMinute, endMinute: range.endMinute)
        }
        var merged: [ProtectionTimeRange] = []
        for range in ranges.sorted(by: { $0.startMinute < $1.startMinute }) {
            if let last = merged.last, range.startMinute <= last.endMinute {
                merged[merged.count - 1].endMinute = max(last.endMinute, range.endMinute)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

/// Deterministic result of evaluating a schedule at one instant.
public struct ProtectionScheduleEvaluation: Equatable, Sendable {
    public let isActive: Bool
    /// Earliest instant that actually flips `isActive`, before the next local
    /// midnight; `nil` when the state holds until then.
    public let nextTransition: Date?
    /// Earliest of the next interval endpoint, the next time-zone offset
    /// transition and the next local midnight — i.e. when to evaluate again.
    public let nextEvaluation: Date
    /// Years with no bundled arrangement, where the weekly rules were used instead.
    public let missingHolidayYears: Set<Int>
    /// Display-only rule label (`全天`, `每周·周三`, `节假日`, `调休上班`);
    /// `nil` when no interval contains the instant.
    public let activeSource: String?
}

/// Names are Monday-first, matching the weekly range index.
private let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

/// Pure evaluation of `schedule` at `date` in the local time of `calendar`.
///
/// The current local day and the previous one both contribute intervals: a
/// cross-midnight interval belongs to its start day, so the previous day's rules
/// still protect the current day until that interval ends. Holidays replace the
/// rules of the day they fall on and never truncate an interval started earlier.
public func evaluateProtectionSchedule(
    _ schedule: ProtectionSchedule,
    at date: Date,
    calendar: Calendar,
    holidays: MainlandHolidayCalendar
) -> ProtectionScheduleEvaluation {
    let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        ?? date.addingTimeInterval(86_400)

    guard schedule.mode == .specified else {
        return ProtectionScheduleEvaluation(
            isActive: true,
            nextTransition: nil,
            nextEvaluation: nextMidnight,
            missingHolidayYears: [],
            activeSource: "全天"
        )
    }

    // Each start day's ranges are merged before evaluation. An invalid range
    // cannot be persisted (decoding and saving both validate), so a failed
    // normalization only means hand-built input, which is evaluated as given.
    let normalized = (try? schedule.normalized()) ?? schedule

    func rules(at instant: Date) -> [DayRule] {
        let start = calendar.startOfDay(for: instant)
        let previous = calendar.date(byAdding: .day, value: -1, to: start)
        return [start, previous].compactMap { $0 }.map {
            DayRule(day: $0, schedule: normalized, calendar: calendar, holidays: holidays)
        }
    }

    func isActive(at instant: Date) -> Bool {
        rules(at: instant).contains { $0.contains(instant) }
    }

    let currentRules = rules(at: date)
    let activeRule = currentRules.first { $0.contains(date) }

    // Only the current and previous day's endpoints matter, plus at most the
    // offset transitions before the next midnight: no unbounded scan.
    var candidates = currentRules.flatMap(\.intervals).flatMap { [$0.start, $0.end] }
    candidates += timeZoneTransitions(after: date, before: nextMidnight, in: calendar.timeZone)
    candidates = candidates.filter { $0 > date && $0 < nextMidnight }.sorted()

    return ProtectionScheduleEvaluation(
        isActive: activeRule != nil,
        // A candidate counts only when the state really flips across it, probed
        // half a second either side so none is sampled exactly on the boundary.
        nextTransition: candidates.first {
            isActive(at: $0.addingTimeInterval(-0.5)) != isActive(at: $0.addingTimeInterval(0.5))
        },
        nextEvaluation: candidates.first ?? nextMidnight,
        missingHolidayYears: Set(currentRules.compactMap(\.missingYear)),
        activeSource: activeRule?.source
    )
}

/// One start day's rule, resolved into absolute half-open intervals.
private struct DayRule {
    let source: String
    let missingYear: Int?
    let intervals: [(start: Date, end: Date)]

    func contains(_ instant: Date) -> Bool {
        intervals.contains { $0.start <= instant && instant < $0.end }
    }

    init(day: Date, schedule: ProtectionSchedule, calendar: Calendar, holidays: MainlandHolidayCalendar) {
        let year = calendar.component(.year, from: day)
        var ranges: [ProtectionTimeRange]
        var source: String
        var missingYear: Int?

        if schedule.followsMainlandHolidays, holidays.hasYear(year) {
            switch holidays.kind(on: day, calendar: calendar) {
            case .rest:
                ranges = schedule.holidayRanges
                source = "节假日"
            case .makeupWorkday:
                ranges = schedule.makeupWorkdayRanges
                source = "调休上班"
            case nil:
                (ranges, source) = weeklyRule(for: day, schedule: schedule, calendar: calendar)
            }
        } else {
            // Following holidays without an arrangement for this year falls back
            // to the weekly rules and warns; another year's data is never reused.
            missingYear = schedule.followsMainlandHolidays ? year : nil
            (ranges, source) = weeklyRule(for: day, schedule: schedule, calendar: calendar)
        }

        self.source = source
        self.missingYear = missingYear
        self.intervals = ranges.map {
            (start: resolvedInstant(atMinute: $0.startMinute, from: day, calendar: calendar),
             end: resolvedInstant(atMinute: $0.endMinute, from: day, calendar: calendar))
        }
    }
}

/// Weekly ranges are Monday-first; `Calendar.weekday` is Sunday-first.
private func weeklyRule(
    for day: Date,
    schedule: ProtectionSchedule,
    calendar: Calendar
) -> (ranges: [ProtectionTimeRange], source: String) {
    let index = (calendar.component(.weekday, from: day) + 5) % 7
    let label = "每周·\(weekdayLabels[index])"
    guard schedule.weeklyRanges.indices.contains(index) else { return ([], label) }
    return (schedule.weeklyRanges[index], label)
}

/// Resolves a wallclock minute offset from `startDay`'s local midnight.
///
/// Repeated wallclock times (fall-back) resolve to their first occurrence, so a
/// range's endpoints are single stable instants: 01:30 is the first 01:30. Times
/// skipped by a spring-forward jump collapse onto the instant the clock jumps
/// over them, so minutes that never exist add no duration — an interval made
/// only of skipped minutes is empty instead of being stretched by the gap.
private func resolvedInstant(atMinute minute: Int, from startDay: Date, calendar: Calendar) -> Date {
    let dayOffset = Int((Double(minute) / 1_440).rounded(.down))
    let minuteOfDay = minute - dayOffset * 1_440
    let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
    var components = calendar.dateComponents([.year, .month, .day], from: day)
    components.hour = minuteOfDay / 60
    components.minute = minuteOfDay % 60
    components.second = 0

    if let exact = calendar.date(from: components) {
        let resolved = calendar.dateComponents([.hour, .minute], from: exact)
        if resolved.hour == components.hour, resolved.minute == components.minute {
            return exact
        }
    }
    return skippedMinuteInstant(atMinute: minuteOfDay, on: day, calendar: calendar)
}

/// First instant of `day` whose wallclock time reaches `minute`.
///
/// Only reached when that wallclock time does not exist, i.e. through a forward
/// jump, and wallclock minutes never move backwards there — so a bounded binary
/// search converges on the moment the clock skips the request.
// ponytail: assumes one forward transition in the day; a day with a forward and
// a backward jump would need a scan instead of a binary search.
private func skippedMinuteInstant(atMinute minute: Int, on day: Date, calendar: Calendar) -> Date {
    func wallclockMinutes(_ instant: Date) -> Double {
        let days = Double(calendar.dateComponents([.day], from: day, to: instant).day ?? 0)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: instant)
        return days * 1_440
            + Double(parts.hour ?? 0) * 60
            + Double(parts.minute ?? 0)
            + Double(parts.second ?? 0) / 60
    }

    let target = Double(minute)
    var low = day
    var high = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    if wallclockMinutes(low) >= target { return low }
    while high.timeIntervalSince(low) > 0.1 {
        let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
        if wallclockMinutes(middle) >= target { high = middle } else { low = middle }
    }
    return Date(timeIntervalSinceReferenceDate: high.timeIntervalSinceReferenceDate.rounded())
}

/// Offset changes strictly inside `(date, limit)`, capped because at most one is
/// expected before the next midnight.
private func timeZoneTransitions(after date: Date, before limit: Date, in timeZone: TimeZone) -> [Date] {
    var transitions: [Date] = []
    var cursor = date
    while transitions.count < 4,
          let next = timeZone.nextDaylightSavingTimeTransition(after: cursor),
          next < limit {
        transitions.append(next)
        cursor = next
    }
    return transitions
}

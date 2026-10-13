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

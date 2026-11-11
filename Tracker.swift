import Foundation

public enum DayGrouping: String, Codable, CaseIterable, Identifiable, Sendable {
    case startDay
    case endDay

    public var id: String { rawValue }
    public var title: String { self == .startDay ? "Start day" : "End day" }
}

public struct Tracker: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var calendarID: String
    public var eventTitles: [String]
    public var grouping: DayGrouping
    public var dailyGoalHours: Double?
    public var daysPerWeek: Int
    public var colorHex: String?
    public var calendarColorHex: String?
    public var calendarTitle: String?
    public var calendarAccount: String?

    public init(id: UUID = UUID(), name: String, calendarID: String, eventTitles: [String], grouping: DayGrouping, dailyGoalHours: Double? = nil, daysPerWeek: Int = 7, colorHex: String? = nil, calendarColorHex: String? = nil, calendarTitle: String? = nil, calendarAccount: String? = nil) {
        self.id = id
        self.name = name
        self.calendarID = calendarID
        self.eventTitles = Self.normalized(eventTitles)
        self.grouping = grouping
        self.dailyGoalHours = dailyGoalHours
        self.daysPerWeek = min(7, max(1, daysPerWeek))
        self.colorHex = colorHex
        self.calendarColorHex = calendarColorHex
        self.calendarTitle = calendarTitle
        self.calendarAccount = calendarAccount
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, calendarID, eventTitles, grouping, dailyGoalHours, daysPerWeek, colorHex, calendarColorHex, calendarTitle, calendarAccount
        case eventTitle
    }

    public static func normalized(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        return titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        calendarID = try values.decode(String.self, forKey: .calendarID)
        if let titles = try values.decodeIfPresent([String].self, forKey: .eventTitles) {
            eventTitles = Self.normalized(titles)
        } else {
            eventTitles = Self.normalized([try values.decode(String.self, forKey: .eventTitle)])
        }
        grouping = try values.decode(DayGrouping.self, forKey: .grouping)
        dailyGoalHours = try values.decodeIfPresent(Double.self, forKey: .dailyGoalHours).flatMap { $0 > 0 ? $0 : nil }
        daysPerWeek = min(7, max(1, try values.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 7))
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex)
        calendarColorHex = try values.decodeIfPresent(String.self, forKey: .calendarColorHex)
        calendarTitle = try values.decodeIfPresent(String.self, forKey: .calendarTitle)
        calendarAccount = try values.decodeIfPresent(String.self, forKey: .calendarAccount)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(calendarID, forKey: .calendarID)
        try values.encode(eventTitles, forKey: .eventTitles)
        try values.encode(grouping, forKey: .grouping)
        try values.encodeIfPresent(dailyGoalHours, forKey: .dailyGoalHours)
        try values.encode(daysPerWeek, forKey: .daysPerWeek)
        try values.encodeIfPresent(colorHex, forKey: .colorHex)
        try values.encodeIfPresent(calendarColorHex, forKey: .calendarColorHex)
        try values.encodeIfPresent(calendarTitle, forKey: .calendarTitle)
        try values.encodeIfPresent(calendarAccount, forKey: .calendarAccount)
    }
}

public struct EventInterval: Sendable {
    public let calendarID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(calendarID: String, title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

public struct DailyDuration: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let duration: TimeInterval
}

public struct WeeklyReport: Equatable, Sendable {
    public let weekStart: Date
    public let days: [DailyDuration]
    public let averageDayCount: Int
    public let eventCount: Int
    public let nextEventEnd: Date?
    public var total: TimeInterval { days.reduce(0) { $0 + $1.duration } }
    public var dailyAverage: TimeInterval { averageDayCount > 0 ? total / Double(averageDayCount) : 0 }
}

public enum DurationText {
    public static func format(_ duration: TimeInterval) -> String {
        guard duration.isFinite else { return "0m" }
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let remainder = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if remainder > 0 { parts.append("\(remainder)s") }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
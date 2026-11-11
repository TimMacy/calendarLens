import Foundation

public struct TimeCalculator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func weekStart(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day)!
    }

    public func addingDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }

    public func assignedDay(for interval: DateInterval, grouping: DayGrouping) -> Date {
        calendar.startOfDay(for: grouping == .endDay ? interval.end : interval.start)
    }

    public func events(weekStart: Date, tracker: Tracker, now: Date, fetch: (DateInterval) throws -> [EventInterval]) rethrows -> [EventInterval] {
        let monday = self.weekStart(containing: weekStart)
        let nextMonday = addingDays(7, to: monday)
        var window = DateInterval(start: addingDays(-1, to: monday), end: addingDays(1, to: nextMonday))
        var events = try fetch(window)
        for _ in 0..<8 {
            let runs = merged(matching(events, tracker: tracker).filter { $0.end <= now }).map(\.interval).filter { $0.end >= monday && $0.start <= nextMonday }
            guard let start = runs.map(\.start).min(), let end = runs.map(\.end).max(), start < window.start || end > window.end else { break }
            window = DateInterval(start: min(start, window.start), end: max(end, window.end))
            events = try fetch(window)
        }
        return events
    }

    public func report(events: [EventInterval], tracker: Tracker, weekStart: Date, now: Date) -> WeeklyReport {
        let monday = self.weekStart(containing: weekStart)
        let nextMonday = addingDays(7, to: monday)
        let matching = matching(events, tracker: tracker)

        var totals: [Date: TimeInterval] = [:]
        var eventCount = 0
        for entry in merged(matching.filter { $0.end <= now }) {
            let day = assignedDay(for: entry.interval, grouping: tracker.grouping)
            if day >= monday && day < nextMonday {
                totals[day, default: 0] += entry.interval.duration
                eventCount += entry.eventCount
            }
        }
        let days = (0..<7).map { offset in
            let day = addingDays(offset, to: monday)
            return DailyDuration(date: day, duration: totals[day, default: 0])
        }
        let currentMonday = self.weekStart(containing: now)
        let elapsedDays = (calendar.dateComponents([.day], from: monday, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        let calendarDayCount = monday == currentMonday ? min(7, max(1, elapsedDays)) : 7
        let activeDayCount = days.filter { $0.duration > 0 }.count
        let denominator = max(1, min(calendarDayCount, tracker.daysPerWeek), activeDayCount)
        let nextEventEnd = matching.filter { $0.end > now }.map(\.end).min()
        return WeeklyReport(weekStart: monday, days: days, averageDayCount: denominator, eventCount: eventCount, nextEventEnd: nextEventEnd)
    }

    private func matching(_ events: [EventInterval], tracker: Tracker) -> [EventInterval] {
        let titles = Set(Tracker.normalized(tracker.eventTitles))
        return events.filter {
            $0.calendarID == tracker.calendarID && titles.contains($0.title.trimmingCharacters(in: .whitespacesAndNewlines)) && !$0.isAllDay && $0.start < $0.end
        }
    }

    private func merged(_ events: [EventInterval]) -> [(interval: DateInterval, eventCount: Int)] {
        var merged: [(interval: DateInterval, eventCount: Int)] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, event.start < last.interval.end {
                merged[merged.count - 1] = (DateInterval(start: last.interval.start, end: max(last.interval.end, event.end)), last.eventCount + 1)
            } else {
                merged.append((DateInterval(start: event.start, end: event.end), 1))
            }
        }
        return merged
    }
}
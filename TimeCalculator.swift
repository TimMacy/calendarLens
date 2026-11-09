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

    public func queryWindow(weekStart: Date, grouping: DayGrouping) -> DateInterval {
        let monday = self.weekStart(containing: weekStart)
        return DateInterval(start: monday, end: addingDays(7, to: monday))
    }

    public func report(events: [EventInterval], tracker: Tracker, weekStart: Date, now: Date) -> WeeklyReport {
        let monday = self.weekStart(containing: weekStart)
        let nextMonday = addingDays(7, to: monday)
        let titles = Set(Tracker.normalized(tracker.eventTitles))
        let matching = events.filter {
            $0.calendarID == tracker.calendarID && titles.contains($0.title.trimmingCharacters(in: .whitespacesAndNewlines)) && !$0.isAllDay && $0.end <= now && $0.start < $0.end
        }.sorted { $0.start < $1.start }

        var merged: [(interval: DateInterval, eventCount: Int)] = []
        for event in matching {
            if let last = merged.last, event.start < last.interval.end {
                merged[merged.count - 1] = (DateInterval(start: last.interval.start, end: max(last.interval.end, event.end)), last.eventCount + 1)
            } else {
                merged.append((DateInterval(start: event.start, end: event.end), 1))
            }
        }

        var totals: [Date: TimeInterval] = [:]
        var eventCount = 0
        for entry in merged {
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
        let denominator = max(min(calendarDayCount, tracker.daysPerWeek), activeDayCount)
        return WeeklyReport(weekStart: monday, days: days, averageDayCount: denominator, eventCount: eventCount)
    }
}
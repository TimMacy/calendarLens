import CoreGraphics
import EventKit
import Foundation

struct CalendarChoice: Identifiable, Sendable {
    let id: String
    let title: String
    let account: String
    let colorHex: String?
    var label: String { "\(title) — \(account)" }
}

enum CalendarAccess: Sendable {
    case needsPermission, allowed, denied, restricted
}

enum CalendarReadError: LocalizedError {
    case missingCalendar
    case permissionUnavailable

    var errorDescription: String? {
        switch self {
        case .missingCalendar: return "The tracker's calendar is no longer available. Edit the tracker to select another calendar."
        case .permissionUnavailable: return "Calendar access is unavailable. Check Calendar permissions in System Settings, then refresh."
        }
    }
}

actor CalendarService {
    private let store = EKEventStore()
    private var calendarChoices: [CalendarChoice]?

    func access(requestPermission: Bool) async throws -> CalendarAccess {
        if requestPermission && Self.currentAccess() == .needsPermission {
            _ = try await store.requestFullAccessToEvents()
        }
        return Self.currentAccess()
    }

    nonisolated static func currentAccess() -> CalendarAccess {
        access(for: EKEventStore.authorizationStatus(for: .event))
    }

    private nonisolated static func access(for status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: return .allowed
        case .notDetermined: return .needsPermission
        case .restricted: return .restricted
        default: return .denied
        }
    }

    func calendars(reload: Bool = false) throws -> [CalendarChoice] {
        try requireAccess()
        if !reload, let calendarChoices { return calendarChoices }
        let choices = store.calendars(for: .event).map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, colorHex: Self.hex($0.cgColor))
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        calendarChoices = choices
        return choices
    }

    func titles(calendarID: String, now: Date = Date()) throws -> [String] {
        try requireAccess()
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw CalendarReadError.missingCalendar }
        let start = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let predicate = store.predicateForEvents(withStart: start, end: now, calendars: [calendar])
        let titles = store.events(matching: predicate).filter {
            !$0.isAllDay && $0.endDate <= now && $0.startDate < $0.endDate
        }.map { ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Set(titles).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func report(tracker: Tracker, weekStart: Date, now: Date) throws -> WeeklyReport {
        try requireAccess()
        guard let calendar = store.calendar(withIdentifier: tracker.calendarID) else { throw CalendarReadError.missingCalendar }
        let calculator = TimeCalculator()
        let events = calculator.events(weekStart: weekStart, tracker: tracker, now: now) { window in
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
            return store.events(matching: predicate).map {
                EventInterval(calendarID: $0.calendar.calendarIdentifier, title: $0.title ?? "", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
            }
        }
        try requireAccess()
        return calculator.report(events: events, tracker: tracker, weekStart: weekStart, now: now)
    }

    private static func hex(_ color: CGColor?) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color?.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        let rgb = components.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarReadError.permissionUnavailable }
    }
}
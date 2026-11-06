import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var trackers: [Tracker] = []
    @Published var selectedTrackerID: UUID?
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var access: CalendarAccess = CalendarService.currentAccess()
    @Published private(set) var report: WeeklyReport?
    @Published private(set) var isLoading = false
    @Published private(set) var refreshError: String?
    @Published private(set) var calendarMissing = false
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published var settingsError: String?
    @Published private(set) var settingsVisible = false
    @Published private(set) var eventTitlesRevision = 0
    @Published private(set) var displayedWeek = TimeCalculator().weekStart(containing: Date())

    let service = CalendarService()
    private let repository: TrackerRepository
    private var settingsLoaded = false
    private var refreshTask: Task<Void, Never>?
    private var refreshSequence = 0
    private var calendarChanges: AnyCancellable?
    private var eventTitleCache: [String: [String]] = [:]
    private var calendarsNeedReload = true
    private static let legacyCalendarColorsKey = "calendarColors"

    var selectedTracker: Tracker? { trackers.first { $0.id == selectedTrackerID } }
    var currentWeek: Date { TimeCalculator().weekStart(containing: Date()) }
    var canGoForward: Bool { displayedWeek < currentWeek }
    var settingsWritable: Bool { settingsLoaded }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calendarLens", isDirectory: true)
        repository = TrackerRepository(fileURL: directory.appendingPathComponent("trackers.json"))
        do {
            trackers = try repository.load()
            settingsLoaded = true
            selectedTrackerID = trackers.first?.id
            moveLegacyCalendarColors()
        } catch {
            settingsError = "Couldn't load saved trackers: \(error.localizedDescription)"
        }
        calendarChanges = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(reloadMetadata: true) }
    }

    func refresh(requestPermission: Bool = false, reloadMetadata: Bool = false) {
        let reloadMetadata = reloadMetadata || requestPermission
        if reloadMetadata {
            invalidateEventTitles()
            calendarsNeedReload = true
        }
        refreshTask?.cancel()
        refreshSequence += 1
        let sequence = refreshSequence
        isLoading = true
        refreshError = nil
        calendarMissing = false
        let tracker = selectedTracker
        let week = min(displayedWeek, currentWeek)
        displayedWeek = week
        refreshTask = Task {
            defer { if sequence == refreshSequence { isLoading = false } }
            do {
                let permission = try await service.access(requestPermission: requestPermission)
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                access = permission
                guard permission == .allowed else {
                    report = nil
                    calendars = []
                    return
                }
                let choices = try await service.calendars(reload: calendarsNeedReload)
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                calendars = choices
                calendarsNeedReload = false
                saveCalendarColors(from: choices)
                if let tracker, !choices.contains(where: { $0.id == tracker.calendarID }) {
                    report = nil
                    calendarMissing = true
                    return
                }
                let now = Date()
                let result: WeeklyReport?
                if let tracker {
                    result = try await service.report(tracker: tracker, weekStart: week, now: now)
                } else {
                    result = nil
                }
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                report = result
                lastSuccessfulRefresh = now
            } catch {
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                report = nil
                if case CalendarReadError.missingCalendar = error {
                    calendarMissing = true
                } else {
                    refreshError = error.localizedDescription
                }
            }
        }
    }

    func moveWeek(_ direction: Int) {
        displayedWeek = min(TimeCalculator().addingDays(direction * 7, to: displayedWeek), currentWeek)
        refresh()
    }

    func showThisWeek() {
        displayedWeek = currentWeek
        refresh()
    }

    func save(_ tracker: Tracker) throws {
        var updated = trackers
        if let index = updated.firstIndex(where: { $0.id == tracker.id }) {
            updated[index] = tracker
        } else {
            updated.append(tracker)
        }
        try repository.save(updated)
        trackers = updated
        selectedTrackerID = tracker.id
        refresh()
    }

    func moveTrackers(from source: IndexSet, to destination: Int) {
        guard settingsWritable else { return }
        var updated = trackers
        updated.move(fromOffsets: source, toOffset: destination)
        guard updated != trackers else { return }
        do {
            try repository.save(updated)
            trackers = updated
        } catch {
            settingsError = "Couldn't save tracker order: \(error.localizedDescription)"
        }
    }

    func removeTracker(_ id: UUID) {
        let updated = trackers.filter { $0.id != id }
        do {
            try repository.save(updated)
            trackers = updated
            if selectedTrackerID == id { selectedTrackerID = updated.first?.id }
            refresh()
        } catch {
            settingsError = "Couldn't save trackers: \(error.localizedDescription)"
        }
    }

    func selectionChanged() {
        refresh()
    }

    func setSettingsVisible(_ visible: Bool) {
        guard settingsVisible != visible else { return }
        settingsVisible = visible
        if !visible { invalidateEventTitles() }
    }

    private func invalidateEventTitles() {
        eventTitleCache = [:]
        eventTitlesRevision += 1
    }

    func eventTitles(for calendarID: String) async throws -> [String] {
        if let cached = eventTitleCache[calendarID] { return cached }
        let revision = eventTitlesRevision
        let titles = try await service.titles(calendarID: calendarID)
        if settingsVisible && revision == eventTitlesRevision { eventTitleCache[calendarID] = titles }
        return titles
    }

    static let fallbackTrackerColor = Color(hex: "#12A38F")!

    func calendarColor(for calendarID: String) -> Color? {
        Color(hex: calendarColorHex(for: calendarID))
    }

    func calendarColorHex(for calendarID: String) -> String? {
        calendars.first { $0.id == calendarID }?.colorHex ?? trackers.first { $0.calendarID == calendarID && $0.calendarColorHex != nil }?.calendarColorHex
    }

    private func saveCalendarColors(from choices: [CalendarChoice]) {
        updateCalendarColors { id in choices.first { $0.id == id }?.colorHex }
    }

    private func moveLegacyCalendarColors() {
        guard let legacy = UserDefaults.standard.dictionary(forKey: Self.legacyCalendarColorsKey) as? [String: String] else { return }
        if updateCalendarColors(onlyMissing: true, { legacy[$0] }) {
            UserDefaults.standard.removeObject(forKey: Self.legacyCalendarColorsKey)
        }
    }

    @discardableResult
    private func updateCalendarColors(onlyMissing: Bool = false, _ colorHex: (String) -> String?) -> Bool {
        guard settingsWritable else { return false }
        var updated = trackers
        for index in updated.indices where !onlyMissing || updated[index].calendarColorHex == nil {
            if let hex = colorHex(updated[index].calendarID), hex != updated[index].calendarColorHex {
                updated[index].calendarColorHex = hex
            }
        }
        guard updated != trackers else { return true }
        do {
            try repository.save(updated)
            trackers = updated
            return true
        } catch {
            settingsError = "Couldn't save calendar colors: \(error.localizedDescription)"
            return false
        }
    }

    func color(for tracker: Tracker) -> Color {
        Color(hex: tracker.colorHex)
            ?? Color(hex: calendars.first { $0.id == tracker.calendarID }?.colorHex)
            ?? Color(hex: tracker.calendarColorHex)
            ?? Self.fallbackTrackerColor
    }

    func openCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }
}

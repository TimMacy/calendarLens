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
    @Published private(set) var access = CalendarService.currentAccess()
    @Published private(set) var report: WeeklyReport?
    @Published private(set) var isLoading = false
    @Published private(set) var refreshError: String?
    @Published private(set) var calendarMissing = false
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published var settingsError: String?
    @Published private(set) var loadProblem: String?
    @Published private(set) var settingsVisible = false
    @Published private(set) var eventTitlesRevision = 0
    @Published private(set) var displayedWeek = TimeCalculator().weekStart(containing: Date())

    let service = CalendarService()
    private let repository: TrackerRepository
    private var refreshTask: Task<Void, Never>?
    private var refreshSequence = 0
    private var observers: Set<AnyCancellable> = []
    private var eventTitleCache: [String: [String]] = [:]
    private var eventTitlesStale = false
    private var calendarsNeedReload = true
    private static let legacyCalendarColorsKey = "calendarColors"
    private var requestingPermission = false
    private var followsCurrentWeek = true
    private var shownSelection: Selection?
    private var staleReportTask: Task<Void, Never>?
    private var eventEndTask: Task<Void, Never>?

    private struct Selection: Equatable {
        var trackerID: UUID?
        var week: Date
    }

    private struct ChangesOff: LocalizedError {
        var errorDescription: String? { "Changes are off until the trackers file is replaced." }
    }

    var selectedTracker: Tracker? { trackers.first { $0.id == selectedTrackerID } }
    var currentWeek: Date { TimeCalculator().weekStart(containing: Date()) }
    var canGoForward: Bool { displayedWeek < currentWeek }
    var settingsWritable: Bool { loadProblem == nil }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calendarLens", isDirectory: true)
        repository = TrackerRepository(fileURL: directory.appendingPathComponent("trackers.json"))
        do {
            let saved = try repository.load()
            trackers = saved.trackers
            if saved.unreadable > 0 {
                loadProblem = "\(saved.unreadable == 1 ? "1 saved tracker" : "\(saved.unreadable) saved trackers") couldn't be read. Changes are off until the file is replaced."
            }
        } catch {
            loadProblem = "Saved trackers couldn't be read. Changes are off until the file is replaced."
        }
        selectedTrackerID = trackers.first?.id
        settingsError = loadProblem
        moveLegacyCalendarColors()

        let center = NotificationCenter.default
        center.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(reloadMetadata: true) }
            .store(in: &observers)
        center.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: center.publisher(for: .NSCalendarDayChanged))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &observers)
    }

    func refresh(requestPermission: Bool = false, reloadMetadata: Bool = false) {
        if requestPermission {
            invalidateEventTitles()
            calendarsNeedReload = true
        } else if reloadMetadata {
            eventTitlesStale = true
            calendarsNeedReload = true
        }
        guard !requestingPermission else { return }
        requestingPermission = requestPermission && CalendarService.currentAccess() == .needsPermission
        refreshTask?.cancel()
        eventEndTask?.cancel()
        refreshSequence += 1
        let sequence = refreshSequence
        isLoading = true
        let week = followsCurrentWeek ? currentWeek : min(displayedWeek, currentWeek)
        if displayedWeek != week { displayedWeek = week }
        let selection = Selection(trackerID: selectedTrackerID, week: week)
        if selection != shownSelection {
            refreshError = nil
            calendarMissing = false
            if report != nil { clearStaleReportSoon() }
        }
        refreshTask = Task {
            defer { if sequence == refreshSequence { isLoading = false } }
            do {
                let permission: CalendarAccess
                do {
                    defer { requestingPermission = false }
                    permission = try await service.access(requestPermission: requestPermission)
                }
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                access = permission
                guard permission == .allowed else {
                    calendars = []
                    show(nil, for: selection)
                    return
                }
                let choices = try await service.calendars(reload: calendarsNeedReload)
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                calendars = choices
                calendarsNeedReload = false
                saveCalendarDetails(from: choices)
                let now = Date()
                guard let tracker = trackers.first(where: { $0.id == selection.trackerID }) else {
                    show(nil, for: selection)
                    lastSuccessfulRefresh = now
                    return
                }
                guard choices.contains(where: { $0.id == tracker.calendarID }) else {
                    show(nil, missing: true, for: selection)
                    return
                }
                let result = try await service.report(tracker: tracker, weekStart: week, now: now)
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                show(result, for: selection)
                lastSuccessfulRefresh = now
                refreshWhenEventEnds(result.nextEventEnd)
            } catch {
                guard sequence == refreshSequence && !Task.isCancelled else { return }
                if case CalendarReadError.missingCalendar = error {
                    show(nil, missing: true, for: selection)
                } else {
                    show(nil, error: error.localizedDescription, for: selection)
                }
            }
        }
    }

    private func show(_ report: WeeklyReport?, missing: Bool = false, error: String? = nil, for selection: Selection) {
        staleReportTask?.cancel()
        staleReportTask = nil
        self.report = report
        calendarMissing = missing
        refreshError = error
        shownSelection = selection
    }

    private func clearStaleReportSoon() {
        guard staleReportTask == nil else { return }
        staleReportTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            staleReportTask = nil
            if shownSelection != Selection(trackerID: selectedTrackerID, week: displayedWeek) { report = nil }
        }
    }

    private func refreshWhenEventEnds(_ end: Date?) {
        guard let end else { return }
        eventEndTask = Task {
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 1))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    func moveWeek(_ direction: Int) {
        displayedWeek = min(TimeCalculator().addingDays(direction * 7, to: displayedWeek), currentWeek)
        followsCurrentWeek = displayedWeek == currentWeek
        refresh()
    }

    func showThisWeek() {
        followsCurrentWeek = true
        refresh()
    }

    func save(_ tracker: Tracker) throws {
        guard settingsWritable else { throw ChangesOff() }
        var updated = trackers
        if let index = updated.firstIndex(where: { $0.id == tracker.id }) {
            updated[index] = tracker
        } else {
            updated.append(tracker)
        }
        try write(updated)
        selectedTrackerID = tracker.id
        refresh()
    }

    func moveTrackers(from source: IndexSet, to destination: Int) {
        guard settingsWritable else { return }
        var updated = trackers
        updated.move(fromOffsets: source, toOffset: destination)
        guard updated != trackers else { return }
        do {
            try write(updated)
        } catch {
            settingsError = "Couldn't save tracker order: \(error.localizedDescription)"
        }
    }

    func removeTracker(_ id: UUID) {
        guard settingsWritable else { return }
        do {
            try write(trackers.filter { $0.id != id })
            if selectedTrackerID == id { selectedTrackerID = trackers.first?.id }
            refresh()
        } catch {
            settingsError = "Couldn't save trackers: \(error.localizedDescription)"
        }
    }

    private func write(_ updated: [Tracker]) throws {
        try repository.save(updated)
        trackers = updated
        settingsError = nil
    }

    func replaceUnreadableSettings() {
        guard !settingsWritable else { return }
        do {
            try repository.backUp()
            try repository.save(trackers)
            loadProblem = nil
            settingsError = nil
        } catch {
            settingsError = "Couldn't replace the file: \(error.localizedDescription)"
        }
    }

    func showSettingsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([repository.fileURL])
    }

    func selectionChanged() {
        refresh()
    }

    func setSettingsVisible(_ visible: Bool) {
        if visible && eventTitlesStale { invalidateEventTitles() }
        guard settingsVisible != visible else { return }
        settingsVisible = visible
        if !visible { invalidateEventTitles() }
    }

    private func invalidateEventTitles() {
        eventTitleCache = [:]
        eventTitlesStale = false
        eventTitlesRevision += 1
    }

    func eventTitles(for calendarID: String) async throws -> [String] {
        if eventTitlesStale {
            eventTitleCache = [:]
            eventTitlesStale = false
        }
        if let cached = eventTitleCache[calendarID] { return cached }
        let revision = eventTitlesRevision
        let titles = try await service.titles(calendarID: calendarID)
        if settingsVisible && revision == eventTitlesRevision && !eventTitlesStale { eventTitleCache[calendarID] = titles }
        return titles
    }

    static let fallbackTrackerColor = Color(hex: "#12A38F")!

    func calendarColor(for calendarID: String) -> Color? {
        Color(hex: calendarColorHex(for: calendarID))
    }

    func calendarColorHex(for calendarID: String) -> String? {
        calendars.first { $0.id == calendarID }?.colorHex ?? trackers.first { $0.calendarID == calendarID && $0.calendarColorHex != nil }?.calendarColorHex
    }

    private func saveCalendarDetails(from choices: [CalendarChoice]) {
        guard settingsWritable else { return }
        var updated = trackers
        for index in updated.indices {
            var choice = choices.first { $0.id == updated[index].calendarID }
            if choice == nil, let title = updated[index].calendarTitle, let account = updated[index].calendarAccount {
                let matches = choices.filter { $0.title == title && $0.account == account }
                if matches.count == 1 { choice = matches[0] }
            }
            guard let choice else { continue }
            updated[index].calendarID = choice.id
            updated[index].calendarTitle = choice.title
            updated[index].calendarAccount = choice.account
            if let hex = choice.colorHex { updated[index].calendarColorHex = hex }
        }
        guard updated != trackers else { return }
        do {
            try write(updated)
        } catch {
            settingsError = "Couldn't save calendar details: \(error.localizedDescription)"
        }
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
            try write(updated)
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
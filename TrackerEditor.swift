import SwiftUI

struct TrackerEditor: View {
    @ObservedObject var model: AppModel
    let existing: Tracker?
    @Binding var hasChanges: Bool
    let onSave: (Tracker) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @State private var calendarID: String
    @State private var eventTitles: [String]
    @State private var grouping: DayGrouping
    @State private var hasDailyGoal: Bool
    @State private var dailyGoalHours: Double
    @State private var daysPerWeek: Int
    @State private var usesCalendarColor: Bool
    @State private var customColor: Color
    @State private var titles: [String] = []
    @State private var loadingTitles = false
    @State private var titleError: String?
    @State private var saveError: String?

    @State private var checkedByCalendar: [String: [String]] = [:]
    @State private var original: Draft?

    private struct Draft: Equatable {
        var name: String
        var calendarID: String
        var eventTitles: [String]
        var grouping: DayGrouping
        var dailyGoalHours: Double?
        var daysPerWeek: Int
        var customColor: Color?
    }

    private var draft: Draft {
        Draft(name: name, calendarID: calendarID, eventTitles: eventTitles, grouping: grouping, dailyGoalHours: hasDailyGoal ? dailyGoalHours : nil, daysPerWeek: daysPerWeek, customColor: usesCalendarColor ? nil : customColor)
    }

    init(model: AppModel, existing: Tracker?, hasChanges: Binding<Bool>, onSave: @escaping (Tracker) -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.existing = existing
        _hasChanges = hasChanges
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        _calendarID = State(initialValue: existing?.calendarID ?? model.calendars.first?.id ?? "")
        _eventTitles = State(initialValue: existing?.eventTitles ?? [])
        _grouping = State(initialValue: existing?.grouping ?? .startDay)
        _hasDailyGoal = State(initialValue: existing?.dailyGoalHours != nil)
        _dailyGoalHours = State(initialValue: existing?.dailyGoalHours ?? 7)
        _daysPerWeek = State(initialValue: existing?.daysPerWeek ?? 7)
        _usesCalendarColor = State(initialValue: existing?.colorHex == nil)
        let calendarID = existing?.calendarID ?? model.calendars.first?.id ?? ""
        _customColor = State(initialValue: Color(hex: existing?.colorHex) ?? model.calendarColor(for: calendarID) ?? AppModel.fallbackTrackerColor)
    }

    private var calendarColor: Color { model.calendarColor(for: calendarID) ?? AppModel.fallbackTrackerColor }

    private var dashboardColor: Color {
        AppModel.dashboardColor(usesCalendarColor ? calendarColor : customColor, isCustom: !usesCalendarColor)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !eventTitles.isEmpty && model.calendars.contains { $0.id == calendarID } && (!hasDailyGoal || (dailyGoalHours > 0 && dailyGoalHours <= 24))
    }

    private var menuTitles: [String] {
        Set(titles + eventTitles).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func isChecked(_ title: String) -> Binding<Bool> {
        Binding(get: { eventTitles.contains(title) }, set: { checked in
            if checked {
                guard !eventTitles.contains(title) else { return }
                eventTitles.append(title)
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = title }
            } else {
                eventTitles.removeAll { $0 == title }
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(existing == nil ? "Add Tracker" : "Edit Tracker").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                Picker("Calendar", selection: $calendarID) {
                    if !model.calendars.contains(where: { $0.id == calendarID }) {
                        Text("Unavailable calendar").tag(calendarID)
                    }
                    ForEach(model.calendars) { calendar in
                        Text(calendar.label).tag(calendar.id)
                    }
                }
                LabeledContent("Event titles") {
                    Menu(eventTitles.isEmpty ? "Choose Titles" : eventTitles.joined(separator: ", ")) {
                        if loadingTitles {
                            Text("Loading event titles…")
                        } else if menuTitles.isEmpty {
                            Text("No past event titles found")
                        }
                        ForEach(menuTitles, id: \.self) { title in
                            Toggle(title, isOn: isChecked(title))
                        }
                        if eventTitles.count > 1 {
                            Divider()
                            Button("Deselect All") { eventTitles = [] }
                        }
                    }
                    .disabled(model.access != .allowed)
                }
                Text("Titles come from completed events in the past year. Events with any checked title count; overlapping time counts once.")
                    .font(.caption).foregroundStyle(.secondary)
                if let titleError {
                    Text(titleError).font(.caption).foregroundStyle(.red)
                }
                Picker("Count toward", selection: $grouping) {
                    ForEach(DayGrouping.allCases) { rule in Text(rule.title).tag(rule) }
                }
                Text(grouping == .endDay ? "Each event counts toward the day it ends, even when it started before midnight." : "Each event counts toward the day it starts, even when it crosses midnight.")
                    .font(.caption).foregroundStyle(.secondary)
                Section("Color") {
                    Toggle("Use Calendar color", isOn: Binding(get: { usesCalendarColor }, set: { on in
                        if !on && existing?.colorHex == nil { customColor = calendarColor }
                        usesCalendarColor = on
                    }))
                    let tooDark = AppModel.isTooDark(dashboardColor)
                    LabeledContent("Color") {
                        HStack(spacing: 10) {
                            if tooDark {
                                Button("Use Lighter Color") {
                                    customColor = AppModel.lighterColor(for: dashboardColor)
                                    usesCalendarColor = false
                                }
                            }
                            ColorPicker("Color", selection: usesCalendarColor ? .constant(calendarColor) : $customColor, supportsOpacity: false)
                                .labelsHidden()
                                .disabled(usesCalendarColor)
                        }
                    }
                    if tooDark {
                        Label("This color is too dark to read well on the dashboard. Use Lighter Color picks a lighter shade; click Save to keep it.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text(usesCalendarColor ? "Matches this calendar's color in Calendar, and follows it when it changes." : "Your own color for this tracker on the dashboard.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Goal & frequency") {
                    Toggle("Daily goal", isOn: $hasDailyGoal)
                    if hasDailyGoal {
                        TextField("Hours per day", value: $dailyGoalHours, format: .number)
                        Text("The goal applies to the daily average.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Days per week", selection: $daysPerWeek) {
                        ForEach(1...7, id: \.self) { count in
                            Text(count == 7 ? "Every day (7 days)" : "\(count) \(count == 1 ? "day" : "days")").tag(count)
                        }
                    }
                    Text("The average counts elapsed days up to this frequency, or more if events fall on extra days.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let saveError { Text(saveError).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(existing == nil ? "Cancel" : "Revert") { onCancel() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || !model.settingsWritable || model.access != .allowed)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(.blue)
        .onChange(of: calendarID) { old, new in
            checkedByCalendar[old] = eventTitles
            if let checked = checkedByCalendar[new] {
                eventTitles = checked
            } else if model.calendars.contains(where: { $0.id == old }) {
                eventTitles = []
            }
        }
        .onChange(of: draft, initial: true) {
            let opened = original ?? draft
            original = opened
            hasChanges = draft != opened
        }
        .onDisappear { hasChanges = false }
        .task(id: "\(calendarID)-\(model.access == .allowed)-\(model.settingsVisible)-\(model.eventTitlesRevision)") {
            guard model.access == .allowed && model.settingsVisible else {
                titles = []
                titleError = nil
                loadingTitles = false
                return
            }
            let requestedID = calendarID
            loadingTitles = true
            titles = []
            titleError = nil
            do {
                let result = try await model.eventTitles(for: requestedID)
                guard !Task.isCancelled && requestedID == calendarID else { return }
                titles = result
            } catch {
                guard !Task.isCancelled && requestedID == calendarID else { return }
                titleError = error.localizedDescription
            }
            loadingTitles = false
        }
    }

    private func save() {
        guard canSave else { return }
        let tracker = Tracker(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), calendarID: calendarID, eventTitles: eventTitles, grouping: grouping, dailyGoalHours: hasDailyGoal ? dailyGoalHours : nil, daysPerWeek: daysPerWeek, colorHex: usesCalendarColor ? nil : customColor.hexString, calendarColorHex: model.calendarColorHex(for: calendarID))
        do {
            try model.save(tracker)
            onSave(tracker)
        } catch {
            saveError = "Couldn't save tracker: \(error.localizedDescription)"
        }
    }
}
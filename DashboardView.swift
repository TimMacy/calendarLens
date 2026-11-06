import SwiftUI

enum Palette {
    static let background = Color(hex: "#0F1115")!
    static let panel = Color(hex: "#181B22")!
    static let control = Color(hex: "#20242C")!
    static let border = Color(hex: "#262A33")!
    static let controlBorder = Color(hex: "#343944")!
    static let grid = Color(hex: "#23272F")!
    static let disabled = Color(hex: "#4A505D")!
    static let text = Color(hex: "#F4F5F7")!
    static let muted = Color(hex: "#B4B9C6")!
    static let dim = Color(hex: "#8A909D")!
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private var showsWelcome: Bool {
        model.access != .allowed || model.trackers.isEmpty
    }

    private func allowCalendarAccess() {
        if model.access == .needsPermission {
            model.refresh(requestPermission: true)
        } else {
            model.openCalendarSettings()
        }
    }

    private var lineColor: Color {
        guard let tracker = model.selectedTracker, !showsWelcome else { return Color(nsColor: .controlAccentColor) }
        return AppModel.dashboardColor(model.color(for: tracker), isCustom: tracker.colorHex != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 1140, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
        .tint(lineColor)
        .alert("Tracker Settings", isPresented: Binding(get: { model.settingsError != nil }, set: { if !$0 { model.settingsError = nil } })) {
            Button("OK") { model.settingsError = nil }
        } message: {
            Text(model.settingsError ?? "")
        }
        .onChange(of: model.selectedTrackerID) { model.selectionChanged() }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("calendarLens").font(.largeTitle.bold())
                Spacer(minLength: 16)
                if !showsWelcome { weekNavigation }
            }
            .padding(.horizontal, 32)
            .padding(.top, 38)
            .padding(.bottom, 18)
            .frame(maxWidth: 1140)
            .frame(maxWidth: .infinity)
            Rectangle().fill(lineColor).frame(height: 8)
        }
        .background(Palette.panel)
    }

    private var weekNavigation: some View {
        HStack(spacing: 8) {
            Button { model.moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(SquareButtonStyle())
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Previous Week")
                .help("Previous Week (←)")
            HStack(spacing: 8) {
                Text("W\(weekNumber)").foregroundStyle(Palette.dim)
                Text(weekRange)
            }
            .font(.headline)
            .monospacedDigit()
            Button { model.moveWeek(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(SquareButtonStyle())
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityLabel("Next Week")
                .help("Next Week (→)")
                .disabled(!model.canGoForward)
            Button("This Week") { model.showThisWeek() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.upArrow, modifiers: [])
                .help("This Week (↑ ↓)")
                .disabled(model.displayedWeek == model.currentWeek)
                .background {
                    Button("This Week") { model.showThisWeek() }
                        .keyboardShortcut(.downArrow, modifiers: [])
                        .disabled(model.displayedWeek == model.currentWeek)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
        }
        .fixedSize()
    }

    private var weekNumber: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: model.displayedWeek)
    }

    private var weekRange: String {
        let calendar = Calendar.current
        let start = model.displayedWeek
        let end = TimeCalculator().addingDays(6, to: start)
        let monthDay = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let year = calendar.component(.year, from: end)
        if calendar.component(.year, from: start) != year {
            return "\(start.formatted(monthDay)), \(calendar.component(.year, from: start)) – \(end.formatted(monthDay)), \(year)"
        }
        let last = calendar.isDate(start, equalTo: end, toGranularity: .month) ? "\(calendar.component(.day, from: end))" : end.formatted(monthDay)
        return "\(start.formatted(monthDay)) – \(last), \(year)"
    }

    @ViewBuilder private var content: some View {
        if !showsWelcome { trackerPicker }
        if model.isLoading && model.report == nil && !showsWelcome, let tracker = model.selectedTracker {
            dashboard(nil, tracker: tracker)
        } else if let error = model.refreshError {
            statusCard("Couldn't Refresh", symbol: "exclamationmark.triangle", description: error) {
                Text("Click Sync Now in Settings to try again.").font(.callout).foregroundStyle(Palette.muted)
            }
        } else if showsWelcome {
            statusCard("See Where the Time Went", symbol: "clock", description: "Allow Calendar access to track events, then open Settings and add a tracker.") {
                Button("Allow Calendar Access") { allowCalendarAccess() }
                    .disabled(model.access == .allowed)
                Button("Open Settings") { openSettings() }
            }
            .buttonStyle(.borderedProminent)
        } else if model.calendarMissing {
            statusCard("Calendar Unavailable", symbol: "calendar.badge.exclamationmark", description: "The selected calendar no longer exists. Choose another calendar for this tracker in Settings.") {}
        } else if let tracker = model.selectedTracker, let report = model.report {
            dashboard(report, tracker: tracker)
        }
    }

    @ViewBuilder private func dashboard(_ report: WeeklyReport?, tracker: Tracker) -> some View {
        HStack(spacing: 20) {
            metric("Weekly Total", value: report.map { DurationText.format($0.total) } ?? "—", note: report.map { "\($0.eventCount) \($0.eventCount == 1 ? "event" : "events")" } ?? " ")
            metric("Daily Average", value: report.map { DurationText.format($0.dailyAverage) } ?? "—", note: report.map { averageNote($0, tracker: tracker) } ?? " ")
        }
        dailyTime(report, tracker: tracker)
    }

    private var trackerPicker: some View {
        HStack(spacing: 12) {
            Text("Tracker")
            Picker("Tracker", selection: $model.selectedTrackerID) {
                ForEach(model.trackers) { tracker in
                    Text(trackerLabel(tracker)).tag(Optional(tracker.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func trackerLabel(_ tracker: Tracker) -> String {
        guard !model.calendars.isEmpty else { return tracker.name }
        let calendar = model.calendars.first(where: { $0.id == tracker.calendarID })?.label ?? "Calendar unavailable"
        return "\(tracker.name) · \(calendar)"
    }

    private func averageNote(_ report: WeeklyReport, tracker: Tracker) -> String {
        let days = "Across \(report.averageDayCount) \(report.averageDayCount == 1 ? "day" : "days")"
        guard let goal = tracker.dailyGoalHours else { return days }
        return "\(days) · Daily goal \(goal.formatted(.number)) \(goal == 1 ? "hour" : "hours")"
    }

    private func metric(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(note).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .card()
    }

    private func dailyTime(_ report: WeeklyReport?, tracker: Tracker) -> some View {
        let days = report?.days ?? (0..<7).map { DailyDuration(date: TimeCalculator().addingDays($0, to: model.displayedWeek), duration: 0) }
        return VStack(alignment: .leading, spacing: 20) {
            Text("Daily Time").font(.headline)
            WeekChart(days: days, color: lineColor, goalHours: tracker.dailyGoalHours, today: Calendar.current.startOfDay(for: Date()), showValues: report != nil)
            if report?.total == 0 {
                Label("Nothing recorded this week", systemImage: "calendar")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private func statusCard<Actions: View>(_ title: String, symbol: String, description: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(lineColor)
            Text(title).font(.title2.bold())
            Text(description).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack { actions() }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .padding(28)
        .card()
    }
}

private struct WeekChart: View {
    let days: [DailyDuration]
    let color: Color
    let goalHours: Double?
    let today: Date
    let showValues: Bool

    init(days: [DailyDuration], color: Color, goalHours: Double?, today: Date, showValues: Bool = true) {
        self.showValues = showValues
        self.days = days
        self.color = color
        self.goalHours = goalHours
        self.today = today
    }

    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private var plotHeight: CGFloat = 0
    private let axisWidth: CGFloat = 44

    private var scale: (top: Double, step: Double) {
        let peak = max(goalHours ?? 0, days.map { $0.duration / 3600 }.max() ?? 0)
        let maximum = max(1, peak * 1.15)
        let step: Double = maximum <= 2 ? 0.5 : maximum <= 6 ? 1 : maximum <= 12 ? 2 : maximum <= 24 ? 4 : 8
        return ((maximum / step).rounded(.up) * step, step)
    }

    var body: some View {
        let scale = self.scale
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let sized = resized(geometry.size.height)
                HStack(spacing: 0) {
                    sized.axisLabels(scale).frame(width: axisWidth)
                    sized.plot(scale)
                }
            }
            .frame(minHeight: 100)
            dayLabels
                .padding(.leading, axisWidth)
                .padding(.top, 10)
        }
    }

    private func resized(_ height: CGFloat) -> WeekChart {
        var copy = self
        copy.plotHeight = max(0, height)
        return copy
    }

    private func gridValues(_ scale: (top: Double, step: Double)) -> [Double] {
        stride(from: 0, through: scale.top + 0.0001, by: scale.step).map { $0 }
    }

    private func y(_ hours: Double, _ scale: (top: Double, step: Double)) -> CGFloat {
        CGFloat(hours / scale.top) * plotHeight
    }

    private func axisLabels(_ scale: (top: Double, step: Double)) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(gridValues(scale), id: \.self) { value in
                Text("\(value.formatted(.number.precision(.fractionLength(0...1))))h")
                    .font(.caption)
                    .foregroundStyle(Palette.dim)
                    .offset(y: -y(value, scale) + 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    private func plot(_ scale: (top: Double, step: Double)) -> some View {
        ZStack(alignment: .bottom) {
            ForEach(gridValues(scale), id: \.self) { value in
                Rectangle().fill(value == 0 ? Palette.controlBorder : Palette.grid).frame(height: 1)
                    .offset(y: -y(value, scale))
            }
            if let goalHours, goalHours > 0 {
                HorizontalLine()
                    .stroke(Palette.text.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                    .offset(y: -y(goalHours, scale))
                Text("Goal")
                    .font(.caption)
                    .foregroundStyle(Palette.dim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: -y(goalHours, scale) - 6)
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(days) { day in
                    UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                        .fill(color.gradient)
                        .frame(maxWidth: 64)
                        .frame(height: showValues && day.date <= today ? y(day.duration / 3600, scale) : 0)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var dayLabels: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let elapsed = showValues && day.date <= today
                VStack(spacing: 4) {
                    Text(Self.weekdays[index % 7])
                        .font(.caption)
                        .foregroundStyle(Palette.dim)
                    Text(day.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Palette.dim)
                    Text(elapsed ? DurationText.format(day.duration) : " ")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(elapsed ? DurationText.format(day.duration) : "")
            }
        }
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

private struct SquareButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(width: 30, height: 28)
            .foregroundStyle(isEnabled ? Palette.text : Palette.disabled)
            .background(isEnabled ? Palette.control : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isEnabled ? Palette.controlBorder : Palette.border))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(isEnabled ? Palette.text : Palette.dim)
            .background(isEnabled ? Palette.control : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isEnabled ? Palette.controlBorder : Palette.border))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

private extension View {
    func card() -> some View {
        background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.border))
    }
}

import SwiftUI

@main
struct CalendarLensApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("calendarLens", id: "main") {
            DashboardView(model: model)
                .frame(minWidth: 720, minHeight: 640)
                .task { model.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 900, height: 820)
        .commands { DashboardCommands() }
        Settings {
            TrackerSettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

private struct DashboardCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("calendarLens") { openWindow(id: "main") }
        }
    }
}
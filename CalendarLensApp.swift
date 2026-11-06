import SwiftUI

@main
struct CalendarLensApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("calendarLens") {
            DashboardView(model: model)
                .frame(minWidth: 720, minHeight: 640)
                .task { model.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 900, height: 820)
        Settings {
            TrackerSettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

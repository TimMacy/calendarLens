import AppKit
import SwiftUI

struct TrackerSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var editorGeneration = UUID()
    @State private var editorHasChanges = false
    @State private var pendingMove: Move?
    @State private var removal: Tracker?
    @State private var showingSync = false
    @State private var windowVisible = false

    private enum Move {
        case select(UUID?), add
    }

    private var selectedTracker: Tracker? { model.trackers.first { $0.id == selectedID } }
    private var needsAttention: Bool {
        model.refreshError != nil || model.calendarMissing || model.access != .allowed
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.trackers) { tracker in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Circle().fill(model.color(for: tracker)).frame(width: 9, height: 9)
                                            .accessibilityHidden(true)
                                        Text(tracker.name).font(.headline)
                                            .foregroundStyle(selectedID == tracker.id ? Color.white : Color.primary)
                                        if AppModel.isTooDark(AppModel.dashboardColor(model.color(for: tracker), isCustom: tracker.colorHex != nil)) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption)
                                                .foregroundStyle(selectedID == tracker.id ? Color.white : Color.orange)
                                                .help("Color is too dark for the dashboard")
                                                .accessibilityLabel("Color is too dark for the dashboard")
                                        }
                                    }
                                    Text(model.calendars.first { $0.id == tracker.calendarID }?.label ?? "Calendar unavailable")
                                        .font(.caption).foregroundStyle(selectedID == tracker.id ? Color.white.opacity(0.8) : Color.secondary).lineLimit(2)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedID == tracker.id ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { go(.select(tracker.id)) }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(selectedID == tracker.id ? .isSelected : [])
                                .accessibilityAction { go(.select(tracker.id)) }
                            }
                            .reorderable()
                        }
                        .reorderContainer(for: Tracker.self, isEnabled: model.settingsWritable) { reorder($0) }
                        .padding(10)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .onMoveCommand { direction in
                        guard !model.trackers.isEmpty else { return }
                        let index = model.trackers.firstIndex { $0.id == selectedID } ?? 0
                        if direction == .up { go(.select(model.trackers[max(0, index - 1)].id)) }
                        else if direction == .down { go(.select(model.trackers[min(model.trackers.count - 1, index + 1)].id)) }
                    }
                    .onChange(of: selectedID) { if selectedID != nil { adding = false } }
                    .confirmationDialog("Discard unsaved changes?", isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }), titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) {
                            if let pendingMove { apply(pendingMove) }
                            pendingMove = nil
                        }
                        Button("Cancel", role: .cancel) { pendingMove = nil }
                    }
                    Divider()
                    HStack {
                        Button { go(.add) } label: { Image(systemName: "plus").frame(height: 16) }
                        .help("Add Tracker")
                        .accessibilityLabel("Add Tracker")
                        .disabled(model.access != .allowed || !model.settingsWritable)
                        Button(role: .destructive) { removal = selectedTracker } label: { Image(systemName: "minus").frame(height: 16) }
                            .help("Remove Tracker")
                            .accessibilityLabel("Remove Tracker")
                            .disabled(selectedTracker == nil || !model.settingsWritable)
                        Spacer()
                    }
                    .padding(12)
                }
                .frame(width: 210)
                Divider()
                if adding || selectedTracker != nil {
                    TrackerEditor(model: model, existing: adding ? nil : selectedTracker, hasChanges: $editorHasChanges, onSave: { tracker in
                        selectedID = tracker.id
                        adding = false
                        editorGeneration = UUID()
                    }, onCancel: {
                        adding = false
                        if selectedID == nil { selectedID = model.selectedTrackerID ?? model.trackers.first?.id }
                        editorGeneration = UUID()
                    })
                    .id("\(selectedID?.uuidString ?? "new")-\(editorGeneration)")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Trackers").font(.title2.bold())
                        Text(model.trackers.isEmpty ? "Use + to add a tracker." : "Select a tracker to edit it.")
                            .foregroundStyle(.secondary)
                        if model.access != .allowed {
                            Button(model.access == .needsPermission ? "Allow Calendar Access" : "Open System Settings") {
                                if model.access == .needsPermission { model.refresh(requestPermission: true) }
                                else { model.openCalendarSettings() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                if let problem = model.loadProblem {
                    Text(model.settingsError ?? problem).font(.caption).foregroundStyle(.red).lineLimit(2)
                    Button("Show File") { model.showSettingsFile() }
                    Button("Replace File") { model.replaceUnreadableSettings() }
                        .help("Keeps a copy of the old file")
                } else if let error = model.settingsError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                Button { showingSync.toggle() } label: {
                    HStack(spacing: 6) {
                        if windowVisible && model.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: needsAttention ? "exclamationmark.triangle" : "arrow.clockwise")
                        }
                        Text(model.isLoading ? "Syncing…" : needsAttention ? "Sync needs attention" : "Sync")
                    }
                }
                .popover(isPresented: $showingSync, arrowEdge: .bottom) { syncDetails }
                .help("Calendar refresh status")
            }
            .padding(12)
        }
        .frame(width: 760, height: 550)
        .background(SettingsWindowVisibility { windowVisible = $0; model.setSettingsVisible($0) })
        .onAppear {
            selectedID = model.selectedTrackerID ?? model.trackers.first?.id
            windowVisible = true
        }
        .onDisappear { windowVisible = false; model.setSettingsVisible(false); showingSync = false }
        .onChange(of: model.trackers) {
            if let selectedID, !model.trackers.contains(where: { $0.id == selectedID }) {
                self.selectedID = model.trackers.first?.id
            }
        }
        .confirmationDialog("Remove \(removal?.name ?? "tracker")?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            Button("Remove Tracker", role: .destructive) {
                if let removal { model.removeTracker(removal.id) }
                removal = nil
            }
        } message: {
            Text("This removes the tracker settings. Calendar events stay in Calendar.")
        }
    }

    private func go(_ move: Move) {
        if case .select(let id) = move, id == selectedID, !adding { return }
        if editorHasChanges { pendingMove = move } else { apply(move) }
    }

    private func apply(_ move: Move) {
        switch move {
        case .select(let id):
            selectedID = id
            adding = false
        case .add:
            selectedID = nil
            adding = true
        }
        editorGeneration = UUID()
    }

    private func reorder(_ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>) {
        let sources = IndexSet(difference.sources.compactMap { id in model.trackers.firstIndex { $0.id == id } })
        let destination: Int
        switch difference.destination.position {
        case .before(let id): destination = model.trackers.firstIndex { $0.id == id } ?? model.trackers.count
        case .end: destination = model.trackers.count
        }
        model.moveTrackers(from: sources, to: destination)
    }

    private var syncDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sync status").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Label("Calendar", systemImage: "calendar")
                Text(calendarStatus).font(.caption).foregroundStyle(.secondary)
                if let refreshed = model.lastSuccessfulRefresh {
                    Text("Last successful refresh: \(refreshed.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Sync Now") { model.refresh(requestPermission: true) }
                    .disabled(model.isLoading)
            }
        }
        .padding(18)
        .frame(width: 330)
    }

    private var calendarStatus: String {
        if model.isLoading { return "Reading Calendar…" }
        if let error = model.refreshError { return error }
        if model.calendarMissing { return "The selected calendar is unavailable." }
        switch model.access {
        case .needsPermission: return "Calendar permission is needed."
        case .denied: return "Allow full Calendar access in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .allowed: return model.lastSuccessfulRefresh == nil ? "Not refreshed yet" : "Up to date"
        }
    }
}

private struct SettingsWindowVisibility: NSViewRepresentable {
    let update: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView { VisibilityView(update: update) }
    func updateNSView(_ nsView: VisibilityView, context: Context) {}

    final class VisibilityView: NSView {
        let update: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(update: @escaping (Bool) -> Void) {
            self.update = update
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { update(false); return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] notification in
                    let visible = notification.name != NSWindow.willCloseNotification && window?.occlusionState.contains(.visible) == true
                    self?.update(visible)
                })
            }
            DispatchQueue.main.async { [weak self, weak window] in self?.update(window?.occlusionState.contains(.visible) == true) }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
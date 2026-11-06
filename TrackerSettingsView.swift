import AppKit
import SwiftUI

struct TrackerSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var editorGeneration = UUID()
    @State private var removal: Tracker?
    @State private var showingSync = false
    @State private var windowVisible = false
    @State private var draggedID: UUID?
    @State private var dropTargetID: UUID?

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
                                .background(selectedID == tracker.id ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture { selectedID = tracker.id }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(selectedID == tracker.id ? .isSelected : [])
                                .onDrag {
                                    guard model.settingsWritable else { return NSItemProvider() }
                                    draggedID = tracker.id
                                    return NSItemProvider(object: tracker.id.uuidString as NSString)
                                } preview: {
                                    Text(tracker.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(width: 150, alignment: .leading)
                                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                        .opacity(0.65)
                                }
                                .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: false, allowMove: true), operationsOutsideApp: .init(allowCopy: false)))
                                .onDragSessionUpdated { session in
                                    if case .ended = session.phase, draggedID == tracker.id {
                                        draggedID = nil
                                        dropTargetID = nil
                                    }
                                }
                                .opacity(draggedID == tracker.id ? 0.3 : 1)
                                .overlay {
                                    if draggedID != nil {
                                        TrackerDropTarget(trackerID: tracker.id, model: model, draggedID: $draggedID, dropTargetID: $dropTargetID)
                                    }
                                }
                                .overlay(alignment: dropAlignment(for: tracker.id)) {
                                    if dropTargetID == tracker.id {
                                        Rectangle().fill(Color.accentColor).frame(height: 2)
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .onMoveCommand { direction in
                        guard !model.trackers.isEmpty else { return }
                        let index = model.trackers.firstIndex { $0.id == selectedID } ?? 0
                        if direction == .up { selectedID = model.trackers[max(0, index - 1)].id }
                        else if direction == .down { selectedID = model.trackers[min(model.trackers.count - 1, index + 1)].id }
                    }
                    .onChange(of: selectedID) { if selectedID != nil { adding = false } }
                    Divider()
                    HStack {
                        Button {
                            selectedID = nil
                            adding = true
                            editorGeneration = UUID()
                        } label: { Image(systemName: "plus").frame(height: 16) }
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
                    TrackerEditor(model: model, existing: adding ? nil : selectedTracker, onSave: { tracker in
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
                if let error = model.settingsError {
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
        .onDisappear { windowVisible = false; model.setSettingsVisible(false); showingSync = false; draggedID = nil; dropTargetID = nil }
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

    private func dropAlignment(for id: UUID) -> Alignment {
        guard let source = model.trackers.firstIndex(where: { $0.id == draggedID }),
              let target = model.trackers.firstIndex(where: { $0.id == id }) else { return .top }
        return source < target ? .bottom : .top
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

private struct TrackerDropTarget: NSViewRepresentable {
    let trackerID: UUID
    let model: AppModel
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes([.string])
        configure(view)
        return view
    }

    func updateNSView(_ view: DropView, context: Context) { configure(view) }

    private func configure(_ view: DropView) {
        view.accepts = { info in
            guard model.settingsWritable, let draggedID, draggedID != trackerID,
                  model.trackers.contains(where: { $0.id == draggedID }) else { return false }
            return info.draggingPasteboard.string(forType: .string) == draggedID.uuidString
        }
        view.enter = {
            if dropTargetID != trackerID { dropTargetID = trackerID }
        }
        view.leave = {
            if dropTargetID == trackerID { dropTargetID = nil }
        }
        view.drop = {
            defer { draggedID = nil; dropTargetID = nil }
            guard model.settingsWritable,
                  let source = model.trackers.firstIndex(where: { $0.id == draggedID }),
                  let target = model.trackers.firstIndex(where: { $0.id == trackerID }),
                  source != target else { return false }
            model.moveTrackers(from: IndexSet(integer: source), to: source < target ? target + 1 : target)
            return true
        }
    }

    final class DropView: NSView {
        var accepts: (any NSDraggingInfo) -> Bool = { _ in false }
        var enter: () -> Void = {}
        var leave: () -> Void = {}
        var drop: () -> Bool = { false }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard accepts(sender) else { return [] }
            enter()
            return .move
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            draggingEntered(sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { leave() }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            sender.animatesToDestination = false
            return accepts(sender)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard accepts(sender) else { return false }
            return drop()
        }

        override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { leave() }
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

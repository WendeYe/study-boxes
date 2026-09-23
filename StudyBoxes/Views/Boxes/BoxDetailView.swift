import AppKit
import SwiftData
import SwiftUI

struct BoxDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState
    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var allBoxes: [StudyBox]
    @State private var isEditing = false
    @State private var confirmsDelete = false
    @State private var layoutMessage: String?
    @State private var showingAccessibilityHelp = false
    @ObservedObject private var license = LicenseManager.shared

    let box: StudyBox

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                resumeCards
                TaskListView(box: box)
                ResourceListView(box: box)
                sessionHistorySection
                settingsDisclosure
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        // MARK: Navigation
        .navigationTitle(box.name)
        .navigationSubtitle(navigationSubtitle)

        // MARK: Toolbar
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    startSession()
                } label: {
                    Label("Start Session", systemImage: "play.circle.fill")
                }
                .help("Open the study setup, start the timer, and show your task list.")

                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Change this Study Box's name, dates, appearance, and session options.")

                Menu {
                    Button {
                        captureLayout()
                    } label: {
                        Label("Capture Window Layout", systemImage: "rectangle.3.group")
                    }
                    .help("Save the currently visible windows for this Study Box.")

                    Button {
                        box.isPinnedToMenuBar.toggle()
                        save()
                    } label: {
                        Label(box.isPinnedToMenuBar ? "Unpin from Menu Bar" : "Pin to Menu Bar", systemImage: "pin")
                    }
                    .help("Keep this Study Box near the top of the menu bar menu.")

                    Button {
                        exportThisBox()
                    } label: {
                        Label("Export Study Box...", systemImage: "square.and.arrow.up")
                    }
                    .help("Export only this Study Box to a JSON backup.")

                    Divider()

                    Button {
                        box.archive()
                        save()
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .help("Hide this Study Box from active lists without deleting it.")

                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Delete Study Box...", systemImage: "trash")
                    }
                    .help("Permanently remove this Study Box from this Mac.")
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
                .help("Capture layout, export, archive, or delete this Study Box.")
            }
        }

        // MARK: Sheets & dialogs
        .sheet(isPresented: $isEditing) {
            BoxEditorView(box: box)
                .frame(minWidth: 460)
        }
        .sheet(isPresented: $showingAccessibilityHelp) {
            AccessibilityOnboardingView()
                .frame(minWidth: 520, minHeight: 360)
        }
        .confirmationDialog(
            "Delete \"\(box.name)\"?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(box)
                save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the Study Box, including its tasks, resources, and session history, from this Mac. This cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let layoutMessage {
                Text(layoutMessage)
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: layoutMessage != nil)
        .onChange(of: layoutMessage) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                layoutMessage = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: box.colorHex).opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: box.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: box.colorHex))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(box.name)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(box.type.title, systemImage: "folder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let courseName = box.courseName, !courseName.isEmpty {
                        Text("-")
                            .foregroundStyle(.tertiary)
                        Text(courseName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let examDate = box.examDate {
                        Text("-")
                            .foregroundStyle(.tertiary)
                        Label(examDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Resume cards

    private var resumeCards: some View {
        let snapshot = StudyResumeService.snapshot(for: box, sessions: box.sessions)
        let progress = StudyProgressService.summary(for: box)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Continue")
                .font(.title3.weight(.semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    resumeCard(
                        title: "Next task",
                        value: snapshot?.nextTaskTitle ?? "No pending tasks.",
                        systemImage: "checklist"
                    )
                    resumeCard(
                        title: "Recent notes",
                        value: snapshot?.notesPreview ?? "Notes from your last session appear here.",
                        systemImage: "note.text"
                    )
                    resumeCard(
                        title: "This week",
                        value: DurationFormatter.minutes(progress.weekMinutes),
                        systemImage: "calendar"
                    )
                }
                VStack(alignment: .leading, spacing: 10) {
                    resumeCard(
                        title: "Next task",
                        value: snapshot?.nextTaskTitle ?? "No pending tasks.",
                        systemImage: "checklist"
                    )
                    resumeCard(
                        title: "Recent notes",
                        value: snapshot?.notesPreview ?? "Notes from your last session appear here.",
                        systemImage: "note.text"
                    )
                    resumeCard(
                        title: "This week",
                        value: DurationFormatter.minutes(progress.weekMinutes),
                        systemImage: "calendar"
                    )
                }
            }
        }
    }

    private func resumeCard(title: String, value: String, systemImage: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        }
    }

    // MARK: Settings disclosure

    private var settingsDisclosure: some View {
        DisclosureGroup {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                detailRow("Tasks", "\(box.tasks.count)")
                detailRow("Resources", "\(box.resources.count)")
                detailRow("Sessions", "\(box.sessions.count)")
                detailRow("Saved windows", "\(box.windowLayouts.count)")
                detailRow("Default session", DurationFormatter.minutes(box.defaultSessionMinutes))
                detailRow("Open resources on start", box.openResourcesOnSessionStart ? "On" : "Off")
                detailRow("Focus Mode", box.focusMode.title)
                detailRow("Restore saved layout", box.restoreWindowLayoutOnSessionStart ? "On" : "Off")
                detailRow("Keep display awake", (box.keepDisplayAwakeDuringSessions ?? true) ? "On" : "Off")
                detailRow("Created", box.createdAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("Updated", box.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .padding(.top, 8)
        } label: {
            Text("Box details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .gridColumnAlignment(.leading)
        }
    }

    @ViewBuilder
    private var sessionHistorySection: some View {
        if license.plan.isPro {
            SessionHistoryView(box: box)
        } else {
            GroupBox {
                HStack(alignment: .top, spacing: 10) {
                    ProBadge()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session history and advanced stats are included with Pro.")
                            .font(.headline)
                        Text("Free keeps the current session timer and recent summary for one Study Box.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("License") {
                        presentLicense(EntitlementRules.canUse(.advancedStats, plan: .free).message)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: Computed helpers

    private var navigationSubtitle: String {
        if let courseName = box.courseName, !courseName.isEmpty {
            return "\(box.type.title) - \(courseName)"
        }
        return box.type.title
    }

    // MARK: Actions

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save StudyBox changes: \(error)")
        }
    }

    private func startSession() {
        let decision = EntitlementRules.canStartSession(totalBoxCount: allBoxes.count, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }
        appState.startSession(boxID: box.id)
    }

    private func captureLayout() {
        let decision = EntitlementRules.canUse(.windowLayoutManagement, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }

        guard PermissionManager.isAccessibilityTrusted else {
            showingAccessibilityHelp = true
            return
        }
        do {
            let count = try WindowLayoutManager.captureLayout(for: box, modelContext: modelContext)
            layoutMessage = count == 1 ? "Captured 1 window." : "Captured \(count) windows."
        } catch {
            layoutMessage = "Study Boxes could not capture this layout."
        }
    }

    private func exportThisBox() {
        guard let url = FilePicker.chooseJSONExport(defaultName: "\(box.name) Study Box.json") else { return }
        do {
            try BackupService.export(boxes: [box], to: url)
            layoutMessage = "Exported \(box.name)."
        } catch {
            layoutMessage = "Study Boxes could not export this Study Box."
        }
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}

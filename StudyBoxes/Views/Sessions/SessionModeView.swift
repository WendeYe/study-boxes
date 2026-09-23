import AppKit
import SwiftData
import SwiftUI

struct SessionModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState
    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var allBoxes: [StudyBox]

    let box: StudyBox
    let session: StudySession
    let launchResults: [ResourceLaunchResult]
    var onNotesChanged: (String) -> Void = { _ in }

    @State private var notes = ""
    @State private var hasEnded = false
    @State private var isAddingTask = false
    @State private var isAddingResource = false
    @State private var showsSessionDetails = false
    @State private var showsNotes = false
    @ObservedObject private var license = LicenseManager.shared

    private var activeTasks: [StudyTask] {
        TaskManager.sorted(box.tasks.filter { $0.status != .done })
    }

    private var accentColor: Color {
        StudyBoxAccentPalette.color(for: box)
    }

    // MARK: Body

    var body: some View {
        Group {
            if hasEnded {
                SessionSummaryView(
                    box: box,
                    session: session,
                    onStartAnother: {
                        appState.endSession()
                        startAnotherSession()
                    },
                    onBackToDashboard: {
                        appState.endSession()
                    }
                )
            } else {
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    sessionContent(elapsed: context.date.timeIntervalSince(session.startedAt))
                }
            }
        }
        .onAppear { notes = session.notes ?? "" }
        .onChange(of: notes) {
            session.notes = notes
            onNotesChanged(notes)
        }
        .sheet(isPresented: $isAddingTask) {
            TaskEditorView(box: box)
                .frame(minWidth: 520, minHeight: 620)
        }
        .sheet(isPresented: $isAddingResource) {
            AddResourceView(box: box)
                .frame(minWidth: 520, minHeight: 520)
        }
    }

    // MARK: Session content

    @ViewBuilder
    private func sessionContent(elapsed: TimeInterval) -> some View {
        let sortedActiveTasks = activeTasks

        VStack(alignment: .leading, spacing: 12) {
            focusHUDHeader(elapsed: elapsed)
            currentTaskCard(activeTasks: sortedActiveTasks)
            wellnessPromptBanner

            DisclosureGroup("Details", isExpanded: $showsSessionDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    upNextPanel(activeTasks: sortedActiveTasks)
                    workspaceStatusPanel
                }
                .padding(.top, 6)
            }
            .font(.subheadline.weight(.medium))

            DisclosureGroup("Notes", isExpanded: $showsNotes) {
                notesEditor
                    .frame(height: 96)
                    .padding(.top, 6)
            }
            .font(.subheadline.weight(.medium))

            primaryHUDControls
        }
        .padding(18)
        .frame(
            minWidth: StudySpacePresentation.minimumWidth,
            idealWidth: StudySpacePresentation.defaultWidth,
            maxWidth: StudySpacePresentation.maximumWidth,
            minHeight: StudySpacePresentation.minimumHeight,
            alignment: .topLeading
        )
        .background(.regularMaterial)
        .symbolRenderingMode(.hierarchical)
    }

    // MARK: Focus HUD

    private func focusHUDHeader(elapsed: TimeInterval) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Focus session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)

                Text(box.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 10) {
                    Text("Planned \(DurationFormatter.minutes(session.plannedMinutes))")
                    focusStatusLabels
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 1) {
                Text(DurationFormatter.clock(elapsed))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(elapsed > Double(session.plannedMinutes * 60) ? .orange : .primary)
                    .frame(width: 124, alignment: .trailing)

                Text("elapsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accentColor.opacity(0.18))
        }
    }

    private func currentTaskCard(activeTasks: [StudyTask]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current task")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            if let task = activeTasks.first {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.headline)
                            .lineLimit(2)

                        taskMetadata(task)

                        if let details = task.details, !details.isEmpty {
                            Text(details)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    taskActions(for: task)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                Label("No tasks left", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accentColor.opacity(0.22))
        }
    }

    @ViewBuilder
    private var wellnessPromptBanner: some View {
        if let prompt = WellnessReminderService.prompt(for: session) {
            VStack(alignment: .leading, spacing: 10) {
                Label(prompt.title, systemImage: "figure.mind.and.body")
                    .font(.headline)
                Text(prompt.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Take Break") { clearWellnessPrompt() }
                    Button("Posture Check") { clearWellnessPrompt() }
                    Button("Skip") { clearWellnessPrompt() }
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.green.opacity(0.24))
            }
        }
    }

    @ViewBuilder
    private func upNextPanel(activeTasks: [StudyTask]) -> some View {
        let upcomingTasks = Array(activeTasks.dropFirst().prefix(StudySpacePresentation.visibleUpcomingTaskLimit))

        if !upcomingTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Up next")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(upcomingTasks) { task in
                        UpcomingSessionTaskRow(
                            task: task,
                            onDone: { markDone(task) },
                            onSkip: { markSkipped(task) }
                        )
                        if task.id != upcomingTasks.last?.id { Divider() }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65))
                }
            }
        }
    }

    private var primaryHUDControls: some View {
        HStack(spacing: 10) {
            Button {
                openStudySetup()
            } label: {
                Label("Setup", systemImage: "arrow.up.forward.app")
            }
            .controlSize(.small)
            .help("Open the resources for this Study Box.")

            Button {
                attemptAddResource()
            } label: {
                Label("Resource", systemImage: "folder.badge.plus")
            }
            .controlSize(.small)
            .help("Add a resource without ending the session.")

            Button {
                isAddingTask = true
            } label: {
                Label("Task", systemImage: "plus")
            }
            .controlSize(.small)
            .help("Add a task without ending the session.")

            Spacer()

            endSessionButton
        }
    }

    private var workspaceStatusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("\(enabledLaunchableResourceCount) setup items", systemImage: "folder")
                launchStatusLabel
                Spacer()
            }
            .font(.caption)

            if let summary = appState.activeWindowRestoreSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(appState.activeStartupIssueMessages.prefix(3), id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Study Boxes can restore browser windows, but it never reads or restores individual tabs.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var launchStatusLabel: some View {
        if launchResults.contains(where: { $0.status == .failed }) {
            Label("Setup needs attention", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if !launchResults.isEmpty {
            Label("Setup opened", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var hudFooter: some View {
        HStack {
            Button {
                isAddingTask = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .controlSize(.small)

            Spacer()

            endSessionButton
        }
    }

    private var enabledLaunchableResourceCount: Int {
        box.resources.filter { $0.enabledByDefault && $0.type.isLaunchable }.count
    }

    private func taskMetadata(_ task: StudyTask) -> some View {
        HStack(spacing: 8) {
            Text(task.type.title)
            if let estimatedMinutes = task.estimatedMinutes {
                Text("\(estimatedMinutes) min")
            }
            if let unit = task.unit {
                Text(unit)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func taskActions(for task: StudyTask) -> some View {
        HStack(spacing: 6) {
            Button("Skip") {
                markSkipped(task)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .help("Leave this task for later.")

            Button {
                markDone(task)
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .controlSize(.small)
            .help("Mark this task as done.")
        }
    }

    private func markDone(_ task: StudyTask) {
        if let prompt = SessionManager.markTaskDone(task, in: session, modelContext: modelContext) {
            Task {
                await NotificationService.notifyWellnessPromptIfNeeded(prompt, appIsActive: NSApp.isActive)
            }
        }
    }

    private func markSkipped(_ task: StudyTask) {
        SessionManager.markTaskSkipped(task, in: session, modelContext: modelContext)
    }

    private func openStudySetup() {
        let results = ResourceLauncher.shared.openEnabledResources(for: box)
        appState.updateLaunchResults(results)
    }

    private func attemptAddResource() {
        let decision = EntitlementRules.canAddResource(currentResourceCount: box.resources.count, plan: license.plan)
        guard decision.isAllowed else {
            appState.presentLicense(reason: decision.message)
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        isAddingResource = true
    }

    private func clearWellnessPrompt() {
        SessionManager.clearWellnessPrompt(in: session, modelContext: modelContext)
    }

    private func startAnotherSession() {
        let decision = EntitlementRules.canStartSession(totalBoxCount: allBoxes.count, plan: license.plan)
        guard decision.isAllowed else {
            appState.presentLicense(reason: decision.message)
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        appState.startSession(boxID: box.id)
    }

    @ViewBuilder
    private var focusStatusLabels: some View {
        if appState.isHidingDistractionsActive {
            Label("Apps hidden", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if appState.isFocusEnforcementActive {
            Button("Pause Strict Focus") {
                appState.pauseFocusEnforcement()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Stop blocking newly launched apps for this session.")
        }
    }

    // MARK: Notes editor

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)

            if notes.isEmpty {
                Text("Notes for this session...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65))
        }
    }

    // MARK: End session button

    private var endSessionButton: some View {
        Button {
            Task {
                let restoreReport = await SessionManager.endSessionAndRestore(
                    session,
                    notes: notes,
                    modelContext: modelContext
                )
                hasEnded = true
                appState.completeExplicitSessionEnd(restoreSummary: restoreReport?.displaySummary)
                await notifyIfNeeded(restoreReport)
            }
        } label: {
            Label("End Session", systemImage: "stop.circle")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .help("Save notes, end the session, and restore affected apps.")
    }

    // MARK: Helpers

    private func launchResultIcon(_ status: ResourceLaunchStatus) -> String {
        switch status {
        case .success: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .skipped: "minus.circle"
        }
    }

    private func launchResultColor(_ status: ResourceLaunchStatus) -> Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .skipped: .secondary
        }
    }

    private func notifyIfNeeded(_ report: SessionRestoreReport?) async {
        guard let report, let summary = report.displaySummary else { return }
        await NotificationService.notifySessionRestoreIfNeeded(
            summary: summary,
            hasIssues: !report.messages.isEmpty,
            appIsActive: NSApp.isActive
        )
    }
}

private struct UpcomingSessionTaskRow: View {
    let task: StudyTask
    let onDone: () -> Void
    let onSkip: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(task.type.title)
                    if let estimatedMinutes = task.estimatedMinutes {
                        Text("\(estimatedMinutes) min")
                    }
                    if let unit = task.unit {
                        Text(unit)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Skip", action: onSkip)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)

            Button {
                onDone()
            } label: {
                Label("Done", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

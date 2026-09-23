import AppKit
import SwiftData
import SwiftUI

struct MenuBarRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var boxes: [StudyBox]

    @Query(sort: \StudySession.startedAt, order: .reverse)
    private var sessions: [StudySession]

    @Query(sort: \SessionRestoreSnapshot.createdAt, order: .reverse)
    private var restoreSnapshots: [SessionRestoreSnapshot]

    @State private var isAddingSessionTask = false
    @State private var isAddingSessionResource = false
    @State private var pendingPreflightBox: StudyBox?
    @State private var menuLaunchMessage: String?
    @ObservedObject private var license = LicenseManager.shared

    private var activeBoxes: [StudyBox] {
        boxes.filter { !$0.isArchived }
    }

    private var pinnedBoxes: [StudyBox] {
        Array(activeBoxes.filter(\.isPinnedToMenuBar).prefix(3))
    }

    private var recentBoxes: [StudyBox] {
        let excluded = Set(pinnedBoxes.map(\.id) + [resumeBox?.id].compactMap { $0 })
        return Array(activeBoxes.filter { !excluded.contains($0.id) }.prefix(3))
    }

    private var pendingRestoreSnapshots: [SessionRestoreSnapshot] {
        restoreSnapshots.filter(\.hasPendingRestore)
    }

    private var activeSession: StudySession? {
        guard let activeSessionID = appState.activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    private var activeSessionTasks: [StudyTask] {
        guard let activeSession, let box = activeSession.box else { return [] }
        return TaskManager.sorted(box.tasks.filter { $0.status != .done })
    }

    private var activeAccentHex: String {
        StudySessionHUDPresentation.tintHex(
            for: .studyContext,
            boxAccentHex: activeSession?.box?.colorHex
        )
    }

    private var activeAccentColor: Color {
        Color(hex: activeAccentHex)
    }

    private var completionTintColor: Color {
        Color(hex: StudySessionHUDPresentation.tintHex(for: .completion, boxAccentHex: activeAccentHex))
    }

    private var restoreTintColor: Color {
        Color(hex: StudySessionHUDPresentation.tintHex(for: .restore, boxAccentHex: activeAccentHex))
    }

    private var destructiveTintColor: Color {
        Color(hex: StudySessionHUDPresentation.tintHex(for: .destructive, boxAccentHex: activeAccentHex))
    }

    private var resumeBox: StudyBox? {
        StudyResumeService.mostRecentlyStudiedBox(from: activeBoxes, sessions: sessions)
    }

    var body: some View {
        panelContent
            .frame(width: 370)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
            }
            .symbolRenderingMode(.hierarchical)
        .sheet(isPresented: $isAddingSessionTask) {
            if let box = activeSession?.box {
                TaskEditorView(box: box)
                    .frame(minWidth: 520, minHeight: 620)
            } else {
                ContentUnavailableView("No active session", systemImage: "timer")
                    .frame(minWidth: 360, minHeight: 220)
            }
        }
        .sheet(isPresented: $isAddingSessionResource) {
            if let box = activeSession?.box {
                AddResourceView(box: box)
                    .frame(minWidth: 520, minHeight: 520)
            } else {
                ContentUnavailableView("No active Study Box", systemImage: "folder.badge.plus")
                    .frame(minWidth: 360, minHeight: 220)
            }
        }
        .sheet(item: $pendingPreflightBox) { box in
            FocusPreflightView(
                box: box,
                focusMode: box.focusMode,
                onContinue: {
                    beginMenuSession(for: box)
                },
                onCancel: {
                    pendingPreflightBox = nil
                }
            )
            .frame(minWidth: 440, minHeight: 360)
        }
        .onAppear {
            SessionRestoreManager.cleanupOldCompletedSnapshots(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if let startedAt = appState.activeSessionStartedAt {
            activeSessionPanel(startedAt: startedAt)
        } else {
            idlePanel
        }
    }

    @ViewBuilder
    private func activeSessionPanel(startedAt: Date) -> some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                activeHeader(elapsed: context.date.timeIntervalSince(startedAt))

                wellnessPromptPanel
                currentTaskPanel
                upcomingTasksPanel
                activeActionGrid

                if appState.activeFocusMode == .strictFocus, appState.isFocusEnforcementActive {
                    Button {
                        appState.pauseFocusEnforcement()
                        menuLaunchMessage = "Strict Focus is paused"
                    } label: {
                        Label("Pause Strict Focus", systemImage: "lock.open")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let snapshot = pendingRestoreSnapshots.first, snapshot.hasPendingRestore {
                    pendingRestoreRow(snapshot)
                }

                if let menuLaunchMessage, shouldShowStatusMessage(menuLaunchMessage) {
                    statusRow(menuLaunchMessage, systemImage: "info.circle")
                }

                Divider()
                activeFooterControls
            }
        }
    }

    private func activeHeader(elapsed: TimeInterval) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Focus session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activeAccentColor)
                    .textCase(.uppercase)

                Text(appState.activeSessionBoxName ?? activeSession?.box?.name ?? "Study Box")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    if let activeSession {
                        Text("Planned \(DurationFormatter.minutes(activeSession.plannedMinutes))")
                    }
                    Label(appState.activeFocusMode.title, systemImage: appState.activeFocusMode.systemImage)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 1) {
                Text(DurationFormatter.clock(elapsed))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(timerColor(elapsed: elapsed))
                    .frame(width: 102, alignment: .trailing)

                Text("elapsed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(activeAccentColor)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(activeAccentColor.opacity(0.14))
        }
    }

    @ViewBuilder
    private var activeActionGrid: some View {
        HStack(spacing: 8) {
            resourceActionControl

            Button {
                isAddingSessionTask = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }

            Button {
                showFocusHUD()
            } label: {
                Label("Open Window", systemImage: "rectangle.inset.filled")
            }

            moreMenu
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)

        Button(role: .destructive) {
            guard let activeSession else { return }
            endSession(activeSession)
        } label: {
            Label("End Session", systemImage: "stop.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(destructiveTintColor)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            if appState.activeFocusMode == .hideApps, appState.isHidingDistractionsActive {
                Button("Show Hidden Apps") {
                    DistractionManager.shared.restoreHiddenApps()
                    appState.isHidingDistractionsActive = false
                    menuLaunchMessage = "Hidden apps shown"
                }
            }

            Button("Quit Study Boxes") {
                NSApp.terminate(nil)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var resourceActionControl: some View {
        if let box = activeSession?.box {
            let resources = launchableResources(for: box)
            let label = MenuResourceActionPresentation.primaryLabel(launchableResourceCount: resources.count)

            if resources.isEmpty {
                Button {
                    attemptAddResource(for: box)
                } label: {
                    Label(label.title, systemImage: label.systemImage)
                }
            } else {
                Menu {
                    if MenuResourceActionPresentation.showsAddResourceMenuItem(launchableResourceCount: resources.count) {
                        Button {
                            attemptAddResource(for: box)
                        } label: {
                            Label("Add Resource", systemImage: "folder.badge.plus")
                        }

                        Divider()
                    }

                    Button("Open All") {
                        openStudySetup(for: box)
                    }

                    Divider()

                    ForEach(resources.prefix(8)) { resource in
                        Button(resource.title) {
                            openMenuResource(resource)
                        }
                    }
                } label: {
                    Label(label.title, systemImage: label.systemImage)
                }
            }
        }
    }

    @ViewBuilder
    private var idlePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Study Boxes")
                    .font(.headline.weight(.semibold))
                Text("Start a saved Study Box from the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let summary = appState.lastSessionRestoreSummary {
                statusRow(summary, systemImage: "checkmark.circle")
            }

            if let resumeBox {
                Button {
                    startFromMenu(resumeBox)
                } label: {
                    Label("Start \(resumeBox.name)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if activeBoxes.isEmpty {
                ContentUnavailableView(
                    "No Study Boxes",
                    systemImage: "books.vertical",
                    description: Text("Open the Library to create your first Study Box.")
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            }

            if !pinnedBoxes.isEmpty {
                boxSection("Pinned", boxes: pinnedBoxes)
            }

            if !recentBoxes.isEmpty {
                boxSection("Recent", boxes: recentBoxes)
            }

            if let snapshot = pendingRestoreSnapshots.first {
                Button {
                    restoreSnapshot(snapshot)
                } label: {
                    Label("Restore Previous Apps...", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Divider()
            idleFooterControls

            if let menuLaunchMessage {
                statusRow(menuLaunchMessage, systemImage: "info.circle")
            }
        }
    }

    private func boxSection(_ title: String, boxes: [StudyBox]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 6) {
                ForEach(boxes) { box in
                    MenuBarStudyBoxRow(
                        box: box,
                        onStart: {
                            startFromMenu(box)
                        },
                        onTogglePin: {
                            toggleMenuPin(for: box)
                        }
                    )
                }
            }
        }
    }

    private var activeFooterControls: some View {
        HStack(spacing: 8) {
            Button {
                openLibrary()
            } label: {
                Label("Library", systemImage: "books.vertical")
            }

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var idleFooterControls: some View {
        HStack(spacing: 8) {
            Button {
                openLibrary()
            } label: {
                Label("Library", systemImage: "books.vertical")
            }

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func openLibrary(selecting box: StudyBox? = nil) {
        if let box {
            appState.openBox(box.id)
        }
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startFromMenu(_ box: StudyBox) {
        guard appState.activeSessionID == nil, !appState.isStartingSession else { return }

        let startDecision = EntitlementRules.canStartSession(totalBoxCount: boxes.count, plan: license.plan)
        guard startDecision.isAllowed else {
            presentLicense(startDecision.message)
            return
        }

        let focusMode = defaultSessionOptions(for: box).resolvedFocusMode
        if focusMode.requiresAccessibilityForRestore, !PermissionManager.isAccessibilityTrusted {
            PermissionManager.requestAccessibilityPermission()
            PermissionManager.openAccessibilitySettings()
            menuLaunchMessage = "\(focusMode.title) needs Accessibility before it can manage other apps."
            return
        }

        if (focusMode == .quitApps || focusMode == .strictFocus), !box.skipFocusQuitConfirmation {
            pendingPreflightBox = box
            return
        }

        beginMenuSession(for: box)
    }

    private func beginMenuSession(for box: StudyBox) {
        guard appState.activeSessionID == nil, !appState.isStartingSession else { return }

        appState.isStartingSession = true
        try? modelContext.save()

        let options = defaultSessionOptions(for: box)
        let session = SessionManager.startSession(for: box, options: options, modelContext: modelContext)
        appState.registerStartedSession(session, box: box, options: options, launchResults: [])
        appState.isSessionSetupPresented = false
        appState.isSessionModePresented = false
        pendingPreflightBox = nil
        menuLaunchMessage = nil
        closeLibraryAfterSessionStart()

        guard options.openResources ||
            options.hideDistractions ||
            options.quitDistractions ||
            options.enforceFocus ||
            options.restoreWindowLayout ||
            options.keepDisplayAwake else { return }

        Task {
            await Task.yield()
            guard appState.activeSessionID == session.id else { return }
            let report = await SessionManager.finishStartup(
                for: box,
                session: session,
                options: options,
                modelContext: modelContext
            )
            guard appState.activeSessionID == session.id else { return }
            appState.updateStartupReport(report)
            if report.hasIssues {
                menuLaunchMessage = report.issueMessages.first ?? "Started with issues"
            }
        }
    }

    private func endSession(_ session: StudySession) {
        Task {
            let restoreReport = await SessionManager.endSessionAndRestore(
                session,
                notes: session.notes,
                modelContext: modelContext
            )
            let restoreSummary = restoreReport?.displaySummary
            appState.completeExplicitSessionEnd(restoreSummary: restoreSummary)
            menuLaunchMessage = restoreSummary ?? "Session ended"
            await notifyIfNeeded(restoreReport)
        }
    }

    private func restoreSnapshot(_ snapshot: SessionRestoreSnapshot) {
        let decision = EntitlementRules.canUse(.windowLayoutManagement, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }

        Task {
            let report = await SessionRestoreManager.restore(snapshot: snapshot, modelContext: modelContext)
            appState.lastSessionRestoreSummary = report.displaySummary
            menuLaunchMessage = report.displaySummary
            await notifyIfNeeded(report)
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

    private func showFocusHUD() {
        guard AppWindowController.shouldOpenStudySpaceWindow(activeSessionID: appState.activeSessionID) else {
            AppWindowController.closeStudySpaceWindows()
            return
        }

        if !AppWindowController.activateStudySpaceIfOpen() {
            openWindow(id: "session")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closeLibraryAfterSessionStart() {
        Task { @MainActor in
            await Task.yield()
            AppWindowController.closeDashboardWindows()
        }
    }

    private func defaultSessionOptions(for box: StudyBox) -> SessionStartOptions {
        SessionStartOptions.defaults(for: box, plan: license.plan)
    }

    private func toggleMenuPin(for box: StudyBox) {
        box.isPinnedToMenuBar.toggle()
        box.touch()
        do {
            try modelContext.save()
            menuLaunchMessage = box.isPinnedToMenuBar
                ? "Pinned \(box.name) to the menu bar"
                : "Unpinned \(box.name)"
        } catch {
            menuLaunchMessage = "Could not update menu bar pins"
        }
    }

    private func openStudySetup(for box: StudyBox) {
        let results = ResourceLauncher.shared.openEnabledResources(for: box)
        menuLaunchMessage = results.contains { $0.status == .failed } ? "Some resources failed to open" : "Opened study setup"
    }

    private func attemptAddResource(for box: StudyBox) {
        let decision = EntitlementRules.canAddResource(currentResourceCount: box.resources.count, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }
        isAddingSessionResource = true
    }

    private func openMenuResource(_ resource: StudyResource) {
        if resource.type == .commandPlaceholder {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(resource.urlString, forType: .string)
            menuLaunchMessage = "Copied \(resource.title)"
            return
        }

        let result = ResourceLauncher.shared.open(resource)
        menuLaunchMessage = result.status == .failed ? result.message : "Opened \(resource.title)"
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
        menuLaunchMessage = reason
    }

    @ViewBuilder
    private var currentTaskPanel: some View {
        if let activeSession, let task = activeSessionTasks.first {
            VStack(alignment: .leading, spacing: 9) {
                Text("Current task")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(alignment: .center, spacing: 10) {
                    taskMetadata(task)
                    Spacer(minLength: 8)

                    Button {
                        SessionManager.markTaskSkipped(task, in: activeSession, modelContext: modelContext)
                        menuLaunchMessage = "Skipped current task"
                    } label: {
                        Label("Skip", systemImage: "forward.circle")
                    }

                    Button {
                        handleWellnessPrompt(SessionManager.markTaskDone(task, in: activeSession, modelContext: modelContext))
                        menuLaunchMessage = "Marked task done"
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(completionTintColor)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .panelCard(accented: true, accentColor: activeAccentColor)
        } else {
            Label("No tasks left", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelCard()
        }
    }

    @ViewBuilder
    private var upcomingTasksPanel: some View {
        let upcomingTasks = Array(activeSessionTasks.dropFirst().prefix(1))

        if let activeSession, !upcomingTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(upcomingTasks) { task in
                    MenuBarUpcomingTaskRow(
                        title: task.title,
                        onSkip: {
                            SessionManager.markTaskSkipped(task, in: activeSession, modelContext: modelContext)
                        },
                        onDone: {
                            handleWellnessPrompt(SessionManager.markTaskDone(task, in: activeSession, modelContext: modelContext))
                        }
                    )
                }
            }
            .panelCard()
        }
    }

    @ViewBuilder
    private var wellnessPromptPanel: some View {
        if let activeSession, let prompt = WellnessReminderService.prompt(for: activeSession) {
            VStack(alignment: .leading, spacing: 8) {
                Label(prompt.title, systemImage: "figure.mind.and.body")
                    .font(.headline)
                Text(prompt.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Take Break") { clearWellnessPrompt(activeSession) }
                    Button("Posture Check") { clearWellnessPrompt(activeSession) }
                    Button("Skip") { clearWellnessPrompt(activeSession) }
                }
                .controlSize(.small)
            }
            .panelCard(accented: true, accentColor: .green)
        }
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

    private func statusRow(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pendingRestoreRow(_ snapshot: SessionRestoreSnapshot) -> some View {
        HStack(spacing: 8) {
            Label("Previous apps are waiting to be restored.", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Restore") {
                restoreSnapshot(snapshot)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(restoreTintColor)
        }
        .padding(9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(restoreTintColor.opacity(0.18))
        }
    }

    private func shouldShowStatusMessage(_ message: String) -> Bool {
        MenuBarStatusMessagePolicy.shouldDisplay(message)
    }

    private func launchableResources(for box: StudyBox) -> [StudyResource] {
        box.resources
            .filter { $0.enabledByDefault && ($0.type.isLaunchable || $0.type == .commandPlaceholder) }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func timerColor(elapsed: TimeInterval) -> Color {
        guard let activeSession else { return .primary }
        return elapsed > Double(activeSession.plannedMinutes * 60) ? .orange : .primary
    }

    private func clearWellnessPrompt(_ session: StudySession) {
        SessionManager.clearWellnessPrompt(in: session, modelContext: modelContext)
        menuLaunchMessage = "Break reminder cleared"
    }

    private func handleWellnessPrompt(_ prompt: WellnessPrompt?) {
        guard let prompt else { return }
        Task {
            await NotificationService.notifyWellnessPromptIfNeeded(prompt, appIsActive: NSApp.isActive)
        }
    }
}

private extension View {
    func panelCard(accented: Bool = false, accentColor: Color = .accentColor) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) {
                if accented {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accented ? accentColor.opacity(0.2) : Color(nsColor: .separatorColor).opacity(0.65))
            }
    }
}

private struct MenuBarStudyBoxRow: View {
    let box: StudyBox
    let onStart: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onStart) {
                rowContent
            }
            .buttonStyle(.plain)

            Button(action: onTogglePin) {
                Image(systemName: box.isPinnedToMenuBar ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(box.isPinnedToMenuBar ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(box.isPinnedToMenuBar ? "Unpin from menu bar" : "Pin to menu bar")
            .accessibilityLabel(box.isPinnedToMenuBar ? "Unpin \(box.name) from menu bar" : "Pin \(box.name) to menu bar")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.secondary.opacity(0.11) : Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: box.colorHex).opacity(0.16))
                    .frame(width: 26, height: 26)
                Image(systemName: box.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: box.colorHex))
                    .symbolRenderingMode(.hierarchical)
            }

            Text(box.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 10)

            Text("\(box.defaultSessionMinutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuBarUpcomingTaskRow: View {
    let title: String
    let onSkip: () -> Void
    let onDone: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onSkip) {
                Image(systemName: "forward.circle")
            }
            .help("Skip")

            Button(action: onDone) {
                Image(systemName: "checkmark.circle")
            }
            .help("Done")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

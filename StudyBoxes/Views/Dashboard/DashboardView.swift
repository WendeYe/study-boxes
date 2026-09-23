import AppKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var boxes: [StudyBox]

    @Query(sort: \StudySession.startedAt, order: .reverse)
    private var sessions: [StudySession]

    @State private var selectedBoxID: UUID?
    @State private var launchResults: [ResourceLaunchResult] = []
    @State private var showingIntegrations = false
    @State private var notificationMessage: String?
    @State private var isShowingOnboarding = false
    @StateObject private var onboardingState = OnboardingState.shared
    @ObservedObject private var license = LicenseManager.shared

    private var activeBoxes: [StudyBox] {
        boxes.filter { !$0.isArchived }
    }

    private var selectedBox: StudyBox? {
        guard let selectedBoxID else { return nil }
        return activeBoxes.first { $0.id == selectedBoxID }
    }

    private var activeSession: StudySession? {
        guard let activeSessionID = appState.activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    // MARK: Body

    var body: some View {
        NavigationSplitView {
            BoxListView(
                selectedBoxID: $selectedBoxID,
                onCreateAndStart: { box in
                    startStudySession(for: box, options: defaultSessionOptions(for: box), opensFocusHUD: false)
                }
                )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let selectedBox {
                BoxDetailView(box: selectedBox)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if !activeBoxes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        dashboardOverview
                        activeBoxesOverview
                    }
                    .padding(28)
                    .frame(maxWidth: 1100, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Create your first Study Box",
                    systemImage: "books.vertical",
                    description: Text("Give each subject a home, then open the whole setup when it is time to study.")
                )
            }
        }
        .frame(minWidth: 820, minHeight: 560)

        // MARK: Toolbar
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Study Boxes settings.")
            }
        }

        // MARK: Lifecycle
        .onAppear {
            selectedBoxID = nil
            SessionRestoreManager.cleanupOldCompletedSnapshots(modelContext: modelContext)
            if onboardingState.hasCompletedOnboarding {
                isShowingOnboarding = false
                showMenuBarHintIfNeeded()
            } else if boxes.isEmpty {
                isShowingOnboarding = true
            } else {
                onboardingState.complete()
                showMenuBarHintIfNeeded()
            }
        }
        .onChange(of: activeBoxes.map(\.id)) {
            if selectedBoxID == nil { return }
            if let selectedBoxID, activeBoxes.contains(where: { $0.id == selectedBoxID }) { return }
            selectedBoxID = nil
        }
        .onReceive(appState.$activeBoxID.compactMap { $0 }) { boxID in
            selectedBoxID = boxID
        }
        .onReceive(appState.$activeSessionID) { activeSessionID in
            if activeSessionID == nil { launchResults = [] }
        }
        .onReceive(appState.$isIntegrationsPresented) { isPresented in
            if isPresented {
                showCalendarFeeds()
                if !license.plan.isPro {
                    appState.isIntegrationsPresented = false
                }
            }
        }
        .onChange(of: onboardingState.hasCompletedOnboarding) { _, hasCompletedOnboarding in
            if hasCompletedOnboarding {
                showMenuBarHintIfNeeded()
            }
        }

        // MARK: Sheets
        .sheet(isPresented: $appState.isSessionSetupPresented) {
            if let boxID = appState.activeBoxID,
               let box = boxes.first(where: { $0.id == boxID }) {
                SessionSetupView(box: box) { options in
                    startStudySession(for: box, options: options)
                }
            } else {
                ContentUnavailableView(
                    "Choose a Study Box",
                    systemImage: "books.vertical",
                    description: Text("Select a Study Box before you start a session.")
                )
                .frame(minWidth: 420, minHeight: 260)
            }
        }
        .sheet(isPresented: $showingIntegrations) {
            LMSIntegrationsView()
                .onDisappear { appState.isIntegrationsPresented = false }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView { box, startImmediately in
                guard startImmediately, let box else { return }
                startStudySession(for: box, options: defaultSessionOptions(for: box))
            }
            .environmentObject(appState)
        }

        // MARK: Toast
        .overlay(alignment: .bottom) {
            if let notificationMessage {
                Text(notificationMessage)
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: notificationMessage != nil)
    }

    // MARK: Dashboard overview

    private var dashboardOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            appErrorBanner
            sessionRestoreBanner
            activeSessionBanner
            progressOverview
        }
    }

    @ViewBuilder
    private var appErrorBanner: some View {
        if let message = appState.lastErrorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Dismiss") {
                    appState.lastErrorMessage = nil
                    UserDefaults.standard.removeObject(forKey: AppState.persistenceRecoveryMessageKey)
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.orange.opacity(0.25))
            }
        }
    }

    @ViewBuilder
    private var sessionRestoreBanner: some View {
        if let summary = appState.lastSessionRestoreSummary {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .foregroundStyle(.tint)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") {
                    appState.lastSessionRestoreSummary = nil
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tint.opacity(0.2))
            }
        }
    }

    // MARK: Active session banner

    @ViewBuilder
    private var activeSessionBanner: some View {
        if let activeSession, let box = activeSession.box {
            TimelineView(.periodic(from: activeSession.startedAt, by: 1)) { context in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        activeSessionIdentity(
                            box: box,
                            elapsed: context.date.timeIntervalSince(activeSession.startedAt)
                        )
                        Spacer(minLength: 16)
                        fullSessionActions(box: box, session: activeSession)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        activeSessionIdentity(
                            box: box,
                            elapsed: context.date.timeIntervalSince(activeSession.startedAt)
                        )
                        compactSessionActions(box: box, session: activeSession)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.tint.opacity(0.2))
                }
            }
        }
    }

    private func activeSessionIdentity(box: StudyBox, elapsed: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(box.name)
                    .font(.headline)
                    .lineLimit(1)
                if hasActiveFocusControls {
                    Text("Focus controls are on")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(DurationFormatter.clock(elapsed))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.tint)
                .fixedSize()
        }
    }

    private func fullSessionActions(box: StudyBox, session: StudySession) -> some View {
        HStack(spacing: 8) {
            Button(action: showFocusHUD) {
                Label("Show Study Space", systemImage: "rectangle.inset.filled")
            }

            Button {
                _ = ResourceLauncher.shared.openEnabledResources(for: box)
            } label: {
                Label("Open Setup", systemImage: "folder")
            }

            if hasActiveFocusControls {
                Button(action: stopFocusControls) {
                    Label("Stop Focus", systemImage: "pause.circle")
                }
            }

            Button(role: .destructive) {
                endSession(session)
            } label: {
                Label("End", systemImage: "stop.circle")
            }
        }
        .controlSize(.small)
    }

    private func compactSessionActions(box: StudyBox, session: StudySession) -> some View {
        HStack(spacing: 8) {
            Button(action: showFocusHUD) {
                Label("Study Space", systemImage: "rectangle.inset.filled")
            }

            Menu {
                Button {
                    _ = ResourceLauncher.shared.openEnabledResources(for: box)
                } label: {
                    Label("Open Study Setup", systemImage: "folder")
                }

                if hasActiveFocusControls {
                    Button(action: stopFocusControls) {
                        Label("Stop Focus Controls", systemImage: "pause.circle")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                endSession(session)
            } label: {
                Label("End Session", systemImage: "stop.circle")
            }
        }
        .controlSize(.small)
    }

    private var hasActiveFocusControls: Bool {
        appState.isHidingDistractionsActive || appState.isFocusEnforcementActive
    }

    private func stopFocusControls() {
        appState.pauseFocusEnforcement()
        DistractionManager.shared.restoreHiddenApps()
    }

    private func endSession(_ session: StudySession) {
        Task {
            let restoreReport = await SessionManager.endSessionAndRestore(
                session,
                notes: session.notes,
                modelContext: modelContext
            )
            appState.completeExplicitSessionEnd(restoreSummary: restoreReport?.displaySummary)
            await notifyIfNeeded(restoreReport)
        }
    }

    // MARK: Progress overview

    @ViewBuilder
    private var progressOverview: some View {
        let summaries = activeBoxes.map { StudyProgressService.summary(for: $0) }
        if summaries.contains(where: { $0.totalMinutes > 0 || $0.completedTasksThisWeek > 0 }) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { progressCards(summaries: summaries) }
                VStack(spacing: 10) { progressCards(summaries: summaries) }
            }
        }
    }

    @ViewBuilder
    private func progressCards(summaries: [StudyProgressSummary]) -> some View {
        progressCard(
            title: "This week",
            value: DurationFormatter.minutes(summaries.reduce(0) { $0 + $1.weekMinutes }),
            systemImage: "calendar"
        )
        progressCard(
            title: "This month",
            value: DurationFormatter.minutes(summaries.reduce(0) { $0 + $1.monthMinutes }),
            systemImage: "chart.bar"
        )
        progressCard(
            title: "Tasks done",
            value: "\(summaries.reduce(0) { $0 + $1.completedTasksThisWeek }) this week",
            systemImage: "checkmark.circle"
        )
    }

    private func progressCard(title: String, value: String, systemImage: String) -> some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Active boxes overview

    private var activeBoxesOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Study Boxes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Menu {
                    Button {
                        showCalendarFeeds()
                    } label: {
                        Label("Calendar Feeds", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        Task {
                            let result = await NotificationService.scheduleDeadlineReminders(for: boxes)
                            notificationMessage = result.message
                        }
                    } label: {
                        Label("Schedule Reminders", systemImage: "bell.badge")
                    }
                } label: {
                    Label("Setup", systemImage: "slider.horizontal.3")
                }
                .controlSize(.small)
                .help("Open setup tools for feeds and reminders.")
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(activeBoxes) { box in
                    Button {
                        selectedBoxID = box.id
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: box.colorHex).opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: box.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color(hex: box.colorHex))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(box.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(openTasksSubtitle(for: box))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.separator)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openTasksSubtitle(for box: StudyBox) -> String {
        let open = box.tasks.filter { $0.status != .done }.count
        return open == 0 ? "No open tasks" : "\(open) open task\(open == 1 ? "" : "s")"
    }

    // MARK: Session management

    private func startStudySession(for box: StudyBox, options: SessionStartOptions, opensFocusHUD: Bool = true) {
        guard appState.activeSessionID == nil, !appState.isStartingSession else { return }

        let startDecision = EntitlementRules.canStartSession(totalBoxCount: boxes.count, plan: license.plan)
        guard startDecision.isAllowed else {
            presentLicense(startDecision.message)
            return
        }

        let options = EntitlementRules.sanitizedSessionOptions(options, plan: license.plan)
        appState.isStartingSession = true

        let session = SessionManager.startSession(for: box, options: options, modelContext: modelContext)
        launchResults = []
        appState.registerStartedSession(session, box: box, options: options, launchResults: [])
        appState.isSessionSetupPresented = false
        appState.isSessionModePresented = true
        if opensFocusHUD {
            showFocusHUD()
        }
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
            launchResults = report.launchResults
            appState.updateStartupReport(report)
        }
    }

    private func defaultSessionOptions(for box: StudyBox) -> SessionStartOptions {
        EntitlementRules.sanitizedSessionOptions(SessionStartOptions(
            plannedMinutes: box.defaultSessionMinutes,
            openResources: box.openResourcesOnSessionStart,
            hideDistractions: box.focusMode.hideDistractions,
            quitDistractions: box.focusMode.quitDistractions,
            enforceFocus: box.focusMode.enforceFocus,
            restoreWindowLayout: box.restoreWindowLayoutOnSessionStart,
            keepDisplayAwake: box.keepDisplayAwakeDuringSessions ?? true,
            focusMode: box.focusMode
        ), plan: license.plan)
    }

    private func showCalendarFeeds() {
        let decision = EntitlementRules.canUse(.calendarFeeds, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }
        showingIntegrations = true
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
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

    private func notifyIfNeeded(_ report: SessionRestoreReport?) async {
        guard let report, let summary = report.displaySummary else { return }
        await NotificationService.notifySessionRestoreIfNeeded(
            summary: summary,
            hasIssues: !report.messages.isEmpty,
            appIsActive: NSApp.isActive
        )
    }

    private func showMenuBarHintIfNeeded() {
        guard onboardingState.consumeMenuBarHintIfNeeded() else { return }
        notificationMessage = "Study Boxes is ready in the menu bar."
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if notificationMessage == "Study Boxes is ready in the menu bar." {
                notificationMessage = nil
            }
        }
    }
}

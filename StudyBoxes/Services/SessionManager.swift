import Foundation
import SwiftData
import os

struct SessionStartOptions {
    var plannedMinutes: Int
    var openResources: Bool
    var hideDistractions: Bool
    var quitDistractions: Bool
    var enforceFocus: Bool
    var restoreWindowLayout: Bool
    var keepDisplayAwake: Bool = true
    var focusMode: StudyFocusMode = .off
    var prepareDesktopSpaces: Bool = false

    var resolvedFocusMode: StudyFocusMode {
        if focusMode != .off { return focusMode }
        return StudyBox.focusMode(
            hideDistractions: hideDistractions,
            quitDistractions: quitDistractions,
            enforceFocus: enforceFocus
        )
    }

    static func defaults(for box: StudyBox, plan: EntitlementPlan) -> SessionStartOptions {
        EntitlementRules.sanitizedSessionOptions(
            SessionStartOptions(
                plannedMinutes: box.defaultSessionMinutes,
                openResources: box.openResourcesOnSessionStart,
                hideDistractions: box.focusMode.hideDistractions,
                quitDistractions: box.focusMode.quitDistractions,
                enforceFocus: box.focusMode.enforceFocus,
                restoreWindowLayout: box.restoreWindowLayoutOnSessionStart,
                keepDisplayAwake: box.keepDisplayAwakeDuringSessions ?? true,
                focusMode: box.focusMode,
                prepareDesktopSpaces: box.prepareDesktopSpacesOnSessionStart
            ),
            plan: plan
        )
    }
}

struct SessionStartupReport {
    var launchResults: [ResourceLaunchResult] = []
    var windowRestoreReport: WindowRestoreReport?
    var sessionRestoreReport: SessionRestoreReport?
    var spacePreparationReport: SpacePreparationReport?
    var focusMessages: [String] = []

    var hasIssues: Bool {
        launchResults.contains { $0.status == .failed } ||
            windowRestoreReport?.messages.isEmpty == false ||
            spacePreparationReport?.messages.isEmpty == false ||
            focusMessages.isEmpty == false ||
            sessionRestoreReport?.messages.isEmpty == false
    }

    var issueMessages: [String] {
        var messages = launchResults
            .filter { $0.status == .failed }
            .map { "\($0.resourceTitle): \($0.message)" }
        messages.append(contentsOf: focusMessages)
        messages.append(contentsOf: spacePreparationReport?.messages ?? [])
        messages.append(contentsOf: windowRestoreReport?.messages ?? [])
        messages.append(contentsOf: sessionRestoreReport?.messages ?? [])
        return messages
    }
}

@MainActor
enum SessionManager {
    private static let logger = Logger(subsystem: "StudyBoxes", category: "SessionManager")

    static func startSession(for box: StudyBox, options: SessionStartOptions, modelContext: ModelContext) -> StudySession {
        let session = StudySession(
            box: box,
            startedAt: .now,
            plannedMinutes: options.plannedMinutes
        )
        modelContext.insert(session)
        box.touch()
        save(modelContext)
        return session
    }

    static func finishStartup(
        for box: StudyBox,
        session: StudySession,
        options: SessionStartOptions,
        modelContext: ModelContext
    ) async -> SessionStartupReport {
        let effectiveOptions = EntitlementRules.sanitizedSessionOptions(options, plan: LicenseManager.shared.plan)
        let restoreSnapshot = SessionRestoreManager.createSnapshotIfNeeded(
            session: session,
            box: box,
            options: effectiveOptions,
            modelContext: modelContext
        )
        let focusMessages: [String] = []

        if effectiveOptions.keepDisplayAwake {
            StudyModePowerManager.shared.beginStudyMode()
        }

        let enabledResources = EntitlementRules.enabledResources(for: box, plan: LicenseManager.shared.plan)
        let preparationReport = effectiveOptions.prepareDesktopSpaces
            ? await SpaceLayoutManager.prepareSpaces(for: box, enabledResources: enabledResources)
            : nil

        let arrangementReport = effectiveOptions.prepareDesktopSpaces && effectiveOptions.openResources
            ? await SpaceLayoutManager.arrangeAppResources(for: box, enabledResources: enabledResources)
            : nil

        let launchResults: [ResourceLaunchResult]
        if effectiveOptions.openResources {
            launchResults = SpaceLayoutManager.immediateLaunchResources(
                for: box,
                enabledResources: enabledResources,
                prepareDesktopSpaces: effectiveOptions.prepareDesktopSpaces
            )
                .map { ResourceLauncher.shared.open($0) }
        } else {
            launchResults = []
        }

        let combinedSpaceReport = combinedSpacePreparationReport(
            preparationReport: preparationReport,
            arrangementReport: arrangementReport
        )

        return await finishFocusAndRestore(
            box: box,
            effectiveOptions: effectiveOptions,
            restoreSnapshot: restoreSnapshot,
            focusMessages: focusMessages,
            launchResults: launchResults,
            spacePreparationReport: combinedSpaceReport,
            modelContext: modelContext
        )
    }

    private static func combinedSpacePreparationReport(
        preparationReport: SpacePreparationReport?,
        arrangementReport: SpacePreparationReport?
    ) -> SpacePreparationReport? {
        guard let preparationReport else {
            return arrangementReport
        }

        guard let arrangementReport else {
            return preparationReport
        }

        return SpacePreparationReport(
            requestedSpaces: max(preparationReport.requestedSpaces, arrangementReport.requestedSpaces),
            availableSpaces: max(preparationReport.availableSpaces, arrangementReport.availableSpaces),
            assignedApps: arrangementReport.assignedApps,
            messages: preparationReport.messages + arrangementReport.messages
        )
    }

    private static func finishFocusAndRestore(
        box: StudyBox,
        effectiveOptions: SessionStartOptions,
        restoreSnapshot: SessionRestoreSnapshot?,
        focusMessages initialFocusMessages: [String],
        launchResults: [ResourceLaunchResult],
        spacePreparationReport: SpacePreparationReport?,
        modelContext: ModelContext
    ) async -> SessionStartupReport {
        var focusMessages = initialFocusMessages

        if SessionRestoreManager.requiresAccessibility(options: effectiveOptions),
           !PermissionManager.isAccessibilityTrusted {
            focusMessages.append("Quit Apps and Strict Focus need Accessibility before they can restore previous windows.")
        } else if effectiveOptions.resolvedFocusMode == .strictFocus {
            DistractionManager.shared.startFocusEnforcement(for: box) { result in
                SessionRestoreManager.recordAffectedApps(
                    snapshot: restoreSnapshot,
                    results: [result],
                    modelContext: modelContext
                )
            }
            let results = DistractionManager.shared.quitUnrelatedAppsWithResult(for: box)
            SessionRestoreManager.recordAffectedApps(
                snapshot: restoreSnapshot,
                results: results,
                modelContext: modelContext
            )
        } else if effectiveOptions.resolvedFocusMode == .quitApps {
            let results = DistractionManager.shared.quitUnrelatedAppsWithResult(for: box)
            SessionRestoreManager.recordAffectedApps(
                snapshot: restoreSnapshot,
                results: results,
                modelContext: modelContext
            )
        } else if effectiveOptions.resolvedFocusMode == .hideApps {
            let results = DistractionManager.shared.hideUnrelatedAppsWithResult(for: box)
            SessionRestoreManager.recordAffectedApps(
                snapshot: restoreSnapshot,
                results: results,
                modelContext: modelContext
            )
        }

        let restoreReport = effectiveOptions.restoreWindowLayout ? await WindowLayoutManager.restoreLayout(for: box) : nil

        return SessionStartupReport(
            launchResults: launchResults,
            windowRestoreReport: restoreReport,
            sessionRestoreReport: nil,
            spacePreparationReport: spacePreparationReport,
            focusMessages: focusMessages
        )
    }

    static func endSession(_ session: StudySession, notes: String?, modelContext: ModelContext) {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.end(notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil)
        StudyModePowerManager.shared.endStudyMode()
        DistractionManager.shared.restoreHiddenApps()
        session.box?.touch()
        save(modelContext)
    }

    @discardableResult
    static func endSessionAndRestore(_ session: StudySession, notes: String?, modelContext: ModelContext) async -> SessionRestoreReport? {
        let snapshot = SessionRestoreManager.snapshot(for: session.id, modelContext: modelContext)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.end(notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil)
        StudyModePowerManager.shared.endStudyMode()
        DistractionManager.shared.stopFocusEnforcement()
        session.box?.touch()
        save(modelContext)

        guard let snapshot else {
            DistractionManager.shared.restoreHiddenApps()
            return nil
        }
        let report = await SessionRestoreManager.restore(snapshot: snapshot, modelContext: modelContext)
        DistractionManager.shared.restoreHiddenApps()
        return report
    }

    @discardableResult
    static func markTaskDone(_ task: StudyTask, in session: StudySession, modelContext: ModelContext) -> WellnessPrompt? {
        task.markDone()
        session.markCompleted(task.id)
        let prompt = WellnessReminderService.recordTaskCompletionIfNeeded(
            for: session,
            remindersEnabled: UserPreferencesService.shared.wellnessRemindersEnabled,
            intervalMinutes: UserPreferencesService.shared.wellnessReminderIntervalMinutes
        )
        save(modelContext)
        return prompt
    }

    static func markTaskSkipped(_ task: StudyTask, in session: StudySession, modelContext: ModelContext) {
        task.markSkipped()
        session.markSkipped(task.id)
        save(modelContext)
    }

    static func clearWellnessPrompt(in session: StudySession, modelContext: ModelContext) {
        WellnessReminderService.clearPendingPrompt(for: session)
        save(modelContext)
    }

    private static func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save session changes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

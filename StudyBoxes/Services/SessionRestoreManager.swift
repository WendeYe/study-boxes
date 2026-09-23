import AppKit
import Foundation
import os
import SwiftData

struct SessionRestoreReport {
    let attemptedApps: Int
    let restoredApps: Int
    let messages: [String]

    var summary: String {
        if attemptedApps == 0 {
            return "No previous apps needed to be restored."
        }
        if restoredApps == 0, !messages.isEmpty {
            return "Could not restore previous apps. \(messages.prefix(2).joined(separator: " "))"
        }
        if messages.isEmpty {
            return "Restored \(restoredApps) of \(attemptedApps) previous apps."
        }
        return "Restored \(restoredApps) of \(attemptedApps) previous apps. \(messages.prefix(2).joined(separator: " "))"
    }

    var displaySummary: String? {
        guard !messages.isEmpty || restoredApps < attemptedApps else { return nil }
        return summary
    }
}

@MainActor
enum SessionRestoreManager {
    private static let logger = Logger(subsystem: "StudyBoxes", category: "SessionRestore")
    private static let appRestoreTimeout: TimeInterval = 8

    static func shouldCaptureSnapshot(options: SessionStartOptions) -> Bool {
        options.resolvedFocusMode != .off
    }

    static func requiresAccessibility(options: SessionStartOptions) -> Bool {
        options.resolvedFocusMode.requiresAccessibilityForRestore
    }

    static func createSnapshotIfNeeded(
        session: StudySession,
        box: StudyBox,
        options: SessionStartOptions,
        modelContext: ModelContext
    ) -> SessionRestoreSnapshot? {
        guard shouldCaptureSnapshot(options: options) else { return nil }

        let snapshot = SessionRestoreSnapshot(sessionID: session.id, boxID: box.id)
        modelContext.insert(snapshot)

        for capturedApp in WindowSnapshotService.captureRunningRegularApps() {
            let app = SessionRestoreApp(
                snapshot: snapshot,
                bundleID: capturedApp.bundleID,
                appName: capturedApp.appName,
                appPath: capturedApp.appPath,
                processIdentifier: Int(capturedApp.processIdentifier),
                wasRunningBeforeSession: true,
                restorePolicy: .observeOnly
            )
            modelContext.insert(app)
            snapshot.apps.append(app)

            for windowSnapshot in capturedApp.windows {
                let screen = windowSnapshot.screen
                let window = SessionRestoreWindow(
                    app: app,
                    title: windowSnapshot.title,
                    windowNumber: windowSnapshot.windowNumber,
                    axRole: windowSnapshot.axRole,
                    axSubrole: windowSnapshot.axSubrole,
                    x: windowSnapshot.frame.origin.x,
                    y: windowSnapshot.frame.origin.y,
                    width: windowSnapshot.frame.width,
                    height: windowSnapshot.frame.height,
                    screenFrameX: screen.map { Double($0.frame.origin.x) },
                    screenFrameY: screen.map { Double($0.frame.origin.y) },
                    screenFrameWidth: screen.map { Double($0.frame.width) },
                    screenFrameHeight: screen.map { Double($0.frame.height) },
                    visibleFrameX: screen.map { Double($0.visibleFrame.origin.x) },
                    visibleFrameY: screen.map { Double($0.visibleFrame.origin.y) },
                    visibleFrameWidth: screen.map { Double($0.visibleFrame.width) },
                    visibleFrameHeight: screen.map { Double($0.visibleFrame.height) },
                    screenIdentifier: WindowSnapshotService.screenIdentifier(screen),
                    orderIndex: windowSnapshot.orderIndex,
                    isMinimized: windowSnapshot.isMinimized,
                    isFullScreen: windowSnapshot.isFullScreen
                )
                modelContext.insert(window)
                app.windows.append(window)
            }
        }

        save(modelContext)
        logger.info("Captured session restore snapshot with \(snapshot.apps.count, privacy: .public) apps.")
        return snapshot
    }

    static func recordAffectedApps(
        snapshot: SessionRestoreSnapshot?,
        results: [DistractionActionResult],
        modelContext: ModelContext
    ) {
        guard let snapshot else { return }
        for result in results {
            let action = restoreAction(for: result.action)
            let app = snapshot.apps.first { $0.bundleID == result.bundleID } ?? {
                let app = SessionRestoreApp(
                    snapshot: snapshot,
                    bundleID: result.bundleID,
                    appName: result.appName,
                    appPath: result.appPath,
                    processIdentifier: result.processIdentifier.map(Int.init),
                    wasRunningBeforeSession: result.wasRunningBeforeSession,
                    restorePolicy: .observeOnly
                )
                modelContext.insert(app)
                snapshot.apps.append(app)
                return app
            }()
            app.appPath = app.appPath ?? result.appPath
            app.processIdentifier = result.processIdentifier.map(Int.init) ?? app.processIdentifier
            app.markAffected(action: action)
        }
        save(modelContext)
    }

    @discardableResult
    static func restore(snapshot: SessionRestoreSnapshot, modelContext: ModelContext) async -> SessionRestoreReport {
        let targets = snapshot.apps
            .filter(\.shouldRestore)
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }

        guard !targets.isEmpty else {
            snapshot.markRestored(message: "No previous apps needed to be restored.")
            save(modelContext)
            return SessionRestoreReport(attemptedApps: 0, restoredApps: 0, messages: [])
        }

        var restoredApps = 0
        var messages: [String] = []

        for app in targets {
            await Task.yield()
            guard let runningApp = await runningOrRelaunchedApp(for: app) else {
                messages.append("Study Boxes could not reopen \(app.appName).")
                app.lastMessage = "Could not reopen."
                continue
            }

            runningApp.unhide()

            if PermissionManager.isAccessibilityTrusted {
                let restoreResult = await restoreWindows(for: app, pid: runningApp.processIdentifier)
                messages.append(contentsOf: restoreResult.messages)
                app.lastMessage = restoreResult.messages.first
            }
            app.restoredAt = .now
            restoredApps += 1
        }

        if messages.isEmpty {
            snapshot.markRestored(message: nil)
        } else if restoredApps > 0 {
            snapshot.markPartial(message: messages.prefix(2).joined(separator: " "))
        } else {
            snapshot.markFailed(message: messages.prefix(2).joined(separator: " "))
        }
        save(modelContext)

        return SessionRestoreReport(attemptedApps: targets.count, restoredApps: restoredApps, messages: messages)
    }

    static func pendingSnapshots(modelContext: ModelContext) -> [SessionRestoreSnapshot] {
        let snapshots = (try? modelContext.fetch(FetchDescriptor<SessionRestoreSnapshot>())) ?? []
        return snapshots
            .filter(\.hasPendingRestore)
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func snapshot(for sessionID: UUID, modelContext: ModelContext) -> SessionRestoreSnapshot? {
        let snapshots = (try? modelContext.fetch(FetchDescriptor<SessionRestoreSnapshot>())) ?? []
        return snapshots
            .filter { $0.sessionID == sessionID }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    static func cleanupOldCompletedSnapshots(modelContext: ModelContext, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let snapshots = (try? modelContext.fetch(FetchDescriptor<SessionRestoreSnapshot>())) ?? []
        for snapshot in snapshots {
            let completedDate = snapshot.restoredAt ?? snapshot.dismissedAt
            guard let completedDate,
                  completedDate < cutoff,
                  snapshot.status == .restored || snapshot.status == .dismissed else {
                continue
            }
            modelContext.delete(snapshot)
        }
        save(modelContext)
    }

    private static func restoreAction(for action: DistractionActionKind) -> SessionRestoreAppAction {
        switch action {
        case .hidden:
            return .hidden
        case .terminateRequested:
            return .terminateRequested
        case .terminateFailedHiddenFallback:
            return .terminateFailedHiddenFallback
        case .blockedNewLaunch:
            return .blockedNewLaunch
        case .skippedAllowed, .skippedProtected:
            return .none
        }
    }

    private static func runningOrRelaunchedApp(for app: SessionRestoreApp) async -> NSRunningApplication? {
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleID }) {
            return runningApp
        }

        guard WindowSnapshotService.openApp(bundleID: app.bundleID, appPath: app.appPath) else {
            return nil
        }

        let deadline = Date().addingTimeInterval(appRestoreTimeout)
        while Date() < deadline {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleID }) {
                return runningApp
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private static func restoreWindows(for app: SessionRestoreApp, pid: pid_t) async -> (restoredWindows: Int, messages: [String]) {
        let savedWindows = app.windows
            .filter { !$0.isMinimized && !$0.isFullScreen }
            .sorted { $0.orderIndex < $1.orderIndex }

        guard !savedWindows.isEmpty else {
            return (0, [])
        }

        var axWindows = await WindowSnapshotService.waitForWindows(pid: pid, timeout: appRestoreTimeout)
        guard !axWindows.isEmpty else {
            return (0, ["\(app.appName) did not show any windows."])
        }

        var restored = 0
        var messages: [String] = []
        for saved in savedWindows {
            guard let matchIndex = WindowSnapshotService.bestMatchIndex(for: saved, in: axWindows) else {
                messages.append("No matching window for \(app.appName).")
                continue
            }
            let window = axWindows.remove(at: matchIndex)
            if WindowSnapshotService.apply(saved: saved, to: window) {
                restored += 1
            } else {
                messages.append("Study Boxes could not move \(saved.title ?? app.appName).")
            }
        }
        return (restored, messages)
    }

    private static func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save session restore state: \(error.localizedDescription, privacy: .public)")
        }
    }
}

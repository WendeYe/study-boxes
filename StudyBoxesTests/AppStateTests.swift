import AppKit
import XCTest
@testable import StudyBoxes

@MainActor
final class AppStateTests: XCTestCase {
    override func tearDown() {
        MenuBarTimerController.shared.stop()
        UserDefaults.standard.removeObject(forKey: AppState.persistenceRecoveryMessageKey)
        super.tearDown()
    }

    func testLoadsPersistenceRecoveryMessageFromUserDefaults() {
        let message = "Study Boxes recovered from a local data issue."
        UserDefaults.standard.set(message, forKey: AppState.persistenceRecoveryMessageKey)

        let appState = AppState()

        XCTAssertEqual(appState.lastErrorMessage, message)
    }

    func testSessionStateResetsOnEndSession() {
        let appState = AppState()
        let box = StudyBox(name: "Physics", type: .course)
        let session = StudySession(box: box, plannedMinutes: 25)
        let options = SessionStartOptions(
            plannedMinutes: 25,
            openResources: true,
            hideDistractions: true,
            quitDistractions: true,
            enforceFocus: true,
            restoreWindowLayout: false
        )

        appState.registerStartedSession(session, box: box, options: options, launchResults: [])
        appState.updateStartupReport(SessionStartupReport(
            launchResults: [ResourceLaunchResult(id: UUID(), resourceTitle: "Missing", status: .failed, message: "Not found.")],
            windowRestoreReport: WindowRestoreReport(attempted: 1, restored: 0, messages: ["No matching window."])
        ))
        XCTAssertEqual(appState.activeSessionID, session.id)
        XCTAssertEqual(appState.activeFocusMode, .strictFocus)
        XCTAssertFalse(appState.isHidingDistractionsActive)
        XCTAssertTrue(appState.isFocusEnforcementActive)
        XCTAssertEqual(appState.activeStartupIssueMessages.count, 2)

        appState.endSession()

        XCTAssertNil(appState.activeSessionID)
        XCTAssertNil(appState.activeSessionStartedAt)
        XCTAssertNil(appState.activeSessionBoxName)
        XCTAssertFalse(appState.isHidingDistractionsActive)
        XCTAssertFalse(appState.isFocusEnforcementActive)
        XCTAssertFalse(appState.isSessionModePresented)
        XCTAssertTrue(appState.activeStartupIssueMessages.isEmpty)
    }

    func testRegisterStartedSessionClearsPreviousRestoreSummary() {
        let appState = AppState()
        appState.lastSessionRestoreSummary = "Restored 0 of 0 previous apps."

        let box = StudyBox(name: "Probability P2", type: .exam)
        let session = StudySession(box: box, plannedMinutes: 50)
        let options = SessionStartOptions(
            plannedMinutes: 50,
            openResources: false,
            hideDistractions: false,
            quitDistractions: false,
            enforceFocus: false,
            restoreWindowLayout: false
        )

        appState.registerStartedSession(session, box: box, options: options, launchResults: [])

        XCTAssertNil(appState.lastSessionRestoreSummary)
    }

    func testSessionRestoreReportOnlyDisplaysActionableSummaries() {
        let noOpReport = SessionRestoreReport(attemptedApps: 0, restoredApps: 0, messages: [])
        let restoredReport = SessionRestoreReport(attemptedApps: 2, restoredApps: 2, messages: [])
        let partialReport = SessionRestoreReport(attemptedApps: 2, restoredApps: 1, messages: ["Safari did not reopen a window."])
        let failedReport = SessionRestoreReport(attemptedApps: 2, restoredApps: 0, messages: ["Safari did not reopen a window."])

        XCTAssertNil(noOpReport.displaySummary)
        XCTAssertNil(restoredReport.displaySummary)
        XCTAssertEqual(partialReport.displaySummary, "Restored 1 of 2 previous apps. Safari did not reopen a window.")
        XCTAssertEqual(failedReport.displaySummary, "Could not restore previous apps. Safari did not reopen a window.")
    }

    func testCompleteSessionEndClearsStateAfterExplicitEnd() {
        let appState = AppState()
        let box = StudyBox(name: "Physics", type: .course)
        let session = StudySession(box: box, plannedMinutes: 25)
        let options = SessionStartOptions(
            plannedMinutes: 25,
            openResources: false,
            hideDistractions: true,
            quitDistractions: false,
            enforceFocus: false,
            restoreWindowLayout: false,
            keepDisplayAwake: false
        )
        appState.registerStartedSession(session, box: box, options: options, launchResults: [])

        appState.completeExplicitSessionEnd()

        XCTAssertNil(appState.activeSessionID)
        XCTAssertFalse(appState.isHidingDistractionsActive)
        XCTAssertFalse(appState.isFocusEnforcementActive)
        XCTAssertFalse(appState.isSessionModePresented)
    }

    func testStartSessionOpensSetupForSelectedBox() {
        let appState = AppState()
        let boxID = UUID()

        appState.startSession(boxID: boxID)

        XCTAssertEqual(appState.activeBoxID, boxID)
        XCTAssertTrue(appState.isSessionSetupPresented)
    }

    func testMenuBarTimerTitleFormatting() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 165)

        XCTAssertEqual(
            MenuBarTimerController.title(startedAt: startedAt, now: now, boxName: "Math", displayMode: .timer),
            "01:05"
        )
        XCTAssertEqual(
            MenuBarTimerController.title(startedAt: startedAt, now: now, boxName: "Math", displayMode: .boxNameAndTimer),
            "Math 01:05"
        )
        XCTAssertNil(
            MenuBarTimerController.title(startedAt: startedAt, now: now, boxName: "Math", displayMode: .iconOnly)
        )
    }

    func testMenuBarTimerActiveWidthDoesNotDependOnCurrentElapsedTime() {
        let boxName = "Weekly course"

        let initialTitle = MenuBarTimerController.title(
            startedAt: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 19),
            boxName: boxName,
            displayMode: .boxNameAndTimer
        )
        let laterTitle = MenuBarTimerController.title(
            startedAt: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 61),
            boxName: boxName,
            displayMode: .boxNameAndTimer
        )

        XCTAssertNotEqual(initialTitle, laterTitle)
        XCTAssertEqual(
            MenuBarTimerController.activeStatusItemLength(boxName: boxName, displayMode: .boxNameAndTimer),
            MenuBarTimerController.activeStatusItemLength(boxName: boxName, displayMode: .boxNameAndTimer)
        )
    }

    func testStudySpacePresentationStaysCompactAndTaskFocused() {
        XCTAssertLessThanOrEqual(StudySpacePresentation.defaultWidth, 520)
        XCTAssertLessThanOrEqual(StudySpacePresentation.defaultHeight, 420)
        XCTAssertEqual(StudySpacePresentation.visibleUpcomingTaskLimit, 1)
        XCTAssertEqual(StudySpacePresentation.menuUpcomingTaskLimit, 5)
    }

    func testMenuResourceActionsAlwaysExposeAddResource() {
        XCTAssertEqual(
            MenuResourceActionPresentation.primaryLabel(launchableResourceCount: 0).title,
            "Add Resource"
        )
        XCTAssertEqual(
            MenuResourceActionPresentation.primaryLabel(launchableResourceCount: 0).systemImage,
            "folder.badge.plus"
        )
        XCTAssertEqual(
            MenuResourceActionPresentation.primaryLabel(launchableResourceCount: 2).title,
            "Resources"
        )
        XCTAssertTrue(MenuResourceActionPresentation.showsAddResourceMenuItem(launchableResourceCount: 2))
    }

    func testBoxNameMenuBarModeCapsWidthToAvoidCrowdingSystemItems() {
        XCTAssertLessThanOrEqual(
            MenuBarTimerController.activeStatusItemLength(
                boxName: "Operating Systems Final Exam Revision",
                displayMode: .boxNameAndTimer
            ),
            220
        )
    }

    func testMenuBarTimerUsesAttributedTitleWithStableString() {
        let attributedTitle = MenuBarTimerController.attributedTitle(" Weekly course 00:59")

        XCTAssertEqual(attributedTitle.string, " Weekly course 00:59")
        XCTAssertNotNil(attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    }

    func testActiveMenuBarKeepsStudyBoxesIcon() {
        XCTAssertEqual(MenuBarTimerController.statusImageSymbolName(isRunning: false), "books.vertical")
        XCTAssertEqual(MenuBarTimerController.statusImageSymbolName(isRunning: true), "books.vertical")
        XCTAssertNotNil(MenuBarTimerController.statusImage(isRunning: false))
        XCTAssertNotNil(MenuBarTimerController.statusImage(isRunning: true))
    }

    func testActiveMenuBarWidthsStayCompactForCrowdedMenuBars() {
        XCTAssertGreaterThanOrEqual(
            MenuBarTimerController.activeStatusItemLength(boxName: "Weekly course", displayMode: .timer),
            90
        )
        XCTAssertLessThanOrEqual(
            MenuBarTimerController.activeStatusItemLength(boxName: "Weekly course", displayMode: .timer),
            96
        )
        XCTAssertLessThanOrEqual(
            MenuBarTimerController.activeStatusItemLength(
                boxName: "Operating Systems Final Exam Revision",
                displayMode: .boxNameAndTimer
            ),
            190
        )
    }

    func testStudySpaceWindowOnlyOpensForActiveSession() {
        XCTAssertFalse(AppWindowController.shouldOpenStudySpaceWindow(activeSessionID: nil))
        XCTAssertTrue(AppWindowController.shouldOpenStudySpaceWindow(activeSessionID: UUID()))
    }

    func testDashboardLaunchPolicyOnlyClosesLibraryAfterOnboarding() {
        XCTAssertFalse(AppWindowController.shouldCloseInitialDashboardWindowAfterLaunch(hasCompletedOnboarding: false))
        XCTAssertTrue(AppWindowController.shouldCloseInitialDashboardWindowAfterLaunch(hasCompletedOnboarding: true))
    }

    func testMenuBarStatusPolicyHidesRoutineSessionMessages() {
        XCTAssertFalse(MenuBarStatusMessagePolicy.shouldDisplay("Started Probability P2"))
        XCTAssertFalse(MenuBarStatusMessagePolicy.shouldDisplay("Marked task done"))
        XCTAssertFalse(MenuBarStatusMessagePolicy.shouldDisplay("Skipped current task"))
        XCTAssertFalse(MenuBarStatusMessagePolicy.shouldDisplay("Session ended"))
        XCTAssertFalse(MenuBarStatusMessagePolicy.shouldDisplay("Restored 0 of 0 previous apps."))
        XCTAssertTrue(MenuBarStatusMessagePolicy.shouldDisplay("Some resources failed to open"))
        XCTAssertTrue(MenuBarStatusMessagePolicy.shouldDisplay("Could not restore previous apps. Safari did not reopen a window."))
    }

    func testStudyBoxAccentPaletteNormalizesHexAndFallsBack() {
        XCTAssertEqual(StudyBoxAccentPalette.normalizedAccentHex("#ef4444"), "#EF4444")
        XCTAssertEqual(StudyBoxAccentPalette.normalizedAccentHex(" 22C55E "), "#22C55E")
        XCTAssertEqual(StudyBoxAccentPalette.normalizedAccentHex("not-a-color"), StudyBoxAccentPalette.fallbackHex)
        XCTAssertEqual(StudyBoxAccentPalette.normalizedAccentHex(nil), StudyBoxAccentPalette.fallbackHex)
    }

    func testHUDPresentationKeepsSemanticActionColorsSeparateFromStudyBoxAccent() {
        XCTAssertEqual(
            StudySessionHUDPresentation.tintHex(for: .studyContext, boxAccentHex: "#EF4444"),
            "#EF4444"
        )
        XCTAssertEqual(
            StudySessionHUDPresentation.tintHex(for: .completion, boxAccentHex: "#EF4444"),
            "#2563EB"
        )
        XCTAssertEqual(
            StudySessionHUDPresentation.tintHex(for: .restore, boxAccentHex: "#EF4444"),
            "#2563EB"
        )
        XCTAssertEqual(
            StudySessionHUDPresentation.tintHex(for: .destructive, boxAccentHex: "#22C55E"),
            "#EF4444"
        )
    }

    func testWellnessPromptTriggersAfterIntervalWhenTaskCompletes() {
        let session = StudySession(
            startedAt: Date(timeIntervalSince1970: 0),
            plannedMinutes: 50
        )

        let prompt = WellnessReminderService.recordTaskCompletionIfNeeded(
            for: session,
            now: Date(timeIntervalSince1970: 25 * 60),
            remindersEnabled: true,
            intervalMinutes: 25
        )

        XCTAssertNotNil(prompt)
        XCTAssertEqual(session.pendingWellnessPromptAt, Date(timeIntervalSince1970: 25 * 60))
        XCTAssertEqual(session.lastWellnessPromptAt, Date(timeIntervalSince1970: 25 * 60))
        XCTAssertEqual(session.wellnessPromptCount, 1)
    }

    func testWellnessPromptIsThrottledFromLastPromptAndClearsPendingPrompt() {
        let session = StudySession(
            startedAt: Date(timeIntervalSince1970: 0),
            plannedMinutes: 50,
            lastWellnessPromptAt: Date(timeIntervalSince1970: 20 * 60),
            pendingWellnessPromptAt: Date(timeIntervalSince1970: 20 * 60),
            wellnessPromptCount: 1
        )

        XCTAssertNil(WellnessReminderService.recordTaskCompletionIfNeeded(
            for: session,
            now: Date(timeIntervalSince1970: 40 * 60),
            remindersEnabled: true,
            intervalMinutes: 25
        ))

        WellnessReminderService.clearPendingPrompt(for: session)

        XCTAssertNil(session.pendingWellnessPromptAt)
        XCTAssertEqual(session.lastWellnessPromptAt, Date(timeIntervalSince1970: 20 * 60))
        XCTAssertEqual(session.wellnessPromptCount, 1)
    }

    func testWellnessReminderPreferencesPersist() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferencesService(userDefaults: defaults)
        preferences.wellnessRemindersEnabled = false
        preferences.wellnessReminderIntervalMinutes = 45

        let reloaded = UserPreferencesService(userDefaults: defaults)

        XCTAssertFalse(reloaded.wellnessRemindersEnabled)
        XCTAssertEqual(reloaded.wellnessReminderIntervalMinutes, 45)
    }

    func testWellnessReminderPreferencesAllowCustomIntervals() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferencesService(userDefaults: defaults)
        preferences.wellnessReminderIntervalMinutes = 37

        let reloaded = UserPreferencesService(userDefaults: defaults)

        XCTAssertEqual(reloaded.wellnessReminderIntervalMinutes, 37)
    }

    func testWellnessReminderPreferencesClampCustomIntervals() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferencesService(userDefaults: defaults)
        preferences.wellnessReminderIntervalMinutes = 2
        XCTAssertEqual(preferences.wellnessReminderIntervalMinutes, 5)

        preferences.wellnessReminderIntervalMinutes = 500
        XCTAssertEqual(preferences.wellnessReminderIntervalMinutes, 180)
    }

    func testReminderIntervalTextFieldDoesNotExposeNumericPromptAsFormLabel() {
        XCTAssertEqual(ReminderIntervalInputPresentation.textFieldTitle, "")
        XCTAssertEqual(ReminderIntervalInputPresentation.prompt, "25")
    }

    func testLicenseActivationControlsHideForLicensedUsers() {
        XCTAssertTrue(LicenseViewPresentation.showsActivationControls(for: .free))
        XCTAssertFalse(LicenseViewPresentation.showsActivationControls(for: .pro))
    }
}

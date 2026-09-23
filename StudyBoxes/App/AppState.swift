import AppKit
import SwiftUI

@MainActor
enum AppWindowController {
    static let dashboardIdentifier = NSUserInterfaceItemIdentifier("StudyBoxes.dashboard")
    static let studySpaceIdentifier = NSUserInterfaceItemIdentifier("StudyBoxes.study-space")
    static var shouldCloseInitialDashboardWindow = shouldCloseInitialDashboardWindowAfterLaunch(
        hasCompletedOnboarding: OnboardingState.shared.hasCompletedOnboarding
    )

    static func closeDashboardWindows() {
        for window in NSApp.windows where window.identifier == dashboardIdentifier {
            window.close()
        }
    }

    static func closeStudySpaceWindows() {
        for window in NSApp.windows where window.identifier == studySpaceIdentifier {
            window.close()
        }
    }

    static func shouldOpenStudySpaceWindow(activeSessionID: UUID?) -> Bool {
        activeSessionID != nil
    }

    static func shouldCloseInitialDashboardWindowAfterLaunch(hasCompletedOnboarding: Bool) -> Bool {
        hasCompletedOnboarding
    }

    @discardableResult
    static func activateStudySpaceIfOpen() -> Bool {
        guard let window = NSApp.windows.first(where: { $0.identifier == studySpaceIdentifier }) else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

enum StudySpacePresentation {
    static let defaultWidth: CGFloat = 500
    static let defaultHeight: CGFloat = 380
    static let minimumWidth: CGFloat = 440
    static let minimumHeight: CGFloat = 320
    static let maximumWidth: CGFloat = 560
    static let visibleUpcomingTaskLimit = 1
    static let menuUpcomingTaskLimit = 5
}

struct MenuResourceActionLabel: Equatable {
    let title: String
    let systemImage: String
}

enum MenuResourceActionPresentation {
    static func primaryLabel(launchableResourceCount: Int) -> MenuResourceActionLabel {
        if launchableResourceCount == 0 {
            return MenuResourceActionLabel(title: "Add Resource", systemImage: "folder.badge.plus")
        }
        return MenuResourceActionLabel(title: "Resources", systemImage: "folder")
    }

    static func showsAddResourceMenuItem(launchableResourceCount: Int) -> Bool {
        launchableResourceCount > 0
    }
}

enum MenuBarStatusMessagePolicy {
    static func shouldDisplay(_ message: String) -> Bool {
        let hiddenPrefixes = [
            "Started ",
            "Marked task done",
            "Skipped current task",
            "Break reminder cleared",
            "Session ended",
            "Restored 0 of 0 previous apps.",
            "No previous apps needed to be restored."
        ]
        return !hiddenPrefixes.contains { message.hasPrefix($0) }
    }
}

struct AppWindowIdentifierView: NSViewRepresentable {
    let identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        assignIdentifier(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        assignIdentifier(from: nsView)
    }

    private func assignIdentifier(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = identifier

            if identifier == AppWindowController.dashboardIdentifier,
               AppWindowController.shouldCloseInitialDashboardWindow {
                AppWindowController.shouldCloseInitialDashboardWindow = false
                window.close()
                return
            }

            if identifier == AppWindowController.studySpaceIdentifier {
                window.level = .floating
                window.collectionBehavior.insert(.fullScreenAuxiliary)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let persistenceRecoveryMessageKey = "PersistenceRecoveryMessage"

    @Published var activeBoxID: UUID?
    @Published var activeSessionID: UUID?
    @Published var isSessionSetupPresented = false
    @Published var isSessionModePresented = false
    @Published var isIntegrationsPresented = false
    @Published var pendingSessionMinutes: Int?
    @Published var isStartingSession = false
    @Published var activeSessionStartedAt: Date?
    @Published var activeSessionBoxName: String?
    @Published var activeFocusMode: StudyFocusMode = .off
    @Published var isHidingDistractionsActive = false
    @Published var isFocusEnforcementActive = false
    @Published var activeLaunchResults: [ResourceLaunchResult] = []
    @Published var activeStartupIssueMessages: [String] = []
    @Published var activeWindowRestoreSummary: String?
    @Published var lastSessionRestoreSummary: String?
    @Published var lastErrorMessage: String?
    @Published var isLicensePresented = false
    @Published var licensePresentationReason: String?

    init() {
        lastErrorMessage = UserDefaults.standard.string(forKey: Self.persistenceRecoveryMessageKey)
    }

    func openBox(_ id: UUID) {
        activeBoxID = id
    }

    func startSession(boxID: UUID) {
        activeBoxID = boxID
        isSessionSetupPresented = true
    }

    func confirmSession(minutes: Int) {
        pendingSessionMinutes = minutes
        isSessionSetupPresented = false
        isSessionModePresented = true
    }

    func registerStartedSession(_ session: StudySession, box: StudyBox, options: SessionStartOptions, launchResults: [ResourceLaunchResult]) {
        activeSessionID = session.id
        activeSessionStartedAt = session.startedAt
        activeSessionBoxName = box.name
        activeFocusMode = options.resolvedFocusMode
        isHidingDistractionsActive = options.resolvedFocusMode == .hideApps
        isFocusEnforcementActive = options.resolvedFocusMode == .strictFocus
        activeLaunchResults = launchResults
        lastSessionRestoreSummary = nil
        isStartingSession = false
        MenuBarTimerController.shared.start(
            startedAt: session.startedAt,
            boxName: box.name,
            displayMode: UserPreferencesService.shared.menuBarDisplayMode
        )
    }

    func updateLaunchResults(_ launchResults: [ResourceLaunchResult]) {
        activeLaunchResults = launchResults
    }

    func updateStartupReport(_ report: SessionStartupReport) {
        activeLaunchResults = report.launchResults
        activeStartupIssueMessages = report.issueMessages
        activeWindowRestoreSummary = report.windowRestoreReport?.summary
    }

    func endSession() {
        activeSessionID = nil
        activeSessionStartedAt = nil
        activeSessionBoxName = nil
        activeFocusMode = .off
        isHidingDistractionsActive = false
        isFocusEnforcementActive = false
        activeLaunchResults = []
        activeStartupIssueMessages = []
        activeWindowRestoreSummary = nil
        lastSessionRestoreSummary = nil
        pendingSessionMinutes = nil
        isStartingSession = false
        isSessionSetupPresented = false
        isSessionModePresented = false
        MenuBarTimerController.shared.stop()
    }

    func completeExplicitSessionEnd(restoreSummary: String? = nil) {
        endSession()
        lastSessionRestoreSummary = restoreSummary
        AppWindowController.closeStudySpaceWindows()
    }

    func showIntegrations() {
        isIntegrationsPresented = true
    }

    func presentLicense(reason: String?) {
        licensePresentationReason = reason
        isLicensePresented = true
    }

    func clearLicensePresentationReason() {
        licensePresentationReason = nil
    }

    func clearLicensePresentation() {
        isLicensePresented = false
        licensePresentationReason = nil
    }

    func pauseFocusEnforcement() {
        DistractionManager.shared.stopFocusEnforcement()
        isFocusEnforcementActive = false
    }
}

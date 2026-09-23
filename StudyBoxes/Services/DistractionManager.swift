import AppKit
import Foundation
import os

enum DistractionActionKind: String, Equatable {
    case skippedAllowed
    case skippedProtected
    case hidden
    case terminateRequested
    case terminateFailedHiddenFallback
    case blockedNewLaunch
}

struct DistractionActionResult: Identifiable, Equatable {
    let id = UUID()
    let bundleID: String
    let appName: String
    let action: DistractionActionKind
    let wasRunningBeforeSession: Bool
    let appPath: String?
    let processIdentifier: pid_t?

    init(
        bundleID: String,
        appName: String,
        action: DistractionActionKind,
        wasRunningBeforeSession: Bool,
        appPath: String? = nil,
        processIdentifier: pid_t? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.action = action
        self.wasRunningBeforeSession = wasRunningBeforeSession
        self.appPath = appPath
        self.processIdentifier = processIdentifier
    }

    var shouldRestoreAfterSession: Bool {
        wasRunningBeforeSession &&
            (action == .hidden || action == .terminateRequested || action == .terminateFailedHiddenFallback)
    }

    var isBlockedEvent: Bool {
        action == .blockedNewLaunch
    }
}

struct HiddenWindowRestoreRecord: Equatable {
    let title: String?
    let axRole: String?
    let axSubrole: String?
    let frame: CGRect
    let orderIndex: Int
    let isMinimized: Bool
    let isFullScreen: Bool
}

struct HiddenAppRestoreRecord: Equatable {
    let bundleID: String
    let wasPreviouslyHidden: Bool
    var windows: [HiddenWindowRestoreRecord]
}

@MainActor
final class DistractionManager: ObservableObject {
    static let shared = DistractionManager()

    private static let protectedBundleIDsKey = "ProtectedBundleIDs"
    private static let defaultProtectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.securityagent",
        "com.apple.accessibility.AccessibilityUIServer",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass",
        "com.studyboxes.StudyBoxes"
    ]

    private let logger = Logger(subsystem: "StudyBoxes", category: "DistractionManager")

    @Published private(set) var protectedBundleIDs: Set<String>
    @Published private(set) var isFocusEnforcementActive = false
    @Published private(set) var lastHideSummary: String?
    @Published private(set) var lastQuitSummary: String?

    private var hiddenBundleIDs: Set<String> = []
    private var previouslyHiddenBundleIDs: Set<String> = []
    private var hiddenAppRestoreRecords: [String: HiddenAppRestoreRecord] = [:]
    private var allowedBundleIDs: Set<String> = []
    private var launchObserver: NSObjectProtocol?
    private var blockedAppHandler: ((DistractionActionResult) -> Void)?

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.protectedBundleIDsKey) ?? []
        protectedBundleIDs = Self.defaultProtectedBundleIDs.union(stored)
        protectedBundleIDs.formUnion(Self.currentAppBundleIDs())
    }

    deinit {
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
    }

    func protect(_ bundleID: String) {
        protectedBundleIDs.insert(bundleID)
        saveProtectedBundleIDs()
    }

    func removeProtection(for bundleID: String) {
        guard !Self.defaultProtectedBundleIDs.contains(bundleID),
              !Self.currentAppBundleIDs().contains(bundleID) else { return }
        protectedBundleIDs.remove(bundleID)
        saveProtectedBundleIDs()
    }

    func hideUnrelatedApps(for box: StudyBox) {
        _ = hideUnrelatedAppsWithResult(for: box)
    }

    @discardableResult
    func hideUnrelatedAppsWithResult(for box: StudyBox) -> [DistractionActionResult] {
        let related = relatedBundleIDs(for: box)
        let candidates = hideCandidates(allowedBundleIDs: related)
        var results: [DistractionActionResult] = []

        hiddenAppRestoreRecords = hiddenRestoreRecords(for: candidates)
        previouslyHiddenBundleIDs = Set(candidates.filter(\.isHidden).compactMap(\.bundleIdentifier))
        hiddenBundleIDs.removeAll()

        for app in candidates where !app.isHidden {
            guard let bundleID = app.bundleIdentifier else { continue }
            if app.hide() {
                hiddenBundleIDs.insert(bundleID)
                results.append(Self.result(for: app, action: .hidden, wasRunningBeforeSession: true))
                logger.info("Hid unrelated app: \(bundleID, privacy: .public)")
            } else {
                logger.warning("Could not hide unrelated app with direct hide: \(bundleID, privacy: .public)")
            }
        }

        if candidates.contains(where: { !$0.isHidden }) {
            NSApp.hideOtherApplications(nil)
            unhideAllowedApps(related)
            markHiddenCandidates(candidates, allowedBundleIDs: related)
            let known = Set(results.map(\.bundleID))
            for app in candidates {
                guard let bundleID = app.bundleIdentifier,
                      !known.contains(bundleID),
                      hiddenBundleIDs.contains(bundleID),
                      !previouslyHiddenBundleIDs.contains(bundleID) else { continue }
                results.append(Self.result(for: app, action: .hidden, wasRunningBeforeSession: true))
            }
        }

        lastHideSummary = "Hidden \(hiddenBundleIDs.count) unrelated apps."
        return results
    }

    func quitUnrelatedApps(for box: StudyBox) {
        _ = quitUnrelatedAppsWithResult(for: box)
    }

    func previewAppsToQuit(for box: StudyBox) -> [DistractionActionResult] {
        let related = relatedBundleIDs(for: box)
        return affectableApps(allowedBundleIDs: related).map {
            Self.result(for: $0, action: .terminateRequested, wasRunningBeforeSession: true)
        }
    }

    @discardableResult
    func quitUnrelatedAppsWithResult(for box: StudyBox) -> [DistractionActionResult] {
        let related = relatedBundleIDs(for: box)
        let candidates = affectableApps(allowedBundleIDs: related)
        var requestedQuitCount = 0
        var hiddenFallbackCount = 0
        var results: [DistractionActionResult] = []

        for app in candidates {
            guard let bundleID = app.bundleIdentifier else { continue }
            if app.terminate() {
                requestedQuitCount += 1
                results.append(Self.result(for: app, action: .terminateRequested, wasRunningBeforeSession: true))
                logger.info("Asked unrelated app to quit: \(bundleID, privacy: .public)")
            } else {
                rememberHiddenRestoreRecord(for: app, wasPreviouslyHidden: app.isHidden)
                guard app.hide() else {
                    logger.warning("Could not quit or hide unrelated app: \(bundleID, privacy: .public)")
                    continue
                }
                hiddenFallbackCount += 1
                hiddenBundleIDs.insert(bundleID)
                results.append(Self.result(for: app, action: .terminateFailedHiddenFallback, wasRunningBeforeSession: true))
                logger.warning("Terminate returned false; hid app instead: \(bundleID, privacy: .public)")
            }
        }

        let hiddenSuffix = hiddenFallbackCount > 0 ? " Hid \(hiddenFallbackCount) instead." : ""
        lastQuitSummary = "Asked \(requestedQuitCount) unrelated apps to quit.\(hiddenSuffix)"
        return results
    }

    func startFocusEnforcement(for box: StudyBox, blockedAppHandler: ((DistractionActionResult) -> Void)? = nil) {
        allowedBundleIDs = relatedBundleIDs(for: box)
        allowedBundleIDs.formUnion(protectedBundleIDs)
        isFocusEnforcementActive = true
        self.blockedAppHandler = blockedAppHandler

        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.handleLaunchedApp(app)
            }
        }
    }

    func stopFocusEnforcement() {
        isFocusEnforcementActive = false
        allowedBundleIDs.removeAll()
        blockedAppHandler = nil
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }
    }

    func restoreHiddenApps() {
        stopFocusEnforcement()
        let records = Self.hiddenRestoreTargets(from: Array(hiddenAppRestoreRecords.values))
        for record in records {
            guard hiddenBundleIDs.contains(record.bundleID),
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == record.bundleID }) else {
                continue
            }
            app.unhide()
            if PermissionManager.isAccessibilityTrusted {
                let processIdentifier = app.processIdentifier
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self.restoreHiddenWindows(record, processIdentifier: processIdentifier)
                }
            }
        }
        hiddenBundleIDs.removeAll()
        previouslyHiddenBundleIDs.removeAll()
        hiddenAppRestoreRecords.removeAll()
        lastHideSummary = nil
        lastQuitSummary = nil
    }

    func isAllowedDuringFocus(_ bundleID: String) -> Bool {
        protectedBundleIDs.contains(bundleID) || allowedBundleIDs.contains(bundleID)
    }

    private func handleLaunchedApp(_ app: NSRunningApplication) {
        guard isFocusEnforcementActive else { return }
        guard !Self.isCurrentApplication(processIdentifier: app.processIdentifier) else { return }
        guard let bundleID = app.bundleIdentifier else {
            logger.info("Ignoring launched app without bundle identifier.")
            return
        }
        guard shouldAffectApp(
            bundleID: bundleID,
            processIdentifier: app.processIdentifier,
            activationPolicy: app.activationPolicy,
            allowedBundleIDs: allowedBundleIDs
        ) else { return }

        logger.info("Terminating app blocked by Focus Enforcement: \(bundleID, privacy: .public)")
        if !app.terminate() {
            _ = app.hide()
            logger.warning("Terminate returned false; hid app instead: \(bundleID, privacy: .public)")
        }
        blockedAppHandler?(Self.result(for: app, action: .blockedNewLaunch, wasRunningBeforeSession: false))
    }

    private func relatedBundleIDs(for box: StudyBox) -> Set<String> {
        var related = protectedBundleIDs
        related.formUnion(Self.currentAppBundleIDs())
        related.insert("com.apple.finder")

        for resource in box.resources {
            if let bundleID = resource.appBundleID {
                related.insert(bundleID)
            }
            if resource.type == .file {
                related.insert("com.apple.Preview")
            }
        }

        if box.resources.contains(where: { $0.type.expectsURL }) {
            related.formUnion(defaultBrowserBundleIDs())
        }

        return related
    }

    private func hideCandidates(allowedBundleIDs: Set<String>) -> [NSRunningApplication] {
        affectableApps(allowedBundleIDs: allowedBundleIDs)
    }

    private func affectableApps(allowedBundleIDs: Set<String>) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return shouldAffectApp(
                bundleID: bundleID,
                processIdentifier: app.processIdentifier,
                activationPolicy: app.activationPolicy,
                allowedBundleIDs: allowedBundleIDs
            )
        }
    }

    private func shouldAffectApp(
        bundleID: String,
        processIdentifier: pid_t,
        activationPolicy: NSApplication.ActivationPolicy,
        allowedBundleIDs: Set<String>
    ) -> Bool {
        Self.shouldAffectApp(
            bundleID: bundleID,
            processIdentifier: processIdentifier,
            activationPolicy: activationPolicy,
            allowedBundleIDs: allowedBundleIDs,
            protectedBundleIDs: protectedBundleIDs
        )
    }

    private func unhideAllowedApps(_ allowedBundleIDs: Set<String>) {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  allowedBundleIDs.contains(bundleID) else { continue }
            app.unhide()
        }
        NSApp.unhide(nil)
    }

    private func markHiddenCandidates(_ candidates: [NSRunningApplication], allowedBundleIDs: Set<String>) {
        for app in candidates {
            guard let bundleID = app.bundleIdentifier,
                  !allowedBundleIDs.contains(bundleID),
                  app.isHidden else { continue }
            hiddenBundleIDs.insert(bundleID)
        }
        logger.info("Hide unrelated apps summary: \(self.hiddenBundleIDs.count, privacy: .public) apps hidden.")
    }

    private func hiddenRestoreRecords(for candidates: [NSRunningApplication]) -> [String: HiddenAppRestoreRecord] {
        let capturedApps = Dictionary(
            WindowSnapshotService.captureRunningRegularApps().map { ($0.bundleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var records: [String: HiddenAppRestoreRecord] = [:]
        for app in candidates {
            guard let bundleID = app.bundleIdentifier else { continue }
            let capturedWindows = capturedApps[bundleID]?.windows ?? []
            records[bundleID] = HiddenAppRestoreRecord(
                bundleID: bundleID,
                wasPreviouslyHidden: app.isHidden,
                windows: capturedWindows.map(Self.hiddenWindowRecord)
            )
        }
        return records
    }

    private func rememberHiddenRestoreRecord(for app: NSRunningApplication, wasPreviouslyHidden: Bool) {
        guard let bundleID = app.bundleIdentifier,
              hiddenAppRestoreRecords[bundleID] == nil else { return }
        let windows = WindowSnapshotService.captureRunningRegularApps()
            .first { $0.bundleID == bundleID }?
            .windows
            .map(Self.hiddenWindowRecord) ?? []
        hiddenAppRestoreRecords[bundleID] = HiddenAppRestoreRecord(
            bundleID: bundleID,
            wasPreviouslyHidden: wasPreviouslyHidden,
            windows: windows
        )
    }

    private func restoreHiddenWindows(_ record: HiddenAppRestoreRecord, processIdentifier: pid_t) {
        let savedWindows = record.windows
            .filter { !$0.isMinimized && !$0.isFullScreen }
            .sorted { $0.orderIndex < $1.orderIndex }
        guard !savedWindows.isEmpty else { return }

        var axWindows = WindowSnapshotService.axWindows(pid: processIdentifier)
        guard !axWindows.isEmpty else { return }

        for saved in savedWindows {
            guard let matchIndex = WindowSnapshotService.bestMatchIndex(for: saved, in: axWindows) else {
                continue
            }
            let window = axWindows.remove(at: matchIndex)
            _ = WindowSnapshotService.apply(saved: saved, to: window)
        }
    }

    private static func hiddenWindowRecord(from snapshot: CapturedWindowSnapshot) -> HiddenWindowRestoreRecord {
        HiddenWindowRestoreRecord(
            title: snapshot.title,
            axRole: snapshot.axRole,
            axSubrole: snapshot.axSubrole,
            frame: snapshot.frame,
            orderIndex: snapshot.orderIndex,
            isMinimized: snapshot.isMinimized,
            isFullScreen: snapshot.isFullScreen
        )
    }

    static func browserBundleIDsForURLResources(resolvedDefaultBrowserBundleID bundleID: String?) -> Set<String> {
        guard let bundleID, !bundleID.isEmpty else {
            return []
        }
        return [bundleID]
    }

    private func defaultBrowserBundleIDs() -> Set<String> {
        if let url = URL(string: "https://example.com"),
           let browserURL = NSWorkspace.shared.urlForApplication(toOpen: url),
           let bundleID = Bundle(url: browserURL)?.bundleIdentifier {
            return Self.browserBundleIDsForURLResources(resolvedDefaultBrowserBundleID: bundleID)
        }
        return []
    }

    private func saveProtectedBundleIDs() {
        let custom = protectedBundleIDs
            .subtracting(Self.defaultProtectedBundleIDs)
            .subtracting(Self.currentAppBundleIDs())
            .sorted()
        UserDefaults.standard.set(custom, forKey: Self.protectedBundleIDsKey)
    }

    static func currentAppBundleIDs() -> Set<String> {
        var ids: Set<String> = ["com.studyboxes.StudyBoxes"]
        if let currentBundleID = Bundle.main.bundleIdentifier {
            ids.insert(currentBundleID)
        }
        return ids
    }

    static func isCurrentApplication(bundleID: String? = nil, processIdentifier: pid_t) -> Bool {
        processIdentifier == ProcessInfo.processInfo.processIdentifier ||
            bundleID.map { currentAppBundleIDs().contains($0) } == true
    }

    static func hiddenRestoreTargets(from records: [HiddenAppRestoreRecord]) -> [HiddenAppRestoreRecord] {
        records
            .filter { !$0.wasPreviouslyHidden }
            .sorted { $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending }
    }

    private static func result(
        for app: NSRunningApplication,
        action: DistractionActionKind,
        wasRunningBeforeSession: Bool
    ) -> DistractionActionResult {
        DistractionActionResult(
            bundleID: app.bundleIdentifier ?? "unknown",
            appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown app",
            action: action,
            wasRunningBeforeSession: wasRunningBeforeSession,
            appPath: app.bundleURL?.path,
            processIdentifier: app.processIdentifier
        )
    }

    static func shouldAffectApp(
        bundleID: String,
        processIdentifier: pid_t,
        activationPolicy: NSApplication.ActivationPolicy,
        allowedBundleIDs: Set<String>,
        protectedBundleIDs: Set<String>
    ) -> Bool {
        activationPolicy == .regular &&
            !allowedBundleIDs.contains(bundleID) &&
            !protectedBundleIDs.contains(bundleID) &&
            !isCurrentApplication(bundleID: bundleID, processIdentifier: processIdentifier)
    }
}

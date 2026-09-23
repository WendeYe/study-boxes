import Foundation
import SwiftData

enum SessionRestoreSnapshotStatus: String, CaseIterable {
    case pending
    case restored
    case partiallyRestored
    case restoreFailed
    case dismissed
}

enum SessionRestoreAppPolicy: String, CaseIterable {
    case observeOnly
    case restoreIfAffected
    case doNotRestore
}

enum SessionRestoreAppAction: String, CaseIterable {
    case none
    case hidden
    case terminateRequested
    case terminateFailedHiddenFallback
    case blockedNewLaunch
}

@Model
final class SessionRestoreSnapshot: Identifiable {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID?
    var boxID: UUID?
    var statusRawValue: String
    var createdAt: Date
    var restoredAt: Date?
    var dismissedAt: Date?
    var lastMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \SessionRestoreApp.snapshot)
    var apps: [SessionRestoreApp]

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        boxID: UUID? = nil,
        status: SessionRestoreSnapshotStatus = .pending,
        createdAt: Date = .now,
        restoredAt: Date? = nil,
        dismissedAt: Date? = nil,
        lastMessage: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.boxID = boxID
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.restoredAt = restoredAt
        self.dismissedAt = dismissedAt
        self.lastMessage = lastMessage
        self.apps = []
    }

    var status: SessionRestoreSnapshotStatus {
        get { SessionRestoreSnapshotStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var hasPendingRestore: Bool {
        status == .pending || status == .partiallyRestored || status == .restoreFailed
    }

    func markRestored(message: String?) {
        status = .restored
        restoredAt = .now
        lastMessage = message
    }

    func markPartial(message: String?) {
        status = .partiallyRestored
        restoredAt = .now
        lastMessage = message
    }

    func markFailed(message: String?) {
        status = .restoreFailed
        restoredAt = .now
        lastMessage = message
    }

    func dismiss() {
        status = .dismissed
        dismissedAt = .now
    }
}

@Model
final class SessionRestoreApp: Identifiable {
    @Attribute(.unique) var id: UUID
    var snapshot: SessionRestoreSnapshot?
    var bundleID: String
    var appName: String
    var appPath: String?
    var processIdentifier: Int?
    var wasRunningBeforeSession: Bool
    var restorePolicyRawValue: String
    var actionRawValue: String
    var affectedAt: Date?
    var restoredAt: Date?
    var lastMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \SessionRestoreWindow.app)
    var windows: [SessionRestoreWindow]

    init(
        id: UUID = UUID(),
        snapshot: SessionRestoreSnapshot? = nil,
        bundleID: String,
        appName: String,
        appPath: String? = nil,
        processIdentifier: Int? = nil,
        wasRunningBeforeSession: Bool = true,
        restorePolicy: SessionRestoreAppPolicy = .observeOnly,
        action: SessionRestoreAppAction = .none,
        affectedAt: Date? = nil,
        restoredAt: Date? = nil,
        lastMessage: String? = nil
    ) {
        self.id = id
        self.snapshot = snapshot
        self.bundleID = bundleID
        self.appName = appName
        self.appPath = appPath
        self.processIdentifier = processIdentifier
        self.wasRunningBeforeSession = wasRunningBeforeSession
        self.restorePolicyRawValue = restorePolicy.rawValue
        self.actionRawValue = action.rawValue
        self.affectedAt = affectedAt
        self.restoredAt = restoredAt
        self.lastMessage = lastMessage
        self.windows = []
    }

    var restorePolicy: SessionRestoreAppPolicy {
        get { SessionRestoreAppPolicy(rawValue: restorePolicyRawValue) ?? .observeOnly }
        set { restorePolicyRawValue = newValue.rawValue }
    }

    var action: SessionRestoreAppAction {
        get { SessionRestoreAppAction(rawValue: actionRawValue) ?? .none }
        set { actionRawValue = newValue.rawValue }
    }

    var shouldRestore: Bool {
        wasRunningBeforeSession &&
            restorePolicy == .restoreIfAffected &&
            action != .blockedNewLaunch
    }

    func markAffected(action: SessionRestoreAppAction) {
        self.action = action
        restorePolicy = action == .blockedNewLaunch ? .doNotRestore : .restoreIfAffected
        affectedAt = .now
    }
}

@Model
final class SessionRestoreWindow: Identifiable {
    @Attribute(.unique) var id: UUID
    var app: SessionRestoreApp?
    var title: String?
    var windowNumber: Int?
    var axRole: String?
    var axSubrole: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var screenFrameX: Double?
    var screenFrameY: Double?
    var screenFrameWidth: Double?
    var screenFrameHeight: Double?
    var visibleFrameX: Double?
    var visibleFrameY: Double?
    var visibleFrameWidth: Double?
    var visibleFrameHeight: Double?
    var screenIdentifier: String?
    var orderIndex: Int
    var isMinimized: Bool
    var isFullScreen: Bool

    init(
        id: UUID = UUID(),
        app: SessionRestoreApp? = nil,
        title: String? = nil,
        windowNumber: Int? = nil,
        axRole: String? = nil,
        axSubrole: String? = nil,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        screenFrameX: Double? = nil,
        screenFrameY: Double? = nil,
        screenFrameWidth: Double? = nil,
        screenFrameHeight: Double? = nil,
        visibleFrameX: Double? = nil,
        visibleFrameY: Double? = nil,
        visibleFrameWidth: Double? = nil,
        visibleFrameHeight: Double? = nil,
        screenIdentifier: String? = nil,
        orderIndex: Int = 0,
        isMinimized: Bool = false,
        isFullScreen: Bool = false
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.windowNumber = windowNumber
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.screenFrameX = screenFrameX
        self.screenFrameY = screenFrameY
        self.screenFrameWidth = screenFrameWidth
        self.screenFrameHeight = screenFrameHeight
        self.visibleFrameX = visibleFrameX
        self.visibleFrameY = visibleFrameY
        self.visibleFrameWidth = visibleFrameWidth
        self.visibleFrameHeight = visibleFrameHeight
        self.screenIdentifier = screenIdentifier
        self.orderIndex = orderIndex
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
    }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

import Foundation
import SwiftData

enum StudyBoxType: String, CaseIterable, Identifiable {
    case course
    case exam
    case assignment
    case topic
    case project
    case language
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .course: "Course"
        case .exam: "Exam"
        case .assignment: "Assignment"
        case .topic: "Topic"
        case .project: "Project"
        case .language: "Language"
        case .other: "Other"
        }
    }
}

enum StudyFocusMode: String, CaseIterable, Identifiable {
    case off
    case hideApps
    case quitApps
    case strictFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .hideApps: "Hide Apps"
        case .quitApps: "Quit Apps"
        case .strictFocus: "Strict Focus"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Study Boxes will leave other apps alone."
        case .hideApps:
            return "Hide unrelated apps during the session, then show them again when you finish."
        case .quitApps:
            return "Ask unrelated apps to quit, then reopen affected apps and restore their windows when you finish."
        case .strictFocus:
            return "Ask unrelated apps to quit, block newly opened distractions, then restore affected windows when you finish."
        }
    }

    var systemImage: String {
        switch self {
        case .off: "circle"
        case .hideApps: "eye.slash"
        case .quitApps: "xmark.app"
        case .strictFocus: "lock.shield"
        }
    }

    var requiresAccessibilityForRestore: Bool {
        self == .quitApps || self == .strictFocus
    }

    var hideDistractions: Bool { self == .hideApps }
    var quitDistractions: Bool { self == .quitApps || self == .strictFocus }
    var enforceFocus: Bool { self == .strictFocus }
}

@Model
final class StudyBox: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var courseName: String?
    var icon: String
    var colorHex: String
    var examDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    @Relationship(deleteRule: .cascade, inverse: \StudyResource.box)
    var resources: [StudyResource]
    @Relationship(deleteRule: .cascade, inverse: \StudyTask.box)
    var tasks: [StudyTask]
    @Relationship(deleteRule: .cascade, inverse: \StudySession.box)
    var sessions: [StudySession]
    @Relationship(deleteRule: .cascade, inverse: \WindowLayout.box)
    var windowLayouts: [WindowLayout]
    var hideDistractionsOnSessionStart: Bool
    var quitDistractionsOnSessionStart: Bool = false
    var enforceFocusOnSessionStart: Bool = false
    var focusModeRawValue: String?
    var skipFocusQuitConfirmation: Bool = false
    var isPinnedToMenuBar: Bool = false
    var restoreWindowLayoutOnSessionStart: Bool
    var openResourcesOnSessionStart: Bool
    var keepDisplayAwakeDuringSessions: Bool?
    var defaultSessionMinutes: Int
    var prepareDesktopSpacesOnSessionStart: Bool = false
    var minimumDesktopSpaces: Int = 1

    init(
        id: UUID = UUID(),
        name: String,
        type: StudyBoxType = .course,
        courseName: String? = nil,
        icon: String = "books.vertical",
        colorHex: String = "#3B82F6",
        examDate: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false,
        hideDistractionsOnSessionStart: Bool = false,
        quitDistractionsOnSessionStart: Bool = false,
        enforceFocusOnSessionStart: Bool = false,
        focusMode: StudyFocusMode? = nil,
        skipFocusQuitConfirmation: Bool = false,
        isPinnedToMenuBar: Bool = false,
        restoreWindowLayoutOnSessionStart: Bool = false,
        openResourcesOnSessionStart: Bool = true,
        keepDisplayAwakeDuringSessions: Bool = true,
        defaultSessionMinutes: Int = 50,
        prepareDesktopSpacesOnSessionStart: Bool = false,
        minimumDesktopSpaces: Int = 1
    ) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.courseName = courseName
        self.icon = icon
        self.colorHex = colorHex
        self.examDate = examDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.resources = []
        self.tasks = []
        self.sessions = []
        self.windowLayouts = []
        self.hideDistractionsOnSessionStart = hideDistractionsOnSessionStart
        self.quitDistractionsOnSessionStart = quitDistractionsOnSessionStart
        self.enforceFocusOnSessionStart = enforceFocusOnSessionStart
        self.focusModeRawValue = focusMode?.rawValue
        self.skipFocusQuitConfirmation = skipFocusQuitConfirmation
        self.isPinnedToMenuBar = isPinnedToMenuBar
        self.restoreWindowLayoutOnSessionStart = restoreWindowLayoutOnSessionStart
        self.openResourcesOnSessionStart = openResourcesOnSessionStart
        self.keepDisplayAwakeDuringSessions = keepDisplayAwakeDuringSessions
        self.defaultSessionMinutes = defaultSessionMinutes
        self.prepareDesktopSpacesOnSessionStart = prepareDesktopSpacesOnSessionStart
        self.minimumDesktopSpaces = Self.clampedMinimumDesktopSpaces(minimumDesktopSpaces)
    }

    var type: StudyBoxType {
        get { StudyBoxType(rawValue: typeRawValue) ?? .course }
        set {
            typeRawValue = newValue.rawValue
            touch()
        }
    }

    var focusMode: StudyFocusMode {
        get {
            if let focusModeRawValue,
               let stored = StudyFocusMode(rawValue: focusModeRawValue) {
                return stored
            }
            if enforceFocusOnSessionStart { return .strictFocus }
            if quitDistractionsOnSessionStart { return .quitApps }
            if hideDistractionsOnSessionStart { return .hideApps }
            return .off
        }
        set {
            focusModeRawValue = newValue.rawValue
            hideDistractionsOnSessionStart = newValue.hideDistractions
            quitDistractionsOnSessionStart = newValue.quitDistractions
            enforceFocusOnSessionStart = newValue.enforceFocus
            touch()
        }
    }

    func update(
        name: String,
        type: StudyBoxType,
        courseName: String?,
        icon: String,
        colorHex: String,
        examDate: Date?,
        defaultSessionMinutes: Int,
        openResourcesOnSessionStart: Bool,
        hideDistractionsOnSessionStart: Bool,
        quitDistractionsOnSessionStart: Bool,
        enforceFocusOnSessionStart: Bool,
        restoreWindowLayoutOnSessionStart: Bool,
        keepDisplayAwakeDuringSessions: Bool,
        prepareDesktopSpacesOnSessionStart: Bool = false,
        minimumDesktopSpaces: Int = 1,
        focusMode: StudyFocusMode? = nil
    ) {
        self.name = name
        self.typeRawValue = type.rawValue
        self.courseName = courseName
        self.icon = icon
        self.colorHex = colorHex
        self.examDate = examDate
        self.defaultSessionMinutes = defaultSessionMinutes
        self.openResourcesOnSessionStart = openResourcesOnSessionStart
        let resolvedFocusMode = focusMode ?? Self.focusMode(
            hideDistractions: hideDistractionsOnSessionStart,
            quitDistractions: quitDistractionsOnSessionStart,
            enforceFocus: enforceFocusOnSessionStart
        )
        self.focusModeRawValue = resolvedFocusMode.rawValue
        self.hideDistractionsOnSessionStart = resolvedFocusMode.hideDistractions
        self.quitDistractionsOnSessionStart = resolvedFocusMode.quitDistractions
        self.enforceFocusOnSessionStart = resolvedFocusMode.enforceFocus
        self.restoreWindowLayoutOnSessionStart = restoreWindowLayoutOnSessionStart
        self.keepDisplayAwakeDuringSessions = keepDisplayAwakeDuringSessions
        self.prepareDesktopSpacesOnSessionStart = prepareDesktopSpacesOnSessionStart
        self.minimumDesktopSpaces = Self.clampedMinimumDesktopSpaces(minimumDesktopSpaces)
        touch()
    }

    static func focusMode(hideDistractions: Bool, quitDistractions: Bool, enforceFocus: Bool) -> StudyFocusMode {
        if enforceFocus { return .strictFocus }
        if quitDistractions { return .quitApps }
        if hideDistractions { return .hideApps }
        return .off
    }

    static func clampedMinimumDesktopSpaces(_ value: Int) -> Int {
        min(max(value, 1), 8)
    }

    func archive() {
        isArchived = true
        touch()
    }

    func restore() {
        isArchived = false
        touch()
    }

    func touch() {
        updatedAt = .now
    }
}

import Combine
import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case timer
    case boxNameAndTimer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .timer: "Timer"
        case .boxNameAndTimer: "Box + timer"
        }
    }
}

enum WellnessReminderInterval: Int, CaseIterable, Identifiable {
    case twenty = 20
    case twentyFive = 25
    case thirty = 30
    case fortyFive = 45

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) min"
    }
}

enum WellnessReminderIntervalRange {
    static let minimum = 5
    static let maximum = 180
    static let fallback = 25
    static let allowedRange = minimum...maximum
}

@MainActor
final class UserPreferencesService: ObservableObject {
    static let shared = UserPreferencesService()

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeKey)
            MenuBarTimerController.shared.updateDisplayMode(menuBarDisplayMode)
        }
    }

    @Published var wellnessRemindersEnabled: Bool {
        didSet {
            userDefaults.set(wellnessRemindersEnabled, forKey: Self.wellnessRemindersEnabledKey)
        }
    }

    @Published var wellnessReminderIntervalMinutes: Int {
        didSet {
            let sanitized = Self.sanitizedWellnessInterval(wellnessReminderIntervalMinutes)
            if sanitized != wellnessReminderIntervalMinutes {
                wellnessReminderIntervalMinutes = sanitized
                return
            }
            userDefaults.set(wellnessReminderIntervalMinutes, forKey: Self.wellnessReminderIntervalMinutesKey)
        }
    }

    private static let menuBarDisplayModeKey = "menuBarDisplayMode"
    private static let wellnessRemindersEnabledKey = "wellnessRemindersEnabled"
    private static let wellnessReminderIntervalMinutesKey = "wellnessReminderIntervalMinutes"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedValue = userDefaults.string(forKey: Self.menuBarDisplayModeKey)
        self.menuBarDisplayMode = storedValue
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .timer
        if userDefaults.object(forKey: Self.wellnessRemindersEnabledKey) == nil {
            self.wellnessRemindersEnabled = true
        } else {
            self.wellnessRemindersEnabled = userDefaults.bool(forKey: Self.wellnessRemindersEnabledKey)
        }
        let storedInterval = userDefaults.integer(forKey: Self.wellnessReminderIntervalMinutesKey)
        self.wellnessReminderIntervalMinutes = Self.sanitizedWellnessInterval(storedInterval == 0 ? WellnessReminderIntervalRange.fallback : storedInterval)
    }

    private static func sanitizedWellnessInterval(_ value: Int) -> Int {
        min(max(value, WellnessReminderIntervalRange.minimum), WellnessReminderIntervalRange.maximum)
    }
}

enum SessionPreset {
    static let defaultMinutes = [25, 50, 90]
}

struct WellnessPrompt: Equatable {
    var title: String
    var body: String
}

enum WellnessReminderService {
    static let promptTitles = [
        "Take a quick reset?",
        "Check posture and breathe?",
        "Time for a small break?"
    ]

    static func recordTaskCompletionIfNeeded(
        for session: StudySession,
        now: Date = .now,
        remindersEnabled: Bool,
        intervalMinutes: Int
    ) -> WellnessPrompt? {
        guard remindersEnabled, session.pendingWellnessPromptAt == nil else {
            return nil
        }

        let anchorDate = max(session.startedAt, session.lastWellnessPromptAt ?? session.startedAt)
        guard now.timeIntervalSince(anchorDate) >= Double(intervalMinutes * 60) else {
            return nil
        }

        session.lastWellnessPromptAt = now
        session.pendingWellnessPromptAt = now
        session.wellnessPromptCount += 1
        return prompt(for: session)
    }

    static func prompt(for session: StudySession) -> WellnessPrompt? {
        guard session.pendingWellnessPromptAt != nil else { return nil }
        let index = max(0, session.wellnessPromptCount - 1) % promptTitles.count
        return WellnessPrompt(
            title: promptTitles[index],
            body: "Stand up, reset your posture, or take a short break before the next task."
        )
    }

    static func clearPendingPrompt(for session: StudySession) {
        session.pendingWellnessPromptAt = nil
    }
}

struct StudyResumeSnapshot: Equatable {
    var boxID: UUID
    var boxName: String
    var lastStudiedAt: Date
    var lastDurationMinutes: Int
    var unfinishedTaskCount: Int
    var enabledResourceCount: Int
    var nextTaskTitle: String?
    var enabledResourceTitles: [String]
    var notesPreview: String?
}

struct StudyProgressSummary: Equatable {
    var totalMinutes: Int
    var weekMinutes: Int
    var monthMinutes: Int
    var completedTasksThisWeek: Int
    var completedTasksThisMonth: Int
    var lastStudiedAt: Date?
    var averageSessionMinutes: Int
}

enum StudyResumeService {
    static func mostRecentlyStudiedBox(from boxes: [StudyBox], sessions: [StudySession]) -> StudyBox? {
        let activeBoxes = boxes.filter { !$0.isArchived }
        let activeBoxIDs = Set(activeBoxes.map(\.id))
        var latest: (session: StudySession, box: StudyBox)?

        for session in sessions {
            guard let box = session.box,
                  activeBoxIDs.contains(box.id) else {
                continue
            }
            if let currentLatest = latest {
                if session.startedAt > currentLatest.session.startedAt {
                    latest = (session, box)
                }
            } else {
                latest = (session, box)
            }
        }

        if let latest {
            return latest.box
        }

        return activeBoxes.max { $0.updatedAt < $1.updatedAt }
    }

    static func snapshot(for box: StudyBox, sessions: [StudySession]) -> StudyResumeSnapshot? {
        guard let lastSession = sessions.lazy
            .filter({ $0.box?.id == box.id })
            .max(by: { $0.startedAt < $1.startedAt }) else {
            return nil
        }

        var enabledResourceCount = 0
        var enabledResources: [StudyResource] = []
        for resource in box.resources where resource.enabledByDefault {
            enabledResourceCount += 1
            enabledResources.append(resource)
        }

        return StudyResumeSnapshot(
            boxID: box.id,
            boxName: box.name,
            lastStudiedAt: lastSession.startedAt,
            lastDurationMinutes: lastSession.durationMinutes,
            unfinishedTaskCount: box.tasks.filter { $0.status != .done }.count,
            enabledResourceCount: enabledResourceCount,
            nextTaskTitle: nextSuggestedTask(for: box)?.title,
            enabledResourceTitles: enabledResources
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(\.title),
            notesPreview: lastSession.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
    }

    static func nextSuggestedTask(for box: StudyBox) -> StudyTask? {
        TaskManager.sorted(box.tasks.filter { $0.status == .pending || $0.status == .inProgress }).first
    }
}

enum StudyProgressService {
    static func summary(
        for box: StudyBox,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StudyProgressSummary {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        var completedSessionCount = 0
        var totalMinutes = 0
        var weekMinutes = 0
        var monthMinutes = 0
        var lastStudiedAt: Date?
        var completedTasksThisWeek = 0
        var completedTasksThisMonth = 0

        for session in box.sessions where session.endedAt != nil {
            let duration = session.durationMinutes
            completedSessionCount += 1
            totalMinutes += duration
            if session.startedAt >= weekStart && session.startedAt <= now {
                weekMinutes += duration
            }
            if session.startedAt >= monthStart && session.startedAt <= now {
                monthMinutes += duration
            }
            if let currentLastStudiedAt = lastStudiedAt {
                if session.startedAt > currentLastStudiedAt {
                    lastStudiedAt = session.startedAt
                }
            } else {
                lastStudiedAt = session.startedAt
            }
        }

        for task in box.tasks {
            guard let completedAt = task.completedAt else { continue }
            if completedAt >= weekStart && completedAt <= now {
                completedTasksThisWeek += 1
            }
            if completedAt >= monthStart && completedAt <= now {
                completedTasksThisMonth += 1
            }
        }

        let average = completedSessionCount == 0 ? 0 : totalMinutes / completedSessionCount

        return StudyProgressSummary(
            totalMinutes: totalMinutes,
            weekMinutes: weekMinutes,
            monthMinutes: monthMinutes,
            completedTasksThisWeek: completedTasksThisWeek,
            completedTasksThisMonth: completedTasksThisMonth,
            lastStudiedAt: lastStudiedAt,
            averageSessionMinutes: average
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

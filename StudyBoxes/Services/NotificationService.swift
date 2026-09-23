import Foundation
import AppKit
import UserNotifications

struct ReminderScheduleResult {
    let scheduledCount: Int
    let removedStaleCount: Int
    let authorized: Bool
    let pendingDueDateCount: Int
    var permissionDescription: String?

    var message: String {
        if !authorized {
            return permissionDescription ?? "Turn on notifications in System Settings to get Study Boxes alerts."
        }
        if scheduledCount == 0 {
            if pendingDueDateCount == 0 {
                return "There are no active Study Box dates or pending task due dates to schedule."
            }
            return "No reminder times are left for \(pendingDueDateCount) pending due dates."
        }
        if removedStaleCount > 0 {
            return "Scheduled \(scheduledCount) deadline reminders and removed \(removedStaleCount) old ones."
        }
        return "Scheduled \(scheduledCount) deadline reminders."
    }
}

struct NotificationPermissionStatus: Equatable {
    let isEnabled: Bool
    let canRequestInApp: Bool
    let description: String
    let canDeliverAlerts: Bool

    static func from(_ status: UNAuthorizationStatus) -> NotificationPermissionStatus {
        switch status {
        case .authorized, .provisional:
            return NotificationPermissionStatus(
                isEnabled: true,
                canRequestInApp: false,
                description: "Notifications are on.",
                canDeliverAlerts: true
            )
        case .notDetermined:
            return NotificationPermissionStatus(
                isEnabled: false,
                canRequestInApp: true,
                description: "Notifications have not been set up yet.",
                canDeliverAlerts: false
            )
        case .denied:
            return NotificationPermissionStatus(
                isEnabled: false,
                canRequestInApp: false,
                description: "Notifications are blocked in System Settings.",
                canDeliverAlerts: false
            )
        @unknown default:
            return NotificationPermissionStatus(
                isEnabled: false,
                canRequestInApp: false,
                description: "Study Boxes could not read notification status from macOS.",
                canDeliverAlerts: false
            )
        }
    }

    static func from(_ settings: UNNotificationSettings) -> NotificationPermissionStatus {
        var status = from(settings.authorizationStatus)
        guard status.isEnabled else { return status }

        if settings.alertSetting == .disabled {
            status = NotificationPermissionStatus(
                isEnabled: true,
                canRequestInApp: false,
                description: "Notifications are allowed, but banners are turned off for Study Boxes.",
                canDeliverAlerts: false
            )
        }
        return status
    }
}

enum NotificationService {
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func openNotificationSettings() {
        let notificationURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")

        if let notificationURL, NSWorkspace.shared.open(notificationURL) {
            return
        }
        if let fallbackURL {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    static func scheduleDeadlineReminders(for boxes: [StudyBox]) async -> ReminderScheduleResult {
        let taskCandidates = boxes
            .flatMap(\.tasks)
            .filter { $0.status != .done && $0.dueDate != nil }
            .map {
                ReminderCandidate(
                    identifier: "task-\($0.id.uuidString)",
                    title: $0.title,
                    body: $0.box?.name ?? "Study task",
                    dueDate: $0.dueDate ?? .distantFuture
                )
            }

        let boxCandidates = boxes
            .filter { !$0.isArchived }
            .compactMap { box -> ReminderCandidate? in
                guard let examDate = box.examDate else { return nil }
                return ReminderCandidate(
                    identifier: "box-\(box.id.uuidString)",
                    title: box.name,
                    body: box.courseName ?? box.type.title,
                    dueDate: examDate
                )
            }

        return await scheduleDeadlineReminders(for: taskCandidates + boxCandidates)
    }

    static func scheduleDeadlineReminders(for tasks: [StudyTask]) async -> ReminderScheduleResult {
        let candidates = tasks
            .filter { $0.status != .done && $0.dueDate != nil }
            .map {
                ReminderCandidate(
                    identifier: "task-\($0.id.uuidString)",
                    title: $0.title,
                    body: $0.box?.name ?? "Study task",
                    dueDate: $0.dueDate ?? .distantFuture
                )
            }

        return await scheduleDeadlineReminders(for: candidates)
    }

    private static func scheduleDeadlineReminders(for candidates: [ReminderCandidate]) async -> ReminderScheduleResult {
        let center = UNUserNotificationCenter.current()
        var status = NotificationPermissionStatus.from(await center.notificationSettings())
        let authorized: Bool

        if status.canRequestInApp {
            _ = await requestPermission()
            status = await permissionStatus()
        }
        authorized = status.canDeliverAlerts

        guard authorized else {
            return ReminderScheduleResult(
                scheduledCount: 0,
                removedStaleCount: 0,
                authorized: false,
                pendingDueDateCount: candidates.count,
                permissionDescription: status.description
            )
        }

        let removedStaleCount = await removeStaleDeadlineReminders(for: candidates, center: center)
        var scheduledCount = 0
        for candidate in candidates {
            if await schedule(candidate: candidate, daysBefore: 1, center: center) {
                scheduledCount += 1
            }
            if await schedule(candidate: candidate, daysBefore: 0, center: center) {
                scheduledCount += 1
            }
        }
        return ReminderScheduleResult(
            scheduledCount: scheduledCount,
            removedStaleCount: removedStaleCount,
            authorized: true,
            pendingDueDateCount: candidates.count
        )
    }

    static func authorizationStatusDescription() async -> String {
        await permissionStatus().description
    }

    static func permissionStatus() async -> NotificationPermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermissionStatus.from(settings)
    }

    static func testNotificationFeedback(
        status: NotificationPermissionStatus,
        didSchedule: Bool,
        schedulingError: Error?
    ) -> String {
        if let schedulingError {
            return "Could not schedule the test notification: \(schedulingError.localizedDescription)"
        }
        guard status.canDeliverAlerts else {
            if status.isEnabled {
                return "\(status.description) Open Notification Settings and turn on banners for Study Boxes."
            }
            return status.description
        }
        return didSchedule
            ? "Test notification scheduled. It should appear in a couple of seconds."
            : "Could not schedule the test notification."
    }

    static func notifyDeadlineChanges(newCount: Int, updatedCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard isAuthorized(settings.authorizationStatus) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Study Boxes calendar updated"
        content.body = "\(newCount) new deadlines, \(updatedCount) changed deadlines."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "deadline-changes-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func notifySessionRestoreIfNeeded(summary: String, hasIssues: Bool, appIsActive: Bool) async {
        guard hasIssues || !appIsActive else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard isAuthorized(settings.authorizationStatus) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = hasIssues ? "Study Boxes restored apps with issues" : "Study session ended"
        content.body = summary
        content.sound = hasIssues ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "session-restore-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func notifyWellnessPromptIfNeeded(_ prompt: WellnessPrompt, appIsActive: Bool) async {
        guard !appIsActive else { return }

        let center = UNUserNotificationCenter.current()
        var status = await permissionStatus()
        if status.canRequestInApp {
            _ = await requestPermission()
            status = await permissionStatus()
        }
        guard status.canDeliverAlerts else { return }

        let content = UNMutableNotificationContent()
        content.title = prompt.title
        content.body = prompt.body
        content.sound = nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "wellness-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static func schedule(candidate: ReminderCandidate, daysBefore: Int, center: UNUserNotificationCenter) async -> Bool {
        guard let triggerDate = reminderDate(for: candidate.dueDate, daysBefore: daysBefore),
              triggerDate > .now else { return false }

        let content = UNMutableNotificationContent()
        content.title = daysBefore == 0 ? "Deadline today" : "Deadline tomorrow"
        content.body = candidate.body.isEmpty ? candidate.title : "\(candidate.title) - \(candidate.body)"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "studyboxes-deadline-\(candidate.identifier)-\(daysBefore)", content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private static func removeStaleDeadlineReminders(for candidates: [ReminderCandidate], center: UNUserNotificationCenter) async -> Int {
        let pendingRequests = await center.pendingNotificationRequests()
        let validPrefixes = Set(candidates.map { "studyboxes-deadline-\($0.identifier)-" })
        let staleIDs = pendingRequests.compactMap { request -> String? in
            guard request.identifier.hasPrefix("studyboxes-deadline-") || request.identifier.hasPrefix("task-") else {
                return nil
            }
            if request.identifier.hasPrefix("task-") {
                return request.identifier
            }
            return validPrefixes.contains(where: { request.identifier.hasPrefix($0) }) ? nil : request.identifier
        }

        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }
        return staleIDs.count
    }

    static func reminderDate(for dueDate: Date, daysBefore: Int, now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let isDateOnly = calendar.component(.hour, from: dueDate) == 0 &&
            calendar.component(.minute, from: dueDate) == 0 &&
            calendar.component(.second, from: dueDate) == 0

        let baseDate: Date
        if isDateOnly {
            var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
            components.hour = 9
            components.minute = 0
            baseDate = calendar.date(from: components) ?? dueDate
        } else {
            baseDate = dueDate
        }

        let triggerDate = calendar.date(byAdding: .day, value: -daysBefore, to: baseDate)

        if daysBefore == 0,
           let triggerDate,
           calendar.isDate(triggerDate, inSameDayAs: now),
           triggerDate <= now,
           dueDate >= calendar.startOfDay(for: now) {
            return now.addingTimeInterval(60)
        }

        return triggerDate
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }
}

private struct ReminderCandidate {
    let identifier: String
    let title: String
    let body: String
    let dueDate: Date
}

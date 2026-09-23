import Foundation

enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case pending
    case done
    case highPriority

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .pending: "Pending"
        case .done: "Done"
        case .highPriority: "High priority"
        }
    }
}

enum TaskManager {
    static func filteredTasks(_ tasks: [StudyTask], filter: TaskFilter) -> [StudyTask] {
        let now = Date.now
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let upcomingLimit = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        return sorted(tasks.filter { task in
            switch filter {
            case .all:
                true
            case .today:
                isTodayCandidate(task, calendar: calendar, startOfToday: startOfToday, upcomingLimit: upcomingLimit)
            case .pending:
                task.status == .pending || task.status == .inProgress
            case .done:
                task.status == .done
            case .highPriority:
                task.priority >= 3 && task.status != .done
            }
        })
    }

    static func searchedTasks(_ tasks: [StudyTask], query: String) -> [StudyTask] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted(tasks) }
        return sorted(tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed) ||
                task.details?.localizedCaseInsensitiveContains(trimmed) == true ||
                task.unit?.localizedCaseInsensitiveContains(trimmed) == true ||
                task.subtasks.contains { $0.title.localizedCaseInsensitiveContains(trimmed) }
        })
    }

    static func sorted(_ tasks: [StudyTask]) -> [StudyTask] {
        tasks.sorted { left, right in
            let leftOrder = left.orderIndex ?? 0
            let rightOrder = right.orderIndex ?? 0
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }

            let leftStatusRank = statusRank(left.status)
            let rightStatusRank = statusRank(right.status)
            if leftStatusRank != rightStatusRank {
                return leftStatusRank < rightStatusRank
            }

            if left.priority != right.priority {
                return left.priority > right.priority
            }

            switch (left.dueDate, right.dueDate) {
            case let (leftDate?, rightDate?):
                return leftDate < rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.createdAt > right.createdAt
            }
        }
    }

    static func normalizeOrder(_ tasks: [StudyTask]) {
        for (index, task) in tasks.sorted(by: { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }).enumerated() {
            task.orderIndex = index
        }
    }

    private static func isTodayCandidate(
        _ task: StudyTask,
        calendar: Calendar,
        startOfToday: Date,
        upcomingLimit: Date
    ) -> Bool {
        guard task.status == .pending || task.status == .inProgress else { return false }

        if let dueDate = task.dueDate {
            if calendar.isDate(dueDate, inSameDayAs: startOfToday) || dueDate < startOfToday {
                return true
            }

            if dueDate <= upcomingLimit {
                return true
            }
        }

        return task.priority >= 3
    }

    private static func statusRank(_ status: StudyTaskStatus) -> Int {
        switch status {
        case .inProgress: 0
        case .pending: 1
        case .skipped: 2
        case .done: 3
        }
    }
}

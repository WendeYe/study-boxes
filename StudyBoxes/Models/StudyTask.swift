import Foundation
import SwiftData

enum StudyTaskType: String, CaseIterable, Identifiable {
    case exercise
    case theory
    case pastExam
    case mockExam
    case coding
    case review
    case flashcards
    case notes
    case assignment
    case quiz
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exercise: "Exercise"
        case .theory: "Theory"
        case .pastExam: "Past exam"
        case .mockExam: "Mock exam"
        case .coding: "Coding"
        case .review: "Review"
        case .flashcards: "Flashcards"
        case .notes: "Notes"
        case .assignment: "Assignment"
        case .quiz: "Quiz"
        case .other: "Other"
        }
    }
}

enum StudyTaskStatus: String, CaseIterable, Identifiable {
    case pending
    case inProgress
    case done
    case skipped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: "Pending"
        case .inProgress: "In progress"
        case .done: "Done"
        case .skipped: "Skipped"
        }
    }
}

@Model
final class StudyTask: Identifiable {
    @Attribute(.unique) var id: UUID
    var box: StudyBox?
    var title: String
    var details: String?
    var typeRawValue: String
    var statusRawValue: String
    var priority: Int
    var estimatedMinutes: Int?
    var dueDate: Date?
    var unit: String?
    var linkedResourceIDs: [UUID]
    var orderIndex: Int?
    var subtasksJSON: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        box: StudyBox? = nil,
        title: String,
        details: String? = nil,
        type: StudyTaskType = .exercise,
        status: StudyTaskStatus = .pending,
        priority: Int = 1,
        estimatedMinutes: Int? = nil,
        dueDate: Date? = nil,
        unit: String? = nil,
        linkedResourceIDs: [UUID] = [],
        orderIndex: Int = 0,
        subtasks: [StudySubtask] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.box = box
        self.title = title
        self.details = details
        self.typeRawValue = type.rawValue
        self.statusRawValue = status.rawValue
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
        self.unit = unit
        self.linkedResourceIDs = linkedResourceIDs
        self.orderIndex = orderIndex
        self.subtasksJSON = Self.encodeSubtasks(subtasks)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    var type: StudyTaskType {
        get { StudyTaskType(rawValue: typeRawValue) ?? .exercise }
        set {
            typeRawValue = newValue.rawValue
            touch()
        }
    }

    var status: StudyTaskStatus {
        get { StudyTaskStatus(rawValue: statusRawValue) ?? .pending }
        set {
            statusRawValue = newValue.rawValue
            completedAt = newValue == .done ? .now : nil
            touch()
        }
    }

    func update(
        title: String,
        details: String?,
        type: StudyTaskType,
        status: StudyTaskStatus,
        priority: Int,
        estimatedMinutes: Int?,
        dueDate: Date?,
        unit: String?,
        linkedResourceIDs: [UUID],
        subtasks: [StudySubtask]? = nil
    ) {
        self.title = title
        self.details = details
        self.typeRawValue = type.rawValue
        self.statusRawValue = status.rawValue
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
        self.unit = unit
        self.linkedResourceIDs = linkedResourceIDs
        if let subtasks {
            self.subtasks = subtasks
        }
        self.completedAt = status == .done ? completedAt ?? .now : nil
        touch()
    }

    func markDone() {
        status = .done
    }

    func markSkipped() {
        status = .skipped
    }

    func markPending() {
        status = .pending
    }

    func touch() {
        updatedAt = .now
        box?.touch()
    }

    var subtasks: [StudySubtask] {
        get { Self.decodeSubtasks(subtasksJSON ?? "") }
        set {
            subtasksJSON = Self.encodeSubtasks(newValue)
            touch()
        }
    }

    static func decodeSubtasks(_ json: String) -> [StudySubtask] {
        guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
        return (try? JSONDecoder().decode([StudySubtask].self, from: data)) ?? []
    }

    static func encodeSubtasks(_ subtasks: [StudySubtask]) -> String {
        guard !subtasks.isEmpty,
              let data = try? JSONEncoder().encode(subtasks),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}

struct StudySubtask: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

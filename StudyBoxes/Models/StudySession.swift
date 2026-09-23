import Foundation
import SwiftData

@Model
final class StudySession: Identifiable {
    @Attribute(.unique) var id: UUID
    var box: StudyBox?
    var startedAt: Date
    var endedAt: Date?
    var plannedMinutes: Int
    var notes: String?
    var completedTaskIDs: [UUID]
    var skippedTaskIDs: [UUID]
    var lastWellnessPromptAt: Date?
    var pendingWellnessPromptAt: Date?
    var wellnessPromptCount: Int = 0
    var createdAt: Date

    init(
        id: UUID = UUID(),
        box: StudyBox? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        plannedMinutes: Int,
        notes: String? = nil,
        completedTaskIDs: [UUID] = [],
        skippedTaskIDs: [UUID] = [],
        lastWellnessPromptAt: Date? = nil,
        pendingWellnessPromptAt: Date? = nil,
        wellnessPromptCount: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.box = box
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
        self.notes = notes
        self.completedTaskIDs = completedTaskIDs
        self.skippedTaskIDs = skippedTaskIDs
        self.lastWellnessPromptAt = lastWellnessPromptAt
        self.pendingWellnessPromptAt = pendingWellnessPromptAt
        self.wellnessPromptCount = wellnessPromptCount
        self.createdAt = createdAt
    }

    var durationMinutes: Int {
        let endDate = endedAt ?? .now
        return max(0, Int(endDate.timeIntervalSince(startedAt) / 60))
    }

    func markCompleted(_ taskID: UUID) {
        skippedTaskIDs.removeAll { $0 == taskID }
        if !completedTaskIDs.contains(taskID) {
            completedTaskIDs.append(taskID)
        }
    }

    func markSkipped(_ taskID: UUID) {
        completedTaskIDs.removeAll { $0 == taskID }
        if !skippedTaskIDs.contains(taskID) {
            skippedTaskIDs.append(taskID)
        }
    }

    func end(notes: String?) {
        endedAt = .now
        self.notes = notes
        pendingWellnessPromptAt = nil
    }
}

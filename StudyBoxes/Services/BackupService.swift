import Foundation
import SwiftData

struct StudyBoxesBackup: Codable {
    var boxes: [BoxBackup]
}

struct BackupImportPreview: Equatable {
    var boxCount: Int
    var resourceCount: Int
    var taskCount: Int
    var sessionCount: Int
    var duplicateBoxNames: [String]

    var summary: String {
        var parts = [
            "\(boxCount) boxes",
            "\(resourceCount) resources",
            "\(taskCount) tasks",
            "\(sessionCount) sessions"
        ]
        if !duplicateBoxNames.isEmpty {
            parts.append("possible duplicates: \(duplicateBoxNames.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }
}

enum BackupDuplicatePolicy {
    case insertCopies
    case skipMatchingNames
}

enum BackupImportError: LocalizedError, Equatable {
    case requiresPro

    var errorDescription: String? {
        switch self {
        case .requiresPro:
            return EntitlementRules.canUse(.backupImport, plan: .free).message
        }
    }
}

struct BoxBackup: Codable {
    var name: String
    var typeRawValue: String
    var courseName: String?
    var icon: String
    var colorHex: String
    var examDate: Date?
    var isArchived: Bool
    var hideDistractionsOnSessionStart: Bool
    var quitDistractionsOnSessionStart: Bool?
    var restoreWindowLayoutOnSessionStart: Bool
    var openResourcesOnSessionStart: Bool
    var keepDisplayAwakeDuringSessions: Bool?
    var defaultSessionMinutes: Int
    var prepareDesktopSpacesOnSessionStart: Bool?
    var minimumDesktopSpaces: Int?
    var resources: [ResourceBackup]
    var tasks: [TaskBackup]
    var sessions: [SessionBackup]
}

struct ResourceBackup: Codable {
    var title: String
    var typeRawValue: String
    var urlString: String
    var appBundleID: String?
    var appPath: String?
    var orderIndex: Int
    var enabledByDefault: Bool
    var targetDesktopSpace: Int?
}

struct TaskBackup: Codable {
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
    var subtasks: [StudySubtask]?
    var completedAt: Date?
}

struct SessionBackup: Codable {
    var startedAt: Date
    var endedAt: Date?
    var plannedMinutes: Int
    var notes: String?
    var completedTaskIDs: [UUID]
    var skippedTaskIDs: [UUID]
    var createdAt: Date
}

@MainActor
enum BackupService {
    static func export(boxes: [StudyBox], to url: URL) throws {
        let backup = StudyBoxesBackup(boxes: boxes.map { box in
            BoxBackup(
                name: box.name,
                typeRawValue: box.typeRawValue,
                courseName: box.courseName,
                icon: box.icon,
                colorHex: box.colorHex,
                examDate: box.examDate,
                isArchived: box.isArchived,
                hideDistractionsOnSessionStart: box.hideDistractionsOnSessionStart,
                quitDistractionsOnSessionStart: box.quitDistractionsOnSessionStart,
                restoreWindowLayoutOnSessionStart: box.restoreWindowLayoutOnSessionStart,
                openResourcesOnSessionStart: box.openResourcesOnSessionStart,
                keepDisplayAwakeDuringSessions: box.keepDisplayAwakeDuringSessions ?? true,
                defaultSessionMinutes: box.defaultSessionMinutes,
                prepareDesktopSpacesOnSessionStart: box.prepareDesktopSpacesOnSessionStart,
                minimumDesktopSpaces: box.minimumDesktopSpaces,
                resources: box.resources.map { resource in
                    ResourceBackup(
                        title: resource.title,
                        typeRawValue: resource.typeRawValue,
                        urlString: resource.urlString,
                        appBundleID: resource.appBundleID,
                        appPath: resource.appPath,
                        orderIndex: resource.orderIndex,
                        enabledByDefault: resource.enabledByDefault,
                        targetDesktopSpace: resource.targetDesktopSpace
                    )
                },
                tasks: box.tasks.map { task in
                    TaskBackup(
                        title: task.title,
                        details: task.details,
                        typeRawValue: task.typeRawValue,
                        statusRawValue: task.statusRawValue,
                        priority: task.priority,
                        estimatedMinutes: task.estimatedMinutes,
                        dueDate: task.dueDate,
                        unit: task.unit,
                        linkedResourceIDs: task.linkedResourceIDs,
                        orderIndex: task.orderIndex,
                        subtasks: task.subtasks,
                        completedAt: task.completedAt
                    )
                },
                sessions: box.sessions.map { session in
                    SessionBackup(
                        startedAt: session.startedAt,
                        endedAt: session.endedAt,
                        plannedMinutes: session.plannedMinutes,
                        notes: session.notes,
                        completedTaskIDs: session.completedTaskIDs,
                        skippedTaskIDs: session.skippedTaskIDs,
                        createdAt: session.createdAt
                    )
                }
            )
        })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: url)
    }

    static func previewImport(from url: URL, existingBoxes: [StudyBox] = []) throws -> BackupImportPreview {
        let backup = try decodeBackup(from: url)
        let existingNames = Set(existingBoxes.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let duplicateNames = backup.boxes
            .map(\.name)
            .filter { existingNames.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        return BackupImportPreview(
            boxCount: backup.boxes.count,
            resourceCount: backup.boxes.flatMap(\.resources).count,
            taskCount: backup.boxes.flatMap(\.tasks).count,
            sessionCount: backup.boxes.flatMap(\.sessions).count,
            duplicateBoxNames: Array(Set(duplicateNames)).sorted()
        )
    }

    static func `import`(
        from url: URL,
        modelContext: ModelContext,
        existingBoxes: [StudyBox] = [],
        duplicatePolicy: BackupDuplicatePolicy = .insertCopies,
        plan: EntitlementPlan? = nil
    ) throws {
        let resolvedPlan = plan ?? LicenseManager.shared.plan
        guard EntitlementRules.canUse(.backupImport, plan: resolvedPlan).isAllowed else {
            throw BackupImportError.requiresPro
        }

        let backup = try decodeBackup(from: url)
        let existingNames = Set(existingBoxes.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        try insert(backup, modelContext: modelContext, existingNames: existingNames, duplicatePolicy: duplicatePolicy)
        try modelContext.save()
    }

    private static func decodeBackup(from url: URL) throws -> StudyBoxesBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StudyBoxesBackup.self, from: Data(contentsOf: url))
    }

    private static func insert(
        _ backup: StudyBoxesBackup,
        modelContext: ModelContext,
        existingNames: Set<String>,
        duplicatePolicy: BackupDuplicatePolicy
    ) throws {
        for boxBackup in backup.boxes {
            let normalizedName = boxBackup.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if duplicatePolicy == .skipMatchingNames, existingNames.contains(normalizedName) {
                continue
            }

            let box = StudyBox(
                name: boxBackup.name,
                type: StudyBoxType(rawValue: boxBackup.typeRawValue) ?? .course,
                courseName: boxBackup.courseName,
                icon: boxBackup.icon,
                colorHex: boxBackup.colorHex,
                examDate: boxBackup.examDate,
                isArchived: boxBackup.isArchived,
                hideDistractionsOnSessionStart: boxBackup.hideDistractionsOnSessionStart,
                quitDistractionsOnSessionStart: boxBackup.quitDistractionsOnSessionStart ?? false,
                restoreWindowLayoutOnSessionStart: boxBackup.restoreWindowLayoutOnSessionStart,
                openResourcesOnSessionStart: boxBackup.openResourcesOnSessionStart,
                keepDisplayAwakeDuringSessions: boxBackup.keepDisplayAwakeDuringSessions ?? true,
                defaultSessionMinutes: boxBackup.defaultSessionMinutes,
                prepareDesktopSpacesOnSessionStart: boxBackup.prepareDesktopSpacesOnSessionStart ?? false,
                minimumDesktopSpaces: boxBackup.minimumDesktopSpaces ?? 1
            )
            modelContext.insert(box)

            for resourceBackup in boxBackup.resources {
                modelContext.insert(StudyResource(
                    box: box,
                    title: resourceBackup.title,
                    type: ResourceType(rawValue: resourceBackup.typeRawValue) ?? .website,
                    urlString: resourceBackup.urlString,
                    appBundleID: resourceBackup.appBundleID,
                    appPath: resourceBackup.appPath,
                    orderIndex: resourceBackup.orderIndex,
                    enabledByDefault: resourceBackup.enabledByDefault,
                    targetDesktopSpace: resourceBackup.targetDesktopSpace
                ))
            }

            for taskBackup in boxBackup.tasks {
                modelContext.insert(StudyTask(
                    box: box,
                    title: taskBackup.title,
                    details: taskBackup.details,
                    type: StudyTaskType(rawValue: taskBackup.typeRawValue) ?? .exercise,
                    status: StudyTaskStatus(rawValue: taskBackup.statusRawValue) ?? .pending,
                    priority: taskBackup.priority,
                    estimatedMinutes: taskBackup.estimatedMinutes,
                    dueDate: taskBackup.dueDate,
                    unit: taskBackup.unit,
                    linkedResourceIDs: taskBackup.linkedResourceIDs,
                    orderIndex: taskBackup.orderIndex ?? 0,
                    subtasks: taskBackup.subtasks ?? [],
                    completedAt: taskBackup.completedAt
                ))
            }

            for sessionBackup in boxBackup.sessions {
                modelContext.insert(StudySession(
                    box: box,
                    startedAt: sessionBackup.startedAt,
                    endedAt: sessionBackup.endedAt,
                    plannedMinutes: sessionBackup.plannedMinutes,
                    notes: sessionBackup.notes,
                    completedTaskIDs: sessionBackup.completedTaskIDs,
                    skippedTaskIDs: sessionBackup.skippedTaskIDs,
                    createdAt: sessionBackup.createdAt
                ))
            }
        }

    }
}

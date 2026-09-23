import Foundation
import SwiftData

enum StudyBoxTemplate: String, CaseIterable, Identifiable {
    case weeklyCourse
    case examPrep
    case assignment
    case codingProject
    case languageStudy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyCourse: "Weekly course"
        case .examPrep: "Exam prep"
        case .assignment: "Assignment"
        case .codingProject: "Coding project"
        case .languageStudy: "Language study"
        }
    }

    var subtitle: String {
        switch self {
        case .weeklyCourse: "Lecture notes, LMS links, and weekly review."
        case .examPrep: "Review, past papers, and a longer default session."
        case .assignment: "A due date, checklist, and hand-in materials."
        case .codingProject: "Repository, folder, and project work tasks."
        case .languageStudy: "Flashcards, listening, and regular practice."
        }
    }

    var systemImage: String {
        switch self {
        case .weeklyCourse: "books.vertical"
        case .examPrep: "graduationcap"
        case .assignment: "doc.text"
        case .codingProject: "chevron.left.forwardslash.chevron.right"
        case .languageStudy: "textformat.abc"
        }
    }

    var colorHex: String {
        switch self {
        case .weeklyCourse: "#3B82F6"
        case .examPrep: "#EF4444"
        case .assignment: "#F59E0B"
        case .codingProject: "#14B8A6"
        case .languageStudy: "#A855F7"
        }
    }

    var boxType: StudyBoxType {
        switch self {
        case .weeklyCourse: .course
        case .examPrep: .exam
        case .assignment: .assignment
        case .codingProject: .project
        case .languageStudy: .language
        }
    }

    var defaultSessionMinutes: Int {
        switch self {
        case .weeklyCourse, .examPrep, .codingProject: 50
        case .assignment: 45
        case .languageStudy: 30
        }
    }

    var defaultTasks: [TemplateTask] {
        switch self {
        case .weeklyCourse:
            [
                TemplateTask(title: "Review lecture notes", type: .review, priority: 2, estimatedMinutes: 25),
                TemplateTask(title: "Finish the next exercise sheet", type: .exercise, priority: 2, estimatedMinutes: 40)
            ]
        case .examPrep:
            [
                TemplateTask(title: "Review weak topics", type: .review, priority: 3, estimatedMinutes: 35),
                TemplateTask(title: "Attempt one past exam section", type: .pastExam, priority: 3, estimatedMinutes: 50)
            ]
        case .assignment:
            [
                TemplateTask(title: "Break down assignment requirements", type: .assignment, priority: 3, estimatedMinutes: 20),
                TemplateTask(title: "Prepare the submission checklist", type: .assignment, priority: 3, estimatedMinutes: 25)
            ]
        case .codingProject:
            [
                TemplateTask(title: "Open the project and run it", type: .coding, priority: 2, estimatedMinutes: 20),
                TemplateTask(title: "Write down the next small commit", type: .coding, priority: 1, estimatedMinutes: 15)
            ]
        case .languageStudy:
            [
                TemplateTask(title: "Review vocabulary", type: .flashcards, priority: 2, estimatedMinutes: 20),
                TemplateTask(title: "Practice listening or reading", type: .review, priority: 2, estimatedMinutes: 25)
            ]
        }
    }
}

struct TemplateTask: Equatable {
    var title: String
    var type: StudyTaskType
    var priority: Int
    var estimatedMinutes: Int?
}

struct TemplateTaskDraft: Equatable, Identifiable {
    var id: UUID
    var title: String
    var type: StudyTaskType
    var priority: Int
    var estimatedMinutes: Int?

    init(
        id: UUID = UUID(),
        title: String,
        type: StudyTaskType,
        priority: Int,
        estimatedMinutes: Int?
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
    }

    init(templateTask: TemplateTask) {
        self.init(
            title: templateTask.title,
            type: templateTask.type,
            priority: templateTask.priority,
            estimatedMinutes: templateTask.estimatedMinutes
        )
    }
}

struct OnboardingResourceDraft: Equatable {
    var title: String
    var type: ResourceType
    var urlString: String
    var appBundleID: String? = nil
    var appPath: String? = nil
    var targetDesktopSpace: Int? = nil
}

@MainActor
enum StudyBoxTemplateService {
    static func makeBox(
        template: StudyBoxTemplate,
        name: String,
        courseName: String? = nil,
        dueDate: Date? = nil,
        firstTaskTitle: String? = nil,
        taskDrafts: [TemplateTaskDraft]? = nil,
        resources: [OnboardingResourceDraft] = []
    ) -> StudyBox {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let box = StudyBox(
            name: trimmedName.isEmpty ? template.title : trimmedName,
            type: template.boxType,
            courseName: courseName?.nilIfBlank,
            icon: template.systemImage,
            colorHex: template.colorHex,
            examDate: dueDate,
            defaultSessionMinutes: template.defaultSessionMinutes
        )

        let resolvedTaskDrafts = taskDrafts ?? template.defaultTasks.map(TemplateTaskDraft.init(templateTask:))
        box.tasks = resolvedTaskDrafts.enumerated().compactMap { index, task in
            let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            return StudyTask(
                box: box,
                title: trimmedTitle,
                type: task.type,
                priority: task.priority,
                estimatedMinutes: task.estimatedMinutes,
                dueDate: template == .assignment ? dueDate : nil,
                orderIndex: index
            )
        }

        if let firstTaskTitle = firstTaskTitle?.nilIfBlank {
            box.tasks.append(StudyTask(
                box: box,
                title: firstTaskTitle,
                type: .other,
                priority: 2,
                dueDate: dueDate
            ))
        }

        box.resources = resources.enumerated().map { index, draft in
            StudyResource(
                box: box,
                title: draft.title,
                type: draft.type,
                urlString: draft.urlString,
                appBundleID: draft.appBundleID,
                appPath: draft.appPath,
                orderIndex: index,
                targetDesktopSpace: draft.targetDesktopSpace
            )
        }

        return box
    }

    static func makeBlankBox(name: String) -> StudyBox {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return StudyBox(name: trimmedName.isEmpty ? "Untitled Study Box" : trimmedName)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation
import SwiftData

enum ResourceType: String, CaseIterable, Identifiable {
    case app
    case file
    case folder
    case website
    case moodleCourse
    case blackboardCourse
    case overleaf
    case github
    case chatgpt
    case anki
    case youtube
    case notes
    case commandPlaceholder

    var id: String { rawValue }

    static var selectableCases: [ResourceType] {
        allCases.filter { $0 != .youtube }
    }

    var title: String {
        switch self {
        case .app: "App"
        case .file: "File"
        case .folder: "Folder"
        case .website: "Website"
        case .moodleCourse: "Moodle course"
        case .blackboardCourse: "Blackboard course"
        case .overleaf: "Overleaf"
        case .github: "GitHub"
        case .chatgpt: "ChatGPT"
        case .anki: "Anki"
        case .youtube: "YouTube"
        case .notes: "Text note"
        case .commandPlaceholder: "Command placeholder"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app"
        case .file: "doc"
        case .folder: "folder"
        case .website: "globe"
        case .moodleCourse: "graduationcap"
        case .blackboardCourse: "rectangle.and.pencil.and.ellipsis"
        case .overleaf: "leaf"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .chatgpt: "sparkles"
        case .anki: "rectangle.stack"
        case .youtube: "play.rectangle"
        case .notes: "note.text"
        case .commandPlaceholder: "terminal"
        }
    }

    var defaultURLString: String? {
        switch self {
        case .website:
            "https://"
        case .moodleCourse:
            "https://your-moodle-site.example/course/view.php?id="
        case .blackboardCourse:
            "https://your-blackboard-site.example/"
        case .overleaf:
            "https://www.overleaf.com/project/"
        case .github:
            "https://github.com/"
        case .chatgpt:
            "https://chatgpt.com/"
        case .anki:
            nil
        case .youtube:
            "https://www.youtube.com/"
        default:
            nil
        }
    }

    var expectsURL: Bool {
        switch self {
        case .website, .moodleCourse, .blackboardCourse, .overleaf, .github, .chatgpt, .youtube:
            true
        default:
            false
        }
    }

    var expectsFilePath: Bool {
        switch self {
        case .app, .file, .folder:
            true
        default:
            false
        }
    }

    var isLaunchable: Bool {
        switch self {
        case .notes, .commandPlaceholder:
            false
        default:
            true
        }
    }
}

@Model
final class StudyResource: Identifiable {
    @Attribute(.unique) var id: UUID
    var box: StudyBox?
    var title: String
    var typeRawValue: String
    var urlString: String
    var appBundleID: String?
    var appPath: String?
    var orderIndex: Int
    var enabledByDefault: Bool
    var targetDesktopSpace: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        box: StudyBox? = nil,
        title: String,
        type: ResourceType,
        urlString: String = "",
        appBundleID: String? = nil,
        appPath: String? = nil,
        orderIndex: Int = 0,
        enabledByDefault: Bool = true,
        targetDesktopSpace: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.box = box
        self.title = title
        self.typeRawValue = type.rawValue
        self.urlString = urlString
        self.appBundleID = appBundleID
        self.appPath = appPath
        self.orderIndex = orderIndex
        self.enabledByDefault = enabledByDefault
        self.targetDesktopSpace = Self.normalizedTargetDesktopSpace(targetDesktopSpace, for: type)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: ResourceType {
        get { ResourceType(rawValue: typeRawValue) ?? .website }
        set {
            typeRawValue = newValue.rawValue
            touch()
        }
    }

    func update(
        title: String,
        type: ResourceType,
        urlString: String,
        appBundleID: String?,
        appPath: String?,
        enabledByDefault: Bool,
        targetDesktopSpace: Int? = nil
    ) {
        self.title = title
        self.typeRawValue = type.rawValue
        self.urlString = urlString
        self.appBundleID = appBundleID
        self.appPath = appPath
        self.enabledByDefault = enabledByDefault
        self.targetDesktopSpace = Self.normalizedTargetDesktopSpace(targetDesktopSpace, for: type)
        touch()
    }

    private static func normalizedTargetDesktopSpace(_ value: Int?, for type: ResourceType) -> Int? {
        guard type == .app, let value else { return nil }
        return min(max(value, 1), 8)
    }

    func touch() {
        updatedAt = .now
        box?.touch()
    }
}

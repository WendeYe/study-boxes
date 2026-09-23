import AppKit
import Foundation

enum ResourceLaunchStatus {
    case success
    case failed
    case skipped
}

struct ResourceLaunchResult: Identifiable {
    let id: UUID
    let resourceTitle: String
    let status: ResourceLaunchStatus
    let message: String
}

enum ResourceHealthStatus: Equatable {
    case ok
    case missingPath
    case invalidURL
    case notLaunchable

    var message: String? {
        switch self {
        case .ok: nil
        case .missingPath: "This file, folder, or app is missing. Relink it to keep using this resource."
        case .invalidURL: "That URL does not look right."
        case .notLaunchable: nil
        }
    }
}

enum ResourceHealthService {
    static func status(for resource: StudyResource) -> ResourceHealthStatus {
        switch resource.type {
        case .app:
            if let appPath = resource.appPath, !appPath.isEmpty {
                return FileManager.default.fileExists(atPath: appPath) ? .ok : .missingPath
            }
            if let bundleID = resource.appBundleID {
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil ? .missingPath : .ok
            }
            return .missingPath
        case .file, .folder:
            return FileManager.default.fileExists(atPath: resource.urlString) ? .ok : .missingPath
        case .website, .moodleCourse, .blackboardCourse, .overleaf, .github, .chatgpt, .youtube:
            return URLValidator.normalizedURLString(resource.urlString) == nil ? .invalidURL : .ok
        case .anki:
            if resource.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AnkiResourceService.installedApplicationURL() == nil ? .missingPath : .ok
            }
            return AnkiResourceService.normalizedLink(resource.urlString) == nil ? .invalidURL : .ok
        case .notes, .commandPlaceholder:
            return .notLaunchable
        }
    }

    @MainActor
    static func relink(_ resource: StudyResource) -> Bool {
        let selectedURL: URL?
        switch resource.type {
        case .app:
            selectedURL = AppPicker.chooseApplication()
        case .file:
            selectedURL = FilePicker.chooseFile()
        case .folder:
            selectedURL = FilePicker.chooseFolder()
        default:
            selectedURL = nil
        }

        guard let selectedURL else { return false }
        resource.urlString = selectedURL.path
        if resource.type == .app {
            resource.appPath = selectedURL.path
            resource.appBundleID = AppPicker.bundleIdentifier(for: selectedURL)
        }
        resource.touch()
        return true
    }
}

@MainActor
final class ResourceLauncher {
    static let shared = ResourceLauncher()

    private init() {}

    func openEnabledResources(for box: StudyBox, plan: EntitlementPlan? = nil) -> [ResourceLaunchResult] {
        let resolvedPlan = plan ?? LicenseManager.shared.plan
        return EntitlementRules.enabledResources(for: box, plan: resolvedPlan).map(open)
    }

    func open(_ resource: StudyResource) -> ResourceLaunchResult {
        switch resource.type {
        case .app:
            return openApp(resource)
        case .file, .folder:
            return openFileSystemResource(resource)
        case .website, .moodleCourse, .blackboardCourse, .overleaf, .github, .chatgpt, .youtube:
            return openWebResource(resource)
        case .anki:
            return openAnkiResource(resource)
        case .notes:
            return result(for: resource, status: .skipped, message: "Notes live inside Study Boxes.")
        case .commandPlaceholder:
            return result(for: resource, status: .skipped, message: "Command placeholders are copy-only for now.")
        }
    }

    private func openApp(_ resource: StudyResource) -> ResourceLaunchResult {
        if let appPath = resource.appPath, !appPath.isEmpty {
            let url = URL(fileURLWithPath: appPath)
            return openURL(url, resource: resource, failureMessage: "Study Boxes could not open this app.")
        }

        if let bundleID = resource.appBundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return openURL(url, resource: resource, failureMessage: "Study Boxes could not open this app.")
        }

        return result(for: resource, status: .failed, message: "Study Boxes could not find this app. Relink it from the resource list.")
    }

    private func openFileSystemResource(_ resource: StudyResource) -> ResourceLaunchResult {
        guard !resource.urlString.isEmpty else {
            return result(for: resource, status: .failed, message: "This resource is missing a file path. Relink it from the resource list.")
        }

        let url = URL(fileURLWithPath: resource.urlString)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return result(for: resource, status: .failed, message: "This file or folder is missing. It may have been moved or deleted.")
        }

        return openURL(url, resource: resource, failureMessage: "Study Boxes could not open this resource.")
    }

    private func openWebResource(_ resource: StudyResource) -> ResourceLaunchResult {
        guard let urlString = URLValidator.normalizedURLString(resource.urlString),
              let url = URL(string: urlString) else {
            return result(for: resource, status: .failed, message: "That URL does not look right.")
        }

        return openURL(url, resource: resource, failureMessage: "Study Boxes could not open this website.")
    }

    private func openAnkiResource(_ resource: StudyResource) -> ResourceLaunchResult {
        let trimmedLink = resource.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLink.isEmpty {
            guard let normalizedLink = AnkiResourceService.normalizedLink(trimmedLink),
                  let url = URL(string: normalizedLink) else {
                return result(for: resource, status: .failed, message: "That Anki link does not look right.")
            }

            return openURL(url, resource: resource, failureMessage: "Study Boxes could not open this Anki link.")
        }

        guard let appURL = AnkiResourceService.installedApplicationURL() else {
            return result(for: resource, status: .failed, message: "Anki is not installed. Install Anki or add an Anki link.")
        }

        return openURL(appURL, resource: resource, failureMessage: "Study Boxes could not open Anki.")
    }

    private func openURL(_ url: URL, resource: StudyResource, failureMessage: String) -> ResourceLaunchResult {
        if NSWorkspace.shared.open(url) {
            return result(for: resource, status: .success, message: "Opened.")
        }

        return result(for: resource, status: .failed, message: failureMessage)
    }

    private func result(for resource: StudyResource, status: ResourceLaunchStatus, message: String) -> ResourceLaunchResult {
        ResourceLaunchResult(
            id: resource.id,
            resourceTitle: resource.title,
            status: status,
            message: message
        )
    }
}

enum AnkiResourceService {
    static let appName = "Anki"
    static let installURLString = "https://apps.ankiweb.net/"
    static let supportedBundleIdentifiers = [
        "net.ankiweb.launcher",
        "net.ankiweb.dtop"
    ]

    static func installedApplicationURL(workspace: NSWorkspace = .shared) -> URL? {
        for bundleIdentifier in supportedBundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }
        return nil
    }

    static func normalizedLink(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           components.scheme?.lowercased() == "anki" {
            return trimmed
        }

        guard let normalizedURL = URLValidator.normalizedURLString(trimmed),
              let scheme = URL(string: normalizedURL)?.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        return normalizedURL
    }
}

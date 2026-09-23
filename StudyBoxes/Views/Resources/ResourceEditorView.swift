import AppKit
import SwiftData
import SwiftUI

enum ResourceEditorDefaults {
    static func initialURLString(for type: ResourceType, existingURLString: String?) -> String {
        if let existingURLString {
            return existingURLString
        }

        return type.expectsURL ? "" : type.defaultURLString ?? ""
    }

    static func initialSuggestion(for type: ResourceType, existingURLString: String?) -> String? {
        guard existingURLString == nil, !type.expectsURL else {
            return nil
        }

        return type.defaultURLString
    }
}

struct ResourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    let box: StudyBox
    private let resource: StudyResource?
    @ObservedObject private var license = LicenseManager.shared

    @State private var title: String
    @State private var type: ResourceType
    @State private var urlString: String
    @State private var appBundleID: String
    @State private var appPath: String
    @State private var enabledByDefault: Bool
    @State private var targetDesktopSpaceSelection: Int
    @State private var errorMessage: String?
    @State private var lastSuggestedURLString: String?

    init(box: StudyBox, resource: StudyResource? = nil) {
        self.box = box
        self.resource = resource
        let initialType = resource?.type ?? .website
        _title = State(initialValue: resource?.title ?? "")
        _type = State(initialValue: initialType == .youtube ? .website : initialType)
        _urlString = State(initialValue: ResourceEditorDefaults.initialURLString(
            for: initialType,
            existingURLString: resource?.urlString
        ))
        _appBundleID = State(initialValue: resource?.appBundleID ?? "")
        _appPath = State(initialValue: resource?.appPath ?? "")
        _enabledByDefault = State(initialValue: resource?.enabledByDefault ?? true)
        _targetDesktopSpaceSelection = State(initialValue: resource?.targetDesktopSpace ?? 0)
        _lastSuggestedURLString = State(initialValue: ResourceEditorDefaults.initialSuggestion(
            for: initialType,
            existingURLString: resource?.urlString
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
	                Section("Resource") {
	                    TextField(type == .anki ? "Deck label" : "Title", text: $title)
	                    .help("Use a short name for the resource list.")

	                    DropdownMenuRow("Type", selection: $type, options: ResourceType.selectableCases)
	                    .help("Choose what Study Boxes stores and how it opens.")

	                    Toggle("Open automatically when a study session starts", isOn: $enabledByDefault)
	                        .help("Turn this off for optional resources you prefer to open manually.")
	                }

                inputSection

                if type == .commandPlaceholder {
                    Text("Command placeholders are copy-only for now. Study Boxes will not run shell commands automatically.")
                        .foregroundStyle(.secondary)
                }

                validationMessage
            }
            .formStyle(.grouped)
            .onChange(of: type) { _, newType in
                applySuggestedURL(for: newType)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(resource == nil ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        switch type {
        case .app:
	            Section("App") {
	                TextField("App path", text: $appPath)
	                    .help("Path to the selected macOS app.")
	                TextField("Bundle ID", text: $appBundleID)
	                    .help("The bundle ID lets Study Boxes recognize this app during focus mode.")

                    HStack {
                        Text("Desktop")
                        Spacer()
                        DropdownMenu(
                            "Desktop Space",
                            selection: $targetDesktopSpaceSelection,
                            options: desktopSpaceOptions,
                            isEnabled: license.plan.isPro,
                            minWidth: 150
                        )
                    }
                    .help("Optional. Place this app on a chosen desktop when the Study Box enables desktop Spaces.")

                Button {
                    if let url = AppPicker.chooseApplication() {
                        appPath = url.path
                        appBundleID = AppPicker.bundleIdentifier(for: url) ?? ""
                        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            title = url.deletingPathExtension().lastPathComponent
                        }
                    }
	                } label: {
	                    Label("Choose App", systemImage: "app.badge")
	                }
	                .help("Pick an app from your Mac.")

                    Text("Desktop assignment is optional and best effort. Study Boxes never removes your existing desktops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !license.plan.isPro {
                        Button {
                            presentLicense(EntitlementRules.canUse(.desktopSpaces, plan: .free).message)
                        } label: {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text("Desktop Space placement is included with Pro.")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
	            }
	        case .file:
	            Section("File") {
	                TextField("File path", text: $urlString)
	                    .help("Path to the file Study Boxes should open.")

                Button {
                    if let url = FilePicker.chooseFile() {
                        urlString = url.path
                        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            title = url.lastPathComponent
                        }
                    }
	                } label: {
	                    Label("Choose File", systemImage: "doc.badge.plus")
	                }
	                .help("Pick a PDF, document, exercise sheet, or other file.")
	            }
	        case .folder:
	            Section("Folder") {
	                TextField("Folder path", text: $urlString)
	                    .help("Path to the folder Study Boxes should open.")

                Button {
                    if let url = FilePicker.chooseFolder() {
                        urlString = url.path
                        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            title = url.lastPathComponent
                        }
                    }
	                } label: {
	                    Label("Choose Folder", systemImage: "folder.badge.plus")
	                }
	                .help("Pick a course folder, code folder, or notes folder.")
	            }
	        case .notes:
	            Section("Note") {
	                Text("Notes live inside Study Boxes and do not open as external files.")
	                    .font(.caption)
	                    .foregroundStyle(.secondary)
	                TextEditor(text: $urlString)
	                    .frame(minHeight: 90)
	            }
	        case .commandPlaceholder:
	            Section("Command Text") {
	                Text("This is a copy-only command placeholder. Study Boxes will not run it.")
	                    .font(.caption)
	                    .foregroundStyle(.secondary)
	                TextEditor(text: $urlString)
	                    .font(.system(.body, design: .monospaced))
	                    .frame(minHeight: 90)
	            }
        case .anki:
            Section("Anki") {
                TextField("Optional Anki link", text: $urlString, prompt: Text("anki://... or https://ankiweb.net/..."))
                    .help("Leave this blank to open the Anki app. Add an Anki or AnkiWeb link if you use one.")

                Text("Study Boxes opens Anki but does not read decks, cards, review counts, or browser tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if AnkiResourceService.installedApplicationURL() == nil {
                    HStack {
                        Label("Anki is not installed.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Anki Website") {
                            if let url = URL(string: AnkiResourceService.installURLString) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
	        default:
	            Section(type.title) {
	                TextField("URL", text: $urlString, prompt: Text(websitePlaceholder))
	                    .help("Paste the course site, LMS page, GitHub repo, Overleaf project, or other study link.")
	                Text("Links open in your browser. Study Boxes cannot manage individual browser tabs.")
	                    .font(.caption)
	                    .foregroundStyle(.secondary)
	            }
	        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var websitePlaceholder: String {
        switch type {
        case .website:
            "https://example.com"
        default:
            type.defaultURLString ?? "https://example.com"
        }
    }

    private func save() {
        if resource == nil {
            let decision = EntitlementRules.canAddResource(currentResourceCount: box.resources.count, plan: license.plan)
            guard decision.isAllowed else {
                errorMessage = decision.message
                presentLicense(decision.message)
                return
            }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required."
            return
        }

        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppPath = appPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundleID = appBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedTargetDesktopSpace = license.plan.isPro
            ? normalizedTargetDesktopSpace
            : resource?.targetDesktopSpace

        if type.expectsURL, URLValidator.normalizedURLString(trimmedURLString) == nil {
            errorMessage = "That URL does not look right."
            return
        }

        if type == .anki,
           !trimmedURLString.isEmpty,
           AnkiResourceService.normalizedLink(trimmedURLString) == nil {
            errorMessage = "That Anki link does not look right."
            return
        }

        if type == .file || type == .folder, trimmedURLString.isEmpty {
            errorMessage = "Choose a file or folder first."
            return
        }

        if type == .app, trimmedAppPath.isEmpty && trimmedBundleID.isEmpty {
            errorMessage = "Choose an app or enter a bundle ID."
            return
        }

        if let resource {
            resource.update(
                title: trimmedTitle,
                type: type,
                urlString: storedURLString(from: trimmedURLString),
                appBundleID: trimmedBundleID.isEmpty ? nil : trimmedBundleID,
                appPath: trimmedAppPath.isEmpty ? nil : trimmedAppPath,
                enabledByDefault: enabledByDefault,
                targetDesktopSpace: savedTargetDesktopSpace
            )
        } else {
            let resource = StudyResource(
                box: box,
                title: trimmedTitle,
                type: type,
                urlString: storedURLString(from: trimmedURLString),
                appBundleID: trimmedBundleID.isEmpty ? nil : trimmedBundleID,
                appPath: trimmedAppPath.isEmpty ? nil : trimmedAppPath,
                orderIndex: nextOrderIndex,
                enabledByDefault: enabledByDefault,
                targetDesktopSpace: savedTargetDesktopSpace
            )
            modelContext.insert(resource)
        }

        box.touch()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Study Boxes could not save this resource."
        }
    }

    private var nextOrderIndex: Int {
        (box.resources.map(\.orderIndex).max() ?? -1) + 1
    }

    private var normalizedTargetDesktopSpace: Int? {
        guard type == .app, targetDesktopSpaceSelection > 0 else { return nil }
        return min(targetDesktopSpaceSelection, SpaceLayoutManager.maximumManagedSpaces)
    }

    private var desktopSpaceOptions: [DropdownMenuOption<Int>] {
        let automatic = DropdownMenuOption(
            value: 0,
            title: "Current desktop",
            systemImage: "circle"
        )
        let numbered = (1...SpaceLayoutManager.maximumManagedSpaces).map { index in
            DropdownMenuOption(
                value: index,
                title: "Desktop \(index)",
                systemImage: "rectangle.3.group"
            )
        }
        return [automatic] + numbered
    }

    private func storedURLString(from input: String) -> String {
        if type == .anki {
            return AnkiResourceService.normalizedLink(input) ?? input
        }
        if type.expectsURL {
            return URLValidator.normalizedURLString(input) ?? input
        }
        return input
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySuggestedURL(for newType: ResourceType) {
        guard !newType.expectsURL else {
            lastSuggestedURLString = nil
            return
        }

        guard let suggestedURLString = newType.defaultURLString else {
            lastSuggestedURLString = nil
            return
        }

        let current = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousSuggestion = lastSuggestedURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == previousSuggestion {
            urlString = suggestedURLString
        }
        lastSuggestedURLString = suggestedURLString
    }
}

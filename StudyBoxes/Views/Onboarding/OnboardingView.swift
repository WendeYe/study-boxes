import AppKit
import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var license = LicenseManager.shared

    let onCompleted: (StudyBox?, Bool) -> Void

    @State private var selectedTemplate: StudyBoxTemplate = .weeklyCourse
    @State private var name = ""
    @State private var courseName = ""
    @State private var includeDueDate = false
    @State private var dueDate = Date()
    @State private var websiteText = ""
    @State private var secondaryWebsiteText = ""
    @State private var firstTaskTitle = ""
    @State private var selectedFileURL: URL?
    @State private var selectedFolderURL: URL?
    @State private var selectedPrimaryAppURL: URL?
    @State private var selectedSecondaryAppURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    templatePicker
                    detailsSection
                    resourceSection
                    firstTaskSection
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.trailing, 32, for: .scrollContent)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up your first Study Box")
                .font(.largeTitle.weight(.semibold))
            Text("Pick a starting point, add one or two materials, and start studying right away.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a template")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                ForEach(StudyBoxTemplate.allCases) { template in
                    Button {
                        guard license.plan.isPro else {
                            presentLicense(EntitlementRules.canUse(.nonBlankTemplates, plan: license.plan).message)
                            return
                        }
                        selectedTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: template.systemImage)
                                    .foregroundStyle(Color(hex: template.colorHex))
                                Spacer()
                                if !license.plan.isPro {
                                    ProBadge()
                                }
                                if selectedTemplate == template {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(template.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .background(.quaternary.opacity(selectedTemplate == template ? 0.35 : 0.18), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTemplate == template ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name it")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Subject")
                        .foregroundStyle(.secondary)
                    TextField("Probability, Operating Systems, French...", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Course")
                        .foregroundStyle(.secondary)
                    TextField("Optional course code or class name", text: $courseName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Toggle("Due date", isOn: $includeDueDate)
                        .foregroundStyle(.secondary)
                    SystemDatePickerField(date: $dueDate, accessibilityLabel: "Due date")
                        .disabled(!includeDueDate)
                        .opacity(includeDueDate ? 1 : 0.5)
                }
            }
        }
    }

    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedTemplate.resourceSectionTitle)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                resourceURLRow(
                    label: selectedTemplate.primaryURLLabel,
                    placeholder: selectedTemplate.primaryURLPlaceholder,
                    text: $websiteText
                )

                if let secondaryURLLabel = selectedTemplate.secondaryURLLabel,
                   let secondaryURLPlaceholder = selectedTemplate.secondaryURLPlaceholder {
                    resourceURLRow(
                        label: secondaryURLLabel,
                        placeholder: secondaryURLPlaceholder,
                        text: $secondaryWebsiteText
                    )
                }

                if let fileLabel = selectedTemplate.fileLabel {
                    resourcePickerRow(label: fileLabel, url: selectedFileURL, placeholder: "No file selected") {
                        selectedFileURL = FilePicker.chooseFile()
                    }
                }

                if let folderLabel = selectedTemplate.folderLabel {
                    resourcePickerRow(label: folderLabel, url: selectedFolderURL, placeholder: "No folder selected") {
                        selectedFolderURL = FilePicker.chooseFolder()
                    }
                }

                if let primaryAppLabel = selectedTemplate.primaryAppLabel {
                    resourcePickerRow(label: primaryAppLabel, url: selectedPrimaryAppURL, placeholder: "No app selected") {
                        selectedPrimaryAppURL = AppPicker.chooseApplication()
                    }
                }

                if let secondaryAppLabel = selectedTemplate.secondaryAppLabel {
                    resourcePickerRow(label: secondaryAppLabel, url: selectedSecondaryAppURL, placeholder: "No app selected") {
                        selectedSecondaryAppURL = AppPicker.chooseApplication()
                    }
                }
            }
        }
    }

    private var firstTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("First task")
                .font(.headline)
            TextField("Optional: what should you do first?", text: $firstTaskTitle)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") {
                OnboardingState.shared.complete()
                onCompleted(nil, false)
                dismiss()
            }

            Spacer()

            Button("Create Blank Study Box") {
                createBlank()
            }

            Button {
                createFromTemplate(startImmediately: true)
            } label: {
                Label("Start first session", systemImage: "play.fill")
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func resourceURLRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func resourcePickerRow(label: String, url: URL?, placeholder: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(url?.lastPathComponent ?? placeholder)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Button("Choose", action: action)
        }
    }

    private func createBlank() {
        let box = StudyBoxTemplateService.makeBlankBox(name: name)
        modelContext.insert(box)
        saveAndFinish(box: box, startImmediately: false)
    }

    private func createFromTemplate(startImmediately: Bool) {
        errorMessage = nil
        let decision = EntitlementRules.canUse(.nonBlankTemplates, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }

        guard let resources = makeResourceDrafts() else { return }

        let box = StudyBoxTemplateService.makeBox(
            template: selectedTemplate,
            name: name,
            courseName: courseName,
            dueDate: includeDueDate ? dueDate : nil,
            firstTaskTitle: firstTaskTitle,
            resources: resources
        )
        modelContext.insert(box)
        saveAndFinish(box: box, startImmediately: startImmediately)
    }

    private func saveAndFinish(box: StudyBox, startImmediately: Bool) {
        do {
            try modelContext.save()
            OnboardingState.shared.complete()
            appState.openBox(box.id)
            dismiss()
            Task { @MainActor in
                await Task.yield()
                onCompleted(box, startImmediately)
            }
        } catch {
            errorMessage = "Study Boxes could not save your first Study Box."
        }
    }

    private func presentLicense(_ reason: String?) {
        errorMessage = reason
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeResourceDrafts() -> [OnboardingResourceDraft]? {
        var resources: [OnboardingResourceDraft] = []

        if let draft = makeURLDraft(
            from: websiteText,
            label: selectedTemplate.primaryURLLabel,
            fallbackTitle: selectedTemplate.primaryURLResourceTitle,
            preferredType: selectedTemplate.primaryURLType
        ) {
            resources.append(draft)
        } else if errorMessage != nil {
            return nil
        }

        if selectedTemplate.secondaryURLLabel != nil {
            if let draft = makeURLDraft(
                from: secondaryWebsiteText,
                label: selectedTemplate.secondaryURLLabel ?? "Website",
                fallbackTitle: selectedTemplate.secondaryURLResourceTitle ?? "Website",
                preferredType: selectedTemplate.secondaryURLType ?? .website
            ) {
                resources.append(draft)
            } else if errorMessage != nil {
                return nil
            }
        }

        if selectedTemplate.fileLabel != nil, let selectedFileURL {
            resources.append(OnboardingResourceDraft(
                title: selectedFileURL.lastPathComponent,
                type: .file,
                urlString: selectedFileURL.path
            ))
        }

        if selectedTemplate.folderLabel != nil, let selectedFolderURL {
            resources.append(OnboardingResourceDraft(
                title: selectedFolderURL.lastPathComponent,
                type: .folder,
                urlString: selectedFolderURL.path
            ))
        }

        if selectedTemplate.primaryAppLabel != nil, let selectedPrimaryAppURL {
            resources.append(makeAppDraft(from: selectedPrimaryAppURL))
        }

        if selectedTemplate.secondaryAppLabel != nil, let selectedSecondaryAppURL {
            resources.append(makeAppDraft(from: selectedSecondaryAppURL))
        }

        return resources
    }

    private func makeURLDraft(
        from input: String,
        label: String,
        fallbackTitle: String,
        preferredType: ResourceType
    ) -> OnboardingResourceDraft? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return nil }

        let normalizedURL: String?
        if preferredType == .anki {
            normalizedURL = AnkiResourceService.normalizedLink(trimmedInput)
        } else {
            normalizedURL = URLValidator.normalizedURLString(trimmedInput)
        }

        guard let normalizedURL else {
            errorMessage = preferredType == .anki
                ? "\(label) Anki link does not look right."
                : "\(label) URL does not look right."
            return nil
        }

        return OnboardingResourceDraft(
            title: titleForURL(normalizedURL, fallback: fallbackTitle),
            type: resourceType(for: normalizedURL, preferredType: preferredType),
            urlString: normalizedURL
        )
    }

    private func makeAppDraft(from appURL: URL) -> OnboardingResourceDraft {
        OnboardingResourceDraft(
            title: appURL.deletingPathExtension().lastPathComponent,
            type: .app,
            urlString: appURL.path,
            appBundleID: AppPicker.bundleIdentifier(for: appURL),
            appPath: appURL.path
        )
    }

    private func titleForURL(_ urlString: String, fallback: String) -> String {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else {
            return fallback
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func resourceType(for urlString: String, preferredType: ResourceType) -> ResourceType {
        if preferredType == .anki {
            return .anki
        }

        guard let host = URL(string: urlString)?.host?.lowercased() else {
            return preferredType
        }

        if host.contains("github.com") { return .github }
        if host.contains("moodle") { return .moodleCourse }
        if host.contains("blackboard") { return .blackboardCourse }
        if host.contains("overleaf.com") { return .overleaf }
        if host.contains("chatgpt.com") { return .chatgpt }
        return preferredType == .github ? .website : preferredType
    }
}

struct TemplateBoxCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var license = LicenseManager.shared

    var currentBoxCount: Int = 0
    var onCreated: (StudyBox, Bool) -> Void

    @State private var selectedTemplate: StudyBoxTemplate?
    @State private var name = ""
    @State private var type: StudyBoxType = .course
    @State private var courseName = ""
    @State private var includeDueDate = false
    @State private var dueDate = Date()
    @State private var icon = "books.vertical"
    @State private var colorHex = "#3B82F6"
    @State private var defaultSessionMinutes = 50
    @State private var defaultSessionMinutesText = "50"
    @State private var focusMode: StudyFocusMode = .off
    @State private var openResourcesOnSessionStart = true
    @State private var keepDisplayAwakeDuringSessions = true
    @State private var prepareDesktopSpacesOnSessionStart = false
    @State private var minimumDesktopSpaces = 1
    @State private var websiteText = ""
    @State private var secondaryWebsiteText = ""
    @State private var selectedFileURL: URL?
    @State private var selectedFolderURL: URL?
    @State private var selectedPrimaryAppURL: URL?
    @State private var primaryAppDesktopSpaceSelection = 0
    @State private var selectedSecondaryAppURL: URL?
    @State private var secondaryAppDesktopSpaceSelection = 0
    @State private var additionalResourceDrafts: [CreateResourceDraft] = []
    @State private var taskDrafts: [TemplateTaskDraft] = []
    @State private var errorMessage: String?

    private let icons = [
        "books.vertical", "graduationcap", "doc.text", "checklist", "calendar.badge.clock",
        "chevron.left.forwardslash.chevron.right", "terminal", "keyboard", "desktopcomputer",
        "textformat.abc", "character.book.closed", "headphones", "brain", "function",
        "sum", "atom", "globe", "building.columns", "paintpalette", "chart.bar"
    ]

    private let colors: [(hex: String, name: String)] = [
        ("#3B82F6", "Blue"),
        ("#14B8A6", "Teal"),
        ("#22C55E", "Green"),
        ("#10B981", "Emerald"),
        ("#06B6D4", "Cyan"),
        ("#F59E0B", "Amber"),
        ("#EF4444", "Red"),
        ("#F43F5E", "Rose"),
        ("#A855F7", "Purple"),
        ("#71717A", "Zinc")
    ]

    private let freeAdditionalResourceLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    templatePicker
                    basicsSection
                    appearanceSection
                    sessionSection
                    resourcesSection
                    tasksSection
                }
                .padding(.vertical, 2)
                .padding(.trailing, 44)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.trailing, 56, for: .scrollContent)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 680)
        .onAppear {
            applyTemplate(nil)
        }
        .onChange(of: selectedTemplate) { _, newValue in
            applyTemplate(newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Create Study Box")
                .font(.title.weight(.semibold))
            Text("Start from a template or keep it blank, then adjust the setup before saving.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                templateButton(title: "Blank", subtitle: "Build your own setup.", systemImage: "square.dashed", colorHex: "#71717A", isSelected: selectedTemplate == nil) {
                    selectedTemplate = nil
                }

                ForEach(StudyBoxTemplate.allCases) { template in
                    templateButton(
                        title: template.title,
                        subtitle: template.subtitle,
                        systemImage: template.systemImage,
                        colorHex: template.colorHex,
                        isSelected: selectedTemplate == template,
                        showsProBadge: !license.plan.isPro
                    ) {
                        guard license.plan.isPro else {
                            presentLicense(EntitlementRules.canUse(.nonBlankTemplates, plan: license.plan).message)
                            return
                        }
                        selectedTemplate = template
                    }
                }
            }
        }
    }

    private func templateButton(
        title: String,
        subtitle: String,
        systemImage: String,
        colorHex: String,
        isSelected: Bool,
        showsProBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color(hex: colorHex))
                    Spacer()
                    if showsProBadge {
                        ProBadge()
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
            .background(.quaternary.opacity(isSelected ? 0.35 : 0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Operating Systems, French, Compiler project...", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    DropdownMenu("Type", selection: $type, options: StudyBoxType.allCases, minWidth: 220)
                }
                GridRow {
                    Text("Course").foregroundStyle(.secondary)
                    TextField("Optional course code or class name", text: $courseName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Toggle("Due date", isOn: $includeDueDate)
                        .foregroundStyle(.secondary)
                    SystemDatePickerField(date: $dueDate, accessibilityLabel: "Due date")
                        .disabled(!includeDueDate)
                        .opacity(includeDueDate ? 1 : 0.5)
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .font(.headline)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: colorHex).opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: colorHex))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? selectedTemplate?.title ?? "New Study Box" : name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(type.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 6) {
                ForEach(icons, id: \.self) { iconName in
                    Button {
                        icon = iconName
                    } label: {
                        Image(systemName: iconName)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(icon == iconName ? Color(hex: colorHex).opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(icon == iconName ? Color(hex: colorHex) : Color.clear, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(iconName)
                }
            }

            HStack(spacing: 8) {
                ForEach(colors, id: \.hex) { swatch in
                    Button {
                        colorHex = swatch.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: swatch.hex))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if colorHex == swatch.hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                }
            }
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session defaults")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Presets").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(SessionPreset.defaultMinutes, id: \.self) { minutes in
                            Button("\(minutes)") {
                                defaultSessionMinutes = minutes
                                defaultSessionMinutesText = String(minutes)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .tint(defaultSessionMinutes == minutes ? .accentColor : nil)
                        }
                    }
                }
                GridRow {
                    Text("Length").foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TextField("", text: $defaultSessionMinutesText)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: defaultSessionMinutesText) { _, newValue in
                        let sanitized = NumericInput.sanitizedIntegerText(newValue, range: 0...999)
                        if sanitized != newValue { defaultSessionMinutesText = sanitized }
                        defaultSessionMinutes = NumericInput.integerValue(from: sanitized, fallback: defaultSessionMinutes, range: 0...999)
                    }
                }
                GridRow {
                    Text("Focus").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        FocusModeMenu(selection: $focusMode, isEnabled: license.plan.isPro, minWidth: 220)
                        if !license.plan.isPro {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text(EntitlementRules.canUse(.focusModes, plan: .free).message ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                GridRow {
                    Text("Startup").foregroundStyle(.secondary)
                    HStack {
                        Toggle("Open study setup", isOn: $openResourcesOnSessionStart)
                        Toggle("Keep display awake", isOn: $keepDisplayAwakeDuringSessions)
                    }
                }
                GridRow {
                    Text("Desktops").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Prepare desktop Spaces", isOn: $prepareDesktopSpacesOnSessionStart)
                            .disabled(!license.plan.isPro)

                        if prepareDesktopSpacesOnSessionStart {
                            Stepper(
                                "Keep at least \(minimumDesktopSpaces) desktops ready",
                                value: $minimumDesktopSpaces,
                                in: 1...SpaceLayoutManager.maximumManagedSpaces
                            )
                            .disabled(!license.plan.isPro)
                        }

                        Text("Best effort. Assign app resources to a desktop below; existing desktops stay untouched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !license.plan.isPro {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text(EntitlementRules.canUse(.desktopSpaces, plan: .free).message ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedTemplate?.resourceSectionTitle ?? "Add resources")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                resourceURLRow(
                    label: selectedTemplate?.primaryURLLabel ?? "Website",
                    placeholder: selectedTemplate?.primaryURLPlaceholder ?? "https://example.com",
                    text: $websiteText
                )

                if let template = selectedTemplate,
                   let secondaryLabel = template.secondaryURLLabel,
                   let secondaryPlaceholder = template.secondaryURLPlaceholder {
                    resourceURLRow(label: secondaryLabel, placeholder: secondaryPlaceholder, text: $secondaryWebsiteText)
                }

                if selectedTemplate?.fileLabel != nil || selectedTemplate == nil {
                    let fileLabel = selectedTemplate?.fileLabel ?? "File"
                    resourcePickerRow(label: fileLabel, url: selectedFileURL, placeholder: "No file selected") {
                        selectedFileURL = FilePicker.chooseFile()
                    } clear: {
                        selectedFileURL = nil
                    }
                }

                if selectedTemplate?.folderLabel != nil || selectedTemplate == nil {
                    let folderLabel = selectedTemplate?.folderLabel ?? "Folder"
                    resourcePickerRow(label: folderLabel, url: selectedFolderURL, placeholder: "No folder selected") {
                        selectedFolderURL = FilePicker.chooseFolder()
                    } clear: {
                        selectedFolderURL = nil
                    }
                }

                if let primaryAppLabel = selectedTemplate?.primaryAppLabel {
                    appResourcePickerRow(label: primaryAppLabel, url: selectedPrimaryAppURL, targetDesktopSpace: $primaryAppDesktopSpaceSelection) {
                        selectedPrimaryAppURL = AppPicker.chooseApplication()
                    } clear: {
                        selectedPrimaryAppURL = nil
                        primaryAppDesktopSpaceSelection = 0
                    }
                }

                if let secondaryAppLabel = selectedTemplate?.secondaryAppLabel {
                    appResourcePickerRow(label: secondaryAppLabel, url: selectedSecondaryAppURL, targetDesktopSpace: $secondaryAppDesktopSpaceSelection) {
                        selectedSecondaryAppURL = AppPicker.chooseApplication()
                    } clear: {
                        selectedSecondaryAppURL = nil
                        secondaryAppDesktopSpaceSelection = 0
                    }
                }

                additionalResourcesEditor
            }
        }
    }

    private var additionalResourcesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Additional resources")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    addAdditionalResourceDraft()
                } label: {
                    Label("Add Resource", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if additionalResourceDrafts.isEmpty {
                Text(additionalResourceHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach($additionalResourceDrafts) { $resource in
                        additionalResourceCard(resource: $resource)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var additionalResourceHelpText: String {
        if license.plan.isPro {
            return "Add extra websites, apps, files, folders, notes, or project links beyond the template presets."
        }
        return "Free includes up to 3 additional resources. Pro includes unlimited additional resources."
    }

    private var desktopSpaceOptions: [DropdownMenuOption<Int>] {
        let current = DropdownMenuOption<Int>(
            value: 0,
            title: "Current desktop",
            systemImage: "rectangle"
        )
        let numbered = (1...SpaceLayoutManager.maximumManagedSpaces).map { index in
            DropdownMenuOption<Int>(
                value: index,
                title: "Desktop \(index)",
                systemImage: "\(index).square"
            )
        }
        return [current] + numbered
    }

    private func additionalResourceCard(resource: Binding<CreateResourceDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DropdownMenu("Resource type", selection: resource.type, options: ResourceType.selectableCases, minWidth: 160)
                    .onChange(of: resource.wrappedValue.type) { _, newType in
                        resource.wrappedValue.applySuggestedURL(for: newType)
                    }
                TextField("Title", text: resource.title)
                    .textFieldStyle(.roundedBorder)
                Button {
                    additionalResourceDrafts.removeAll { $0.id == resource.wrappedValue.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this resource.")
            }

            additionalResourceInput(resource: resource)
        }
        .padding(10)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func additionalResourceInput(resource: Binding<CreateResourceDraft>) -> some View {
        switch resource.wrappedValue.type {
        case .app:
            VStack(alignment: .leading, spacing: 8) {
                resourcePathRow(
                    placeholder: "No app selected",
                    value: resource.wrappedValue.appPath,
                    chooseTitle: "Choose App"
                ) {
                    guard let url = AppPicker.chooseApplication() else { return }
                    resource.wrappedValue.appPath = url.path
                    resource.wrappedValue.appBundleID = AppPicker.bundleIdentifier(for: url) ?? ""
                    if resource.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        resource.wrappedValue.title = url.deletingPathExtension().lastPathComponent
                    }
                } clear: {
                    resource.wrappedValue.appPath = ""
                    resource.wrappedValue.appBundleID = ""
                    resource.wrappedValue.targetDesktopSpace = 0
                }

                HStack(spacing: 10) {
                    Text("Desktop")
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    DropdownMenu(
                        "Desktop Space",
                        selection: resource.targetDesktopSpace,
                        options: desktopSpaceOptions,
                        isEnabled: license.plan.isPro && prepareDesktopSpacesOnSessionStart,
                        minWidth: 170
                    )
                    Spacer()
                }
            }
        case .file:
            resourcePathRow(
                placeholder: "No file selected",
                value: resource.wrappedValue.urlString,
                chooseTitle: "Choose File"
            ) {
                guard let url = FilePicker.chooseFile() else { return }
                resource.wrappedValue.urlString = url.path
                if resource.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resource.wrappedValue.title = url.lastPathComponent
                }
            } clear: {
                resource.wrappedValue.urlString = ""
            }
        case .folder:
            resourcePathRow(
                placeholder: "No folder selected",
                value: resource.wrappedValue.urlString,
                chooseTitle: "Choose Folder"
            ) {
                guard let url = FilePicker.chooseFolder() else { return }
                resource.wrappedValue.urlString = url.path
                if resource.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resource.wrappedValue.title = url.lastPathComponent
                }
            } clear: {
                resource.wrappedValue.urlString = ""
            }
        case .notes:
            TextEditor(text: resource.urlString)
                .frame(minHeight: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
        case .commandPlaceholder:
            TextField("Command text", text: resource.urlString)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        case .anki:
            TextField("Optional Anki link", text: resource.urlString, prompt: Text("anki://... or https://ankiweb.net/..."))
                .textFieldStyle(.roundedBorder)
        default:
            TextField("URL", text: resource.urlString, prompt: Text(resource.wrappedValue.type.defaultURLString ?? "https://example.com"))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                Spacer()
                Button {
                    taskDrafts.append(TemplateTaskDraft(title: "New task", type: .other, priority: 1, estimatedMinutes: nil))
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if taskDrafts.isEmpty {
                Text("No starter tasks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach($taskDrafts) { $task in
                        HStack(spacing: 8) {
                            TextField("Task title", text: $task.title)
                                .textFieldStyle(.roundedBorder)
                            DropdownMenu("Task type", selection: $task.type, options: StudyTaskType.allCases, minWidth: 142)
                            if let estimatedMinutes = task.estimatedMinutes {
                                Text("\(estimatedMinutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 46, alignment: .trailing)
                            }
                            Button {
                                taskDrafts.removeAll { $0.id == task.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove this starter task.")
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Create") {
                create(startImmediately: false)
            }
            .keyboardShortcut(.defaultAction)

            Button {
                create(startImmediately: true)
            } label: {
                Label("Create and Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func resourceURLRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear this resource.")
            }
        }
    }

    private func resourcePickerRow(
        label: String,
        url: URL?,
        placeholder: String,
        choose: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(url?.lastPathComponent ?? placeholder)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if url != nil {
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Button("Choose", action: choose)
        }
    }

    private func appResourcePickerRow(
        label: String,
        url: URL?,
        targetDesktopSpace: Binding<Int>,
        choose: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            resourcePickerRow(label: label, url: url, placeholder: "No app selected", choose: choose, clear: clear)

            if url != nil {
                HStack(spacing: 14) {
                    Text("Desktop")
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    DropdownMenu(
                        "Desktop Space",
                        selection: targetDesktopSpace,
                        options: desktopSpaceOptions,
                        isEnabled: license.plan.isPro && prepareDesktopSpacesOnSessionStart,
                        minWidth: 170
                    )
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .help("Place this app on a chosen desktop when desktop Spaces are prepared.")
            }
        }
    }

    private func applyTemplate(_ template: StudyBoxTemplate?) {
        errorMessage = nil
        if let template {
            type = template.boxType
            icon = template.systemImage
            colorHex = template.colorHex
            defaultSessionMinutes = template.defaultSessionMinutes
            defaultSessionMinutesText = String(template.defaultSessionMinutes)
            focusMode = .off
            taskDrafts = template.defaultTasks.map(TemplateTaskDraft.init(templateTask:))
        } else {
            type = .course
            icon = "books.vertical"
            colorHex = "#3B82F6"
            defaultSessionMinutes = 50
            defaultSessionMinutesText = "50"
            focusMode = .off
            taskDrafts = []
        }
    }

    private func create(startImmediately: Bool) {
        errorMessage = nil
        let createDecision = EntitlementRules.canCreateStudyBox(currentBoxCount: currentBoxCount, plan: license.plan)
        guard createDecision.isAllowed else {
            presentLicense(createDecision.message)
            return
        }
        if selectedTemplate != nil {
            let templateDecision = EntitlementRules.canUse(.nonBlankTemplates, plan: license.plan)
            guard templateDecision.isAllowed else {
                presentLicense(templateDecision.message)
                return
            }
        }
        let additionalResourceCount = additionalResourceDrafts.filter { !$0.isBlank }.count
        guard license.plan.isPro || additionalResourceCount <= freeAdditionalResourceLimit else {
            presentLicense(additionalResourceLimitMessage)
            return
        }
        guard let resources = makeResourceDrafts() else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedName = trimmedName.isEmpty ? selectedTemplate?.title ?? "Untitled Study Box" : trimmedName
        let storedCourseName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedSessionMinutes = NumericInput.integerValue(
            from: defaultSessionMinutesText,
            fallback: defaultSessionMinutes,
            range: 0...999
        )
        let savedPrepareDesktopSpaces = license.plan.isPro ? prepareDesktopSpacesOnSessionStart : false
        let savedMinimumDesktopSpaces = savedPrepareDesktopSpaces ? minimumDesktopSpaces : 1

        let box: StudyBox
        if let selectedTemplate {
            box = StudyBoxTemplateService.makeBox(
                template: selectedTemplate,
                name: storedName,
                courseName: storedCourseName.isEmpty ? nil : storedCourseName,
                dueDate: includeDueDate ? dueDate : nil,
                taskDrafts: taskDrafts,
                resources: resources
            )
            box.update(
                name: storedName,
                type: type,
                courseName: storedCourseName.isEmpty ? nil : storedCourseName,
                icon: icon,
                colorHex: colorHex,
                examDate: includeDueDate ? dueDate : nil,
                defaultSessionMinutes: storedSessionMinutes,
                openResourcesOnSessionStart: openResourcesOnSessionStart,
                hideDistractionsOnSessionStart: focusMode.hideDistractions,
                quitDistractionsOnSessionStart: focusMode.quitDistractions,
                enforceFocusOnSessionStart: focusMode.enforceFocus,
                restoreWindowLayoutOnSessionStart: false,
                keepDisplayAwakeDuringSessions: keepDisplayAwakeDuringSessions,
                prepareDesktopSpacesOnSessionStart: savedPrepareDesktopSpaces,
                minimumDesktopSpaces: savedMinimumDesktopSpaces,
                focusMode: focusMode
            )
        } else {
            box = StudyBox(
                name: storedName,
                type: type,
                courseName: storedCourseName.isEmpty ? nil : storedCourseName,
                icon: icon,
                colorHex: colorHex,
                examDate: includeDueDate ? dueDate : nil,
                focusMode: focusMode,
                openResourcesOnSessionStart: openResourcesOnSessionStart,
                keepDisplayAwakeDuringSessions: keepDisplayAwakeDuringSessions,
                defaultSessionMinutes: storedSessionMinutes,
                prepareDesktopSpacesOnSessionStart: savedPrepareDesktopSpaces,
                minimumDesktopSpaces: savedMinimumDesktopSpaces
            )
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
            box.tasks = taskDrafts.enumerated().compactMap { index, draft in
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return StudyTask(
                    box: box,
                    title: title,
                    type: draft.type,
                    priority: draft.priority,
                    estimatedMinutes: draft.estimatedMinutes,
                    dueDate: includeDueDate ? dueDate : nil,
                    orderIndex: index
                )
            }
        }

        dismiss()
        Task { @MainActor in
            await Task.yield()
            onCreated(box, startImmediately)
        }
    }

    private func presentLicense(_ reason: String?) {
        errorMessage = reason
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addAdditionalResourceDraft() {
        guard license.plan.isPro || additionalResourceDrafts.count < freeAdditionalResourceLimit else {
            presentLicense(additionalResourceLimitMessage)
            return
        }
        additionalResourceDrafts.append(CreateResourceDraft())
    }

    private var additionalResourceLimitMessage: String {
        "Free includes up to 3 additional resources. Upgrade to Pro to add more."
    }

    private func makeResourceDrafts() -> [OnboardingResourceDraft]? {
        var resources: [OnboardingResourceDraft] = []
        let primaryType = selectedTemplate?.primaryURLType ?? .website
        let primaryTitle = selectedTemplate?.primaryURLResourceTitle ?? "Website"
        let primaryLabel = selectedTemplate?.primaryURLLabel ?? "Website"

        if let draft = makeURLDraft(from: websiteText, label: primaryLabel, fallbackTitle: primaryTitle, preferredType: primaryType) {
            resources.append(draft)
        } else if errorMessage != nil {
            return nil
        }

        if let selectedTemplate, selectedTemplate.secondaryURLLabel != nil {
            if let draft = makeURLDraft(
                from: secondaryWebsiteText,
                label: selectedTemplate.secondaryURLLabel ?? "Website",
                fallbackTitle: selectedTemplate.secondaryURLResourceTitle ?? "Website",
                preferredType: selectedTemplate.secondaryURLType ?? .website
            ) {
                resources.append(draft)
            } else if errorMessage != nil {
                return nil
            }
        }

        if selectedTemplate?.fileLabel != nil || selectedTemplate == nil, let selectedFileURL {
            resources.append(OnboardingResourceDraft(title: selectedFileURL.lastPathComponent, type: .file, urlString: selectedFileURL.path))
        }
        if selectedTemplate?.folderLabel != nil || selectedTemplate == nil, let selectedFolderURL {
            resources.append(OnboardingResourceDraft(title: selectedFolderURL.lastPathComponent, type: .folder, urlString: selectedFolderURL.path))
        }
        if selectedTemplate?.primaryAppLabel != nil, let selectedPrimaryAppURL {
            resources.append(makeAppDraft(from: selectedPrimaryAppURL, targetDesktopSpace: primaryAppDesktopSpaceSelection))
        }
        if selectedTemplate?.secondaryAppLabel != nil, let selectedSecondaryAppURL {
            resources.append(makeAppDraft(from: selectedSecondaryAppURL, targetDesktopSpace: secondaryAppDesktopSpaceSelection))
        }

        for draft in additionalResourceDrafts {
            guard let resource = makeAdditionalResourceDraft(from: draft) else {
                if errorMessage != nil { return nil }
                continue
            }
            resources.append(resource)
        }

        return resources
    }

    private func makeAdditionalResourceDraft(from draft: CreateResourceDraft) -> OnboardingResourceDraft? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURLString = draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppPath = draft.appPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundleID = draft.appBundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty, trimmedURLString.isEmpty, trimmedAppPath.isEmpty, trimmedBundleID.isEmpty {
            return nil
        }

        switch draft.type {
        case .app:
            guard !trimmedAppPath.isEmpty || !trimmedBundleID.isEmpty else {
                errorMessage = "Choose an app for the additional app resource."
                return nil
            }
            return OnboardingResourceDraft(
                title: trimmedTitle.isEmpty ? URL(fileURLWithPath: trimmedAppPath).deletingPathExtension().lastPathComponent : trimmedTitle,
                type: .app,
                urlString: trimmedAppPath,
                appBundleID: trimmedBundleID.isEmpty ? nil : trimmedBundleID,
                appPath: trimmedAppPath.isEmpty ? nil : trimmedAppPath,
                targetDesktopSpace: normalizedDesktopSpace(draft.targetDesktopSpace)
            )
        case .file, .folder:
            guard !trimmedURLString.isEmpty else {
                errorMessage = "Choose a \(draft.type.title.lowercased()) for the additional resource."
                return nil
            }
            return OnboardingResourceDraft(
                title: trimmedTitle.isEmpty ? URL(fileURLWithPath: trimmedURLString).lastPathComponent : trimmedTitle,
                type: draft.type,
                urlString: trimmedURLString
            )
        case .notes, .commandPlaceholder:
            guard !trimmedURLString.isEmpty else {
                errorMessage = "Add text for the additional \(draft.type.title.lowercased())."
                return nil
            }
            return OnboardingResourceDraft(
                title: trimmedTitle.isEmpty ? draft.type.title : trimmedTitle,
                type: draft.type,
                urlString: trimmedURLString
            )
        case .anki:
            guard trimmedURLString.isEmpty || AnkiResourceService.normalizedLink(trimmedURLString) != nil else {
                errorMessage = "Additional Anki link does not look right."
                return nil
            }
            return OnboardingResourceDraft(
                title: trimmedTitle.isEmpty ? "Anki" : trimmedTitle,
                type: .anki,
                urlString: AnkiResourceService.normalizedLink(trimmedURLString) ?? trimmedURLString
            )
        default:
            guard let normalizedURLString = URLValidator.normalizedURLString(trimmedURLString) else {
                errorMessage = "Additional \(draft.type.title.lowercased()) URL does not look right."
                return nil
            }
            return OnboardingResourceDraft(
                title: trimmedTitle.isEmpty ? titleForURL(normalizedURLString, fallback: draft.type.title) : trimmedTitle,
                type: resourceType(for: normalizedURLString, preferredType: draft.type),
                urlString: normalizedURLString
            )
        }
    }

    private func makeURLDraft(
        from input: String,
        label: String,
        fallbackTitle: String,
        preferredType: ResourceType
    ) -> OnboardingResourceDraft? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return nil }
        let normalizedURL: String?
        if preferredType == .anki {
            normalizedURL = AnkiResourceService.normalizedLink(trimmedInput)
        } else {
            normalizedURL = URLValidator.normalizedURLString(trimmedInput)
        }

        guard let normalizedURL else {
            errorMessage = preferredType == .anki
                ? "\(label) Anki link does not look right."
                : "\(label) URL does not look right."
            return nil
        }
        return OnboardingResourceDraft(
            title: titleForURL(normalizedURL, fallback: fallbackTitle),
            type: resourceType(for: normalizedURL, preferredType: preferredType),
            urlString: normalizedURL
        )
    }

    private func makeAppDraft(from appURL: URL, targetDesktopSpace: Int = 0) -> OnboardingResourceDraft {
        OnboardingResourceDraft(
            title: appURL.deletingPathExtension().lastPathComponent,
            type: .app,
            urlString: appURL.path,
            appBundleID: AppPicker.bundleIdentifier(for: appURL),
            appPath: appURL.path,
            targetDesktopSpace: normalizedDesktopSpace(targetDesktopSpace)
        )
    }

    private func normalizedDesktopSpace(_ value: Int) -> Int? {
        guard license.plan.isPro, prepareDesktopSpacesOnSessionStart, value > 0 else { return nil }
        return min(value, SpaceLayoutManager.maximumManagedSpaces)
    }

    private func titleForURL(_ urlString: String, fallback: String) -> String {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else {
            return fallback
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func resourceType(for urlString: String, preferredType: ResourceType) -> ResourceType {
        if preferredType == .anki {
            return .anki
        }

        guard let host = URL(string: urlString)?.host?.lowercased() else {
            return preferredType
        }
        if host.contains("github.com") { return .github }
        if host.contains("moodle") { return .moodleCourse }
        if host.contains("blackboard") { return .blackboardCourse }
        if host.contains("overleaf.com") { return .overleaf }
        if host.contains("chatgpt.com") { return .chatgpt }
        return preferredType == .github ? .website : preferredType
    }

    private func resourcePathRow(
        placeholder: String,
        value: String,
        chooseTitle: String,
        choose: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(value.isEmpty ? placeholder : URL(fileURLWithPath: value).lastPathComponent)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if !value.isEmpty {
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Button(chooseTitle, action: choose)
        }
    }
}

private struct CreateResourceDraft: Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var type: ResourceType = .website
    var urlString = ""
    var appBundleID = ""
    var appPath = ""
    var targetDesktopSpace = 0

    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && appBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func applySuggestedURL(for newType: ResourceType) {
        type = newType
        appBundleID = ""
        appPath = ""
        urlString = ""
        targetDesktopSpace = 0
    }
}

private extension StudyBoxTemplate {
    var resourceSectionTitle: String {
        switch self {
        case .weeklyCourse: "Add course materials"
        case .examPrep: "Add exam prep materials"
        case .assignment: "Add assignment materials"
        case .codingProject: "Add project workspace"
        case .languageStudy: "Add practice materials"
        }
    }

    var primaryURLLabel: String {
        switch self {
        case .weeklyCourse: "Course site"
        case .examPrep: "Exam site"
        case .assignment: "Submission portal"
        case .codingProject: "Repository"
        case .languageStudy: "Anki deck/link"
        }
    }

    var primaryURLPlaceholder: String {
        switch self {
        case .weeklyCourse: "https://moodle.example/course/view.php?id=..."
        case .examPrep: "https://example.edu/exams"
        case .assignment: "https://example.edu/submit"
        case .codingProject: "https://github.com/example/project"
        case .languageStudy: "anki://... or https://ankiweb.net/..."
        }
    }

    var primaryURLResourceTitle: String {
        switch self {
        case .weeklyCourse: "Course site"
        case .examPrep: "Exam site"
        case .assignment: "Submission portal"
        case .codingProject: "Repository"
        case .languageStudy: "Anki"
        }
    }

    var primaryURLType: ResourceType {
        switch self {
        case .codingProject: .github
        case .languageStudy: .anki
        default: .website
        }
    }

    var secondaryURLLabel: String? {
        switch self {
        case .examPrep: "Anki deck/link"
        case .codingProject: "Docs"
        case .languageStudy: "Dictionary/listening"
        default: nil
        }
    }

    var secondaryURLPlaceholder: String? {
        switch self {
        case .examPrep: "anki://... or https://ankiweb.net/..."
        case .codingProject: "https://developer.apple.com/documentation/..."
        case .languageStudy: "https://www.wordreference.com/..."
        default: nil
        }
    }

    var secondaryURLResourceTitle: String? {
        switch self {
        case .examPrep: "Anki"
        case .codingProject: "Docs"
        case .languageStudy: "Dictionary or listening"
        default: nil
        }
    }

    var secondaryURLType: ResourceType? {
        switch self {
        case .examPrep: .anki
        default: nil
        }
    }

    var fileLabel: String? {
        switch self {
        case .weeklyCourse: "Syllabus/reading"
        case .examPrep: "Past paper"
        case .assignment: "Brief/spec"
        case .languageStudy: "Textbook/audio"
        case .codingProject: nil
        }
    }

    var folderLabel: String? {
        switch self {
        case .weeklyCourse: "Notes folder"
        case .examPrep: "Revision folder"
        case .assignment: "Working folder"
        case .codingProject: "Project folder"
        case .languageStudy: "Materials folder"
        }
    }

    var primaryAppLabel: String? {
        switch self {
        case .codingProject: "Code editor"
        case .languageStudy: "Practice app"
        default: nil
        }
    }

    var secondaryAppLabel: String? {
        switch self {
        case .codingProject: "Terminal/tool"
        default: nil
        }
    }
}

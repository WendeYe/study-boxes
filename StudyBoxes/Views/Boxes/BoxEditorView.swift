import AppKit
import SwiftData
import SwiftUI

struct BoxEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    private let box: StudyBox?
    @ObservedObject private var license = LicenseManager.shared

    @State private var name: String
    @State private var type: StudyBoxType
    @State private var courseName: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var hasExamDate: Bool
    @State private var examDate: Date
    @State private var defaultSessionMinutes: Int
    @State private var defaultSessionMinutesText: String
    @State private var openResourcesOnSessionStart: Bool
    @State private var focusMode: StudyFocusMode
    @State private var restoreWindowLayoutOnSessionStart: Bool
    @State private var keepDisplayAwakeDuringSessions: Bool
    @State private var prepareDesktopSpacesOnSessionStart: Bool
    @State private var minimumDesktopSpaces: Int
    @State private var errorMessage: String?

    // MARK: Available icons and colors

    private let icons = [
        "books.vertical", "graduationcap", "function", "sum",
        "atom", "desktopcomputer", "doc.text", "calendar",
        "flask", "brain", "music.note", "paintpalette",
        "globe", "building.columns", "chart.bar", "pencil"
    ]

    private let colors: [(hex: String, name: String)] = [
        ("#3B82F6", "Blue"),
        ("#14B8A6", "Teal"),
        ("#22C55E", "Green"),
        ("#F59E0B", "Amber"),
        ("#EF4444", "Red"),
        ("#A855F7", "Purple"),
        ("#EC4899", "Pink"),
        ("#64748B", "Slate")
    ]

    init(box: StudyBox? = nil) {
        self.box = box
        _name = State(initialValue: box?.name ?? "")
        _type = State(initialValue: box?.type ?? .course)
        _courseName = State(initialValue: box?.courseName ?? "")
        _icon = State(initialValue: box?.icon ?? "books.vertical")
        _colorHex = State(initialValue: box?.colorHex ?? "#3B82F6")
        _hasExamDate = State(initialValue: box?.examDate != nil)
        _examDate = State(initialValue: box?.examDate ?? .now)
        _defaultSessionMinutes = State(initialValue: box?.defaultSessionMinutes ?? 50)
        _defaultSessionMinutesText = State(initialValue: String(box?.defaultSessionMinutes ?? 50))
        _openResourcesOnSessionStart = State(initialValue: box?.openResourcesOnSessionStart ?? true)
        _focusMode = State(initialValue: box?.focusMode ?? .off)
        _restoreWindowLayoutOnSessionStart = State(initialValue: box?.restoreWindowLayoutOnSessionStart ?? false)
        _keepDisplayAwakeDuringSessions = State(initialValue: box?.keepDisplayAwakeDuringSessions ?? true)
        _prepareDesktopSpacesOnSessionStart = State(initialValue: box?.prepareDesktopSpacesOnSessionStart ?? false)
        _minimumDesktopSpaces = State(initialValue: box?.minimumDesktopSpaces ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                // MARK: Identity
                Section("Study Box") {
                    TextField("Name", text: $name)
                        .help("Use a short name, like Calculus II, Operating Systems, or French Oral.")

                    DropdownMenuRow("Type", selection: $type, options: StudyBoxType.allCases)

                    TextField("Course code or class name", text: $courseName)
                        .help("Optional. Shown under the box name.")
                }

                // MARK: Appearance
                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: colorHex).opacity(0.15))
                                    .frame(width: 52, height: 52)
                                Image(systemName: icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color(hex: colorHex))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name.isEmpty ? "Study Box" : name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(type.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        Text("Icon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 6) {
                            ForEach(icons, id: \.self) { iconName in
                                Button {
                                    icon = iconName
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(icon == iconName
                                                  ? Color(hex: colorHex).opacity(0.2)
                                                  : Color.clear)
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(icon == iconName
                                                          ? Color(hex: colorHex)
                                                          : Color.clear, lineWidth: 1.5)
                                        Image(systemName: iconName)
                                            .font(.system(size: 15))
                                            .foregroundStyle(icon == iconName
                                                             ? Color(hex: colorHex)
                                                             : Color.primary)
                                    }
                                    .frame(height: 34)
                                }
                                .buttonStyle(.plain)
                                .help(iconName)
                            }
                        }

                        Text("Color")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(colors, id: \.hex) { swatch in
                                Button {
                                    colorHex = swatch.hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: swatch.hex))
                                            .frame(width: 24, height: 24)
                                        if colorHex == swatch.hex {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 2)
                                                .frame(width: 24, height: 24)
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

                // MARK: Planning
                Section("Planning") {
                    HStack {
                        Toggle("Exam or deadline date", isOn: $hasExamDate)
                        Spacer()
                        if hasExamDate {
                            SystemDatePickerField(date: $examDate, accessibilityLabel: "Exam or deadline date")
                        }
                    }

                    HStack {
                        Text("Presets")
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(SessionPreset.defaultMinutes, id: \.self) { minutes in
                                Button("\(minutes)") {
                                    defaultSessionMinutesText = String(minutes)
                                    defaultSessionMinutes = minutes
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .tint(defaultSessionMinutes == minutes ? .accentColor : nil)
                            }
                        }
                    }

                    HStack {
                        Text("Session length")
                        Spacer()
                        HStack(spacing: 4) {
                            TextField("", text: $defaultSessionMinutesText)
                                .frame(width: 64)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            Text("min")
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    .help("Choose a preset or type any whole number up to 999 minutes.")
                    .onChange(of: defaultSessionMinutesText) { _, newValue in
                        let sanitized = NumericInput.sanitizedIntegerText(newValue, range: 0...999)
                        if sanitized != newValue { defaultSessionMinutesText = sanitized }
                        defaultSessionMinutes = NumericInput.integerValue(from: sanitized, fallback: defaultSessionMinutes, range: 0...999)
                    }
                }

                // MARK: Session start behaviour
                Section("Session Start") {
                    Toggle("Open study setup", isOn: $openResourcesOnSessionStart)
                    FocusModeMenu(selection: $focusMode, isEnabled: license.plan.isPro)
                    Toggle("Restore saved window layout", isOn: $restoreWindowLayoutOnSessionStart)
                        .disabled(!license.plan.isPro)
                    Toggle("Prepare desktop Spaces", isOn: $prepareDesktopSpacesOnSessionStart)
                        .disabled(!license.plan.isPro)
                    if prepareDesktopSpacesOnSessionStart {
                        Stepper(
                            "Keep at least \(minimumDesktopSpaces) desktops ready",
                            value: $minimumDesktopSpaces,
                            in: 1...SpaceLayoutManager.maximumManagedSpaces
                        )
                    }
                    Toggle("Keep display awake", isOn: $keepDisplayAwakeDuringSessions)

                    Text(focusMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if prepareDesktopSpacesOnSessionStart {
                        Text("Best effort. Study Boxes can create missing desktops and place chosen app resources there when a session starts. Existing desktops stay untouched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !license.plan.isPro {
                        Button {
                            presentLicense(EntitlementRules.canUse(.focusModes, plan: .free).message)
                        } label: {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text("Focus modes, saved window layouts, and desktop Space setup are included with Pro. Your saved Pro settings stay here, but Free sessions will ignore them.")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text("Study Boxes can restore browser windows, but it never reads or restores individual tabs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(box == nil ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    // MARK: Save logic (unchanged from original)

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Give this Study Box a name."
            return
        }

        let trimmedCourseName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedCourseName = trimmedCourseName.isEmpty ? nil : trimmedCourseName
        let storedExamDate = hasExamDate ? examDate : nil
        let storedDefaultSessionMinutes = NumericInput.integerValue(
            from: defaultSessionMinutesText,
            fallback: defaultSessionMinutes,
            range: 0...999
        )
        let savedFocusMode = license.plan.isPro ? focusMode : (box?.focusMode ?? .off)
        let savedRestoreWindowLayout = license.plan.isPro ? restoreWindowLayoutOnSessionStart : (box?.restoreWindowLayoutOnSessionStart ?? false)
        let savedPrepareDesktopSpaces = license.plan.isPro ? prepareDesktopSpacesOnSessionStart : (box?.prepareDesktopSpacesOnSessionStart ?? false)
        let savedMinimumDesktopSpaces = license.plan.isPro ? minimumDesktopSpaces : (box?.minimumDesktopSpaces ?? 1)

        if let box {
            box.update(
                name: trimmedName,
                type: type,
                courseName: storedCourseName,
                icon: icon,
                colorHex: colorHex,
                examDate: storedExamDate,
                defaultSessionMinutes: storedDefaultSessionMinutes,
                openResourcesOnSessionStart: openResourcesOnSessionStart,
                hideDistractionsOnSessionStart: savedFocusMode.hideDistractions,
                quitDistractionsOnSessionStart: savedFocusMode.quitDistractions,
                enforceFocusOnSessionStart: savedFocusMode.enforceFocus,
                restoreWindowLayoutOnSessionStart: savedRestoreWindowLayout,
                keepDisplayAwakeDuringSessions: keepDisplayAwakeDuringSessions,
                prepareDesktopSpacesOnSessionStart: savedPrepareDesktopSpaces,
                minimumDesktopSpaces: savedMinimumDesktopSpaces,
                focusMode: savedFocusMode
            )
        } else {
            let box = StudyBox(
                name: trimmedName,
                type: type,
                courseName: storedCourseName,
                icon: icon,
                colorHex: colorHex,
                examDate: storedExamDate,
                hideDistractionsOnSessionStart: savedFocusMode.hideDistractions,
                quitDistractionsOnSessionStart: savedFocusMode.quitDistractions,
                enforceFocusOnSessionStart: savedFocusMode.enforceFocus,
                focusMode: savedFocusMode,
                restoreWindowLayoutOnSessionStart: savedRestoreWindowLayout,
                openResourcesOnSessionStart: openResourcesOnSessionStart,
                keepDisplayAwakeDuringSessions: keepDisplayAwakeDuringSessions,
                defaultSessionMinutes: storedDefaultSessionMinutes,
                prepareDesktopSpacesOnSessionStart: savedPrepareDesktopSpaces,
                minimumDesktopSpaces: savedMinimumDesktopSpaces
            )
            modelContext.insert(box)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Study Boxes could not save this Study Box."
        }
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}

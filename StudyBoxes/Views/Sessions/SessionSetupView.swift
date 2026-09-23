import AppKit
import SwiftUI

struct SessionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    let box: StudyBox
    let onStart: (SessionStartOptions) -> Void

    @State private var plannedMinutes: Int
    @State private var plannedMinutesText: String
    @State private var openResources: Bool
    @State private var focusMode: StudyFocusMode
    @State private var restoreWindowLayout: Bool
    @State private var keepDisplayAwake: Bool
    @State private var prepareDesktopSpaces: Bool
    @State private var showingFocusPreflight = false
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var license = LicenseManager.shared

    init(box: StudyBox, onStart: @escaping (SessionStartOptions) -> Void) {
        self.box = box
        self.onStart = onStart
        _plannedMinutes = State(initialValue: box.defaultSessionMinutes)
        _plannedMinutesText = State(initialValue: String(box.defaultSessionMinutes))
        _openResources = State(initialValue: box.openResourcesOnSessionStart)
        _focusMode = State(initialValue: box.focusMode)
        _restoreWindowLayout = State(initialValue: box.restoreWindowLayoutOnSessionStart)
        _keepDisplayAwake = State(initialValue: box.keepDisplayAwakeDuringSessions ?? true)
        _prepareDesktopSpaces = State(initialValue: box.prepareDesktopSpacesOnSessionStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: box.colorHex).opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: box.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(hex: box.colorHex))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Start Study Session")
                        .font(.title2.weight(.semibold))
                    Text(box.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .padding(.bottom, 4)

            Divider()

            // MARK: Form
            Form {
                Section("Plan") {
                    HStack {
                        Text("Presets")
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(SessionPreset.defaultMinutes, id: \.self) { minutes in
                                Button("\(minutes)") {
                                    plannedMinutesText = String(minutes)
                                    plannedMinutes = minutes
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .tint(plannedMinutes == minutes ? .accentColor : nil)
                            }
                        }
                    }

                    HStack {
                        Text("Session length")
                        Spacer()
                        HStack(spacing: 6) {
                            TextField("", text: $plannedMinutesText)
                                .frame(width: 64)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            Text("min")
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    .help("Type any whole number up to 999 minutes.")
                    .onChange(of: plannedMinutesText) { _, newValue in
                        let sanitized = NumericInput.sanitizedIntegerText(newValue, range: 0...999)
                        if sanitized != newValue { plannedMinutesText = sanitized }
                        plannedMinutes = NumericInput.integerValue(from: sanitized, fallback: plannedMinutes, range: 0...999)
                    }
                }

                Section("On Start") {
                    Toggle(isOn: $openResources) {
                        Label("Open study setup", systemImage: "folder")
                    }
                    FocusModeMenu(selection: $focusMode, isEnabled: license.plan.isPro)
                    Text(focusMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $restoreWindowLayout) {
                        Label("Restore saved window layout", systemImage: "macwindow")
                    }
                    .disabled(!permissions.isAccessibilityTrusted || !license.plan.isPro)

                    Toggle(isOn: $prepareDesktopSpaces) {
                        Label("Prepare desktop Spaces", systemImage: "rectangle.3.group")
                    }
                    .disabled(!license.plan.isPro)

                    Toggle(isOn: $keepDisplayAwake) {
                        Label("Keep display awake", systemImage: "display")
                    }

                    if !permissions.isAccessibilityTrusted {
                        Label(
                            "Window layout restore, Quit Apps, and Strict Focus need Accessibility. You can still start without them.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    if !license.plan.isPro {
                        Button {
                            presentLicense(EntitlementRules.canUse(.focusModes, plan: .free).message)
                        } label: {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text("Focus modes, saved window layouts, and desktop Space setup are included with Pro. Free sessions ignore those settings.")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if prepareDesktopSpaces {
                        Text("Best effort. Study Boxes can create missing desktops and place chosen app resources there before you start. Existing desktops stay untouched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Study Boxes can restore browser windows, but it never reads or restores individual tabs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            // MARK: Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 420)
        .onAppear {
            permissions.refresh()
            if !permissions.isAccessibilityTrusted { restoreWindowLayout = false }
            if !license.plan.isPro {
                focusMode = .off
                restoreWindowLayout = false
                prepareDesktopSpaces = false
            }
        }
        .onChange(of: permissions.isAccessibilityTrusted) { _, isTrusted in
            if !isTrusted { restoreWindowLayout = false }
            if !isTrusted, focusMode.requiresAccessibilityForRestore {
                focusMode = .hideApps
            }
        }
        .sheet(isPresented: $showingFocusPreflight) {
            FocusPreflightView(box: box, focusMode: focusMode) {
                showingFocusPreflight = false
                beginSession()
            } onCancel: {
                showingFocusPreflight = false
            }
            .frame(minWidth: 460, minHeight: 360)
        }
    }

    private func start() {
        if !license.plan.isPro {
            focusMode = .off
            restoreWindowLayout = false
            prepareDesktopSpaces = false
        }
        if focusMode.requiresAccessibilityForRestore, !permissions.isAccessibilityTrusted {
            PermissionManager.requestAccessibilityPermission()
            PermissionManager.openAccessibilitySettings()
            return
        }
        if (focusMode == .quitApps || focusMode == .strictFocus), !box.skipFocusQuitConfirmation {
            showingFocusPreflight = true
            return
        }
        beginSession()
    }

    private func beginSession() {
        let options = SessionStartOptions(
            plannedMinutes: NumericInput.integerValue(from: plannedMinutesText, fallback: plannedMinutes, range: 0...999),
            openResources: openResources,
            hideDistractions: focusMode.hideDistractions,
            quitDistractions: focusMode.quitDistractions,
            enforceFocus: focusMode.enforceFocus,
            restoreWindowLayout: restoreWindowLayout,
            keepDisplayAwake: keepDisplayAwake,
            focusMode: focusMode,
            prepareDesktopSpaces: prepareDesktopSpaces
        )
        onStart(EntitlementRules.sanitizedSessionOptions(options, plan: license.plan))
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var boxes: [StudyBox]

    @State private var backupMessage: String?
    @State private var pendingImportURL: URL?
    @State private var importPreview: BackupImportPreview?
    @State private var skipDuplicateNames = false
    @State private var isConfirmingImport = false
    @State private var reminderIntervalText = ""
    @ObservedObject private var preferences = UserPreferencesService.shared
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        Form {
            if appState.isLicensePresented {
                LicenseView()
            }

            settingsSections(includeLicense: !appState.isLicensePresented)
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 620)
        .onAppear {
            reminderIntervalText = String(preferences.wellnessReminderIntervalMinutes)
        }
        .onDisappear {
            appState.clearLicensePresentation()
        }
        .alert("Import backup?", isPresented: $isConfirmingImport) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
                importPreview = nil
            }
            if importPreview?.duplicateBoxNames.isEmpty == false {
                Button("Skip Duplicates") {
                    skipDuplicateNames = true
                    performImportBackup()
                }
            }
            Button("Import as Copies", role: .destructive) {
                skipDuplicateNames = false
                performImportBackup()
            }
        } message: {
            if let importPreview {
                Text("Study Boxes found \(importPreview.summary). Your existing data will stay in place.")
            } else {
                Text("Study Boxes will add boxes, resources, tasks, and sessions from this file. Your existing data will stay in place.")
            }
        }
    }

    @ViewBuilder
    private func settingsSections(includeLicense: Bool) -> some View {
        Section("Sessions") {
            DropdownMenuRow(
                "Active session title",
                selection: $preferences.menuBarDisplayMode,
                options: MenuBarDisplayMode.allCases
            )
            Text("When no session is running, the menu bar stays out of the way. During a session, choose whether it shows the icon, the timer, or the box name and timer.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Break and posture reminders", isOn: $preferences.wellnessRemindersEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Remind after")
                    Spacer()
                    HStack(spacing: 6) {
                        TextField(
                            ReminderIntervalInputPresentation.textFieldTitle,
                            text: $reminderIntervalText,
                            prompt: Text(ReminderIntervalInputPresentation.prompt)
                        )
                            .labelsHidden()
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Reminder interval minutes")
                            .disabled(!preferences.wellnessRemindersEnabled)
                            .onChange(of: reminderIntervalText) { _, newValue in
                                let sanitized = NumericInput.sanitizedIntegerText(
                                    newValue,
                                    range: WellnessReminderIntervalRange.allowedRange
                                )
                                if sanitized != newValue {
                                    reminderIntervalText = sanitized
                                    return
                                }
                                guard !sanitized.isEmpty else { return }
                                preferences.wellnessReminderIntervalMinutes = NumericInput.integerValue(
                                    from: sanitized,
                                    fallback: preferences.wellnessReminderIntervalMinutes,
                                    range: WellnessReminderIntervalRange.allowedRange
                                )
                            }
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(WellnessReminderInterval.allCases) { interval in
                        Button(interval.title) {
                            preferences.wellnessReminderIntervalMinutes = interval.rawValue
                            reminderIntervalText = String(interval.rawValue)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!preferences.wellnessRemindersEnabled)
                    }
                }

                Text("Choose a preset or enter any value from 5 to 180 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("After you mark a task done, Study Boxes can suggest a quick break or posture check when enough time has passed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        PermissionsView()
        DiagnosticsSettingsView()
        DistractionSettingsView()
        if includeLicense {
            LicenseView()
        }
        UpdateSettingsView()

        Section("Backup and safety") {
            Text("Your Study Boxes stay on this Mac. Private calendar feed links stay in Keychain and are not exported by default.")
                .foregroundStyle(.secondary)
            Text("Backups can include ordinary website links and local file paths. Review imported files before adding them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Export Backup JSON") {
                    exportBackup()
                }
                .help("Save boxes, resources, tasks, and sessions to a JSON file. Private feed tokens stay out of the export.")

                Button("Import Backup JSON") {
                    chooseImportBackup()
                }
                .help("Review and import boxes, resources, tasks, and sessions from a Study Boxes JSON backup.")

                if !license.plan.isPro {
                    ProBadge()
                }
            }

            if let backupMessage {
                Text(backupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Browser limitation") {
            Text("Study Boxes can restore browser windows it affected, but it never reads or restores individual tabs.")
                .foregroundStyle(.secondary)
        }
    }

    private func exportBackup() {
        guard let url = FilePicker.chooseJSONExport(defaultName: "Study Boxes Backup.json") else { return }
        do {
            try BackupService.export(boxes: boxes, to: url)
            backupMessage = "Exported backup."
        } catch {
            backupMessage = "Study Boxes could not export the backup."
        }
    }

    private func chooseImportBackup() {
        let decision = EntitlementRules.canUse(.backupImport, plan: license.plan)
        guard decision.isAllowed else {
            backupMessage = decision.message
            appState.presentLicense(reason: decision.message)
            return
        }

        guard let url = FilePicker.chooseJSONImport() else { return }
        do {
            importPreview = try BackupService.previewImport(from: url, existingBoxes: boxes)
            pendingImportURL = url
            isConfirmingImport = true
        } catch {
            backupMessage = "Study Boxes could not read this backup."
        }
    }

    private func performImportBackup() {
        guard let url = pendingImportURL else { return }
        do {
            try BackupService.import(
                from: url,
                modelContext: modelContext,
                existingBoxes: boxes,
                duplicatePolicy: skipDuplicateNames ? .skipMatchingNames : .insertCopies,
                plan: license.plan
            )
            backupMessage = "Imported backup."
        } catch BackupImportError.requiresPro {
            let message = EntitlementRules.canUse(.backupImport, plan: .free).message
            backupMessage = message
            appState.presentLicense(reason: message)
        } catch {
            backupMessage = "Study Boxes could not import the backup."
        }
        pendingImportURL = nil
        importPreview = nil
    }
}

enum ReminderIntervalInputPresentation {
    static let textFieldTitle = ""
    static let prompt = "25"
}

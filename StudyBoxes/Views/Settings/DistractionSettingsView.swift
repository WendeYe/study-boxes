import SwiftUI
import SwiftData

enum FocusRestoreSettingsPresentation {
    static let title = "Restore on session end"
    static let body = "Study Boxes restores affected apps and window positions automatically after Quit Apps or Strict Focus sessions end. Hide Apps restores window positions best effort when Accessibility is available."
    static let systemImage = "arrow.counterclockwise"
    static let isConfigurable = false
}

struct DistractionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var boxes: [StudyBox]
    @ObservedObject private var manager = DistractionManager.shared
    @ObservedObject private var license = LicenseManager.shared
    @State private var bundleID = ""

    var body: some View {
        Section("Focus controls") {
            Text("Hide moves unrelated apps out of view. Quit asks unrelated apps to close. Strict Focus blocks newly opened unrelated apps during a session. Study Boxes never force quits, never touches protected apps, and never reads browser tabs.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: FocusRestoreSettingsPresentation.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(FocusRestoreSettingsPresentation.title)
                            .font(.headline)

                        Text("Automatic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }

                    Text(FocusRestoreSettingsPresentation.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !license.plan.isPro {
                HStack(spacing: 6) {
                    ProBadge()
                    Text("Focus controls and previous app restore are included with Pro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if manager.isFocusEnforcementActive {
                Button("Pause Strict Focus") {
                    manager.stopFocusEnforcement()
                }
                .help("Stop blocking newly launched apps for the current session.")
            }

            Button {
                chooseProtectedApp()
            } label: {
                Label("Choose Protected App...", systemImage: "app.badge")
            }
            .disabled(!license.plan.isPro)
            .help("Pick an app that should never be hidden or quit during study sessions.")

            DisclosureGroup("Advanced Bundle ID Entry") {
                HStack {
                    TextField("Protected app bundle ID", text: $bundleID)
                    Button("Add") {
                        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        manager.protect(trimmed)
                        bundleID = ""
                    }
                    .disabled(!license.plan.isPro)
                }
            }
            .disabled(!license.plan.isPro)

            Button("Reset Quit/Strict Confirmations") {
                for box in boxes {
                    box.skipFocusQuitConfirmation = false
                }
                try? modelContext.save()
            }
            .disabled(!license.plan.isPro)
            .help("Show the Quit Apps and Strict Focus pre-flight sheet again for every Study Box.")

            pendingRestoreSection

            ForEach(Array(manager.protectedBundleIDs).sorted(), id: \.self) { id in
                HStack {
                    Text(id)
                        .font(.caption)
                    Spacer()
                    Button("Remove") {
                        manager.removeProtection(for: id)
                    }
                    .disabled(!license.plan.isPro || id == "com.apple.finder" || id == "com.apple.systempreferences" || id == "com.apple.systemsettings")
                }
            }
        }
    }

    @ViewBuilder
    private var pendingRestoreSection: some View {
        let snapshots = SessionRestoreManager.pendingSnapshots(modelContext: modelContext)
        if !snapshots.isEmpty {
            DisclosureGroup("Pending Previous App Restores") {
                ForEach(snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(snapshot.lastMessage ?? "\(snapshot.apps.filter(\.shouldRestore).count) apps pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Retry") {
                            Task {
                                _ = await SessionRestoreManager.restore(snapshot: snapshot, modelContext: modelContext)
                            }
                        }
                        .disabled(!license.plan.isPro)
                        Button("Dismiss") {
                            snapshot.dismiss()
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
    }

    private func chooseProtectedApp() {
        guard let appURL = AppPicker.chooseApplication(),
              let bundleID = AppPicker.bundleIdentifier(for: appURL) else {
            return
        }
        manager.protect(bundleID)
    }
}

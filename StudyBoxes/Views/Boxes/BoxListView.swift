import AppKit
import SwiftData
import SwiftUI

struct BoxListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState
    @Binding var selectedBoxID: UUID?
    var onCreateAndStart: (StudyBox) -> Void = { _ in }

    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var boxes: [StudyBox]

    @State private var isCreatingBox = false
    @State private var showsArchived = false
    @ObservedObject private var license = LicenseManager.shared

    private var visibleBoxes: [StudyBox] {
        boxes.filter { showsArchived ? $0.isArchived : !$0.isArchived }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedBoxID) {
                Section {
                    Label("Home", systemImage: "house")
                        .tag(Optional<UUID>.none)
                }

                Section(showsArchived ? "Archived" : "Active") {
                    ForEach(visibleBoxes) { box in
                        BoxListRow(box: box)
                            .tag(Optional(box.id))
                            .contextMenu {
                                if box.isArchived {
                                    Button("Restore") {
                                        restore(box)
                                    }
                                } else {
                                    Button("Archive") {
                                        box.archive()
                                        save()
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    delete(box)
                                }
                            }
                    }
                }
            }

            Divider()

            HStack {
                Toggle(isOn: $showsArchived) {
                    Label(
                        showsArchived ? "Hide Archived" : "Show Archived",
                        systemImage: showsArchived ? "archivebox.fill" : "archivebox"
                    )
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(showsArchived ? "Switch back to active Study Boxes." : "Show archived Study Boxes.")

                Spacer()

                Button {
                    attemptCreateBox()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new Study Box.")
            }
            .padding(12)
        }
        .sheet(isPresented: $isCreatingBox) {
            TemplateBoxCreatorView(currentBoxCount: boxes.count) { box, startImmediately in
                modelContext.insert(box)
                save()
                selectedBoxID = box.id
                appState.openBox(box.id)
                isCreatingBox = false
                if startImmediately {
                    Task { @MainActor in
                        await Task.yield()
                        onCreateAndStart(box)
                    }
                }
            }
            .environmentObject(appState)
        }
    }

    // MARK: Helpers

    private func attemptCreateBox() {
        let decision = EntitlementRules.canCreateStudyBox(currentBoxCount: boxes.count, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }
        isCreatingBox = true
    }

    private func restore(_ box: StudyBox) {
        let decision = EntitlementRules.canUnarchiveStudyBox(totalBoxCount: boxes.count, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }
        box.restore()
        save()
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func delete(_ box: StudyBox) {
        if selectedBoxID == box.id {
            selectedBoxID = nil
        }
        modelContext.delete(box)
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save StudyBox changes: \(error)")
        }
    }
}

// MARK: - BoxListRow

private struct BoxListRow: View {
    let box: StudyBox

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(box.name)
                    .font(.body)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: box.colorHex).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: box.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: box.colorHex))
            }
        }
    }

    private var subtitle: String {
        if let courseName = box.courseName, !courseName.isEmpty {
            return "\(box.type.title) - \(courseName)"
        }
        return box.type.title
    }
}

import SwiftData
import SwiftUI

#if DEBUG
struct DeveloperTestToolsView: View {
    let boxes: [StudyBox]

    @State private var selectedBoxID: UUID?
    @State private var message: String?
    @State private var isRunning = false

    private var activeBoxes: [StudyBox] {
        boxes.filter { !$0.isArchived }
    }

    private var selectedBox: StudyBox? {
        guard let selectedBoxID else { return activeBoxes.first }
        return activeBoxes.first { $0.id == selectedBoxID }
    }

    var body: some View {
        Section("Debug system tests") {
            Text("These buttons exercise real macOS behavior in this debug build. They may open TextEdit, show a notification, move a window, hide apps, or ask unrelated apps to quit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !activeBoxes.isEmpty {
                DropdownMenuRow(
                    "Study Box for app hiding",
                    selection: selectedBoxBinding,
                    options: activeBoxes.map {
                        DropdownMenuOption(value: Optional($0.id), title: $0.name, systemImage: $0.icon)
                    },
                    minWidth: 220
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Button {
                        run {
                            await SystemTestService.sendTestNotification()
                        }
                    } label: {
                        Label("Test Notification", systemImage: "bell.badge")
                    }

                    Button {
                        run {
                            await MainActor.run {
                                SystemTestService.openTestWebsite()
                            }
                        }
                    } label: {
                        Label("Open Website", systemImage: "globe")
                    }
                }

                GridRow {
                    Button {
                        run {
                            await SystemTestService.launchTextEdit()
                        }
                    } label: {
                        Label("Launch TextEdit", systemImage: "app")
                    }

                    Button {
                        guard let selectedBox else {
                            message = "Create a Study Box before testing app hiding."
                            return
                        }
                        run {
                            await MainActor.run {
                                SystemTestService.hideUnrelatedApps(for: selectedBox)
                            }
                        }
                    } label: {
                        Label("Hide Unrelated Apps", systemImage: "eye.slash")
                    }
                    .disabled(selectedBox == nil)
                }

                GridRow {
                    Button {
                        guard let selectedBox else {
                            message = "Create a Study Box before testing quit requests."
                            return
                        }
                        run {
                            await MainActor.run {
                                SystemTestService.quitUnrelatedApps(for: selectedBox)
                            }
                        }
                    } label: {
                        Label("Ask Apps To Quit", systemImage: "xmark.app")
                    }
                    .disabled(selectedBox == nil)

                    Button {
                        run {
                            await MainActor.run {
                                SystemTestService.restoreHiddenApps()
                            }
                        }
                    } label: {
                        Label("Restore Hidden Apps", systemImage: "eye")
                    }

                    Button {
                        run {
                            await SystemTestService.moveTextEditWindow()
                        }
                    } label: {
                        Label("Move TextEdit Window", systemImage: "rectangle.arrowtriangle.2.inward")
                    }
                }
            }
            .disabled(isRunning)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedBoxBinding: Binding<UUID?> {
        Binding {
            selectedBoxID ?? activeBoxes.first?.id
        } set: { selectedBoxID = $0 }
    }

    private func run(_ operation: @escaping () async -> String) {
        isRunning = true
        message = "Running..."
        Task {
            let result = await operation()
            message = result
            isRunning = false
        }
    }
}
#endif

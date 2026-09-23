import SwiftUI

struct FocusPreflightView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var box: StudyBox
    let focusMode: StudyFocusMode
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var skipNextTime = false

    private var affectedApps: [DistractionActionResult] {
        DistractionManager.shared.previewAppsToQuit(for: box)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(focusMode.title, systemImage: focusMode.systemImage)
                .font(.title2.weight(.semibold))

            Text("Study Boxes will ask these apps to quit. When you finish, it will reopen affected apps and restore their windows.")
                .foregroundStyle(.secondary)

            if affectedApps.isEmpty {
                ContentUnavailableView(
                    "No unrelated apps need to quit",
                    systemImage: "checkmark.circle",
                    description: Text("Study apps and protected apps will stay open.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(affectedApps) { app in
                    Label(app.appName, systemImage: "app")
                        .help(app.bundleID)
                }
                .frame(minHeight: 120)
            }

            Text("Study Boxes can restore browser windows, but it never reads or restores individual tabs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Don't ask again for this Study Box", isOn: $skipNextTime)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    box.skipFocusQuitConfirmation = skipNextTime
                    dismiss()
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
    }
}

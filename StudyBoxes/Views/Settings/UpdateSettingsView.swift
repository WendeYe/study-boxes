import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject private var manager = UpdateManager.shared

    var body: some View {
        Section("Updates") {
            Text("Update checks are prepared for direct-download releases. This debug build does not have Sparkle bundled yet.")
                .foregroundStyle(.secondary)

            Button("Check for Updates") {
                manager.checkForUpdates()
            }

            Text(manager.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Release builds will use a signed Sparkle appcast.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

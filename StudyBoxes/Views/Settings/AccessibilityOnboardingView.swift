import AppKit
import SwiftUI

struct AccessibilityOnboardingView: View {
    @ObservedObject private var permissions = PermissionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTask: Task<Void, Never>?
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Window layout restore needs Accessibility", systemImage: "rectangle.3.group")
                .font(.title2.weight(.semibold))

            Text("Study Boxes needs Accessibility permission to arrange and resize windows for your study setup.")
                .foregroundStyle(.secondary)

            Text("It does not read messages or type for you. Without this permission, Study Boxes can still open resources, track tasks, and run sessions.")
                .foregroundStyle(.secondary)

            HStack {
                Label(
                    permissions.isAccessibilityTrusted ? "Permission granted" : "Permission not granted",
                    systemImage: permissions.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(permissions.isAccessibilityTrusted ? .green : .orange)

                Spacer()
            }
            .padding(12)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(permissions.isAccessibilityTrusted ? .green : .secondary)
            }

            HStack {
                Button("Open System Settings") {
                    statusMessage = "After you turn Study Boxes on, come back here and choose Check Again."
                    PermissionManager.requestAccessibilityPermission()
                    PermissionManager.openAccessibilitySettings()
                }

                Button("Check Again") {
                    refreshAndDismissIfGranted()
                }

                Button("Continue Without Layout Restore") {
                    dismiss()
                }
                .help("Skip window layout restore. Resources, tasks, sessions, and app hiding still work.")

                Spacer()

                Button("Done") {
                    refreshAndDismissIfGranted()
                    if !permissions.isAccessibilityTrusted {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear {
            permissions.refresh()
            startRefreshLoop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            startRefreshLoop()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func refreshAndDismissIfGranted() {
        permissions.refresh()
        if permissions.isAccessibilityTrusted {
            statusMessage = "Accessibility is on."
            dismiss()
        } else {
            statusMessage = "Still not detected. Make sure this exact Study Boxes app is enabled, then quit and reopen Study Boxes if macOS does not refresh."
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task {
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                permissions.refresh()
                if permissions.isAccessibilityTrusted {
                    statusMessage = "Accessibility is on."
                    dismiss()
                    return
                }
            }
        }
    }
}

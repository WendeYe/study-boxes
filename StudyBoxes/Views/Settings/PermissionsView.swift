import AppKit
import SwiftUI

struct PermissionsView: View {
    @ObservedObject private var permissions = PermissionManager.shared
    @State private var notificationStatus = NotificationPermissionStatus(
        isEnabled: false,
        canRequestInApp: true,
        description: "Checking notification status...",
        canDeliverAlerts: false
    )
    @State private var notificationFeedback: String?
    @State private var isRequestingNotifications = false
    @State private var notificationRefreshTask: Task<Void, Never>?
    @State private var accessibilityFeedback: String?

    var body: some View {
        Section("Permissions") {
            HStack {
                VStack(alignment: .leading) {
                    Text("Notifications")
                    Text("Reminders for today, tomorrow, and changed deadlines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(notificationButtonTitle) {
                    Task {
                        isRequestingNotifications = true
                        let granted = await NotificationService.requestPermission()
                        await refreshNotificationStatus()
                        notificationFeedback = granted
                            ? "Notifications are on."
                            : "Notifications are not on. If macOS blocked the request, allow Study Boxes in System Settings."
                        startNotificationStatusRefresh()
                        isRequestingNotifications = false
                    }
                }
                .disabled(notificationStatus.isEnabled || isRequestingNotifications)
            }

            HStack {
                Label(notificationStatus.description, systemImage: notificationStatus.isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(notificationStatus.isEnabled ? .green : .secondary)

                Spacer()

                Button("Open Notification Settings") {
                    NotificationService.openNotificationSettings()
                    startNotificationStatusRefresh()
                }
                .buttonStyle(.link)

                Button("Check Again") {
                    Task {
                        await refreshNotificationStatus()
                        notificationFeedback = notificationStatus.canDeliverAlerts
                            ? "Notification delivery is on."
                            : notificationStatus.description
                    }
                }
                .buttonStyle(.link)
            }

            if let notificationFeedback {
                Text(notificationFeedback)
                    .font(.caption)
                    .foregroundStyle(notificationStatus.isEnabled ? .green : .secondary)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Accessibility")
                    Text("Needed only for best-effort window layout restore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open") {
                    accessibilityFeedback = "After you enable Study Boxes in System Settings, choose Check Accessibility Again."
                    PermissionManager.requestAccessibilityPermission()
                    PermissionManager.openAccessibilitySettings()
                }
            }

            Text(permissions.isAccessibilityTrusted ? "Accessibility is on." : "Accessibility is not on.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Check Accessibility Again") {
                permissions.refresh()
                accessibilityFeedback = permissions.isAccessibilityTrusted
                    ? "Accessibility is on."
                    : "Still not detected. Make sure this exact Study Boxes app is enabled, then quit and reopen Study Boxes if macOS does not refresh."
            }

            if let accessibilityFeedback {
                Text(accessibilityFeedback)
                    .font(.caption)
                    .foregroundStyle(permissions.isAccessibilityTrusted ? .green : .secondary)
            }
        }
        .task {
            await refreshNotificationStatus()
            permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            Task {
                await refreshNotificationStatus()
                startNotificationStatusRefresh()
            }
        }
        .onDisappear {
            notificationRefreshTask?.cancel()
            notificationRefreshTask = nil
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.permissionStatus()
    }

    private var notificationButtonTitle: String {
        if notificationStatus.isEnabled {
            return "Enabled"
        }
        if isRequestingNotifications {
            return "Requesting..."
        }
        return notificationStatus.canRequestInApp ? "Enable" : "Blocked"
    }

    private func startNotificationStatusRefresh() {
        notificationRefreshTask?.cancel()
        notificationRefreshTask = Task {
            let delays: [UInt64] = [
                500_000_000,
                1_500_000_000,
                3_000_000_000,
                5_000_000_000
            ]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await refreshNotificationStatus()
            }
        }
    }
}

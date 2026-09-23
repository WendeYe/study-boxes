import AppKit
import ApplicationServices
import Foundation
import UserNotifications

@MainActor
enum SystemTestService {
    static func sendTestNotification() async -> String {
        var status = await NotificationService.permissionStatus()
        if status.canRequestInApp {
            _ = await NotificationService.requestPermission()
            status = await NotificationService.permissionStatus()
        }
        guard status.canDeliverAlerts else {
            return NotificationService.testNotificationFeedback(
                status: status,
                didSchedule: false,
                schedulingError: nil
            )
        }

        let content = UNMutableNotificationContent()
        content.title = "Study Boxes test"
        content.body = "Notifications are working."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "studyboxes-debug-notification-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return NotificationService.testNotificationFeedback(
                status: status,
                didSchedule: true,
                schedulingError: nil
            )
        } catch {
            return NotificationService.testNotificationFeedback(
                status: status,
                didSchedule: false,
                schedulingError: error
            )
        }
    }

    static func openTestWebsite() -> String {
        let resource = StudyResource(
            title: "Example website",
            type: .website,
            urlString: "https://example.com"
        )
        let result = ResourceLauncher.shared.open(resource)
        return result.message
    }

    static func launchTextEdit() async -> String {
        let configuration = NSWorkspace.OpenConfiguration()
        do {
            let app = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: configuration
            )
            return "Opened \(app.localizedName ?? "TextEdit")."
        } catch {
            return "Study Boxes could not open TextEdit: \(error.localizedDescription)"
        }
    }

    static func hideUnrelatedApps(for box: StudyBox) -> String {
        DistractionManager.shared.hideUnrelatedApps(for: box)
        return DistractionManager.shared.lastHideSummary ?? "Hide unrelated apps ran."
    }

    static func quitUnrelatedApps(for box: StudyBox) -> String {
        DistractionManager.shared.quitUnrelatedApps(for: box)
        return DistractionManager.shared.lastQuitSummary ?? "Quit unrelated apps ran."
    }

    static func restoreHiddenApps() -> String {
        DistractionManager.shared.restoreHiddenApps()
        return "Showed apps hidden by Study Boxes."
    }

    static func moveTextEditWindow() async -> String {
        guard PermissionManager.isAccessibilityTrusted else {
            return "Accessibility is not enabled for Study Boxes."
        }

        _ = await launchTextEdit()
        guard let app = await waitForApp(bundleID: "com.apple.TextEdit") else {
            return "TextEdit did not open."
        }
        guard let window = await waitForFirstWindow(pid: app.processIdentifier) else {
            return "TextEdit did not show a movable window. Create or open a document, then try again."
        }

        AXUIElementSetMessagingTimeout(window, 0.5)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return "Study Boxes could not read the TextEdit window frame."
        }

        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else {
            return "Study Boxes could not decode the TextEdit window frame."
        }

        var newPosition = CGPoint(x: position.x + 24, y: position.y + 24)
        var newSize = CGSize(
            width: max(420, min(size.width + 20, 900)),
            height: max(300, min(size.height + 20, 700))
        )

        guard let newPositionValue = AXValueCreate(.cgPoint, &newPosition),
              let newSizeValue = AXValueCreate(.cgSize, &newSize) else {
            return "Study Boxes could not prepare the new TextEdit window frame."
        }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, newPositionValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSizeValue)

        guard positionResult == .success, sizeResult == .success else {
            return "TextEdit did not allow the window move."
        }
        return "Moved and resized a TextEdit window."
    }

    private static func waitForApp(bundleID: String) async -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                return app
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private static func waitForFirstWindow(pid: pid_t) async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let window = firstWindow(pid: pid) {
                return window
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private static func firstWindow(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }
}

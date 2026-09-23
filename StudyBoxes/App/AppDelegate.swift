import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            MenuBarTimerController.shared.ensureStatusItemVisible()
            try? await Task.sleep(nanoseconds: 500_000_000)
            MenuBarTimerController.shared.ensureStatusItemVisible()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            MenuBarTimerController.shared.ensureStatusItemVisible()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isQuitShortcut(event) {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    static func isQuitShortcut(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else {
            return false
        }

        var modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        modifiers.remove(.capsLock)

        guard modifiers == .command else {
            return false
        }

        return event.charactersIgnoringModifiers?.lowercased() == "q" || event.keyCode == 12
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

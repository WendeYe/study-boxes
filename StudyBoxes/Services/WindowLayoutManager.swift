import AppKit
import ApplicationServices
import Foundation
import os
import SwiftData

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var isAccessibilityTrusted: Bool
    @Published private(set) var lastAccessibilityCheck: Date?

    static var isAccessibilityTrusted: Bool {
        let trusted = checkAccessibilityTrust()
        if shared.isAccessibilityTrusted != trusted {
            shared.isAccessibilityTrusted = trusted
        }
        return trusted
    }

    private init() {
        isAccessibilityTrusted = PermissionManager.checkAccessibilityTrust()
        lastAccessibilityCheck = .now
    }

    func refresh() {
        isAccessibilityTrusted = Self.checkAccessibilityTrust()
        lastAccessibilityCheck = .now
    }

    static func checkAccessibilityTrust(prompt: Bool = false) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) || AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        _ = checkAccessibilityTrust(prompt: true)
        shared.refresh()
        Task { @MainActor in
            let delays: [UInt64] = [
                500_000_000,
                1_500_000_000,
                3_000_000_000
            ]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                shared.refresh()
            }
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let url, NSWorkspace.shared.open(url) {
            return
        }
        if let fallback {
            NSWorkspace.shared.open(fallback)
        }
    }
}

struct WindowRestoreReport {
    let attempted: Int
    let restored: Int
    let messages: [String]

    var summary: String {
        if messages.isEmpty {
            return "Restored \(restored) of \(attempted) saved windows."
        }
        return "Restored \(restored) of \(attempted) saved windows. \(messages.prefix(2).joined(separator: " "))"
    }
}

@MainActor
enum WindowLayoutManager {
    private static let logger = Logger(subsystem: "StudyBoxes", category: "WindowLayout")
    private static let appLaunchTimeout: TimeInterval = 4
    private static let windowWaitTimeout: TimeInterval = 4
    private static let pollIntervalNanoseconds: UInt64 = 250_000_000

    static func captureLayout(for box: StudyBox, modelContext: ModelContext) throws -> Int {
        let candidates = WindowSnapshotService.visibleWindowSnapshots()
        for layout in box.windowLayouts {
            modelContext.delete(layout)
        }
        box.windowLayouts.removeAll()

        for (index, candidate) in candidates.enumerated() {
            guard let app = NSRunningApplication(processIdentifier: pid_t(candidate.pid)),
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else {
                continue
            }

            let screen = candidate.screen
            let layout = WindowLayout(
                box: box,
                appBundleID: bundleID,
                appName: app.localizedName ?? candidate.ownerName,
                capturedPID: candidate.pid,
                windowTitle: candidate.title,
                windowNumber: candidate.windowNumber,
                axRole: candidate.axRole,
                axSubrole: candidate.axSubrole,
                x: candidate.frame.origin.x,
                y: candidate.frame.origin.y,
                width: candidate.frame.width,
                height: candidate.frame.height,
                screenFrameX: screen.map { Double($0.frame.origin.x) },
                screenFrameY: screen.map { Double($0.frame.origin.y) },
                screenFrameWidth: screen.map { Double($0.frame.width) },
                screenFrameHeight: screen.map { Double($0.frame.height) },
                visibleFrameX: screen.map { Double($0.visibleFrame.origin.x) },
                visibleFrameY: screen.map { Double($0.visibleFrame.origin.y) },
                visibleFrameWidth: screen.map { Double($0.visibleFrame.width) },
                visibleFrameHeight: screen.map { Double($0.visibleFrame.height) },
                screenIdentifier: WindowSnapshotService.screenIdentifier(screen),
                orderIndex: index,
                isMinimized: candidate.isMinimized,
                isFullScreen: candidate.isFullScreen
            )
            modelContext.insert(layout)
        }

        box.touch()
        try modelContext.save()
        logger.info("Captured \(box.windowLayouts.count) windows for \(box.name, privacy: .public)")
        return box.windowLayouts.count
    }

    @discardableResult
    static func restoreLayout(for box: StudyBox) async -> WindowRestoreReport {
        guard PermissionManager.isAccessibilityTrusted else {
            return WindowRestoreReport(
                attempted: box.windowLayouts.count,
                restored: 0,
                messages: ["Accessibility is needed to arrange windows."]
            )
        }

        let layouts = box.windowLayouts.sorted { $0.orderIndex < $1.orderIndex }
        var restored = 0
        var messages: [String] = []

        for group in Dictionary(grouping: layouts, by: \.appBundleID) {
            await Task.yield()
            let bundleID = group.key
            let savedWindows = group.value.sorted { $0.orderIndex < $1.orderIndex }
            let app = await runningOrLaunchedApp(bundleID: bundleID, from: box)
            guard let app else {
                messages.append("Study Boxes could not find \(savedWindows.first?.appName ?? bundleID).")
                continue
            }

            let axWindows = await WindowSnapshotService.waitForWindows(pid: app.processIdentifier, timeout: windowWaitTimeout)
            guard !axWindows.isEmpty else {
                messages.append("\(app.localizedName ?? bundleID) did not show any windows.")
                continue
            }

            var unmatched = axWindows
            for saved in savedWindows {
                guard let matchIndex = WindowSnapshotService.bestMatchIndex(for: saved, in: unmatched) else {
                    messages.append("No matching window for \(saved.appName).")
                    continue
                }

                let window = unmatched.remove(at: matchIndex)
                guard WindowSnapshotService.apply(saved: saved, to: window) else {
                    messages.append("Study Boxes could not move \(saved.windowTitle ?? saved.appName).")
                    continue
                }
                restored += 1
            }
        }

        return WindowRestoreReport(attempted: layouts.count, restored: restored, messages: messages)
    }

    static func clampedFrame(_ frame: CGRect, to screens: [NSScreen] = NSScreen.screens) -> CGRect {
        WindowSnapshotService.clampedFrame(frame, to: screens)
    }

    private static func runningOrLaunchedApp(bundleID: String, from box: StudyBox) async -> NSRunningApplication? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return app
        }

        guard let resource = box.resources.first(where: { $0.appBundleID == bundleID || Bundle(path: $0.appPath ?? "")?.bundleIdentifier == bundleID }) else {
            return nil
        }

        _ = ResourceLauncher.shared.open(resource)

        let deadline = Date().addingTimeInterval(appLaunchTimeout)
        while Date() < deadline {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                return app
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return nil
    }
}

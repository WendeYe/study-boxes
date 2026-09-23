import AppKit
import ApplicationServices
import Foundation

struct CapturedWindowSnapshot {
    let pid: Int
    let ownerName: String
    let windowNumber: Int?
    let title: String?
    let frame: CGRect
    let axRole: String?
    let axSubrole: String?
    let isMinimized: Bool
    let isFullScreen: Bool
    let orderIndex: Int
    let screen: NSScreen?
}

struct CapturedAppSnapshot {
    let bundleID: String
    let appName: String
    let appPath: String?
    let processIdentifier: pid_t
    let windows: [CapturedWindowSnapshot]
}

@MainActor
enum WindowSnapshotService {
    private static let axMessagingTimeout: Float = 0.25
    private static let pollIntervalNanoseconds: UInt64 = 250_000_000

    static func captureRunningRegularApps() -> [CapturedAppSnapshot] {
        let windowsByPID = Dictionary(grouping: visibleWindowSnapshots(), by: \.pid)

        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  !DistractionManager.isCurrentApplication(
                    bundleID: app.bundleIdentifier,
                    processIdentifier: app.processIdentifier
                  ),
                  let bundleID = app.bundleIdentifier else {
                return nil
            }

            return CapturedAppSnapshot(
                bundleID: bundleID,
                appName: app.localizedName ?? bundleID,
                appPath: app.bundleURL?.path,
                processIdentifier: app.processIdentifier,
                windows: (windowsByPID[Int(app.processIdentifier)] ?? []).sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }

    static func visibleWindowSnapshots() -> [CapturedWindowSnapshot] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return infoList.enumerated().compactMap { index, info -> CapturedWindowSnapshot? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 120,
                  bounds.height >= 80 else {
                return nil
            }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }

            let title = info[kCGWindowName as String] as? String
            let metadata = accessibilityMetadata(pid: ownerPID, title: title)
            return CapturedWindowSnapshot(
                pid: ownerPID,
                ownerName: ownerName,
                windowNumber: info[kCGWindowNumber as String] as? Int,
                title: title,
                frame: bounds,
                axRole: metadata.role,
                axSubrole: metadata.subrole,
                isMinimized: metadata.minimized,
                isFullScreen: metadata.fullScreen,
                orderIndex: index,
                screen: screen(containing: bounds)
            )
        }
    }

    static func axWindows(pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return []
        }
        return windows
    }

    static func waitForWindows(pid: pid_t, timeout: TimeInterval) async -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = axWindows(pid: pid)
            if !windows.isEmpty {
                return windows
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return []
    }

    static func bestMatchIndex(for saved: SessionRestoreWindow, in windows: [AXUIElement]) -> Int? {
        guard !windows.isEmpty else { return nil }
        return windows.enumerated()
            .map { ($0.offset, matchScore(saved: saved, window: $0.element)) }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func bestMatchIndex(for saved: HiddenWindowRestoreRecord, in windows: [AXUIElement]) -> Int? {
        guard !windows.isEmpty else { return nil }
        return windows.enumerated()
            .map { ($0.offset, matchScore(saved: saved, window: $0.element)) }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func bestMatchIndex(for saved: WindowLayout, in windows: [AXUIElement]) -> Int? {
        guard !windows.isEmpty else { return nil }
        return windows.enumerated()
            .map { ($0.offset, matchScore(saved: saved, window: $0.element)) }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func apply(saved: SessionRestoreWindow, to window: AXUIElement) -> Bool {
        guard !saved.isMinimized, !saved.isFullScreen else { return false }
        return apply(frame: saved.frame, to: window)
    }

    static func apply(saved: HiddenWindowRestoreRecord, to window: AXUIElement) -> Bool {
        guard !saved.isMinimized, !saved.isFullScreen else { return false }
        return apply(frame: saved.frame, to: window)
    }

    static func apply(saved: WindowLayout, to window: AXUIElement) -> Bool {
        apply(frame: saved.frame, to: window)
    }

    static func apply(frame: CGRect, to window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, axMessagingTimeout)
        let target = clampedFrame(frame)
        guard isSettable(window, kAXPositionAttribute),
              isSettable(window, kAXSizeAttribute) else {
            return false
        }

        var point = target.origin
        var size = target.size
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return positionResult == .success && sizeResult == .success
    }

    static func clampedFrame(_ frame: CGRect, to screens: [NSScreen] = NSScreen.screens) -> CGRect {
        guard let bestScreen = screens.max(by: { intersectionArea($0.visibleFrame, frame) < intersectionArea($1.visibleFrame, frame) }) else {
            return frame
        }
        let visible = bestScreen.visibleFrame
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        let x = min(max(frame.origin.x, visible.minX), visible.maxX - width)
        let y = min(max(frame.origin.y, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func openApp(bundleID: String, appPath: String?) -> Bool {
        if let appPath,
           FileManager.default.fileExists(atPath: appPath),
           NSWorkspace.shared.open(URL(fileURLWithPath: appPath)) {
            return true
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        return NSWorkspace.shared.open(appURL)
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return value as? Bool ?? false
    }

    static func sizeAttribute(_ element: AXUIElement) -> CGSize? {
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    static func screenIdentifier(_ screen: NSScreen?) -> String? {
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.stringValue
    }

    private static func matchScore(saved: SessionRestoreWindow, window: AXUIElement) -> Int {
        matchScore(
            title: saved.title,
            role: saved.axRole,
            subrole: saved.axSubrole,
            width: saved.width,
            height: saved.height,
            orderIndex: saved.orderIndex,
            window: window
        )
    }

    private static func matchScore(saved: HiddenWindowRestoreRecord, window: AXUIElement) -> Int {
        matchScore(
            title: saved.title,
            role: saved.axRole,
            subrole: saved.axSubrole,
            width: saved.frame.width,
            height: saved.frame.height,
            orderIndex: saved.orderIndex,
            window: window
        )
    }

    private static func matchScore(saved: WindowLayout, window: AXUIElement) -> Int {
        matchScore(
            title: saved.windowTitle,
            role: saved.axRole,
            subrole: saved.axSubrole,
            width: saved.width,
            height: saved.height,
            orderIndex: saved.orderIndex,
            window: window
        )
    }

    private static func matchScore(
        title savedTitle: String?,
        role savedRole: String?,
        subrole savedSubrole: String?,
        width savedWidth: Double,
        height savedHeight: Double,
        orderIndex: Int,
        window: AXUIElement
    ) -> Int {
        var score = max(0, 10 - orderIndex)
        let title = stringAttribute(window, kAXTitleAttribute)
        let role = stringAttribute(window, kAXRoleAttribute)
        let subrole = stringAttribute(window, kAXSubroleAttribute)

        if let savedTitle, !savedTitle.isEmpty, title == savedTitle {
            score += 50
        } else if let savedTitle,
                  let title,
                  !savedTitle.isEmpty,
                  title.localizedCaseInsensitiveContains(savedTitle) || savedTitle.localizedCaseInsensitiveContains(title) {
            score += 25
        }
        if let role, role == savedRole { score += 20 }
        if let subrole, subrole == savedSubrole { score += 15 }
        if let size = sizeAttribute(window) {
            let widthDelta = abs(Double(size.width) - savedWidth)
            let heightDelta = abs(Double(size.height) - savedHeight)
            if widthDelta < 80 && heightDelta < 80 {
                score += 10
            }
        }
        return score
    }

    private static func accessibilityMetadata(pid: Int, title: String?) -> (role: String?, subrole: String?, minimized: Bool, fullScreen: Bool) {
        guard PermissionManager.isAccessibilityTrusted else {
            return (nil, nil, false, false)
        }
        let windows = axWindows(pid: pid_t(pid))
        let window = windows.first { stringAttribute($0, kAXTitleAttribute) == title } ?? windows.first
        guard let window else { return (nil, nil, false, false) }
        return (
            stringAttribute(window, kAXRoleAttribute),
            stringAttribute(window, kAXSubroleAttribute),
            boolAttribute(window, kAXMinimizedAttribute),
            boolAttribute(window, "AXFullScreen")
        )
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { intersectionArea($0.frame, frame) < intersectionArea($1.frame, frame) }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

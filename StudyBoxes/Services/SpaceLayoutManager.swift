import AppKit
import Foundation
import os

typealias ManagedSpaceID = UInt64

struct ManagedDisplaySnapshot: Equatable {
    let displayIdentifier: String
    let userSpaceIDs: [ManagedSpaceID]
    let currentSpaceID: ManagedSpaceID?
}

struct ManagedSpacesSnapshot: Equatable {
    let displays: [ManagedDisplaySnapshot]

    var minimumUserSpaceCount: Int {
        displays.map(\.userSpaceIDs.count).min() ?? 0
    }

    var maximumUserSpaceCount: Int {
        displays.map(\.userSpaceIDs.count).max() ?? 0
    }

    func targetSpaceID(forCurrentSpaceIDs currentSpaceIDs: [ManagedSpaceID], requestedSpaceIndex: Int) -> ManagedSpaceID? {
        guard requestedSpaceIndex > 0 else { return nil }

        if let matchedDisplay = matchingDisplay(forCurrentSpaceIDs: currentSpaceIDs),
           requestedSpaceIndex <= matchedDisplay.userSpaceIDs.count {
            return matchedDisplay.userSpaceIDs[requestedSpaceIndex - 1]
        }

        if let primaryDisplay = displays.first,
           requestedSpaceIndex <= primaryDisplay.userSpaceIDs.count {
            return primaryDisplay.userSpaceIDs[requestedSpaceIndex - 1]
        }

        guard let fallbackDisplay = displays.first(where: { requestedSpaceIndex <= $0.userSpaceIDs.count }) else {
            return nil
        }
        return fallbackDisplay.userSpaceIDs[requestedSpaceIndex - 1]
    }

    private func matchingDisplay(forCurrentSpaceIDs currentSpaceIDs: [ManagedSpaceID]) -> ManagedDisplaySnapshot? {
        guard !currentSpaceIDs.isEmpty else { return nil }

        return displays.first { display in
            display.userSpaceIDs.contains { currentSpaceIDs.contains($0) }
        }
    }
}

struct SpaceResourceAssignment: Equatable {
    let resourceID: UUID
    let title: String
    let bundleID: String
    let appPath: String?
    let launchURL: URL?
    let spaceIndex: Int
}

struct SpacePreparationPlan: Equatable {
    let minimumSpaces: Int
    let assignments: [SpaceResourceAssignment]
}

struct SpacePreparationReport: Equatable {
    let requestedSpaces: Int
    let availableSpaces: Int
    let assignedApps: Int
    let messages: [String]

    var summary: String {
        if messages.isEmpty {
            return "Prepared \(availableSpaces) desktop Spaces and placed \(assignedApps) apps."
        }
        return messages.prefix(2).joined(separator: " ")
    }
}

@MainActor
enum SpaceLayoutManager {
    static let maximumManagedSpaces = 8

    private static let logger = Logger(subsystem: "StudyBoxes", category: "DesktopSpaces")
    private static let allSpacesMask = 0x7
    private static let windowPollDelayNanoseconds: UInt64 = 300_000_000
    private static let windowPollTimeout: TimeInterval = 4

    static func plan(
        for box: StudyBox,
        enabledResources: [StudyResource]? = nil,
        browserBundleIdentifier: @MainActor (StudyResource) -> String? = defaultBrowserBundleIdentifier
    ) -> SpacePreparationPlan? {
        guard box.prepareDesktopSpacesOnSessionStart else { return nil }

        let resources = (enabledResources ?? box.resources.filter(\.enabledByDefault))
            .sorted { $0.orderIndex < $1.orderIndex }

        let appAssignments = resources.compactMap { resource -> SpaceResourceAssignment? in
            guard resource.type == .app,
                  let targetDesktopSpace = resource.targetDesktopSpace,
                  let bundleID = resource.appBundleID ?? bundleIdentifier(for: resource.appPath) else {
                return nil
            }

            return SpaceResourceAssignment(
                resourceID: resource.id,
                title: resource.title,
                bundleID: bundleID,
                appPath: resource.appPath,
                launchURL: nil,
                spaceIndex: clampedSpaceIndex(targetDesktopSpace)
            )
        }
        let firstAppSpaceIndex = appAssignments.first?.spaceIndex

        let assignments = resources.compactMap { resource -> SpaceResourceAssignment? in
            if let appAssignment = appAssignments.first(where: { $0.resourceID == resource.id }) {
                return appAssignment
            }

            guard resource.type.expectsURL,
                  let firstAppSpaceIndex,
                  let url = normalizedWebURL(for: resource),
                  let bundleID = browserBundleIdentifier(resource) else {
                return nil
            }

            return SpaceResourceAssignment(
                resourceID: resource.id,
                title: resource.title,
                bundleID: bundleID,
                appPath: nil,
                launchURL: url,
                spaceIndex: firstAppSpaceIndex
            )
        }

        guard !assignments.isEmpty else { return nil }

        let minimumSpaces = max(
            clampedSpaceIndex(box.minimumDesktopSpaces),
            assignments.map(\.spaceIndex).max() ?? 1
        )

        return SpacePreparationPlan(minimumSpaces: minimumSpaces, assignments: assignments)
    }

    static func immediateLaunchResources(
        for box: StudyBox,
        enabledResources: [StudyResource],
        prepareDesktopSpaces: Bool,
        browserBundleIdentifier: @MainActor (StudyResource) -> String? = defaultBrowserBundleIdentifier
    ) -> [StudyResource] {
        guard prepareDesktopSpaces,
              let plan = plan(
                for: box,
                enabledResources: enabledResources,
                browserBundleIdentifier: browserBundleIdentifier
              ) else {
            return enabledResources.filter(\.type.isLaunchable)
        }

        let managedResourceIDs = Set(plan.assignments.map(\.resourceID))
        return enabledResources.filter { resource in
            resource.type.isLaunchable && !managedResourceIDs.contains(resource.id)
        }
    }

    static func prepareSpaces(for box: StudyBox, enabledResources: [StudyResource]) async -> SpacePreparationReport? {
        guard let plan = plan(for: box, enabledResources: enabledResources) else { return nil }

        guard var snapshot = SkyLightBridge.snapshot() else {
            return SpacePreparationReport(
                requestedSpaces: plan.minimumSpaces,
                availableSpaces: 0,
                assignedApps: 0,
                messages: ["Study Boxes could not inspect your current desktop Spaces on this version of macOS."]
            )
        }

        var messages: [String] = []
        if snapshot.minimumUserSpaceCount < plan.minimumSpaces {
            do {
                snapshot = try await SkyLightBridge.ensureUserSpaceCount(plan.minimumSpaces)
            } catch {
                logger.error("Failed to create desktop Spaces: \(error.localizedDescription, privacy: .public)")
                messages.append("Study Boxes could not create enough desktop Spaces automatically.")
            }
        }

        if snapshot.minimumUserSpaceCount < plan.minimumSpaces {
            let displaySuffix = snapshot.displays.count > 1 ? " across \(snapshot.displays.count) displays" : ""
            messages.append("Study Boxes found only \(snapshot.minimumUserSpaceCount) matching desktop Spaces\(displaySuffix), so some app placement may be skipped.")
        }

        return SpacePreparationReport(
            requestedSpaces: plan.minimumSpaces,
            availableSpaces: snapshot.minimumUserSpaceCount,
            assignedApps: 0,
            messages: messages
        )
    }

    static func arrangeAppResources(for box: StudyBox, enabledResources: [StudyResource]) async -> SpacePreparationReport {
        guard let plan = plan(for: box, enabledResources: enabledResources) else {
            return SpacePreparationReport(requestedSpaces: 0, availableSpaces: 0, assignedApps: 0, messages: [])
        }

        guard let snapshot = SkyLightBridge.snapshot() else {
            return SpacePreparationReport(
                requestedSpaces: plan.minimumSpaces,
                availableSpaces: 0,
                assignedApps: 0,
                messages: ["Study Boxes could not place apps into desktop Spaces on this version of macOS."]
            )
        }

        var assignedApps = 0
        var messages: [String] = []

        for assignment in plan.assignments {
            let resourceWindowNumbers: [UInt32]
            if let launchURL = assignment.launchURL {
                guard let browserWindows = await openBrowserResourceAndFindWindows(
                    assignment: assignment,
                    launchURL: launchURL
                ) else {
                    messages.append("Study Boxes could not find a browser window for \(assignment.title) to place it on desktop \(assignment.spaceIndex).")
                    continue
                }
                resourceWindowNumbers = browserWindows
            } else {
                guard let app = await launchOrFindApplication(bundleID: assignment.bundleID, appPath: assignment.appPath) else {
                    messages.append("Study Boxes could not find \(assignment.title) to place it on desktop \(assignment.spaceIndex).")
                    continue
                }

                resourceWindowNumbers = await windowNumbers(for: app)
            }

            guard !resourceWindowNumbers.isEmpty else {
                messages.append("Study Boxes could not find a visible window for \(assignment.title) to place it on desktop \(assignment.spaceIndex).")
                continue
            }

            var groupedWindowNumbers: [ManagedSpaceID: [UInt32]] = [:]
            var hadUnmatchedDisplay = false

            for windowNumber in resourceWindowNumbers {
                let currentSpaceIDs = (try? SkyLightBridge.currentSpaceIDs(forWindowNumber: windowNumber)) ?? []
                guard let targetSpaceID = snapshot.targetSpaceID(
                    forCurrentSpaceIDs: currentSpaceIDs,
                    requestedSpaceIndex: assignment.spaceIndex
                ) else {
                    hadUnmatchedDisplay = true
                    continue
                }
                groupedWindowNumbers[targetSpaceID, default: []].append(windowNumber)
            }

            var movedAnyWindow = false
            for (targetSpaceID, groupedNumbers) in groupedWindowNumbers {
                do {
                    try SkyLightBridge.move(windowNumbers: groupedNumbers, to: targetSpaceID)
                    movedAnyWindow = true
                } catch {
                    logger.error("Failed to move windows for \(assignment.bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            if movedAnyWindow {
                assignedApps += 1
            } else {
                messages.append("\(assignment.title) could not be placed on desktop \(assignment.spaceIndex).")
            }

            if hadUnmatchedDisplay {
                messages.append("\(assignment.title) opened on a display without desktop \(assignment.spaceIndex), so some windows stayed where they were.")
            }
        }

        return SpacePreparationReport(
            requestedSpaces: plan.minimumSpaces,
            availableSpaces: snapshot.minimumUserSpaceCount,
            assignedApps: assignedApps,
            messages: messages
        )
    }

    private static func launchOrFindApplication(bundleID: String, appPath: String?) async -> NSRunningApplication? {
        if let running = runningApplication(bundleID: bundleID) {
            return running
        }

        guard WindowSnapshotService.openApp(bundleID: bundleID, appPath: appPath) else {
            return nil
        }

        return await waitForRunningApplication(bundleID: bundleID)
    }

    private static func openBrowserResourceAndFindWindows(
        assignment: SpaceResourceAssignment,
        launchURL: URL
    ) async -> [UInt32]? {
        let existingApp = runningApplication(bundleID: assignment.bundleID)
        let existingWindowNumbers: Set<UInt32>
        if let existingApp {
            existingWindowNumbers = Set(await windowNumbers(for: existingApp))
        } else {
            existingWindowNumbers = []
        }

        guard NSWorkspace.shared.open(launchURL) else {
            return nil
        }

        guard let app = await waitForRunningApplication(bundleID: assignment.bundleID) else {
            return nil
        }

        let currentWindowNumbers = await windowNumbers(for: app)
        let newWindowNumbers = currentWindowNumbers.filter { !existingWindowNumbers.contains($0) }
        return newWindowNumbers.isEmpty ? currentWindowNumbers : newWindowNumbers
    }

    private static func waitForRunningApplication(bundleID: String) async -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(windowPollTimeout)
        while Date() < deadline {
            if let running = runningApplication(bundleID: bundleID) {
                return running
            }
            try? await Task.sleep(nanoseconds: windowPollDelayNanoseconds)
        }

        return nil
    }

    private static func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.activationPolicy == .regular } ??
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private static func windowNumbers(for app: NSRunningApplication) async -> [UInt32] {
        let processIdentifier = Int(app.processIdentifier)

        func currentWindowNumbers() -> [UInt32] {
            WindowSnapshotService.visibleWindowSnapshots()
                .filter { $0.pid == processIdentifier }
                .compactMap { snapshot -> UInt32? in
                    guard let windowNumber = snapshot.windowNumber else { return nil }
                    return UInt32(windowNumber)
                }
        }

        let initial = currentWindowNumbers()
        if !initial.isEmpty {
            return initial
        }

        let deadline = Date().addingTimeInterval(windowPollTimeout)
        while Date() < deadline {
            let current = currentWindowNumbers()
            if !current.isEmpty {
                return current
            }
            try? await Task.sleep(nanoseconds: windowPollDelayNanoseconds)
        }

        return []
    }

    private static func bundleIdentifier(for appPath: String?) -> String? {
        guard let appPath, !appPath.isEmpty else { return nil }
        return Bundle(path: appPath)?.bundleIdentifier
    }

    private static func defaultBrowserBundleIdentifier(for resource: StudyResource) -> String? {
        guard let url = normalizedWebURL(for: resource),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    private static func normalizedWebURL(for resource: StudyResource) -> URL? {
        guard resource.type.expectsURL,
              let normalizedURLString = URLValidator.normalizedURLString(resource.urlString) else {
            return nil
        }
        return URL(string: normalizedURLString)
    }

    private static func clampedSpaceIndex(_ value: Int) -> Int {
        min(max(value, 1), maximumManagedSpaces)
    }
}

private enum SkyLightBridge {
    typealias ConnectionID = UInt32

    private static let libraryHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let logger = Logger(subsystem: "StudyBoxes", category: "SkyLight")
    private static let allSpacesMask = 0x7

    enum BridgeError: LocalizedError {
        case unavailable(String)
        case invalidState

        var errorDescription: String? {
            switch self {
            case .unavailable(let symbol):
                return "Missing private macOS symbol: \(symbol)"
            case .invalidState:
                return "Desktop Spaces state was unavailable."
            }
        }
    }

    static func snapshot() -> ManagedSpacesSnapshot? {
        guard let rawDisplays = copyManagedDisplaySpaces() else {
            return nil
        }

        let displays = rawDisplays.compactMap { rawDisplay -> ManagedDisplaySnapshot? in
            guard let displayIdentifier = rawDisplay["Display Identifier"] as? String else {
                return nil
            }

            let rawSpaces = rawDisplay["Spaces"] as? [[String: Any]] ?? []
            let userSpaceIDs = rawSpaces.compactMap { rawSpace -> ManagedSpaceID? in
                let type = integerValue(rawSpace["type"])
                guard type == 0 else { return nil }
                return spaceID(from: rawSpace)
            }

            let currentSpaceID: ManagedSpaceID?
            if let rawCurrentSpace = rawDisplay["Current Space"] as? [String: Any] {
                currentSpaceID = spaceID(from: rawCurrentSpace)
            } else {
                currentSpaceID = nil
            }

            return ManagedDisplaySnapshot(
                displayIdentifier: displayIdentifier,
                userSpaceIDs: userSpaceIDs,
                currentSpaceID: currentSpaceID
            )
        }

        guard !displays.isEmpty else {
            return nil
        }

        return ManagedSpacesSnapshot(displays: displays)
    }

    static func ensureUserSpaceCount(_ minimumSpaces: Int) async throws -> ManagedSpacesSnapshot {
        guard minimumSpaces > 0 else {
            throw BridgeError.invalidState
        }

        guard var currentSnapshot = snapshot() else {
            throw BridgeError.invalidState
        }

        if currentSnapshot.minimumUserSpaceCount >= minimumSpaces {
            return currentSnapshot
        }

        let createSpace = try loadSymbol(
            named: "CGSSpaceCreate",
            as: (@convention(c) (ConnectionID, CFTypeRef?, CFDictionary) -> ManagedSpaceID).self
        )

        let connection = mainConnection()
        let options = ["type": 0] as NSDictionary
        var previousMinimum = currentSnapshot.minimumUserSpaceCount
        var stalledAttempts = 0

        while currentSnapshot.minimumUserSpaceCount < minimumSpaces {
            let newSpaceID = createSpace(connection, nil, options as CFDictionary)
            if newSpaceID == 0 {
                throw BridgeError.invalidState
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let refreshed = snapshot() else {
                throw BridgeError.invalidState
            }
            currentSnapshot = refreshed

            if currentSnapshot.minimumUserSpaceCount <= previousMinimum {
                stalledAttempts += 1
            } else {
                stalledAttempts = 0
            }
            previousMinimum = currentSnapshot.minimumUserSpaceCount

            if stalledAttempts >= 2 {
                throw BridgeError.invalidState
            }
        }

        return currentSnapshot
    }

    static func currentSpaceIDs(forWindowNumber windowNumber: UInt32) throws -> [ManagedSpaceID] {
        try currentSpaceIDs(forWindowNumbers: [windowNumber])
    }

    static func move(windowNumbers: [UInt32], to targetSpaceID: ManagedSpaceID) throws {
        guard !windowNumbers.isEmpty else { return }

        let connection = mainConnection()
        let existingSpaceIDs = try currentSpaceIDs(forWindowNumbers: windowNumbers)
        if existingSpaceIDs.contains(targetSpaceID) {
            return
        }

        if let targetType = try? spaceType(targetSpaceID), targetType != 0 {
            throw BridgeError.invalidState
        }

        do {
            try moveUsingManagedSpaceAPI(
                connection: connection,
                windowNumbers: windowNumbers,
                targetSpaceID: targetSpaceID
            )
        } catch {
            try moveUsingAddRemoveAPI(
                connection: connection,
                windowNumbers: windowNumbers,
                targetSpaceID: targetSpaceID,
                currentSpaceIDs: existingSpaceIDs
            )
        }

        let refreshedSpaceIDs = try currentSpaceIDs(forWindowNumbers: windowNumbers)
        guard refreshedSpaceIDs.contains(targetSpaceID) else {
            throw BridgeError.invalidState
        }
    }

    private static func moveUsingManagedSpaceAPI(
        connection: ConnectionID,
        windowNumbers: [UInt32],
        targetSpaceID: ManagedSpaceID
    ) throws {
        if workspaceCompatibilityModeIsRequired {
            let setSpaceCompatibilityID = try loadSymbol(
                named: "SLSSpaceSetCompatID",
                as: (@convention(c) (ConnectionID, ManagedSpaceID, Int32) -> Int32).self
            )
            let setWindowListWorkspace = try loadSymbol(
                named: "SLSSetWindowListWorkspace",
                as: (@convention(c) (ConnectionID, UnsafeMutablePointer<UInt32>, Int32, Int32) -> Int32).self
            )

            let compatibilityWorkspaceID: Int32 = 0x7961_6265
            var mutableWindowNumbers = windowNumbers
            _ = setSpaceCompatibilityID(connection, targetSpaceID, compatibilityWorkspaceID)
            let result = mutableWindowNumbers.withUnsafeMutableBufferPointer { buffer -> Int32 in
                guard let baseAddress = buffer.baseAddress else { return -1 }
                return setWindowListWorkspace(connection, baseAddress, Int32(buffer.count), compatibilityWorkspaceID)
            }
            _ = setSpaceCompatibilityID(connection, targetSpaceID, 0)

            guard result == 0 else {
                throw BridgeError.invalidState
            }
            return
        }

        let moveWindowsToManagedSpace = try loadFirstSymbol(
            named: ["SLSMoveWindowsToManagedSpace", "CGSMoveWindowsToManagedSpace"],
            as: (@convention(c) (ConnectionID, CFArray, ManagedSpaceID) -> Void).self
        )

        let windows = windowNumbers.map { NSNumber(value: $0) } as CFArray
        moveWindowsToManagedSpace(connection, windows, targetSpaceID)
    }

    private static func moveUsingAddRemoveAPI(
        connection: ConnectionID,
        windowNumbers: [UInt32],
        targetSpaceID: ManagedSpaceID,
        currentSpaceIDs: [ManagedSpaceID]
    ) throws {
        let addWindowsToSpaces = try loadFirstSymbol(
            named: ["SLSAddWindowsToSpaces", "CGSAddWindowsToSpaces"],
            as: (@convention(c) (ConnectionID, CFArray, CFArray) -> Int32).self
        )
        let removeWindowsFromSpaces = try loadFirstSymbol(
            named: ["SLSRemoveWindowsFromSpaces", "CGSRemoveWindowsFromSpaces"],
            as: (@convention(c) (ConnectionID, CFArray, CFArray) -> Int32).self
        )

        let windows = windowNumbers.map { NSNumber(value: $0) } as CFArray
        let removableSpaces = currentSpaceIDs
            .filter { $0 != targetSpaceID }
            .map { NSNumber(value: $0) } as CFArray
        let targetSpaces = [NSNumber(value: targetSpaceID)] as CFArray

        if CFArrayGetCount(removableSpaces) > 0 {
            let removeResult = removeWindowsFromSpaces(connection, windows, removableSpaces)
            guard removeResult == 0 else {
                throw BridgeError.invalidState
            }
        }

        let addResult = addWindowsToSpaces(connection, windows, targetSpaces)
        guard addResult == 0 else {
            throw BridgeError.invalidState
        }
    }

    private static func mainConnection() -> ConnectionID {
        guard let mainConnectionID = try? loadFirstSymbol(
            named: ["SLSMainConnectionID", "CGSMainConnectionID"],
            as: (@convention(c) () -> ConnectionID).self
        ) else {
            return 0
        }
        return mainConnectionID()
    }

    private static func copyManagedDisplaySpaces() -> [[String: Any]]? {
        guard let copyManagedDisplaySpaces = try? loadFirstSymbol(
            named: ["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"],
            as: (@convention(c) (ConnectionID) -> Unmanaged<CFArray>?).self
        ) else {
            return nil
        }

        return copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
    }

    private static var workspaceCompatibilityModeIsRequired: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion > 14 { return true }
        return version.majorVersion == 14 && version.minorVersion >= 5
    }

    private static func loadSymbol<T>(named name: String, as type: T.Type) throws -> T {
        guard let libraryHandle,
              let symbol = dlsym(libraryHandle, name) else {
            logger.error("Missing SkyLight symbol: \(name, privacy: .public)")
            throw BridgeError.unavailable(name)
        }
        return unsafeBitCast(symbol, to: type)
    }

    private static func loadFirstSymbol<T>(named names: [String], as type: T.Type) throws -> T {
        for name in names {
            if let symbol = try? loadSymbol(named: name, as: type) {
                return symbol
            }
        }
        throw BridgeError.unavailable(names.joined(separator: ", "))
    }

    private static func spaceType(_ spaceID: ManagedSpaceID) throws -> Int32 {
        let spaceGetType = try loadFirstSymbol(
            named: ["SLSSpaceGetType", "CGSSpaceGetType"],
            as: (@convention(c) (ConnectionID, ManagedSpaceID) -> Int32).self
        )
        return spaceGetType(mainConnection(), spaceID)
    }

    private static func currentSpaceIDs(forWindowNumbers windowNumbers: [UInt32]) throws -> [ManagedSpaceID] {
        let copySpacesForWindows = try loadFirstSymbol(
            named: ["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"],
            as: (@convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?).self
        )

        let connection = mainConnection()
        let windows = windowNumbers.map { NSNumber(value: $0) } as CFArray
        let currentSpaces = copySpacesForWindows(connection, Int32(allSpacesMask), windows)?
            .takeRetainedValue() as Any
        return extractSpaceIDs(from: currentSpaces as Any)
    }

    private static func spaceID(from rawSpace: [String: Any]) -> ManagedSpaceID? {
        if let id = rawSpace["id64"] as? NSNumber {
            return id.uint64Value
        }
        if let id = rawSpace["id64"] as? UInt64 {
            return id
        }
        if let id = rawSpace["ManagedSpaceID"] as? NSNumber {
            return id.uint64Value
        }
        return nil
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let integer = value as? Int {
            return integer
        }
        return nil
    }

    private static func extractSpaceIDs(from value: Any) -> [ManagedSpaceID] {
        if let numbers = value as? [NSNumber] {
            return numbers.map(\.uint64Value)
        }

        if let array = value as? [Any] {
            return array.flatMap(extractSpaceIDs)
        }

        if let dictionary = value as? [String: Any],
           let id = spaceID(from: dictionary) {
            return [id]
        }

        return []
    }
}

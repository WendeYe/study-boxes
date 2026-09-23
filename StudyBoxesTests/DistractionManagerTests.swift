import XCTest
@testable import StudyBoxes

@MainActor
final class DistractionManagerTests: XCTestCase {
    func testCurrentAppBundleIDsAlwaysIncludeStudyBoxesReleaseIdentifier() {
        XCTAssertTrue(DistractionManager.currentAppBundleIDs().contains("com.studyboxes.StudyBoxes"))
    }

    func testCurrentProcessIsAlwaysTreatedAsCurrentApplication() {
        XCTAssertTrue(
            DistractionManager.isCurrentApplication(
                bundleID: nil,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            )
        )
    }

    func testStudyBoxesBundleIDIsTreatedAsCurrentApplicationEvenWithDifferentPID() {
        XCTAssertTrue(
            DistractionManager.isCurrentApplication(
                bundleID: "com.studyboxes.StudyBoxes",
                processIdentifier: -1
            )
        )
    }

    func testFocusActionsSkipAllowedProtectedCurrentAndNonRegularApps() {
        XCTAssertFalse(DistractionManager.shouldAffectApp(
            bundleID: "com.apple.finder",
            processIdentifier: -1,
            activationPolicy: .regular,
            allowedBundleIDs: [],
            protectedBundleIDs: ["com.apple.finder"]
        ))

        XCTAssertFalse(DistractionManager.shouldAffectApp(
            bundleID: "com.apple.Safari",
            processIdentifier: -1,
            activationPolicy: .regular,
            allowedBundleIDs: ["com.apple.Safari"],
            protectedBundleIDs: []
        ))

        XCTAssertFalse(DistractionManager.shouldAffectApp(
            bundleID: "com.example.Helper",
            processIdentifier: -1,
            activationPolicy: .accessory,
            allowedBundleIDs: [],
            protectedBundleIDs: []
        ))

        XCTAssertTrue(DistractionManager.shouldAffectApp(
            bundleID: "com.example.Distraction",
            processIdentifier: -1,
            activationPolicy: .regular,
            allowedBundleIDs: [],
            protectedBundleIDs: []
        ))
    }

    func testURLResourcesAllowOnlyResolvedDefaultBrowser() {
        let allowedBrowsers = DistractionManager.browserBundleIDsForURLResources(
            resolvedDefaultBrowserBundleID: "app.helium.mac"
        )

        XCTAssertEqual(allowedBrowsers, ["app.helium.mac"])
        XCTAssertFalse(allowedBrowsers.contains("com.apple.Safari"))
        XCTAssertFalse(allowedBrowsers.contains("com.google.Chrome"))
    }

    func testURLResourcesAllowNoBrowserWhenDefaultCannotBeResolved() {
        XCTAssertTrue(
            DistractionManager.browserBundleIDsForURLResources(resolvedDefaultBrowserBundleID: nil).isEmpty
        )
    }

    func testDistractionActionResultsIdentifyRestoreTargetsAndBlockedEvents() {
        let hidden = DistractionActionResult(
            bundleID: "com.example.Hidden",
            appName: "Hidden",
            action: .hidden,
            wasRunningBeforeSession: true
        )
        let quit = DistractionActionResult(
            bundleID: "com.example.Quit",
            appName: "Quit",
            action: .terminateRequested,
            wasRunningBeforeSession: true
        )
        let blocked = DistractionActionResult(
            bundleID: "com.example.Blocked",
            appName: "Blocked",
            action: .blockedNewLaunch,
            wasRunningBeforeSession: false
        )

        XCTAssertTrue(hidden.shouldRestoreAfterSession)
        XCTAssertTrue(quit.shouldRestoreAfterSession)
        XCTAssertFalse(blocked.shouldRestoreAfterSession)
        XCTAssertTrue(blocked.isBlockedEvent)
    }

    func testHiddenAppRestoreTargetsSkipPreviouslyHiddenAppsAndKeepFrames() {
        let frame = CGRect(x: 20, y: 30, width: 640, height: 480)
        let newlyHidden = HiddenAppRestoreRecord(
            bundleID: "com.example.Editor",
            wasPreviouslyHidden: false,
            windows: [
                HiddenWindowRestoreRecord(
                    title: "Notes",
                    axRole: "AXWindow",
                    axSubrole: "AXStandardWindow",
                    frame: frame,
                    orderIndex: 0,
                    isMinimized: false,
                    isFullScreen: false
                )
            ]
        )
        let alreadyHidden = HiddenAppRestoreRecord(
            bundleID: "com.example.AlreadyHidden",
            wasPreviouslyHidden: true,
            windows: []
        )

        let targets = DistractionManager.hiddenRestoreTargets(from: [newlyHidden, alreadyHidden])

        XCTAssertEqual(targets.map(\.bundleID), ["com.example.Editor"])
        XCTAssertEqual(targets.first?.windows.first?.frame, frame)
    }
}

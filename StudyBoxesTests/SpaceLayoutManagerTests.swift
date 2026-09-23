import XCTest
@testable import StudyBoxes

@MainActor
final class SpaceLayoutManagerTests: XCTestCase {
    func testSpacePreparationPlanClampsMinimumAndKeepsAppTargetsOnly() {
        let box = StudyBox(
            name: "Probability",
            prepareDesktopSpacesOnSessionStart: true,
            minimumDesktopSpaces: 12
        )
        let appWithTarget = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            orderIndex: 1,
            targetDesktopSpace: 2
        )
        let browser = StudyResource(
            box: box,
            title: "Overleaf",
            type: .overleaf,
            urlString: "https://www.overleaf.com/project/abc",
            orderIndex: 0,
            targetDesktopSpace: 3
        )
        let disabledApp = StudyResource(
            box: box,
            title: "Notes",
            type: .app,
            appBundleID: "com.apple.Notes",
            orderIndex: 2,
            enabledByDefault: false,
            targetDesktopSpace: 3
        )
        box.resources = [appWithTarget, browser, disabledApp]

        guard let plan = SpaceLayoutManager.plan(
            for: box,
            enabledResources: [browser, appWithTarget],
            browserBundleIdentifier: { _ in nil }
        ) else {
            XCTFail("Expected a desktop Spaces plan.")
            return
        }

        XCTAssertEqual(plan.minimumSpaces, SpaceLayoutManager.maximumManagedSpaces)
        XCTAssertEqual(plan.assignments.map(\.bundleID), ["com.apple.dt.Xcode"])
        XCTAssertEqual(plan.assignments.map(\.spaceIndex), [2])
    }

    func testSpacePreparationPlanGroupsBrowserLinksWithFirstAppDesktopSpace() {
        let box = StudyBox(
            name: "Probability",
            prepareDesktopSpacesOnSessionStart: true,
            minimumDesktopSpaces: 3
        )
        let appWithTarget = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            orderIndex: 1,
            targetDesktopSpace: 2
        )
        let website = StudyResource(
            box: box,
            title: "Formula sheet",
            type: .website,
            urlString: "https://example.com/formula",
            orderIndex: 2
        )
        box.resources = [appWithTarget, website]

        guard let plan = SpaceLayoutManager.plan(
            for: box,
            enabledResources: [appWithTarget, website],
            browserBundleIdentifier: { _ in "com.apple.Safari" }
        ) else {
            XCTFail("Expected a desktop Spaces plan.")
            return
        }

        XCTAssertEqual(plan.minimumSpaces, 3)
        XCTAssertEqual(plan.assignments.map(\.title), ["Xcode", "Formula sheet"])
        XCTAssertEqual(plan.assignments.map(\.bundleID), ["com.apple.dt.Xcode", "com.apple.Safari"])
        XCTAssertEqual(plan.assignments.map(\.spaceIndex), [2, 2])
        XCTAssertEqual(plan.assignments.last?.launchURL?.absoluteString, "https://example.com/formula")
    }

    func testSpacePreparationPlanSkipsBrowserLinksWhenDefaultBrowserIsUnavailable() {
        let box = StudyBox(
            name: "Probability",
            prepareDesktopSpacesOnSessionStart: true,
            minimumDesktopSpaces: 3
        )
        let appWithTarget = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            orderIndex: 1,
            targetDesktopSpace: 2
        )
        let website = StudyResource(
            box: box,
            title: "Formula sheet",
            type: .website,
            urlString: "https://example.com/formula",
            orderIndex: 2
        )

        let plan = SpaceLayoutManager.plan(
            for: box,
            enabledResources: [appWithTarget, website],
            browserBundleIdentifier: { _ in nil }
        )

        XCTAssertEqual(plan?.assignments.map(\.title), ["Xcode"])
    }

    func testSpacePreparationPlanIsNilWhenOptInIsOffOrNoAssignmentsExist() {
        let disabledBox = StudyBox(name: "Spanish", prepareDesktopSpacesOnSessionStart: false, minimumDesktopSpaces: 3)
        let app = StudyResource(
            box: disabledBox,
            title: "Dictionary",
            type: .app,
            appBundleID: "com.example.Dictionary",
            targetDesktopSpace: 2
        )

        XCTAssertNil(SpaceLayoutManager.plan(for: disabledBox, enabledResources: [app]))

        let noAssignmentsBox = StudyBox(name: "Math", prepareDesktopSpacesOnSessionStart: true, minimumDesktopSpaces: 3)
        let website = StudyResource(
            box: noAssignmentsBox,
            title: "Course site",
            type: .website,
            urlString: "https://example.com",
            targetDesktopSpace: 2
        )

        XCTAssertNil(SpaceLayoutManager.plan(for: noAssignmentsBox, enabledResources: [website]))
    }

    func testTargetSpaceUsesDisplayThatCurrentlyOwnsTheWindow() {
        let snapshot = ManagedSpacesSnapshot(displays: [
            ManagedDisplaySnapshot(displayIdentifier: "display-a", userSpaceIDs: [101, 102, 103], currentSpaceID: 101),
            ManagedDisplaySnapshot(displayIdentifier: "display-b", userSpaceIDs: [201, 202, 203], currentSpaceID: 201)
        ])

        XCTAssertEqual(
            snapshot.targetSpaceID(forCurrentSpaceIDs: [201], requestedSpaceIndex: 2),
            202
        )
    }

    func testTargetSpaceFallsBackToPrimaryDisplayWhenWindowSpaceCannotBeMatched() {
        let snapshot = ManagedSpacesSnapshot(displays: [
            ManagedDisplaySnapshot(displayIdentifier: "display-a", userSpaceIDs: [101, 102], currentSpaceID: 101),
            ManagedDisplaySnapshot(displayIdentifier: "display-b", userSpaceIDs: [201, 202], currentSpaceID: 201)
        ])

        XCTAssertEqual(
            snapshot.targetSpaceID(forCurrentSpaceIDs: [999], requestedSpaceIndex: 2),
            102
        )
    }

    func testManagedSpacesSnapshotReportsMinimumAvailableDesktopCountAcrossDisplays() {
        let snapshot = ManagedSpacesSnapshot(displays: [
            ManagedDisplaySnapshot(displayIdentifier: "display-a", userSpaceIDs: [101, 102, 103], currentSpaceID: 101),
            ManagedDisplaySnapshot(displayIdentifier: "display-b", userSpaceIDs: [201, 202], currentSpaceID: 201)
        ])

        XCTAssertEqual(snapshot.minimumUserSpaceCount, 2)
    }

    func testImmediateLaunchResourcesSkipAppsHandledByDesktopSpacePlacement() {
        let box = StudyBox(name: "Systems", prepareDesktopSpacesOnSessionStart: true, minimumDesktopSpaces: 2)
        let targetApp = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            orderIndex: 0,
            targetDesktopSpace: 2
        )
        let untargetedApp = StudyResource(
            box: box,
            title: "Preview",
            type: .app,
            appBundleID: "com.apple.Preview",
            orderIndex: 1
        )
        let website = StudyResource(
            box: box,
            title: "Docs",
            type: .website,
            urlString: "https://example.com",
            orderIndex: 2
        )

        let immediate = SpaceLayoutManager.immediateLaunchResources(
            for: box,
            enabledResources: [targetApp, untargetedApp, website],
            prepareDesktopSpaces: true,
            browserBundleIdentifier: { _ in nil }
        )

        XCTAssertEqual(immediate.map(\.title), ["Preview", "Docs"])
    }

    func testImmediateLaunchResourcesSkipBrowserLinksHandledByDesktopSpacePlacement() {
        let box = StudyBox(name: "Systems", prepareDesktopSpacesOnSessionStart: true, minimumDesktopSpaces: 2)
        let targetApp = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            orderIndex: 0,
            targetDesktopSpace: 2
        )
        let website = StudyResource(
            box: box,
            title: "Docs",
            type: .website,
            urlString: "https://example.com",
            orderIndex: 1
        )

        let immediate = SpaceLayoutManager.immediateLaunchResources(
            for: box,
            enabledResources: [targetApp, website],
            prepareDesktopSpaces: true,
            browserBundleIdentifier: { _ in "com.apple.Safari" }
        )

        XCTAssertTrue(immediate.isEmpty)
    }

    func testImmediateLaunchResourcesIncludesEverythingWhenDesktopSpacesAreNotPrepared() {
        let box = StudyBox(name: "Systems", prepareDesktopSpacesOnSessionStart: true, minimumDesktopSpaces: 2)
        let targetApp = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            targetDesktopSpace: 2
        )
        let website = StudyResource(
            box: box,
            title: "Docs",
            type: .website,
            urlString: "https://example.com"
        )

        let immediate = SpaceLayoutManager.immediateLaunchResources(
            for: box,
            enabledResources: [targetApp, website],
            prepareDesktopSpaces: false
        )

        XCTAssertEqual(immediate.map(\.title), ["Xcode", "Docs"])
    }
}

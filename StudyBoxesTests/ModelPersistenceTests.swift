import SwiftData
import XCTest
@testable import StudyBoxes

@MainActor
final class ModelPersistenceTests: XCTestCase {
    func testStudyBoxPersistsWithTasksAndResourcesInSharedSchema() throws {
        let container = try ModelContainer(
            for: StudyBox.self,
            StudyResource.self,
            StudyTask.self,
            StudySession.self,
            LMSCalendarFeed.self,
            LMSImportedEvent.self,
            WindowLayout.self,
            SessionRestoreSnapshot.self,
            SessionRestoreApp.self,
            SessionRestoreWindow.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let box = StudyBox(name: "Operating Systems", type: .course)
        let resource = StudyResource(
            box: box,
            title: "Course site",
            type: .moodleCourse,
            urlString: "https://moodle.example/course/view.php?id=1"
        )
        let task = StudyTask(box: box, title: "Read scheduler notes", priority: 3)

        context.insert(box)
        context.insert(resource)
        context.insert(task)
        try context.save()

        let boxes = try context.fetch(FetchDescriptor<StudyBox>())
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes.first?.resources.first?.title, "Course site")
        XCTAssertEqual(boxes.first?.tasks.first?.title, "Read scheduler notes")
    }

    func testSessionRestoreSnapshotPersistsAppsAndWindows() throws {
        let container = try ModelContainer(
            for: StudyBox.self,
            StudyResource.self,
            StudyTask.self,
            StudySession.self,
            LMSCalendarFeed.self,
            LMSImportedEvent.self,
            WindowLayout.self,
            SessionRestoreSnapshot.self,
            SessionRestoreApp.self,
            SessionRestoreWindow.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let sessionID = UUID()
        let boxID = UUID()
        let snapshot = SessionRestoreSnapshot(sessionID: sessionID, boxID: boxID)
        let app = SessionRestoreApp(
            snapshot: snapshot,
            bundleID: "com.example.Editor",
            appName: "Editor",
            appPath: "/Applications/Editor.app",
            processIdentifier: 42,
            wasRunningBeforeSession: true,
            restorePolicy: .restoreIfAffected
        )
        let window = SessionRestoreWindow(
            app: app,
            title: "Notes",
            windowNumber: 7,
            axRole: "AXWindow",
            axSubrole: "AXStandardWindow",
            x: 10,
            y: 20,
            width: 640,
            height: 480,
            orderIndex: 0,
            isMinimized: false,
            isFullScreen: false
        )

        context.insert(snapshot)
        context.insert(app)
        context.insert(window)
        try context.save()

        let snapshots = try context.fetch(FetchDescriptor<SessionRestoreSnapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, sessionID)
        XCTAssertEqual(snapshots.first?.boxID, boxID)
        XCTAssertEqual(snapshots.first?.status, .pending)
        XCTAssertEqual(snapshots.first?.apps.first?.bundleID, "com.example.Editor")
        XCTAssertEqual(snapshots.first?.apps.first?.windows.first?.frame.width, 640)
    }
}

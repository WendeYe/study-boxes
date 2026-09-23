import SwiftData
import XCTest
@testable import StudyBoxes

final class TaskSessionTests: XCTestCase {
    @MainActor
    func testSessionManagerStartsSessionForPersistedEmptyBox() throws {
        let container = try ModelContainer(
            for: StudyBox.self,
            StudyResource.self,
            StudyTask.self,
            StudySession.self,
            LMSCalendarFeed.self,
            LMSImportedEvent.self,
            WindowLayout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let box = StudyBox(name: "Crash repro", defaultSessionMinutes: 25)
        context.insert(box)
        try context.save()

        let options = SessionStartOptions(
            plannedMinutes: 25,
            openResources: false,
            hideDistractions: false,
            quitDistractions: false,
            enforceFocus: false,
            restoreWindowLayout: false,
            keepDisplayAwake: false
        )

        let session = SessionManager.startSession(for: box, options: options, modelContext: context)

        XCTAssertEqual(session.box?.id, box.id)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.plannedMinutes, 25)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudySession>()).count, 1)
    }

    func testStudyBoxStoresDesktopSpaceDefaultsAndResourceTargets() {
        let box = StudyBox(
            name: "Operating Systems",
            prepareDesktopSpacesOnSessionStart: true,
            minimumDesktopSpaces: 3
        )
        let app = StudyResource(
            box: box,
            title: "Xcode",
            type: .app,
            appBundleID: "com.apple.dt.Xcode",
            targetDesktopSpace: 2
        )

        XCTAssertTrue(box.prepareDesktopSpacesOnSessionStart)
        XCTAssertEqual(box.minimumDesktopSpaces, 3)
        XCTAssertEqual(app.targetDesktopSpace, 2)

        box.update(
            name: "OS",
            type: .course,
            courseName: nil,
            icon: "desktopcomputer",
            colorHex: "#3B82F6",
            examDate: nil,
            defaultSessionMinutes: 50,
            openResourcesOnSessionStart: true,
            hideDistractionsOnSessionStart: false,
            quitDistractionsOnSessionStart: false,
            enforceFocusOnSessionStart: false,
            restoreWindowLayoutOnSessionStart: false,
            keepDisplayAwakeDuringSessions: true,
            prepareDesktopSpacesOnSessionStart: false,
            minimumDesktopSpaces: 1
        )
        app.update(
            title: "Xcode",
            type: .app,
            urlString: "",
            appBundleID: "com.apple.dt.Xcode",
            appPath: nil,
            enabledByDefault: true,
            targetDesktopSpace: nil
        )

        XCTAssertFalse(box.prepareDesktopSpacesOnSessionStart)
        XCTAssertEqual(box.minimumDesktopSpaces, 1)
        XCTAssertNil(app.targetDesktopSpace)
    }

    func testDefaultSessionOptionsCarryDesktopSpacesForProOnly() {
        let box = StudyBox(
            name: "Operating Systems",
            prepareDesktopSpacesOnSessionStart: true,
            minimumDesktopSpaces: 3
        )

        let proOptions = SessionStartOptions.defaults(for: box, plan: .pro)
        let freeOptions = SessionStartOptions.defaults(for: box, plan: .free)

        XCTAssertTrue(proOptions.prepareDesktopSpaces)
        XCTAssertFalse(freeOptions.prepareDesktopSpaces)
    }

    func testTaskStatusTransitionsSetAndClearCompletionDate() {
        let task = StudyTask(title: "Problem set")

        task.markDone()
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt)

        task.markPending()
        XCTAssertEqual(task.status, .pending)
        XCTAssertNil(task.completedAt)
    }

    func testStudyBoxAndResourceUpdatesTouchParentState() {
        let oldDate = Date(timeIntervalSince1970: 1)
        let box = StudyBox(name: "Old", updatedAt: oldDate)
        let resource = StudyResource(box: box, title: "Old", type: .website, updatedAt: oldDate)

        box.update(
            name: "New",
            type: .assignment,
            courseName: "CS",
            icon: "folder",
            colorHex: "#111111",
            examDate: nil,
            defaultSessionMinutes: 30,
            openResourcesOnSessionStart: false,
            hideDistractionsOnSessionStart: true,
            quitDistractionsOnSessionStart: true,
            enforceFocusOnSessionStart: true,
            restoreWindowLayoutOnSessionStart: false,
            keepDisplayAwakeDuringSessions: false
        )
        resource.update(
            title: "Site",
            type: .github,
            urlString: "https://github.com/",
            appBundleID: nil,
            appPath: nil,
            enabledByDefault: false
        )

        XCTAssertEqual(box.name, "New")
        XCTAssertEqual(box.type, .assignment)
        XCTAssertTrue(box.quitDistractionsOnSessionStart)
        XCTAssertFalse(box.keepDisplayAwakeDuringSessions ?? true)
        XCTAssertTrue(box.updatedAt > oldDate)
        XCTAssertEqual(resource.title, "Site")
        XCTAssertEqual(resource.type, .github)
        XCTAssertFalse(resource.enabledByDefault)
        XCTAssertTrue(resource.updatedAt > oldDate)
    }

    func testArchiveRestoreAndFallbackRawValues() {
        let box = StudyBox(name: "Box")
        box.typeRawValue = "unknown"
        XCTAssertEqual(box.type, .course)

        box.archive()
        XCTAssertTrue(box.isArchived)
        box.restore()
        XCTAssertFalse(box.isArchived)

        let task = StudyTask(title: "Task")
        task.statusRawValue = "unknown"
        task.typeRawValue = "unknown"
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.type, .exercise)
    }

    func testTaskFilteringAndSortingPrioritizesInProgressThenPriorityThenDueDate() {
        let now = Date()
        let lowPriorityDueSoon = StudyTask(
            title: "Low",
            priority: 1,
            dueDate: now.addingTimeInterval(3600)
        )
        let highPriorityLater = StudyTask(
            title: "High",
            priority: 3,
            dueDate: now.addingTimeInterval(86_400)
        )
        let inProgress = StudyTask(
            title: "In progress",
            status: .inProgress,
            priority: 1,
            dueDate: now.addingTimeInterval(172_800)
        )

        let sorted = TaskManager.sorted([lowPriorityDueSoon, highPriorityLater, inProgress])
        XCTAssertEqual(sorted.map(\.title), ["In progress", "High", "Low"])

        let today = TaskManager.filteredTasks([lowPriorityDueSoon, highPriorityLater, inProgress], filter: .today)
        XCTAssertTrue(today.contains { $0.title == "Low" })
        XCTAssertTrue(today.contains { $0.title == "High" })
    }

    func testTaskSearchAndSubtasksRoundTrip() {
        let subtasks = [
            StudySubtask(title: "Read chapter", isDone: true),
            StudySubtask(title: "Redo exercise")
        ]
        let task = StudyTask(title: "Linear algebra", unit: "Matrices", subtasks: subtasks)

        XCTAssertEqual(task.subtasks, subtasks)
        XCTAssertEqual(StudyTask.decodeSubtasks(task.subtasksJSON ?? ""), subtasks)

        let matchedBySubtask = TaskManager.searchedTasks([task], query: "redo")
        XCTAssertEqual(matchedBySubtask.map(\.title), ["Linear algebra"])
        XCTAssertTrue(TaskManager.searchedTasks([task], query: "missing").isEmpty)
    }

    func testTaskOrderNormalization() {
        let first = StudyTask(title: "First", orderIndex: 10)
        let second = StudyTask(title: "Second", orderIndex: 20)

        TaskManager.normalizeOrder([second, first])

        XCTAssertEqual(first.orderIndex, 0)
        XCTAssertEqual(second.orderIndex, 1)
    }

    func testSessionTaskCompletionAndSkipListsAreMutuallyExclusive() {
        let id = UUID()
        let session = StudySession(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 180),
            plannedMinutes: 25
        )

        session.markCompleted(id)
        XCTAssertEqual(session.completedTaskIDs, [id])
        XCTAssertTrue(session.skippedTaskIDs.isEmpty)

        session.markSkipped(id)
        XCTAssertTrue(session.completedTaskIDs.isEmpty)
        XCTAssertEqual(session.skippedTaskIDs, [id])
        XCTAssertEqual(session.durationMinutes, 3)
    }

    func testSessionEndTrimsEmptyNotesAndDurationHandlesOpenSession() {
        let openSession = StudySession(startedAt: Date(), plannedMinutes: 25)
        XCTAssertEqual(openSession.durationMinutes, 0)

        openSession.end(notes: "   ")
        XCTAssertNotNil(openSession.endedAt)
        XCTAssertEqual(openSession.notes, "   ")
    }

    func testDurationFormatterDoesNotReturnNegativeTimes() {
        XCTAssertEqual(DurationFormatter.clock(-2), "00:00")
        XCTAssertEqual(DurationFormatter.clock(65), "01:05")
        XCTAssertEqual(DurationFormatter.clock(3_661), "1:01:01")
        XCTAssertEqual(DurationFormatter.minutes(1), "1 min")
        XCTAssertEqual(DurationFormatter.minutes(25), "25 min")
    }
}

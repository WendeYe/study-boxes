import SwiftData
import XCTest
@testable import StudyBoxes

@MainActor
final class BackupServiceTests: XCTestCase {
    func testExportAndImportPreservesBoxResourcesTasksAndSessions() throws {
        let sourceBox = StudyBox(
            name: "Calculus",
            type: .exam,
            courseName: "MATH101",
            icon: "function",
            colorHex: "#2F80ED",
            examDate: Date(timeIntervalSince1970: 2_000),
            hideDistractionsOnSessionStart: true,
            quitDistractionsOnSessionStart: true,
            restoreWindowLayoutOnSessionStart: false,
            openResourcesOnSessionStart: true,
            keepDisplayAwakeDuringSessions: false,
            defaultSessionMinutes: 45,
            prepareDesktopSpacesOnSessionStart: true,
            minimumDesktopSpaces: 3
        )
        sourceBox.resources = [
            StudyResource(
                box: sourceBox,
                title: "Problem sheet",
                type: .file,
                urlString: "/tmp/sheet.pdf",
                orderIndex: 1
            ),
            StudyResource(
                box: sourceBox,
                title: "Xcode",
                type: .app,
                appBundleID: "com.apple.dt.Xcode",
                orderIndex: 2,
                targetDesktopSpace: 2
            )
        ]
        sourceBox.tasks = [
            StudyTask(
                box: sourceBox,
                title: "Redo limits",
                details: "Section 3",
                type: .exercise,
                status: .done,
                priority: 3,
                estimatedMinutes: 20,
                dueDate: Date(timeIntervalSince1970: 3_000),
                unit: "Limits",
                orderIndex: 7,
                subtasks: [StudySubtask(title: "Warmup", isDone: true)],
                completedAt: Date(timeIntervalSince1970: 4_000)
            )
        ]
        sourceBox.sessions = [
            StudySession(
                box: sourceBox,
                startedAt: Date(timeIntervalSince1970: 5_000),
                endedAt: Date(timeIntervalSince1970: 5_900),
                plannedMinutes: 45,
                notes: "Good progress"
            )
        ]

        let backupURL = temporaryURL(named: "study-boxes-backup.json")
        try BackupService.export(boxes: [sourceBox], to: backupURL)
        let preview = try BackupService.previewImport(from: backupURL, existingBoxes: [sourceBox])
        XCTAssertEqual(preview.boxCount, 1)
        XCTAssertEqual(preview.resourceCount, 2)
        XCTAssertEqual(preview.taskCount, 1)
        XCTAssertEqual(preview.sessionCount, 1)
        XCTAssertEqual(preview.duplicateBoxNames, ["Calculus"])

        let container = try makeContainer()
        try BackupService.import(from: backupURL, modelContext: container.mainContext, plan: .pro)

        let boxes = try container.mainContext.fetch(FetchDescriptor<StudyBox>())
        let imported = try XCTUnwrap(boxes.first)
        XCTAssertEqual(imported.name, "Calculus")
        XCTAssertEqual(imported.type, .exam)
        XCTAssertEqual(imported.defaultSessionMinutes, 45)
        XCTAssertTrue(imported.prepareDesktopSpacesOnSessionStart)
        XCTAssertEqual(imported.minimumDesktopSpaces, 3)
        XCTAssertTrue(imported.quitDistractionsOnSessionStart)
        XCTAssertFalse(imported.keepDisplayAwakeDuringSessions ?? true)
        let importedProblemSheet = imported.resources.first(where: { $0.title == "Problem sheet" })
        let importedXcode = imported.resources.first(where: { $0.title == "Xcode" })
        XCTAssertEqual(importedProblemSheet?.orderIndex, 1)
        XCTAssertEqual(importedXcode?.orderIndex, 2)
        XCTAssertEqual(importedXcode?.targetDesktopSpace, 2)
        XCTAssertEqual(imported.tasks.first?.status, .done)
        XCTAssertEqual(imported.tasks.first?.orderIndex, 7)
        XCTAssertEqual(imported.tasks.first?.subtasks.first?.title, "Warmup")
        XCTAssertEqual(imported.sessions.first?.notes, "Good progress")
    }

    func testImportCanSkipDuplicateBoxNames() throws {
        let sourceBox = StudyBox(name: "Physics")
        let backupURL = temporaryURL(named: "duplicates.json")
        try BackupService.export(boxes: [sourceBox], to: backupURL)

        let container = try makeContainer()
        let existing = StudyBox(name: "Physics")
        container.mainContext.insert(existing)
        try container.mainContext.save()

        try BackupService.import(
            from: backupURL,
            modelContext: container.mainContext,
            existingBoxes: [existing],
            duplicatePolicy: .skipMatchingNames,
            plan: .pro
        )

        let boxes = try container.mainContext.fetch(FetchDescriptor<StudyBox>())
        XCTAssertEqual(boxes.count, 1)
    }

    func testImportInvalidJSONThrowsAndDoesNotInsertBoxes() throws {
        let backupURL = temporaryURL(named: "invalid.json")
        try Data("not-json".utf8).write(to: backupURL)
        let container = try makeContainer()

        XCTAssertThrowsError(try BackupService.import(from: backupURL, modelContext: container.mainContext))
        let boxes = try container.mainContext.fetch(FetchDescriptor<StudyBox>())
        XCTAssertTrue(boxes.isEmpty)
    }

    func testFreePlanBlocksBackupImport() throws {
        let sourceBox = StudyBox(name: "Physics")
        let backupURL = temporaryURL(named: "free-import.json")
        try BackupService.export(boxes: [sourceBox], to: backupURL)
        let container = try makeContainer()

        XCTAssertThrowsError(try BackupService.import(from: backupURL, modelContext: container.mainContext, plan: .free)) { error in
            XCTAssertEqual(error as? BackupImportError, .requiresPro)
        }
        let boxes = try container.mainContext.fetch(FetchDescriptor<StudyBox>())
        XCTAssertTrue(boxes.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: StudyBox.self,
            StudyResource.self,
            StudyTask.self,
            StudySession.self,
            LMSCalendarFeed.self,
            LMSImportedEvent.self,
            WindowLayout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func temporaryURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(name)
    }
}

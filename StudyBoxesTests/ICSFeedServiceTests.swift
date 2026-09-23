import SwiftData
import XCTest
@testable import StudyBoxes

@MainActor
final class ICSFeedServiceTests: XCTestCase {
    func testAddFeedRejectsInvalidURLsBeforeSaving() throws {
        let container = try makeContainer()

        XCTAssertThrowsError(
            try ICSFeedService.addFeed(
                title: "Bad feed",
                provider: .genericICS,
                feedURL: "not a url",
                modelContext: container.mainContext
            )
        ) { error in
            guard case FeedSyncError.invalidURL = error else {
                return XCTFail("Expected invalid URL error, got \(error)")
            }
        }

        let feeds = try container.mainContext.fetch(FetchDescriptor<LMSCalendarFeed>())
        XCTAssertTrue(feeds.isEmpty)
    }

    func testDisabledFeedSyncIsNoOpWithoutKeychainURL() async throws {
        let container = try makeContainer()
        let feed = LMSCalendarFeed(
            provider: .moodle,
            title: "Moodle",
            feedURLKeychainIdentifier: "missing-\(UUID().uuidString)",
            enabled: false
        )
        container.mainContext.insert(feed)

        let summary = try await ICSFeedService.sync(feed, modelContext: container.mainContext)

        XCTAssertEqual(summary.newEvents, 0)
        XCTAssertEqual(summary.updatedEvents, 0)
    }

    func testEnabledFeedWithoutStoredURLThrowsMissingURL() async throws {
        let container = try makeContainer()
        let feed = LMSCalendarFeed(
            provider: .genericICS,
            title: "Calendar",
            feedURLKeychainIdentifier: "missing-\(UUID().uuidString)"
        )
        container.mainContext.insert(feed)

        do {
            _ = try await ICSFeedService.sync(feed, modelContext: container.mainContext)
            XCTFail("Expected missing URL error.")
        } catch {
            guard case FeedSyncError.missingURL = error else {
                return XCTFail("Expected missing URL error, got \(error)")
            }
        }
    }

    func testSyncEnabledFeedsCountsFailuresAndSkipsDisabledFeeds() async throws {
        let container = try makeContainer()
        let disabled = LMSCalendarFeed(
            provider: .genericICS,
            title: "Disabled",
            feedURLKeychainIdentifier: "disabled-\(UUID().uuidString)",
            enabled: false
        )
        let missing = LMSCalendarFeed(
            provider: .genericICS,
            title: "Missing",
            feedURLKeychainIdentifier: "missing-\(UUID().uuidString)",
            enabled: true
        )
        container.mainContext.insert(disabled)
        container.mainContext.insert(missing)

        let result = await ICSFeedService.syncEnabledFeeds([disabled, missing], modelContext: container.mainContext)

        XCTAssertEqual(result.summary.newEvents, 0)
        XCTAssertEqual(result.summary.updatedEvents, 0)
        XCTAssertEqual(result.failures, 1)
    }

    func testConvertEventCreatesTaskAndMapsEventToBox() throws {
        let container = try makeContainer()
        let box = StudyBox(name: "Databases")
        let event = LMSImportedEvent(
            externalUID: "deadline-1",
            title: "Project due",
            eventDescription: "Submit report",
            location: "Unit 4",
            dueDate: Date(timeIntervalSince1970: 10_000)
        )
        container.mainContext.insert(box)
        container.mainContext.insert(event)

        try ICSFeedService.convertEvent(event, to: box, modelContext: container.mainContext)

        let tasks = try container.mainContext.fetch(FetchDescriptor<StudyTask>())
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.title, "Project due")
        XCTAssertEqual(task.details, "Submit report")
        XCTAssertEqual(task.type, .assignment)
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(task.unit, "Unit 4")
        XCTAssertEqual(event.mappedBoxID, box.id)
        XCTAssertEqual(event.mappedTaskID, task.id)
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
}

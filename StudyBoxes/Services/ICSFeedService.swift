import Foundation
import SwiftData

struct FeedSyncSummary {
    let newEvents: Int
    let updatedEvents: Int

    static func +(left: FeedSyncSummary, right: FeedSyncSummary) -> FeedSyncSummary {
        FeedSyncSummary(
            newEvents: left.newEvents + right.newEvents,
            updatedEvents: left.updatedEvents + right.updatedEvents
        )
    }
}

@MainActor
enum ICSFeedService {
    static func addFeed(title: String, provider: LMSProvider, feedURL: String, modelContext: ModelContext) throws -> LMSCalendarFeed {
        guard let normalized = URLValidator.normalizedURLString(feedURL) else {
            throw FeedSyncError.invalidURL
        }

        let key = "ics-feed-\(UUID().uuidString)"
        try KeychainService.save(normalized, for: key)
        let feed = LMSCalendarFeed(provider: provider, title: title, feedURLKeychainIdentifier: key)
        modelContext.insert(feed)
        try modelContext.save()
        return feed
    }

    static func sync(_ feed: LMSCalendarFeed, modelContext: ModelContext) async throws -> FeedSyncSummary {
        guard feed.enabled else { return FeedSyncSummary(newEvents: 0, updatedEvents: 0) }
        feed.lastSyncAttemptAt = .now
        feed.lastSyncErrorMessage = nil
        feed.touch()

        do {
            guard let storedURL = try KeychainService.load(for: feed.feedURLKeychainIdentifier),
                  let url = URL(string: storedURL) else {
                throw FeedSyncError.missingURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw FeedSyncError.fetchFailed
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw FeedSyncError.parseFailed
            }

            let parsedEvents = ICSParser.parse(text)
            var newCount = 0
            var updatedCount = 0

            for parsed in parsedEvents {
                if let existing = feed.importedEvents.first(where: { $0.externalUID == parsed.uid }) {
                    if existing.title != parsed.summary || existing.dueDate != (parsed.dueDate ?? parsed.startDate) {
                        updatedCount += 1
                    }
                    existing.update(from: parsed)
                } else {
                    let event = LMSImportedEvent(
                        feed: feed,
                        externalUID: parsed.uid,
                        title: parsed.summary,
                        eventDescription: parsed.description,
                        location: parsed.location,
                        startDate: parsed.startDate,
                        endDate: parsed.endDate,
                        dueDate: parsed.dueDate ?? parsed.startDate,
                        urlString: parsed.urlString
                    )
                    modelContext.insert(event)
                    newCount += 1
                }
            }

            let now = Date.now
            feed.lastSyncedAt = now
            feed.lastSyncSucceededAt = now
            feed.lastImportedCount = newCount
            feed.lastUpdatedCount = updatedCount
            feed.lastSyncErrorMessage = nil
            feed.touch()
            try modelContext.save()

            if newCount > 0 || updatedCount > 0 {
                await NotificationService.notifyDeadlineChanges(newCount: newCount, updatedCount: updatedCount)
            }
            return FeedSyncSummary(newEvents: newCount, updatedEvents: updatedCount)
        } catch {
            feed.lastSyncErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            feed.lastImportedCount = 0
            feed.lastUpdatedCount = 0
            feed.touch()
            try? modelContext.save()
            throw error
        }
    }

    static func syncEnabledFeeds(_ feeds: [LMSCalendarFeed], modelContext: ModelContext) async -> (summary: FeedSyncSummary, failures: Int) {
        var summary = FeedSyncSummary(newEvents: 0, updatedEvents: 0)
        var failures = 0

        for feed in feeds where feed.enabled {
            do {
                summary = summary + (try await sync(feed, modelContext: modelContext))
            } catch {
                failures += 1
            }
        }

        return (summary, failures)
    }

    static func convertEvent(_ event: LMSImportedEvent, to box: StudyBox, modelContext: ModelContext) throws {
        let task = StudyTask(
            box: box,
            title: event.title,
            details: event.eventDescription,
            type: .assignment,
            priority: 2,
            dueDate: event.dueDate,
            unit: event.location
        )
        modelContext.insert(task)
        event.mappedBoxID = box.id
        event.mappedTaskID = task.id
        event.updatedAt = .now
        box.touch()
        try modelContext.save()
    }

    static func deleteFeed(_ feed: LMSCalendarFeed, modelContext: ModelContext) throws {
        try KeychainService.delete(for: feed.feedURLKeychainIdentifier)
        modelContext.delete(feed)
        try modelContext.save()
    }
}

enum FeedSyncError: LocalizedError {
    case invalidURL
    case missingURL
    case fetchFailed
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That URL does not look right."
        case .missingURL: "The calendar feed URL could not be found in Keychain."
        case .fetchFailed: "Study Boxes could not fetch this calendar feed. Check the link or try again later."
        case .parseFailed: "Study Boxes could not parse this calendar feed."
        }
    }
}

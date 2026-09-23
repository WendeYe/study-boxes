import Foundation
import SwiftData

@Model
final class LMSImportedEvent: Identifiable {
    @Attribute(.unique) var id: UUID
    var feed: LMSCalendarFeed?
    var externalUID: String
    var title: String
    var eventDescription: String?
    var location: String?
    var startDate: Date?
    var endDate: Date?
    var dueDate: Date?
    var urlString: String?
    var mappedBoxID: UUID?
    var mappedTaskID: UUID?
    var ignored: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        feed: LMSCalendarFeed? = nil,
        externalUID: String,
        title: String,
        eventDescription: String? = nil,
        location: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        dueDate: Date? = nil,
        urlString: String? = nil,
        mappedBoxID: UUID? = nil,
        mappedTaskID: UUID? = nil,
        ignored: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.feed = feed
        self.externalUID = externalUID
        self.title = title
        self.eventDescription = eventDescription
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.dueDate = dueDate
        self.urlString = urlString
        self.mappedBoxID = mappedBoxID
        self.mappedTaskID = mappedTaskID
        self.ignored = ignored
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func update(from parsed: ParsedICSEvent) {
        title = parsed.summary
        eventDescription = parsed.description
        location = parsed.location
        startDate = parsed.startDate
        endDate = parsed.endDate
        dueDate = parsed.dueDate ?? parsed.startDate
        urlString = parsed.urlString
        updatedAt = .now
    }
}

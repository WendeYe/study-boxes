import Foundation
import SwiftData

enum LMSProvider: String, CaseIterable, Identifiable, Codable {
    case moodle
    case blackboard
    case genericICS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moodle: "Moodle"
        case .blackboard: "Blackboard"
        case .genericICS: "Generic ICS"
        }
    }
}

@Model
final class LMSCalendarFeed: Identifiable {
    @Attribute(.unique) var id: UUID
    var providerRawValue: String
    var title: String
    var feedURLKeychainIdentifier: String
    var enabled: Bool
    var lastSyncedAt: Date?
    var lastSyncAttemptAt: Date?
    var lastSyncSucceededAt: Date?
    var lastSyncErrorMessage: String?
    var lastImportedCount: Int?
    var lastUpdatedCount: Int?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \LMSImportedEvent.feed)
    var importedEvents: [LMSImportedEvent]

    init(
        id: UUID = UUID(),
        provider: LMSProvider,
        title: String,
        feedURLKeychainIdentifier: String,
        enabled: Bool = true,
        lastSyncedAt: Date? = nil,
        lastSyncAttemptAt: Date? = nil,
        lastSyncSucceededAt: Date? = nil,
        lastSyncErrorMessage: String? = nil,
        lastImportedCount: Int = 0,
        lastUpdatedCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.title = title
        self.feedURLKeychainIdentifier = feedURLKeychainIdentifier
        self.enabled = enabled
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncAttemptAt = lastSyncAttemptAt
        self.lastSyncSucceededAt = lastSyncSucceededAt
        self.lastSyncErrorMessage = lastSyncErrorMessage
        self.lastImportedCount = lastImportedCount
        self.lastUpdatedCount = lastUpdatedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importedEvents = []
    }

    var provider: LMSProvider {
        get { LMSProvider(rawValue: providerRawValue) ?? .genericICS }
        set {
            providerRawValue = newValue.rawValue
            touch()
        }
    }

    func touch() {
        updatedAt = .now
    }
}

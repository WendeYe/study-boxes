import AppKit
import SwiftData
import SwiftUI

struct LMSIntegrationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    @Query(sort: \LMSCalendarFeed.updatedAt, order: .reverse)
    private var feeds: [LMSCalendarFeed]

    @Query(sort: \StudyBox.updatedAt, order: .reverse)
    private var boxes: [StudyBox]

    @State private var showingAddFeed = false
    @State private var syncMessage: String?
    @State private var feedPendingDeletion: LMSCalendarFeed?
    @State private var isDeleteConfirmationPresented = false
    @ObservedObject private var license = LicenseManager.shared

    private var activeBoxes: [StudyBox] {
        boxes.filter { !$0.isArchived }
    }

    private var importedEvents: [LMSImportedEvent] {
        feeds
            .flatMap(\.importedEvents)
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if license.plan.isPro {
                integrationsContent
            } else {
                lockedContent
            }
        }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calendar feeds")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                ProBadge()
                Text(EntitlementRules.canUse(.calendarFeeds, plan: .free).message ?? "Calendar feeds are included with Pro.")
                    .foregroundStyle(.secondary)
            }

            Button("License") {
                appState.presentLicense(reason: EntitlementRules.canUse(.calendarFeeds, plan: .free).message)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 260)
    }

    private var integrationsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar feeds")
                        .font(.largeTitle.weight(.semibold))
	                    Text("Paste a Moodle, Blackboard, or generic ICS calendar feed to bring deadlines into Study Boxes.")
	                        .foregroundStyle(.secondary)
	                    Text("Private feed URLs can contain tokens, so Study Boxes stores them in Keychain.")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)
	                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .help("Close calendar feeds.")

                Button {
                    Task { await syncAll() }
                } label: {
                    Label("Sync All", systemImage: "arrow.clockwise")
                }
                .disabled(feeds.filter(\.enabled).isEmpty)
                .help("Fetch every enabled calendar feed.")

                Button {
                    showingAddFeed = true
	                } label: {
	                    Label("Add Calendar Feed", systemImage: "plus")
	                }
	                .help("Paste a private calendar feed URL from Moodle, Blackboard, or another ICS calendar.")
            }

            if let syncMessage {
                Text(syncMessage)
                    .foregroundStyle(.secondary)
            }

            List {
                feedsSection
                importedEventsSection
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
        .sheet(isPresented: $showingAddFeed) {
            ICSFeedEditorView()
                .frame(minWidth: 480)
        }
        .confirmationDialog(
            "Delete this calendar feed?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Feed", role: .destructive) {
                if let feedPendingDeletion {
                    delete(feedPendingDeletion)
                }
                feedPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                feedPendingDeletion = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var feedsSection: some View {
        Section("Feeds") {
            if feeds.isEmpty {
                Text("No feeds yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(feeds) { feed in
                FeedRow(
                    feed: feed,
                    subtitle: feedSubtitle(feed),
                    enabled: binding(for: feed),
                    onSync: { Task { await sync(feed) } },
                    onDelete: {
                        feedPendingDeletion = feed
                        isDeleteConfirmationPresented = true
                    }
                )
            }
        }
    }

    private var importedEventsSection: some View {
        Section("Imported events") {
            if importedEvents.isEmpty {
                Text("No imported events yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(importedEvents) { event in
                ImportedEventRow(event: event, boxes: activeBoxes) { box in
                    convert(event, to: box)
                } onSave: {
                    save()
                }
            }
        }
    }

    private func sync(_ feed: LMSCalendarFeed) async {
        do {
            let summary = try await ICSFeedService.sync(feed, modelContext: modelContext)
            syncMessage = "Synced \(feed.title): \(summary.newEvents) new, \(summary.updatedEvents) updated."
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    private func syncAll() async {
        let result = await ICSFeedService.syncEnabledFeeds(feeds, modelContext: modelContext)
        var message = "Synced feeds: \(result.summary.newEvents) new, \(result.summary.updatedEvents) updated."
        if result.failures > 0 {
            message += " \(result.failures) failed."
        }
        syncMessage = message
    }

    private func binding(for feed: LMSCalendarFeed) -> Binding<Bool> {
        Binding {
            feed.enabled
        } set: { isEnabled in
            feed.enabled = isEnabled
            feed.touch()
            save()
        }
    }

    private func feedSubtitle(_ feed: LMSCalendarFeed) -> String {
        if let error = feed.lastSyncErrorMessage, !error.isEmpty {
            return "\(feed.provider.title) - last sync failed: \(error)"
        }
        if let lastSyncedAt = feed.lastSyncedAt {
            return "\(feed.provider.title) - last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened)) · \(feed.lastImportedCount ?? 0) new, \(feed.lastUpdatedCount ?? 0) updated"
        }
        if let attempt = feed.lastSyncAttemptAt {
            return "\(feed.provider.title) - last tried \(attempt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(feed.provider.title) - not synced yet"
    }

    private func delete(_ feed: LMSCalendarFeed) {
        do {
            try ICSFeedService.deleteFeed(feed, modelContext: modelContext)
            syncMessage = "Deleted \(feed.title)."
        } catch {
            syncMessage = "Study Boxes could not delete this feed."
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            syncMessage = "Study Boxes could not save these changes."
        }
    }

    private func convert(_ event: LMSImportedEvent, to box: StudyBox) {
        do {
            try ICSFeedService.convertEvent(event, to: box, modelContext: modelContext)
            syncMessage = "Converted \(event.title) to a task."
        } catch {
            syncMessage = "Study Boxes could not convert this event."
        }
    }

    private var deleteConfirmationMessage: String {
        guard let feedPendingDeletion else {
            return "Study Boxes will remove this feed, its imported events, and the private feed URL saved in Keychain."
        }
        return "Study Boxes will remove \(feedPendingDeletion.title), its imported events, and the private feed URL saved in Keychain."
    }
}

private struct FeedRow: View {
    let feed: LMSCalendarFeed
    let subtitle: String
    @Binding var enabled: Bool
    let onSync: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(feed.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(feed.lastSyncErrorMessage == nil ? Color.secondary : Color.orange)
            }

            Spacer()

            Toggle("Enabled", isOn: $enabled)
                .toggleStyle(.switch)
                .help("Disabled feeds stay saved but are skipped when syncing.")

            Button("Sync Deadlines", action: onSync)
                .disabled(!enabled)
                .help("Fetch this calendar feed and update imported deadlines.")

            Menu {
                Button("Delete Feed", role: .destructive, action: onDelete)
            } label: {
                Label("More feed actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }
}

private struct ImportedEventRow: View {
    @Bindable var event: LMSImportedEvent

    let boxes: [StudyBox]
    let onConvert: (StudyBox) -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                Text(event.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if event.ignored {
                Text("Ignored")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

	            Menu("Convert to Task") {
	                ForEach(boxes) { box in
	                    Button(box.name) {
	                        onConvert(box)
	                    }
	                }
	            }
	            .disabled(boxes.isEmpty || event.mappedTaskID != nil)
	            .help("Create a Study Box task from this imported deadline.")

            Button(event.ignored ? "Restore" : "Ignore") {
                event.ignored.toggle()
                event.updatedAt = .now
                onSave()
            }
            .help(event.ignored ? "Show this event again." : "Hide this event from the active imported event list.")
	        }
	    }
}

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ResourceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    let box: StudyBox

    @State private var isAddingResource = false
    @State private var editingResource: StudyResource?
    @State private var launchResults: [ResourceLaunchResult] = []
    @State private var isDropTargeted = false
    @ObservedObject private var license = LicenseManager.shared

    private var resources: [StudyResource] {
        box.resources.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
	                    Text("Resources")
	                        .font(.title2.weight(.semibold))
	                    Text("Add the files, apps, folders, and links you want ready when you study this subject.")
	                        .font(.callout)
	                        .foregroundStyle(.secondary)
	                    Text("Websites open in your browser. Study Boxes cannot manage individual browser tabs.")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)
	                }

                Spacer()

                Button {
                    openAll()
	                } label: {
	                    Label("Open Study Setup", systemImage: "arrow.up.forward.app")
	                }
	                .disabled(resources.filter(\.enabledByDefault).isEmpty)
	                .help("Open every enabled resource for this Study Box.")

                Button {
                    attemptAddResource()
	                } label: {
	                    Label("Add Resource", systemImage: "plus")
	                }
	                .help("Add an app, file, folder, website, note, or copy-only command.")
            }

            if !license.plan.isPro {
                HStack(spacing: 6) {
                    ProBadge()
                    Text("Free includes up to 3 resources. Additional resources and automatic opening beyond the first 3 are included with Pro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if resources.isEmpty {
                ContentUnavailableView(
                    "No resources yet",
                    systemImage: "folder.badge.plus",
                    description: Text("Drop in a PDF, folder, app, or course link to build this study setup.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(resources) { resource in
                        ResourceRow(
                            resource: resource,
                            canMoveUp: resource.id != resources.first?.id,
                            canMoveDown: resource.id != resources.last?.id,
                            onOpen: { launchResults = [ResourceLauncher.shared.open(resource)] },
                            onEdit: { editingResource = resource },
                            onDelete: { delete(resource) },
                            onRelink: { relink(resource) },
                            onMoveUp: { move(resource, direction: -1) },
                            onMoveDown: { move(resource, direction: 1) },
                            onSave: save
                        )

                        if resource.id != resources.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
            }

            if !launchResults.isEmpty {
                launchSummary
            }
        }
        .padding(10)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $isAddingResource) {
            AddResourceView(box: box)
                .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(item: $editingResource) { resource in
            ResourceEditorView(box: box, resource: resource)
                .frame(minWidth: 520, minHeight: 520)
        }
    }

    private var launchSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Launch results")
                .font(.headline)

            ForEach(launchResults) { result in
                Label(result.resourceTitle, systemImage: icon(for: result.status))
                    .foregroundStyle(color(for: result.status))
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openAll() {
        launchResults = ResourceLauncher.shared.openEnabledResources(for: box)
    }

    private func attemptAddResource() {
        let decision = EntitlementRules.canAddResource(currentResourceCount: resources.count, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }
        isAddingResource = true
    }

    private func delete(_ resource: StudyResource) {
        modelContext.delete(resource)
        normalizeOrder()
        save()
    }

    private func relink(_ resource: StudyResource) {
        guard ResourceHealthService.relink(resource) else { return }
        save()
    }

    private func move(_ resource: StudyResource, direction: Int) {
        var ordered = resources
        guard let currentIndex = ordered.firstIndex(where: { $0.id == resource.id }) else { return }
        let targetIndex = currentIndex + direction
        guard ordered.indices.contains(targetIndex) else { return }

        ordered.swapAt(currentIndex, targetIndex)
        for (index, resource) in ordered.enumerated() {
            resource.orderIndex = index
            resource.touch()
        }
        save()
    }

    private func normalizeOrder() {
        for (index, resource) in resources.enumerated() {
            resource.orderIndex = index
        }
    }

    private func save() {
        do {
            box.touch()
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save resource changes: \(error)")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didSchedule = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = Self.fileURL(from: item)
                Task { @MainActor in
                    guard let url else { return }
                    addDroppedResource(url)
                }
            }
            didSchedule = true
        }
        return didSchedule
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private func addDroppedResource(_ url: URL) {
        let decision = EntitlementRules.canAddResource(currentResourceCount: resources.count, plan: license.plan)
        guard decision.isAllowed else {
            presentLicense(decision.message)
            return
        }

        let type: ResourceType
        if url.pathExtension == "app" {
            type = .app
        } else {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            type = isDirectory.boolValue ? .folder : .file
        }

        let resource = StudyResource(
            box: box,
            title: url.deletingPathExtension().lastPathComponent,
            type: type,
            urlString: url.path,
            appBundleID: type == .app ? AppPicker.bundleIdentifier(for: url) : nil,
            appPath: type == .app ? url.path : nil,
            orderIndex: resources.count
        )
        modelContext.insert(resource)
        normalizeOrder()
        save()
    }

    private func presentLicense(_ reason: String?) {
        appState.presentLicense(reason: reason)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func icon(for status: ResourceLaunchStatus) -> String {
        switch status {
        case .success: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .skipped: "minus.circle"
        }
    }

    private func color(for status: ResourceLaunchStatus) -> Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .skipped: .secondary
        }
    }
}

private struct ResourceRow: View {
    private enum Layout {
        static let automaticOpenWidth: CGFloat = 150
        static let primaryActionWidth: CGFloat = 150
        static let menuWidth: CGFloat = 34
    }

    @Bindable var resource: StudyResource

    let canMoveUp: Bool
    let canMoveDown: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRelink: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resource.type.systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(resource.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let healthMessage = healthStatus.message {
                    Label(healthMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer()

            Toggle("Open in sessions", isOn: $resource.enabledByDefault)
                .toggleStyle(.checkbox)
                .frame(width: Layout.automaticOpenWidth, alignment: .leading)
                .help("When enabled, this resource opens automatically at the start of a session.")
                .onChange(of: resource.enabledByDefault) {
                    resource.touch()
                    onSave()
                }

            if resource.type == .commandPlaceholder {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resource.urlString, forType: .string)
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .frame(width: Layout.primaryActionWidth, alignment: .leading)
                .help("Copy this command to the clipboard. Study Boxes does not run commands automatically.")
            } else if resource.type.isLaunchable {
                Button {
                    onOpen()
                } label: {
                    Label("Open Now", systemImage: "arrow.up.forward")
                }
                .frame(width: Layout.primaryActionWidth, alignment: .leading)
                .help("Open this resource now.")
            } else {
                Color.clear
                    .frame(width: Layout.primaryActionWidth)
            }

            Menu {
                Button("Move Up", action: onMoveUp)
                    .disabled(!canMoveUp)
                Button("Move Down", action: onMoveDown)
                    .disabled(!canMoveDown)
                Divider()
                if healthStatus == .missingPath {
                    Button("Relink", action: onRelink)
                }
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: Layout.menuWidth, height: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("More resource actions")
            .help("Edit or delete this resource.")
        }
        .padding(12)
    }

    private var subtitle: String {
        switch resource.type {
        case .app:
            return resource.appBundleID ?? resource.appPath ?? "App"
        case .notes:
            return "Note"
        case .anki:
            let link = resource.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            return link.isEmpty ? "Open Anki" : link
        case .commandPlaceholder:
            return "Copy-only command"
        default:
            return resource.urlString
        }
    }

    private var healthStatus: ResourceHealthStatus {
        ResourceHealthService.status(for: resource)
    }
}

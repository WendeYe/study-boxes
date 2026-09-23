import SwiftData
import SwiftUI

struct ICSFeedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var provider: LMSProvider = .genericICS
    @State private var title = ""
    @State private var feedURL = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
	                Section("Feed") {
	                    DropdownMenuRow("Provider", selection: $provider, options: LMSProvider.allCases)
	                    .help("This labels the feed. Study Boxes still imports it as a standard ICS calendar.")

	                    TextField("Name", text: $title)
	                        .help("A name like Moodle deadlines or Operating Systems calendar.")
	                    TextField("Calendar feed URL", text: $feedURL)
	                        .help("Paste the full private calendar export URL, including query parameters and tokens.")
	                }

	                Text("Calendar feed links can contain private tokens. Study Boxes stores the link in Keychain and keeps only a lookup key in SwiftData.")
	                    .font(.caption)
	                    .foregroundStyle(.secondary)
	                Text("After saving, press Sync Deadlines to fetch events and convert them into Study Box tasks.")
	                    .font(.caption)
	                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
	                Button("Save Feed") { save() }
	                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        do {
            _ = try ICSFeedService.addFeed(title: trimmedTitle, provider: provider, feedURL: feedURL, modelContext: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

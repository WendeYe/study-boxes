import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject private var diagnostics = DiagnosticsService.shared
    @ObservedObject private var license = LicenseManager.shared
    @State private var diagnosticMessage: String?

    var body: some View {
        Section("Privacy and diagnostics") {
            Toggle("Share crash reports", isOn: $diagnostics.crashReportingEnabled)
                .help("Crash reports are off by default and only start after you opt in.")

            Text("Crash reports help fix bugs. Study Boxes does not include study box names, tasks, notes, URLs, file paths, app/window lists, license keys, email, tokens, or calendar feed links.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                createDiagnosticReport()
            } label: {
                Label("Create Diagnostic Report...", systemImage: "doc.badge.gearshape")
            }
                .help("Create a local report you can review before you send it to support.")

            if let diagnosticMessage {
                Text(diagnosticMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func createDiagnosticReport() {
        guard let url = FilePicker.chooseTextExport(defaultName: "Study Boxes Diagnostic Report.txt") else {
            return
        }

        do {
            try diagnostics.writeDiagnosticReport(to: url, licensePlan: license.plan)
            diagnosticMessage = "Diagnostic report created."
        } catch {
            diagnosticMessage = "Study Boxes could not create the diagnostic report."
        }
    }
}

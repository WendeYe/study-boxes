import AppKit
import SwiftUI

struct LicenseView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var manager = LicenseManager.shared
    @State private var licenseKey = ""
    @FocusState private var isLicenseFieldFocused: Bool

    var body: some View {
        Section("License") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(manager.plan.title) plan")
                        .font(.headline)
                    if manager.plan.isPro {
                        ProBadge()
                    }
                }
                Text(manager.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reason = appState.licensePresentationReason {
                    Label(reason, systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }

            if LicenseViewPresentation.showsActivationControls(for: manager.plan) {
                activationControls
            } else {
                Button("Deactivate License", role: .destructive) {
                    Task {
                        await manager.deactivate()
                    }
                }
                .disabled(manager.state == .validating)
            }

            if LicenseViewPresentation.showsActivationControls(for: manager.plan) {
                Text("Buy Study Boxes Pro, then paste the Lemon Squeezy license key from your receipt email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activationControls: some View {
        Group {
            HStack(spacing: 8) {
                TextField("License key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .focused($isLicenseFieldFocused)
                    .disabled(manager.state == .validating)
                    .onSubmit {
                        activateIfPossible()
                    }

                Button {
                    pasteLicenseKey()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(manager.state == .validating)

                Button {
                    licenseKey = ""
                    isLicenseFieldFocused = true
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(licenseKey.isEmpty || manager.state == .validating)
            }

            HStack {
                Button {
                    NSWorkspace.shared.open(LicenseConfiguration.production.checkoutURL)
                } label: {
                    Label("Buy Pro", systemImage: "cart")
                }

                Button("Activate", action: activateIfPossible)
                    .disabled(manager.state == .validating || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Validate") {
                    Task {
                        await manager.validateStoredLicense()
                    }
                }
                .disabled(manager.state == .validating)
            }
        }
    }

    private func activateIfPossible() {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isLicenseFieldFocused = true
            return
        }

        Task {
            await manager.activate(licenseKey: trimmed)
            if case .licensed = manager.state {
                licenseKey = ""
            }
        }
    }

    private func pasteLicenseKey() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            licenseKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isLicenseFieldFocused = true
    }
}

enum LicenseViewPresentation {
    static func showsActivationControls(for plan: EntitlementPlan) -> Bool {
        !plan.isPro
    }
}

struct ProBadge: View {
    var body: some View {
        Label("Pro", systemImage: "star.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.purple)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.purple.opacity(0.12), in: Capsule())
            .accessibilityLabel("Pro feature")
    }
}

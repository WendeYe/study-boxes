import AppKit
import Foundation
import UniformTypeIdentifiers

enum AppPicker {
    @MainActor
    static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func bundleIdentifier(for appURL: URL) -> String? {
        Bundle(url: appURL)?.bundleIdentifier
    }
}

import Foundation
import os

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    static let placeholderAppcastURL = "https://example.com/study-boxes/appcast.xml"

    private let logger = Logger(subsystem: "StudyBoxes", category: "Updates")

    #if canImport(Sparkle)
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif

    @Published private(set) var statusMessage = "Sparkle is not bundled in this debug build."

    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        statusMessage = "Checking for updates."
        #else
        logger.info("Sparkle package is not linked. Add Sparkle 2 and configure SUFeedURL before enabling updates.")
        statusMessage = "Add Sparkle 2 and configure the appcast URL before shipping update checks."
        #endif
    }
}

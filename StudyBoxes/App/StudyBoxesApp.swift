import SwiftData
import SwiftUI

@main
struct StudyBoxesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let sharedModelContainer: ModelContainer
    @StateObject private var appState: AppState

    init() {
        let modelContainer = Self.makeModelContainer()
        let appState = AppState()

        self.sharedModelContainer = modelContainer
        self._appState = StateObject(wrappedValue: appState)
        DiagnosticsService.shared.configureCrashReportingIfNeeded()
        MenuBarTimerController.shared.configure(appState: appState, modelContainer: modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            StudyBox.self,
            StudyResource.self,
            StudyTask.self,
            StudySession.self,
            LMSCalendarFeed.self,
            LMSImportedEvent.self,
            WindowLayout.self,
            SessionRestoreSnapshot.self,
            SessionRestoreApp.self,
            SessionRestoreWindow.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            UserDefaults.standard.removeObject(forKey: AppState.persistenceRecoveryMessageKey)
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            let backupMessage = recoverPersistentStore(after: error)
            UserDefaults.standard.set(backupMessage, forKey: AppState.persistenceRecoveryMessageKey)
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            } catch {
                fatalError("Could not initialize SwiftData ModelContainer after recovery: \(error)")
            }
        }
    }

    private static func recoverPersistentStore(after error: Error) -> String {
        let fileManager = FileManager.default
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backupFolder = supportURL
            .appendingPathComponent("StudyBoxes Store Backups", isDirectory: true)
            .appendingPathComponent(Self.backupTimestamp(), isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            for fileName in ["default.store", "default.store-shm", "default.store-wal"] {
                let source = supportURL.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: backupFolder.appendingPathComponent(fileName))
            }
            return "Study Boxes found an incompatible local database and moved it to \(backupFolder.path). A fresh local database was created."
        } catch {
            return "Study Boxes could not open the local database and recovery also failed: \(error.localizedDescription)"
        }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    var body: some Scene {
        WindowGroup("Study Boxes", id: "dashboard") {
            DashboardView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .background(AppWindowIdentifierView(identifier: AppWindowController.dashboardIdentifier))
        }

        Window("Study Space", id: "session") {
            SessionWorkspaceView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .background(AppWindowIdentifierView(identifier: AppWindowController.studySpaceIdentifier))
        }
        .defaultSize(width: StudySpacePresentation.defaultWidth, height: StudySpacePresentation.defaultHeight)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
        }
    }
}

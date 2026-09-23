import SwiftData
import SwiftUI

struct SessionWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: \StudySession.startedAt, order: .reverse)
    private var sessions: [StudySession]

    private var activeSession: StudySession? {
        guard let activeSessionID = appState.activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    var body: some View {
        Group {
            if let activeSession, let box = activeSession.box {
                SessionModeView(
                    box: box,
                    session: activeSession,
                    launchResults: appState.activeLaunchResults,
                    onNotesChanged: { notes in
                        activeSession.notes = notes
                    }
                )
                .environmentObject(appState)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear(perform: closeIfIdle)
            }
        }
        .onChange(of: appState.activeSessionID) { _, _ in
            closeIfIdle()
        }
    }

    private func closeIfIdle() {
        guard !AppWindowController.shouldOpenStudySpaceWindow(activeSessionID: appState.activeSessionID) else {
            return
        }

        AppWindowController.closeStudySpaceWindows()
    }
}

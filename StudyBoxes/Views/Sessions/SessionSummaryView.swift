import SwiftUI

struct SessionSummaryView: View {
    let box: StudyBox
    let session: StudySession
    let onStartAnother: () -> Void
    let onBackToDashboard: () -> Void

    private var completedTasks: [StudyTask] { tasks(matching: session.completedTaskIDs) }
    private var skippedTasks: [StudyTask] { tasks(matching: session.skippedTaskIDs) }
    private var nextTask: StudyTask? { StudyResumeService.nextSuggestedTask(for: box) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session complete")
                        .font(.largeTitle.weight(.bold))
                    Text(box.name)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // MARK: Metrics
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { metricCards }
                    VStack(spacing: 10) { metricCards }
                }

                // MARK: Task lists
                if !completedTasks.isEmpty {
                    taskGroup(title: "Completed", systemImage: "checkmark.circle.fill", color: .green, tasks: completedTasks)
                }
                if !skippedTasks.isEmpty {
                    taskGroup(title: "Skipped", systemImage: "forward.circle.fill", color: .orange, tasks: skippedTasks)
                }
                if completedTasks.isEmpty && skippedTasks.isEmpty {
                    GroupBox {
                        Text("No task statuses changed during this session.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: What's next
                if let nextTask {
                    GroupBox(label: Label("What's next", systemImage: "arrow.right.circle").font(.headline)) {
                        Label(nextTask.title, systemImage: nextTask.type.systemImageName)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: Notes
                if let notes = session.notes, !notes.isEmpty {
                    GroupBox(label: Label("Notes", systemImage: "note.text").font(.headline)) {
                        Text(notes)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(28)
        }

        // MARK: Footer
        Divider()
        HStack {
            Spacer()
            Button("Back to Dashboard", action: onBackToDashboard)
                .keyboardShortcut(.cancelAction)
            Button {
                onStartAnother()
            } label: {
                Label("Start Another Session", systemImage: "play.fill")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: Metric cards

    @ViewBuilder
    private var metricCards: some View {
        summaryMetric(
            label: "Duration",
            value: DurationFormatter.minutes(session.durationMinutes),
            systemImage: "timer",
            color: .accentColor
        )
        summaryMetric(
            label: "Completed",
            value: "\(completedTasks.count)",
            systemImage: "checkmark.circle",
            color: .green
        )
        summaryMetric(
            label: "Skipped",
            value: "\(skippedTasks.count)",
            systemImage: "forward.circle",
            color: .orange
        )
    }

    private func summaryMetric(label: String, value: String, systemImage: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title.weight(.semibold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Task group

    private func taskGroup(title: String, systemImage: String, color: Color, tasks: [StudyTask]) -> some View {
        GroupBox(label: Label(title, systemImage: systemImage).font(.headline).foregroundStyle(color)) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tasks) { task in
                    Label(task.title, systemImage: task.type.systemImageName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tasks(matching ids: [UUID]) -> [StudyTask] {
        ids.compactMap { id in box.tasks.first { $0.id == id } }
    }
}

private extension StudyTaskType {
    var systemImageName: String {
        switch self {
        case .exercise: "checklist"
        case .theory: "book"
        case .pastExam, .mockExam: "doc.text"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .review: "arrow.clockwise"
        case .flashcards: "rectangle.stack"
        case .notes: "note.text"
        case .assignment: "doc.badge.clock"
        case .quiz: "questionmark.circle"
        case .other: "circle"
        }
    }
}

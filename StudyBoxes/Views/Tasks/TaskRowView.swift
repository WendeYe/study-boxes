import SwiftData
import SwiftUI

struct TaskRowView: View {
    @Bindable var task: StudyTask

    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Remove this task from bulk actions." : "Select this task for bulk actions.")

            statusButton

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.status == .done)

                    if task.priority >= 3 {
                        Label("High", systemImage: "exclamationmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    Text(task.type.title)
                    if let unit = task.unit, !unit.isEmpty {
                        Text(unit)
                    }
                    if let estimatedMinutes = task.estimatedMinutes {
                        Text("\(estimatedMinutes) min")
                    }
                    if let dueDate = task.dueDate {
                        Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let details = task.details, !details.isEmpty {
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !task.subtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(task.subtasks.prefix(4)) { subtask in
                            Label(subtask.title, systemImage: subtask.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

	            Button("Skip") {
	                task.markSkipped()
	                onSave()
	            }
	            .disabled(task.status == .skipped || task.status == .done)
	            .help("Mark this task as skipped for now. It will not count as completed.")

	            Menu {
                    Button("Move Up", action: onMoveUp)
                        .disabled(!canMoveUp)
                    Button("Move Down", action: onMoveDown)
                        .disabled(!canMoveDown)
                    Divider()
	                Button("Edit Task", action: onEdit)
	                if task.status == .done || task.status == .skipped {
	                    Button("Mark Pending") {
	                        task.markPending()
                        onSave()
                    }
                }
	                Button("Delete", role: .destructive, action: onDelete)
	            } label: {
	                Label("More task actions", systemImage: "ellipsis.circle")
	            }
	            .menuStyle(.borderlessButton)
	            .help("Edit, reset, or delete this task.")
        }
        .padding(12)
    }

    private var statusButton: some View {
        Button {
            if task.status == .done {
                task.markPending()
            } else {
                task.markDone()
            }
            onSave()
	        } label: {
	            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
	                .font(.title3)
	                .foregroundStyle(task.status == .done ? .green : .secondary)
	        }
	        .buttonStyle(.plain)
	        .help(task.status == .done ? "Mark this task pending again." : "Mark this task done.")
	    }
}

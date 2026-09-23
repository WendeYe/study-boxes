import SwiftData
import SwiftUI

struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext

    let box: StudyBox

    @State private var filter: TaskFilter = .today
    @State private var isAddingTask = false
    @State private var editingTask: StudyTask?
    @State private var searchText = ""
    @State private var selectedTaskIDs: Set<UUID> = []

    private var tasks: [StudyTask] {
        TaskManager.searchedTasks(TaskManager.filteredTasks(box.tasks, filter: filter), query: searchText)
    }

    private var pendingCount: Int {
        box.tasks.filter { $0.status == .pending || $0.status == .inProgress }.count
    }

    private var doneCount: Int {
        box.tasks.filter { $0.status == .done }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
	                    Text("Tasks")
	                        .font(.title2.weight(.semibold))
	                    Text("\(pendingCount) pending, \(doneCount) done")
	                        .font(.callout)
	                        .foregroundStyle(.secondary)
	                    Text("Use tasks for exercises, readings, review items, and assignment steps.")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)
	                }

                Spacer()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        taskControls
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        taskControls
                    }
                }
            }

            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)

            if tasks.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "checklist",
                    description: Text("Add the next exercise, reading, or assignment step you want to finish.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        TaskRowView(
                            task: task,
                            isSelected: selectedTaskIDs.contains(task.id),
                            canMoveUp: task.id != tasks.first?.id,
                            canMoveDown: task.id != tasks.last?.id,
                            onSelect: { toggleSelection(task) },
                            onEdit: { editingTask = task },
                            onDelete: { delete(task) },
                            onMoveUp: { move(task, direction: -1) },
                            onMoveDown: { move(task, direction: 1) },
                            onSave: save
                        )

                        if task.id != tasks.last?.id {
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
        }
        .sheet(isPresented: $isAddingTask) {
            TaskEditorView(box: box)
                .frame(minWidth: 520, minHeight: 560)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(box: box, task: task)
                .frame(minWidth: 520, minHeight: 560)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No tasks yet"
        case .today: "Nothing urgent for today"
        case .pending: "No pending tasks"
        case .done: "No completed tasks"
        case .highPriority: "No high priority tasks"
        }
    }

    private var taskControls: some View {
        Group {
            DropdownMenu(
                "Filter",
                selection: $filter,
                options: TaskFilter.allCases,
                minWidth: 160
            )
            .help("Choose which tasks to show in this list.")

            Menu {
                Button("Mark Done") { bulkSetStatus(.done) }
                    .disabled(selectedTaskIDs.isEmpty)
                Button("Mark Pending") { bulkSetStatus(.pending) }
                    .disabled(selectedTaskIDs.isEmpty)
                Button("Skip") { bulkSetStatus(.skipped) }
                    .disabled(selectedTaskIDs.isEmpty)
                Divider()
                Button("Delete Selected", role: .destructive) { bulkDelete() }
                    .disabled(selectedTaskIDs.isEmpty)
            } label: {
                Label("Bulk Actions", systemImage: "checklist.checked")
            }
            .help("Apply a status change or delete selected tasks.")

            Button {
                isAddingTask = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .help("Create a new checklist item for this Study Box.")
        }
    }

    private func delete(_ task: StudyTask) {
        selectedTaskIDs.remove(task.id)
        modelContext.delete(task)
        TaskManager.normalizeOrder(box.tasks)
        save()
    }

    private func toggleSelection(_ task: StudyTask) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
    }

    private func move(_ task: StudyTask, direction: Int) {
        var ordered = tasks
        guard let currentIndex = ordered.firstIndex(where: { $0.id == task.id }) else { return }
        let targetIndex = currentIndex + direction
        guard ordered.indices.contains(targetIndex) else { return }
        ordered.swapAt(currentIndex, targetIndex)
        for (index, task) in ordered.enumerated() {
            task.orderIndex = index
            task.touch()
        }
        save()
    }

    private func bulkSetStatus(_ status: StudyTaskStatus) {
        for task in box.tasks where selectedTaskIDs.contains(task.id) {
            task.status = status
        }
        selectedTaskIDs.removeAll()
        save()
    }

    private func bulkDelete() {
        for task in box.tasks where selectedTaskIDs.contains(task.id) {
            modelContext.delete(task)
        }
        selectedTaskIDs.removeAll()
        TaskManager.normalizeOrder(box.tasks)
        save()
    }

    private func save() {
        do {
            box.touch()
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save task changes: \(error)")
        }
    }
}

import SwiftData
import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let box: StudyBox
    private let task: StudyTask?

    @State private var title: String
    @State private var details: String
    @State private var type: StudyTaskType
    @State private var status: StudyTaskStatus
    @State private var priority: Int
    @State private var hasEstimate: Bool
    @State private var estimatedMinutes: Int
    @State private var estimatedMinutesText: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var unit: String
    @State private var linkedResourceIDs: Set<UUID>
    @State private var subtasksText: String
    @State private var errorMessage: String?

    private var resources: [StudyResource] {
        box.resources.sorted { $0.orderIndex < $1.orderIndex }
    }

    init(box: StudyBox, task: StudyTask? = nil) {
        self.box = box
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _type = State(initialValue: task?.type ?? .exercise)
        _status = State(initialValue: task?.status ?? .pending)
        _priority = State(initialValue: task?.priority ?? 1)
        _hasEstimate = State(initialValue: task?.estimatedMinutes != nil)
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 30)
        _estimatedMinutesText = State(initialValue: String(task?.estimatedMinutes ?? 30))
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? .now)
        _unit = State(initialValue: task?.unit ?? "")
        _linkedResourceIDs = State(initialValue: Set(task?.linkedResourceIDs ?? []))
        _subtasksText = State(initialValue: task?.subtasks.map(\.title).joined(separator: "\n") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)

                    DropdownMenuRow("Type", selection: $type, options: StudyTaskType.allCases)

                    DropdownMenuRow("Status", selection: $status, options: StudyTaskStatus.allCases)

                    Stepper("Priority: \(priorityLabel)", value: $priority, in: 0...3)
                }

                Section("Planning") {
                    TextField("Unit or topic", text: $unit)

                    Toggle("Estimated time", isOn: $hasEstimate)
                    if hasEstimate {
                        HStack {
                            Text("Estimate")
                            Spacer()
                            HStack(spacing: 6) {
                                TextField("", text: $estimatedMinutesText)
                                    .frame(width: 64)
                                    .multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder)
                                Text("minutes")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help("Type any whole-minute estimate up to 999 minutes.")
                        .onChange(of: estimatedMinutesText) { _, newValue in
                            let sanitized = NumericInput.sanitizedIntegerText(newValue, range: 0...999)
                            if sanitized != newValue {
                                estimatedMinutesText = sanitized
                            }
                            estimatedMinutes = NumericInput.integerValue(from: sanitized, fallback: estimatedMinutes, range: 0...999)
                        }
                    }

                    HStack {
                        Toggle("Due date", isOn: $hasDueDate)
                        Spacer()
                        if hasDueDate {
                            SystemDatePickerField(date: $dueDate, accessibilityLabel: "Due date")
                        }
                    }
                }

                Section("Details") {
                    TextEditor(text: $details)
                        .frame(minHeight: 90)
                }

                Section("Subtasks") {
                    Text("One subtask per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $subtasksText)
                        .frame(minHeight: 72)
                }

                Section("Linked Resources") {
                    if resources.isEmpty {
                        Text("Add resources to this Study Box before linking them to tasks.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(resources) { resource in
                            Toggle(isOn: binding(for: resource.id)) {
                                Label(resource.title, systemImage: resource.type.systemImage)
                            }
                            .help("Show this resource as related context for the task.")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(task == nil ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private var priorityLabel: String {
        switch priority {
        case 0: "Low"
        case 1: "Normal"
        case 2: "Important"
        default: "High"
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required."
            return
        }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSubtasks = subtasksText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { title in
                task?.subtasks.first(where: { $0.title == title }) ?? StudySubtask(title: title)
            }
        let storedEstimatedMinutes = NumericInput.integerValue(
            from: estimatedMinutesText,
            fallback: estimatedMinutes,
            range: 0...999
        )

        if let task {
            task.update(
                title: trimmedTitle,
                details: trimmedDetails.isEmpty ? nil : trimmedDetails,
                type: type,
                status: status,
                priority: priority,
                estimatedMinutes: hasEstimate ? storedEstimatedMinutes : nil,
                dueDate: hasDueDate ? dueDate : nil,
                unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                linkedResourceIDs: Array(linkedResourceIDs),
                subtasks: parsedSubtasks
            )
        } else {
            let task = StudyTask(
                box: box,
                title: trimmedTitle,
                details: trimmedDetails.isEmpty ? nil : trimmedDetails,
                type: type,
                status: status,
                priority: priority,
                estimatedMinutes: hasEstimate ? storedEstimatedMinutes : nil,
                dueDate: hasDueDate ? dueDate : nil,
                unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                linkedResourceIDs: Array(linkedResourceIDs),
                subtasks: parsedSubtasks,
                completedAt: status == .done ? .now : nil
            )
            modelContext.insert(task)
        }

        box.touch()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Study Boxes could not save this task."
        }
    }

    private func binding(for resourceID: UUID) -> Binding<Bool> {
        Binding {
            linkedResourceIDs.contains(resourceID)
        } set: { isLinked in
            if isLinked {
                linkedResourceIDs.insert(resourceID)
            } else {
                linkedResourceIDs.remove(resourceID)
            }
        }
    }
}

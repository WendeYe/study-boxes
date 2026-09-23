import AppKit
import SwiftUI

protocol DropdownMenuDisplayable: Hashable, Identifiable {
    var dropdownTitle: String { get }
    var dropdownSystemImage: String { get }
}

struct DropdownMenuOption<Value: Hashable>: Identifiable, Equatable {
    let value: Value
    let title: String
    let systemImage: String

    var id: Value { value }

    static func selectedOption(
        in options: [Self],
        matching value: Value,
        fallback: Self?
    ) -> Self? {
        options.first { $0.value == value } ?? fallback
    }
}

extension DropdownMenuOption where Value: DropdownMenuDisplayable {
    static func options(for values: [Value]) -> [Self] {
        values.map {
            Self(
                value: $0,
                title: $0.dropdownTitle,
                systemImage: $0.dropdownSystemImage
            )
        }
    }
}

struct DropdownMenu<Value: Hashable>: View {
    private let accessibilityLabel: String
    @Binding private var selection: Value
    private let options: [DropdownMenuOption<Value>]
    private let isEnabled: Bool
    private let minWidth: CGFloat
    private let fallbackTitle: String
    private let fallbackSystemImage: String

    init(
        _ accessibilityLabel: String,
        selection: Binding<Value>,
        options: [DropdownMenuOption<Value>],
        isEnabled: Bool = true,
        minWidth: CGFloat = 180,
        fallbackTitle: String = "Choose",
        fallbackSystemImage: String = "questionmark.circle"
    ) {
        self.accessibilityLabel = accessibilityLabel
        _selection = selection
        self.options = options
        self.isEnabled = isEnabled
        self.minWidth = minWidth
        self.fallbackTitle = fallbackTitle
        self.fallbackSystemImage = fallbackSystemImage
    }

    private var selectedOption: DropdownMenuOption<Value> {
        DropdownMenuOption.selectedOption(
            in: options,
            matching: selection,
            fallback: options.first
        ) ?? DropdownMenuOption(
            value: selection,
            title: fallbackTitle,
            systemImage: fallbackSystemImage
        )
    }

    var body: some View {
        AppKitDropdownMenu(
            accessibilityLabel: accessibilityLabel,
            selection: $selection,
            options: options,
            selectedOption: selectedOption,
            isEnabled: isEnabled
        )
        .frame(width: minWidth, height: 28)
    }
}

private struct AppKitDropdownMenu<Value: Hashable>: NSViewRepresentable {
    let accessibilityLabel: String
    @Binding var selection: Value
    let options: [DropdownMenuOption<Value>]
    let selectedOption: DropdownMenuOption<Value>
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectCurrentItem(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection

        button.target = context.coordinator
        button.action = #selector(Coordinator.selectCurrentItem(_:))
        button.removeAllItems()
        button.menu?.autoenablesItems = false

        let renderedOptions = options.isEmpty ? [selectedOption] : options
        for option in renderedOptions {
            button.menu?.addItem(Self.menuItem(for: option, target: context.coordinator))
        }

        if let selectedItem = button.menu?.items.first(where: { item in
            guard let box = item.representedObject as? DropdownMenuOptionBox<Value> else { return false }
            return box.value == selection
        }) {
            button.select(selectedItem)
        }

        button.isEnabled = isEnabled && !options.isEmpty
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityValue(selectedOption.title)
    }

    private static func menuItem(for option: DropdownMenuOption<Value>, target: Coordinator) -> NSMenuItem {
        let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: option.systemImage, accessibilityDescription: option.title)
        item.image?.isTemplate = true
        item.representedObject = DropdownMenuOptionBox(option.value)
        item.target = target
        return item
    }

    final class Coordinator: NSObject {
        var selection: Binding<Value>

        init(selection: Binding<Value>) {
            self.selection = selection
        }

        @objc func selectCurrentItem(_ sender: NSPopUpButton) {
            guard let box = sender.selectedItem?.representedObject as? DropdownMenuOptionBox<Value> else {
                return
            }
            selection.wrappedValue = box.value
        }
    }
}

private final class DropdownMenuOptionBox<Value> {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

extension DropdownMenu where Value: DropdownMenuDisplayable {
    init(
        _ accessibilityLabel: String,
        selection: Binding<Value>,
        options: [Value],
        isEnabled: Bool = true,
        minWidth: CGFloat = 180
    ) {
        self.init(
            accessibilityLabel,
            selection: selection,
            options: DropdownMenuOption.options(for: options),
            isEnabled: isEnabled,
            minWidth: minWidth
        )
    }
}

struct DropdownMenuRow<Value: Hashable>: View {
    private let title: String
    @Binding private var selection: Value
    private let options: [DropdownMenuOption<Value>]
    private let isEnabled: Bool
    private let minWidth: CGFloat

    init(
        _ title: String,
        selection: Binding<Value>,
        options: [DropdownMenuOption<Value>],
        isEnabled: Bool = true,
        minWidth: CGFloat = 180
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.isEnabled = isEnabled
        self.minWidth = minWidth
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            DropdownMenu(
                title,
                selection: $selection,
                options: options,
                isEnabled: isEnabled,
                minWidth: minWidth
            )
        }
    }
}

extension DropdownMenuRow where Value: DropdownMenuDisplayable {
    init(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        isEnabled: Bool = true,
        minWidth: CGFloat = 180
    ) {
        self.init(
            title,
            selection: selection,
            options: DropdownMenuOption.options(for: options),
            isEnabled: isEnabled,
            minWidth: minWidth
        )
    }
}

struct FocusModeMenu: View {
    @Binding var selection: StudyFocusMode
    var isEnabled = true
    var minWidth: CGFloat = 180

    var body: some View {
        DropdownMenu(
            "Focus Mode",
            selection: $selection,
            options: StudyFocusMode.allCases,
            isEnabled: isEnabled,
            minWidth: minWidth
        )
    }
}

extension StudyFocusMode: DropdownMenuDisplayable {
    var dropdownTitle: String { title }
    var dropdownSystemImage: String { systemImage }
}

extension StudyBoxType: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
        switch self {
        case .course: "books.vertical"
        case .exam: "graduationcap"
        case .assignment: "doc.text"
        case .topic: "lightbulb"
        case .project: "folder"
        case .language: "globe"
        case .other: "circle"
        }
    }
}

extension ResourceType: DropdownMenuDisplayable {
    var dropdownTitle: String { title }
    var dropdownSystemImage: String { systemImage }
}

extension StudyTaskType: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
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

extension StudyTaskStatus: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
        switch self {
        case .pending: "circle"
        case .inProgress: "play.circle"
        case .done: "checkmark.circle"
        case .skipped: "forward.circle"
        }
    }
}

extension TaskFilter: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
        switch self {
        case .all: "tray.full"
        case .today: "calendar"
        case .pending: "circle.dashed"
        case .done: "checkmark.circle"
        case .highPriority: "exclamationmark.circle"
        }
    }
}

extension MenuBarDisplayMode: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
        switch self {
        case .iconOnly: "menubar.rectangle"
        case .timer: "timer"
        case .boxNameAndTimer: "textformat"
        }
    }
}

extension LMSProvider: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
        switch self {
        case .moodle: "graduationcap"
        case .blackboard: "rectangle.and.pencil.and.ellipsis"
        case .genericICS: "calendar.badge.plus"
        }
    }
}

extension SessionHistoryFilter: DropdownMenuDisplayable {
    var dropdownTitle: String { title }

    var dropdownSystemImage: String {
        switch self {
        case .all: "clock"
        case .thisWeek: "calendar"
        case .thisMonth: "calendar.badge.clock"
        }
    }
}

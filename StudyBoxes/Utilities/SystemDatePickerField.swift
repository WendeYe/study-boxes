import Foundation
import SwiftUI

enum SystemDateFormat {
    static func string(
        for date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(date: .numeric, time: .omitted)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

struct SystemDatePickerField: View {
    @Binding var date: Date
    var accessibilityLabel: String = "Date"

    @State private var isShowingPicker = false

    private var displayText: String {
        SystemDateFormat.string(for: date)
    }

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(displayText)
                    .font(.body.monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 122, alignment: .center)
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(displayText))
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            VStack(alignment: .trailing, spacing: 12) {
                DatePicker(accessibilityLabel, selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                Button("Done") {
                    isShowingPicker = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .frame(minWidth: 280)
        }
    }
}

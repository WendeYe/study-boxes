import XCTest
@testable import StudyBoxes

final class InputControlTests: XCTestCase {
    func testNumericInputKeepsEmptyTextEditable() {
        XCTAssertEqual(NumericInput.sanitizedIntegerText("", range: 0...999), "")
        XCTAssertEqual(NumericInput.integerValue(from: "", fallback: 50, range: 0...999), 50)
    }

    func testNumericInputFiltersNonDigitsAndClampsToRange() {
        XCTAssertEqual(NumericInput.sanitizedIntegerText("abc12 min", range: 0...999), "12")
        XCTAssertEqual(NumericInput.sanitizedIntegerText("1000", range: 0...999), "999")
        XCTAssertEqual(NumericInput.integerValue(from: "1000", fallback: 50, range: 0...999), 999)
    }

    func testNumericInputAllowsZero() {
        XCTAssertEqual(NumericInput.sanitizedIntegerText("0", range: 0...999), "0")
        XCTAssertEqual(NumericInput.integerValue(from: "0", fallback: 50, range: 0...999), 0)
    }

    func testDefaultSessionPresetsStayStudyFocused() {
        XCTAssertEqual(SessionPreset.defaultMinutes, [25, 50, 90])
    }

    func testDropdownOptionsUseSharedTitleAndIconPresentation() {
        let focusOptions = DropdownMenuOption.options(for: StudyFocusMode.allCases)
        XCTAssertEqual(focusOptions.map(\.title), ["Off", "Hide Apps", "Quit Apps", "Strict Focus"])
        XCTAssertEqual(focusOptions.map(\.systemImage), ["circle", "eye.slash", "xmark.app", "lock.shield"])

        let boxTypeOptions = DropdownMenuOption.options(for: StudyBoxType.allCases)
        XCTAssertEqual(boxTypeOptions.first?.title, "Course")
        XCTAssertEqual(boxTypeOptions.first?.systemImage, "books.vertical")

        let taskStatusOptions = DropdownMenuOption.options(for: StudyTaskStatus.allCases)
        XCTAssertEqual(taskStatusOptions.map(\.systemImage), ["circle", "play.circle", "checkmark.circle", "forward.circle"])
    }

    func testDropdownOptionSelectionFallsBackWhenStoredValueIsUnavailable() throws {
        let options = [
            DropdownMenuOption(value: "timer", title: "Timer", systemImage: "timer"),
            DropdownMenuOption(value: "box", title: "Box + timer", systemImage: "textformat")
        ]

        let selected = try XCTUnwrap(DropdownMenuOption.selectedOption(
            in: options,
            matching: "missing",
            fallback: options.first
        ))

        XCTAssertEqual(selected.value, "timer")
        XCTAssertEqual(selected.title, "Timer")
        XCTAssertEqual(selected.systemImage, "timer")
    }

    func testSystemDateFormatUsesLocaleDateOrder() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: 2026,
            month: 6,
            day: 1,
            hour: 12
        ).date)

        let usDate = SystemDateFormat.string(
            for: date,
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: timeZone
        )
        let ukDate = SystemDateFormat.string(
            for: date,
            locale: Locale(identifier: "en_GB"),
            calendar: calendar,
            timeZone: timeZone
        )

        XCTAssertEqual(usDate, "6/1/2026")
        XCTAssertEqual(ukDate, "01/06/2026")
        XCTAssertFalse(usDate.contains("/ "))
        XCTAssertFalse(ukDate.contains("/ "))
    }
}

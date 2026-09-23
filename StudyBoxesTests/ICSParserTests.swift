import XCTest
@testable import StudyBoxes

final class ICSParserTests: XCTestCase {
    func testParsesBasicEventWithDateOnlyDueDate() throws {
        let events = ICSParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:exam-1
            SUMMARY:Final exam
            DESCRIPTION:Bring notes\\, calculator\\nand ID
            DUE;VALUE=DATE:20260512
            URL:https://example.com/exam
            END:VEVENT
            END:VCALENDAR
            """
        )

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.uid, "exam-1")
        XCTAssertEqual(event.summary, "Final exam")
        XCTAssertEqual(event.description, "Bring notes, calculator\nand ID")
        XCTAssertEqual(event.urlString, "https://example.com/exam")

        let components = Calendar.current.dateComponents([.year, .month, .day], from: try XCTUnwrap(event.dueDate))
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 12)
    }

    func testUnfoldsFoldedLines() throws {
        let events = ICSParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:folded-1
            SUMMARY:Very long
             assignment title
            END:VEVENT
            END:VCALENDAR
            """
        )

        XCTAssertEqual(try XCTUnwrap(events.first).summary, "Very longassignment title")
    }

    func testParsesUTCAndTZIDDateTimes() throws {
        let events = ICSParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:tz-1
            SUMMARY:Timed event
            DTSTART:20260429T090000Z
            DUE;TZID=Europe/Madrid:20260430T110000
            END:VEVENT
            END:VCALENDAR
            """
        )

        let event = try XCTUnwrap(events.first)
        let utcComponents = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: try XCTUnwrap(event.startDate))
        XCTAssertEqual(utcComponents.hour, 9)

        let madridComponents = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Europe/Madrid")!, from: try XCTUnwrap(event.dueDate))
        XCTAssertEqual(madridComponents.year, 2026)
        XCTAssertEqual(madridComponents.month, 4)
        XCTAssertEqual(madridComponents.day, 30)
        XCTAssertEqual(madridComponents.hour, 11)
    }

    func testIgnoresEventsWithoutUIDAndInvalidDates() {
        let events = ICSParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            SUMMARY:No UID
            DUE:20260430T120000Z
            END:VEVENT
            BEGIN:VEVENT
            UID:invalid-date
            SUMMARY:Bad date
            DUE:not-a-date
            END:VEVENT
            END:VCALENDAR
            """
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.uid, "invalid-date")
        XCTAssertNil(events.first?.dueDate)
    }

    func testDecodesCommonEscapedTextFields() throws {
        let events = ICSParser.parse(
            """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:escaped
            SUMMARY:Line\\, one\\; two
            LOCATION:Room\\\\A
            END:VEVENT
            END:VCALENDAR
            """
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.summary, "Line, one; two")
        XCTAssertEqual(event.location, "Room\\A")
    }
}

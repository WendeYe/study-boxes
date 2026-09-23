import Foundation

struct ParsedICSEvent: Identifiable {
    var id: String { uid }
    let uid: String
    let summary: String
    let description: String?
    let location: String?
    let startDate: Date?
    let endDate: Date?
    let dueDate: Date?
    let urlString: String?
}

enum ICSParser {
    private struct ICSProperty {
        let name: String
        let parameters: [String: String]
        let value: String
    }

    private struct StoredValue {
        let value: String
        let parameters: [String: String]
    }

    static func parse(_ text: String) -> [ParsedICSEvent] {
        let lines = unfoldedLines(text)
        var events: [ParsedICSEvent] = []
        var current: [String: StoredValue]?

        for line in lines {
            if line == "BEGIN:VEVENT" {
                current = [:]
                continue
            }

            if line == "END:VEVENT" {
                if let current, let event = event(from: current) {
                    events.append(event)
                }
                current = nil
                continue
            }

            guard current != nil else { continue }
            guard let property = property(from: line) else { continue }
            current?[property.name] = StoredValue(value: decode(property.value), parameters: property.parameters)
        }

        return events
    }

    private static func event(from values: [String: StoredValue]) -> ParsedICSEvent? {
        guard let uid = values["UID"]?.value, !uid.isEmpty else { return nil }
        return ParsedICSEvent(
            uid: uid,
            summary: values["SUMMARY"]?.value ?? "Untitled deadline",
            description: values["DESCRIPTION"]?.value,
            location: values["LOCATION"]?.value,
            startDate: parseDate(values["DTSTART"]),
            endDate: parseDate(values["DTEND"]),
            dueDate: parseDate(values["DUE"]),
            urlString: values["URL"]?.value
        )
    }

    private static func property(from line: String) -> ICSProperty? {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let nameAndParameters = parts[0].split(separator: ";", omittingEmptySubsequences: false)
        guard let rawName = nameAndParameters.first else { return nil }

        var parameters: [String: String] = [:]
        for parameter in nameAndParameters.dropFirst() {
            let keyValue = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard keyValue.count == 2 else { continue }
            parameters[String(keyValue[0]).uppercased()] = String(keyValue[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return ICSProperty(
            name: String(rawName).uppercased(),
            parameters: parameters,
            value: String(parts[1])
        )
    }

    private static func unfoldedLines(_ text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func parseDate(_ stored: StoredValue?) -> Date? {
        guard let stored, !stored.value.isEmpty else { return nil }
        let value = stored.value
        let isUTC = value.hasSuffix("Z")
        let dateText = isUTC ? String(value.dropLast()) : value
        let timeZone = isUTC
            ? TimeZone(secondsFromGMT: 0)
            : stored.parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current

        if dateText.count == 8 {
            return date(
                year: component(in: dateText, offset: 0, length: 4),
                month: component(in: dateText, offset: 4, length: 2),
                day: component(in: dateText, offset: 6, length: 2),
                timeZone: timeZone
            )
        }

        guard dateText.count == 15,
              dateText[dateText.index(dateText.startIndex, offsetBy: 8)] == "T" else {
            return nil
        }

        return date(
            year: component(in: dateText, offset: 0, length: 4),
            month: component(in: dateText, offset: 4, length: 2),
            day: component(in: dateText, offset: 6, length: 2),
            hour: component(in: dateText, offset: 9, length: 2),
            minute: component(in: dateText, offset: 11, length: 2),
            second: component(in: dateText, offset: 13, length: 2),
            timeZone: timeZone
        )
    }

    private static func component(in text: String, offset: Int, length: Int) -> Int? {
        let start = text.index(text.startIndex, offsetBy: offset)
        let end = text.index(start, offsetBy: length)
        return Int(text[start..<end])
    }

    private static func date(
        year: Int?,
        month: Int?,
        day: Int?,
        hour: Int? = 0,
        minute: Int? = 0,
        second: Int? = 0,
        timeZone: TimeZone?
    ) -> Date? {
        guard let year,
              let month,
              let day,
              let hour,
              let minute,
              let second else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = calendar.date(from: components) else { return nil }

        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day,
              resolved.hour == hour,
              resolved.minute == minute,
              resolved.second == second else {
            return nil
        }
        return date
    }

    private static func decode(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

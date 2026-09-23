import Foundation
import SwiftUI

enum StudyBoxAccentPalette {
    static let fallbackHex = "#3B82F6"

    static func normalizedAccentHex(_ hex: String?) -> String {
        guard let hex else { return fallbackHex }

        let trimmed = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()

        guard trimmed.count == 6,
              trimmed.allSatisfy({ $0.isHexDigit }) else {
            return fallbackHex
        }

        return "#\(trimmed)"
    }

    static func color(for box: StudyBox?) -> Color {
        Color(hex: normalizedAccentHex(box?.colorHex))
    }
}

enum StudySessionHUDActionRole {
    case studyContext
    case completion
    case restore
    case destructive
}

enum StudySessionHUDPresentation {
    static let completionHex = "#2563EB"
    static let restoreHex = "#2563EB"
    static let destructiveHex = "#EF4444"

    static func tintHex(for role: StudySessionHUDActionRole, boxAccentHex: String?) -> String {
        switch role {
        case .studyContext:
            return StudyBoxAccentPalette.normalizedAccentHex(boxAccentHex)
        case .completion:
            return completionHex
        case .restore:
            return restoreHex
        case .destructive:
            return destructiveHex
        }
    }
}

extension Color {
    init(hex: String) {
        let trimmed = StudyBoxAccentPalette.normalizedAccentHex(hex)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double

        switch trimmed.count {
        case 6:
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
        default:
            red = 0.23
            green = 0.51
            blue = 0.96
        }

        self.init(red: red, green: green, blue: blue)
    }
}

import Foundation

enum DurationFormatter {
    static func clock(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func minutes(_ minutes: Int) -> String {
        if minutes == 1 {
            return "1 min"
        }
        return "\(minutes) min"
    }
}

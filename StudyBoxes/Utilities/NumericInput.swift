import Foundation

enum NumericInput {
    static func sanitizedIntegerText(_ text: String, range: ClosedRange<Int>) -> String {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }

        let value = min(max(Int(digits) ?? range.lowerBound, range.lowerBound), range.upperBound)
        return String(value)
    }

    static func integerValue(from text: String, fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let value = Int(text) else {
            return min(max(fallback, range.lowerBound), range.upperBound)
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

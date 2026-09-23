import Foundation

enum URLValidator {
    static func normalizedURLString(_ input: String) -> String? {
        let sanitized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
        guard !sanitized.isEmpty else { return nil }

        let candidate: String
        if sanitized.contains("://") {
            candidate = sanitized
        } else {
            candidate = "https://\(sanitized)"
        }

        if let components = URLComponents(string: candidate),
           isAllowedWebURL(scheme: components.scheme, host: components.host) {
            return components.url?.absoluteString ?? candidate
        }

        guard let url = URL(string: candidate),
              isAllowedWebURL(scheme: url.scheme, host: url.host) else {
            return nil
        }

        return url.absoluteString
    }

    private static func isAllowedWebURL(scheme: String?, host: String?) -> Bool {
        guard let scheme = scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              host?.isEmpty == false else {
            return false
        }
        return true
    }
}

import Foundation
import Security

enum KeychainService {
    private static let service = "com.studyboxes.secrets"
    private static let cacheLock = NSLock()
    private static var cachedSecrets: [String: String] = [:]
    private static var suppressedPromptKeys: Set<String> = []

    static func save(_ secret: String, for key: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            remember(secret, for: key)
            return
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        addQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
        remember(secret, for: key)
    }

    static func load(for key: String) throws -> String? {
        if let secret = cachedSecret(for: key) {
            return secret
        }

        guard !isPromptSuppressed(for: key) else {
            throw KeychainError.accessDenied
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            let error = KeychainError.unhandledStatus(status)
            if shouldSuppressPrompt(for: error) {
                suppressPrompt(for: key)
            }
            throw error
        }
        let secret = String(data: data, encoding: .utf8)
        if let secret {
            remember(secret, for: key)
        }
        return secret
    }

    static func loadMany(for keys: [String]) throws -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        var secrets: [String: String] = [:]
        for key in keys {
            if let secret = try load(for: key) {
                secrets[key] = secret
            }
        }
        return secrets
    }

    static func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
        forgetSecret(for: key)
    }

    static func shouldSuppressPrompt(for error: Error) -> Bool {
        guard let keychainError = error as? KeychainError else { return false }
        switch keychainError {
        case .accessDenied:
            return true
        case .unhandledStatus(let status):
            return status == errSecUserCanceled
                || status == errSecAuthFailed
                || status == errSecInteractionNotAllowed
                || status == errSecNotAvailable
        }
    }

    private static func cachedSecret(for key: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedSecrets[key]
    }

    private static func remember(_ secret: String, for key: String) {
        cacheLock.lock()
        cachedSecrets[key] = secret
        suppressedPromptKeys.remove(key)
        cacheLock.unlock()
    }

    private static func forgetSecret(for key: String) {
        cacheLock.lock()
        cachedSecrets.removeValue(forKey: key)
        suppressedPromptKeys.remove(key)
        cacheLock.unlock()
    }

    private static func isPromptSuppressed(for key: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return suppressedPromptKeys.contains(key)
    }

    private static func suppressPrompt(for key: String) {
        cacheLock.lock()
        suppressedPromptKeys.insert(key)
        cacheLock.unlock()
    }
}

enum KeychainError: LocalizedError {
    case accessDenied
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Keychain access was not allowed."
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}

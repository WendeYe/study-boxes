import CryptoKit
import Darwin
import Foundation
import os

enum LicenseState: Equatable {
    case unlicensed
    case validating
    case licensed(email: String?, expiresAt: Date?)
    case expired
    case invalid
    case offlineGrace(until: Date)
    case error(message: String)

    var title: String {
        switch self {
        case .unlicensed: "Unlicensed"
        case .validating: "Checking license"
        case .licensed: "Licensed"
        case .expired: "Expired"
        case .invalid: "Invalid license"
        case .offlineGrace: "Offline grace"
        case .error: "License error"
        }
    }

    var detail: String {
        switch self {
        case .unlicensed:
            return "Enter your license key to unlock Pro."
        case .validating:
            return "Checking your license."
        case .licensed(let email, let expiresAt):
            if let expiresAt {
                return "Active until \(expiresAt.formatted(date: .abbreviated, time: .omitted))."
            }
            return email.map { "Activated for \($0)." } ?? "Your Pro license is active."
        case .expired:
            return "This license has expired."
        case .invalid:
            return "That license key was not accepted."
        case .offlineGrace:
            return "Your Pro license is active."
        case .error(let message):
            return message
        }
    }
}

enum EntitlementPlan: Equatable {
    case free
    case pro

    var title: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        }
    }

    var isPro: Bool {
        self == .pro
    }

    static func forLicenseState(_ state: LicenseState) -> EntitlementPlan {
        switch state {
        case .licensed, .offlineGrace:
            .pro
        case .unlicensed, .validating, .expired, .invalid, .error:
            .free
        }
    }
}

struct EntitlementDecision: Equatable {
    var isAllowed: Bool
    var message: String?

    static let allowed = EntitlementDecision(isAllowed: true, message: nil)

    static func blocked(_ message: String) -> EntitlementDecision {
        EntitlementDecision(isAllowed: false, message: message)
    }
}

enum EntitlementFeature {
    case tasks
    case backupExport
    case nonBlankTemplates
    case calendarFeeds
    case backupImport
    case windowLayoutManagement
    case focusModes
    case desktopSpaces
    case advancedStats
}

enum EntitlementRules {
    static let freeStudyBoxLimit = 1
    static let freeResourceLimit = 3

    static func canUse(_ feature: EntitlementFeature, plan: EntitlementPlan) -> EntitlementDecision {
        guard !plan.isPro else { return .allowed }

        switch feature {
        case .tasks, .backupExport:
            return .allowed
        case .nonBlankTemplates:
            return .blocked("Templates are included with Pro. Free includes one blank Study Box.")
        case .calendarFeeds:
            return .blocked("Calendar feeds are included with Pro.")
        case .backupImport:
            return .blocked("Backup import is included with Pro. You can still export your data on Free.")
        case .windowLayoutManagement:
            return .blocked("Window layout capture and restore are included with Pro.")
        case .focusModes:
            return .blocked("Hide Apps, Quit Apps, and Strict Focus are included with Pro.")
        case .desktopSpaces:
            return .blocked("Desktop Spaces setup is included with Pro.")
        case .advancedStats:
            return .blocked("Session history and advanced stats are included with Pro.")
        }
    }

    static func canCreateStudyBox(currentBoxCount: Int, plan: EntitlementPlan) -> EntitlementDecision {
        if plan.isPro || currentBoxCount < freeStudyBoxLimit {
            return .allowed
        }
        return .blocked("Free includes 1 Study Box. Upgrade to Pro to create more.")
    }

    static func canUnarchiveStudyBox(totalBoxCount: Int, plan: EntitlementPlan) -> EntitlementDecision {
        if plan.isPro || totalBoxCount <= freeStudyBoxLimit {
            return .allowed
        }
        return .blocked("Free includes 1 Study Box. Delete a box or upgrade to Pro before restoring archived boxes.")
    }

    static func canStartSession(totalBoxCount: Int, plan: EntitlementPlan) -> EntitlementDecision {
        if plan.isPro || totalBoxCount <= freeStudyBoxLimit {
            return .allowed
        }
        return .blocked("Free includes 1 Study Box. Delete a box or upgrade to Pro before starting sessions.")
    }

    static func canAddResource(currentResourceCount: Int, plan: EntitlementPlan) -> EntitlementDecision {
        canAddResources(currentResourceCount: currentResourceCount, additionalResourceCount: 1, plan: plan)
    }

    static func canAddResources(
        currentResourceCount: Int,
        additionalResourceCount: Int,
        plan: EntitlementPlan
    ) -> EntitlementDecision {
        guard additionalResourceCount > 0 else { return .allowed }
        if plan.isPro || currentResourceCount + additionalResourceCount <= freeResourceLimit {
            return .allowed
        }
        return .blocked("Free Study Boxes can include up to 3 resources. Upgrade to Pro to add more.")
    }

    static func enabledResources(for box: StudyBox, plan: EntitlementPlan) -> [StudyResource] {
        let enabled = box.resources
            .filter(\.enabledByDefault)
            .sorted { $0.orderIndex < $1.orderIndex }

        guard !plan.isPro else { return enabled }
        return Array(enabled.prefix(freeResourceLimit))
    }

    static func sanitizedSessionOptions(_ options: SessionStartOptions, plan: EntitlementPlan) -> SessionStartOptions {
        guard !plan.isPro else { return options }
        return SessionStartOptions(
            plannedMinutes: options.plannedMinutes,
            openResources: options.openResources,
            hideDistractions: false,
            quitDistractions: false,
            enforceFocus: false,
            restoreWindowLayout: false,
            keepDisplayAwake: options.keepDisplayAwake,
            focusMode: .off,
            prepareDesktopSpaces: false
        )
    }
}

struct LicenseActivationResponse: Codable, Equatable {
    let licenseKey: String
    let instanceID: String
    let token: String
    let email: String?
    let expiresAt: Date?
    let validatedAt: Date
}

protocol LicenseAPIClientProtocol {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse
    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse
    func deactivate(instanceID: String, token: String) async throws
}

protocol LicenseKeychainProtocol {
    func save(_ secret: String, for key: String) throws
    func load(for key: String) throws -> String?
    func loadMany(for keys: [String]) throws -> [String: String]
    func delete(for key: String) throws
}

extension LicenseKeychainProtocol {
    func loadMany(for keys: [String]) throws -> [String: String] {
        var secrets: [String: String] = [:]
        for key in keys {
            secrets[key] = try load(for: key)
        }
        return secrets
    }
}

struct LicenseConfiguration: Equatable {
    var productID: Int
    var checkoutURL: URL

    static let production = LicenseConfiguration(
        productID: 1_019_393,
        checkoutURL: URL(string: "https://studyboxes.lemonsqueezy.com/checkout/buy/d0db9d0e-eab3-4322-9905-46e3e38469bc")!
    )
}

struct LicenseMetadata: Equatable {
    var isLicensed: Bool
    var email: String?
    var expiresAt: Date?
    var validatedAt: Date?

    var signingPayload: String {
        [
            isLicensed ? "1" : "0",
            email ?? "",
            Self.timestamp(expiresAt),
            Self.timestamp(validatedAt)
        ].joined(separator: "\u{1F}")
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        return String(Int(date.timeIntervalSince1970.rounded()))
    }
}

enum LicenseMetadataStore {
    private enum Key {
        static let isLicensed = "license.metadata.isLicensed"
        static let email = "license.metadata.email"
        static let expiresAt = "license.metadata.expiresAt"
        static let validatedAt = "license.metadata.validatedAt"
        static let signature = "license.metadata.signature"
    }

    static func load(from userDefaults: UserDefaults) -> LicenseMetadata? {
        guard userDefaults.object(forKey: Key.isLicensed) != nil else {
            return nil
        }

        return LicenseMetadata(
            isLicensed: userDefaults.bool(forKey: Key.isLicensed),
            email: userDefaults.string(forKey: Key.email),
            expiresAt: date(for: Key.expiresAt, in: userDefaults),
            validatedAt: date(for: Key.validatedAt, in: userDefaults)
        )
    }

    static func save(_ metadata: LicenseMetadata, to userDefaults: UserDefaults) {
        userDefaults.set(metadata.isLicensed, forKey: Key.isLicensed)
        setOptional(metadata.email, for: Key.email, in: userDefaults)
        setOptional(metadata.expiresAt?.timeIntervalSince1970, for: Key.expiresAt, in: userDefaults)
        setOptional(metadata.validatedAt?.timeIntervalSince1970, for: Key.validatedAt, in: userDefaults)
    }

    static func signature(in userDefaults: UserDefaults) -> String? {
        userDefaults.string(forKey: Key.signature)
    }

    static func saveSignature(_ signature: String, to userDefaults: UserDefaults) {
        userDefaults.set(signature, forKey: Key.signature)
    }

    static func clear(in userDefaults: UserDefaults) {
        for key in [Key.isLicensed, Key.email, Key.expiresAt, Key.validatedAt, Key.signature] {
            userDefaults.removeObject(forKey: key)
        }
    }

    private static func date(for key: String, in userDefaults: UserDefaults) -> Date? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: userDefaults.double(forKey: key))
    }

    private static func setOptional(_ value: String?, for key: String, in userDefaults: UserDefaults) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private static func setOptional(_ value: TimeInterval?, for key: String, in userDefaults: UserDefaults) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}

struct LicenseSecrets: Codable, Equatable {
    var licenseKey: String
    var instanceID: String
    var token: String
    var metadataSigningKey: String
}

final class LicenseSecretStore {
    static let bundleKey = "license.secrets"

    private enum LegacyKey {
        static let licenseKey = "license.key"
        static let instanceID = "license.instanceID"
        static let token = "license.token"
        static let metadataSigningKey = "license.metadataSigningKey"
    }

    private let keychain: LicenseKeychainProtocol
    private var cachedSecrets: LicenseSecrets?
    private var keychainAccessUnavailable = false

    init(keychain: LicenseKeychainProtocol) {
        self.keychain = keychain
    }

    func credentials() throws -> (instanceID: String, token: String)? {
        guard let secrets = try loadSecrets(),
              !secrets.instanceID.isEmpty,
              !secrets.token.isEmpty else {
            return nil
        }
        return (secrets.instanceID, secrets.token)
    }

    func saveLicenseResponse(_ response: LicenseActivationResponse) throws {
        let signingKey = try signingKeyBase64(createIfNeeded: true)
        let secrets = LicenseSecrets(
            licenseKey: response.licenseKey,
            instanceID: response.instanceID,
            token: response.token,
            metadataSigningKey: signingKey
        )
        try saveBundledSecrets(secrets)
    }

    func signingKeyData(createIfNeeded: Bool) throws -> Data {
        if let encoded = try loadSecrets()?.metadataSigningKey,
           let data = Data(base64Encoded: encoded),
           data.count == 32 {
            return data
        }

        guard createIfNeeded else {
            throw LicenseAPIError.serverMessage("The local license receipt could not be verified.")
        }

        let encoded = try generateSigningKeyBase64()
        let existing = try loadSecrets()
        let secrets = LicenseSecrets(
            licenseKey: existing?.licenseKey ?? "",
            instanceID: existing?.instanceID ?? "",
            token: existing?.token ?? "",
            metadataSigningKey: encoded
        )
        try saveBundledSecrets(secrets)
        guard let data = Data(base64Encoded: encoded) else {
            throw LicenseAPIError.serverMessage("The local license receipt could not be verified.")
        }
        return data
    }

    func clear() {
        cachedSecrets = nil
        keychainAccessUnavailable = false
        for key in [
            Self.bundleKey,
            LegacyKey.licenseKey,
            LegacyKey.instanceID,
            LegacyKey.token,
            LegacyKey.metadataSigningKey
        ] {
            try? keychain.delete(for: key)
        }
    }

    static func decode(_ encoded: String) -> LicenseSecrets? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(LicenseSecrets.self, from: data)
    }

    private func loadSecrets() throws -> LicenseSecrets? {
        if let cachedSecrets {
            return cachedSecrets
        }

        guard !keychainAccessUnavailable else {
            return nil
        }

        do {
            if let bundled = try keychain.load(for: Self.bundleKey),
               let secrets = Self.decode(bundled) {
                cachedSecrets = secrets
                return secrets
            }

            return try migrateLegacySecretsIfAvailable()
        } catch {
            if KeychainService.shouldSuppressPrompt(for: error) {
                keychainAccessUnavailable = true
                return nil
            }
            throw error
        }
    }

    private func migrateLegacySecretsIfAvailable() throws -> LicenseSecrets? {
        let licenseKey = try keychain.load(for: LegacyKey.licenseKey) ?? ""
        guard let instanceID = try keychain.load(for: LegacyKey.instanceID),
              let token = try keychain.load(for: LegacyKey.token) else {
            return nil
        }

        let signingKey = try keychain.load(for: LegacyKey.metadataSigningKey) ?? generateSigningKeyBase64()
        let secrets = LicenseSecrets(
            licenseKey: licenseKey,
            instanceID: instanceID,
            token: token,
            metadataSigningKey: signingKey
        )
        try saveBundledSecrets(secrets)
        return secrets
    }

    private func saveBundledSecrets(_ secrets: LicenseSecrets) throws {
        let data = try JSONEncoder().encode(secrets)
        try keychain.save(data.base64EncodedString(), for: Self.bundleKey)
        cachedSecrets = secrets
        keychainAccessUnavailable = false
        for key in [
            LegacyKey.licenseKey,
            LegacyKey.instanceID,
            LegacyKey.token,
            LegacyKey.metadataSigningKey
        ] {
            try? keychain.delete(for: key)
        }
    }

    private func signingKeyBase64(createIfNeeded: Bool) throws -> String {
        if let encoded = try loadSecrets()?.metadataSigningKey,
           let data = Data(base64Encoded: encoded),
           data.count == 32 {
            return encoded
        }

        guard createIfNeeded else {
            throw LicenseAPIError.serverMessage("The local license receipt could not be verified.")
        }

        return try generateSigningKeyBase64()
    }

    private func generateSigningKeyBase64() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        return Data(bytes).base64EncodedString()
    }
}

struct LicenseMetadataSigner {
    private let secretStore: LicenseSecretStore

    init(secretStore: LicenseSecretStore) {
        self.secretStore = secretStore
    }

    func signature(for metadata: LicenseMetadata) throws -> String {
        let keyData = try secretStore.signingKeyData(createIfNeeded: true)
        let key = SymmetricKey(data: keyData)
        let code = HMAC<SHA256>.authenticationCode(
            for: Data(metadata.signingPayload.utf8),
            using: key
        )
        return Data(code).base64EncodedString()
    }

    func isValidSignature(_ signature: String, for metadata: LicenseMetadata) -> Bool {
        guard let signatureData = Data(base64Encoded: signature),
              let keyData = try? secretStore.signingKeyData(createIfNeeded: false) else {
            return false
        }
        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: Data(metadata.signingPayload.utf8),
            using: SymmetricKey(data: keyData)
        )
    }
}

struct SystemLicenseKeychain: LicenseKeychainProtocol {
    func save(_ secret: String, for key: String) throws {
        try KeychainService.save(secret, for: key)
    }

    func load(for key: String) throws -> String? {
        try KeychainService.load(for: key)
    }

    func loadMany(for keys: [String]) throws -> [String: String] {
        try KeychainService.loadMany(for: keys)
    }

    func delete(for key: String) throws {
        try KeychainService.delete(for: key)
    }
}

enum LicenseNetworkTrustError: LocalizedError, Equatable {
    case blockedHost(host: String, address: String)

    var errorDescription: String? {
        switch self {
        case .blockedHost:
            "Study Boxes could not reach the licensing service because local network settings appear to be blocking it."
        }
    }
}

protocol LicenseHostTrustChecking {
    func resolvedAddresses(for host: String) throws -> [String]
}

extension LicenseHostTrustChecking {
    func validate(host: String) throws {
        for address in try resolvedAddresses(for: host) where LicenseHostAddressPolicy.isBlocked(address) {
            throw LicenseNetworkTrustError.blockedHost(host: host, address: address)
        }
    }
}

struct SystemLicenseHostTrustChecker: LicenseHostTrustChecking {
    func resolvedAddresses(for host: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            throw LicenseAPIError.serverMessage(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var pointer = result
        while let current = pointer {
            if let address = Self.stringAddress(from: current.pointee.ai_addr) {
                addresses.append(address)
            }
            pointer = current.pointee.ai_next
        }
        return addresses
    }

    private static func stringAddress(from socketAddress: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let socketAddress else { return nil }

        switch Int32(socketAddress.pointee.sa_family) {
        case AF_INET:
            var address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        case AF_INET6:
            var address = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_addr
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        default:
            return nil
        }
    }
}

enum LicenseHostAddressPolicy {
    static func isBlocked(_ address: String) -> Bool {
        isBlockedIPv4(address) || isBlockedIPv6(address)
    }

    private static func isBlockedIPv4(_ address: String) -> Bool {
        var parsed = in_addr()
        guard inet_pton(AF_INET, address, &parsed) == 1 else { return false }
        let value = UInt32(bigEndian: parsed.s_addr)
        let first = UInt8((value >> 24) & 0xff)
        let second = UInt8((value >> 16) & 0xff)

        return first == 0 ||
            first == 10 ||
            first == 127 ||
            (first == 100 && (second >= 64 && second <= 127)) ||
            (first == 169 && second == 254) ||
            (first == 172 && (second >= 16 && second <= 31)) ||
            (first == 192 && second == 168)
    }

    private static func isBlockedIPv6(_ address: String) -> Bool {
        var parsed = in6_addr()
        guard inet_pton(AF_INET6, address, &parsed) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &parsed) { Array($0) }
        let isLoopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes.last == 1
        let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc
        let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        return isLoopback || isUniqueLocal || isLinkLocal
    }
}

struct LemonSqueezyLicenseAPIClient: LicenseAPIClientProtocol {
    typealias RequestPerformer = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let configuration: LicenseConfiguration
    private let hostTrustChecker: LicenseHostTrustChecking
    private let performRequest: RequestPerformer
    private let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    init(
        configuration: LicenseConfiguration = .production,
        hostTrustChecker: LicenseHostTrustChecking = SystemLicenseHostTrustChecker(),
        performRequest: @escaping RequestPerformer = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LicenseAPIError.serverMessage("The licensing service returned an invalid response.")
            }
            return (data, httpResponse)
        }
    ) {
        self.configuration = configuration
        self.hostTrustChecker = hostTrustChecker
        self.performRequest = performRequest
    }

    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        let response: LemonSqueezyLicenseResponse = try await post(
            path: "activate",
            fields: [
                ("license_key", licenseKey),
                ("instance_name", "Study Boxes")
            ]
        )

        guard response.activated == true, response.isUsableLicense(for: configuration.productID) else {
            throw LicenseAPIError.invalidLicense
        }

        return try response.activationResponse(fallbackLicenseKey: licenseKey)
    }

    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse {
        let response: LemonSqueezyLicenseResponse = try await post(
            path: "validate",
            fields: [
                ("license_key", token),
                ("instance_id", instanceID)
            ]
        )

        guard response.valid == true, response.isUsableLicense(for: configuration.productID) else {
            throw LicenseAPIError.invalidLicense
        }

        return try response.activationResponse(fallbackLicenseKey: token, fallbackInstanceID: instanceID)
    }

    func deactivate(instanceID: String, token: String) async throws {
        let response: LemonSqueezyLicenseResponse = try await post(
            path: "deactivate",
            fields: [
                ("license_key", token),
                ("instance_id", instanceID)
            ]
        )

        guard response.deactivated == true, response.error == nil else {
            throw LicenseAPIError.serverMessage(response.error ?? "The license could not be deactivated.")
        }
    }

    private func post<Response: Decodable>(path: String, fields: [(String, String)]) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)

        if let host = request.url?.host {
            try hostTrustChecker.validate(host: host)
        }

        let (data, response) = try await performRequest(request)
        guard (200..<300).contains(response.statusCode) else {
            if let error = try? JSONDecoder().decode(LemonSqueezyErrorResponse.self, from: data).error {
                throw LicenseAPIError.serverMessage(error)
            }
            throw LicenseAPIError.serverMessage("The licensing service returned HTTP \(response.statusCode).")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LicenseAPIError.serverMessage("The licensing service returned an unreadable response.")
        }
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        let body = fields
            .map { key, value in
                "\(escapeFormValue(key))=\(escapeFormValue(value))"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escapeFormValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct LemonSqueezyLicenseResponse: Decodable {
    var activated: Bool?
    var valid: Bool?
    var deactivated: Bool?
    var error: String?
    var licenseKey: LemonSqueezyLicenseKey?
    var instance: LemonSqueezyInstance?
    var meta: LemonSqueezyMeta?

    enum CodingKeys: String, CodingKey {
        case activated
        case valid
        case deactivated
        case error
        case licenseKey = "license_key"
        case instance
        case meta
    }

    func isUsableLicense(for productID: Int) -> Bool {
        error == nil &&
            licenseKey?.status == "active" &&
            meta?.productID == productID
    }

    func activationResponse(
        fallbackLicenseKey: String,
        fallbackInstanceID: String? = nil
    ) throws -> LicenseActivationResponse {
        guard let instanceID = instance?.id ?? fallbackInstanceID else {
            throw LicenseAPIError.serverMessage("The licensing service did not return an activation instance.")
        }
        guard let licenseKey else {
            throw LicenseAPIError.invalidLicense
        }

        return LicenseActivationResponse(
            licenseKey: licenseKey.key ?? fallbackLicenseKey,
            instanceID: instanceID,
            token: licenseKey.key ?? fallbackLicenseKey,
            email: meta?.customerEmail,
            expiresAt: licenseKey.expiresAt,
            validatedAt: .now
        )
    }
}

private struct LemonSqueezyLicenseKey: Decodable {
    var status: String
    var key: String?
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case key
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        expiresAt = expiresAtString.flatMap(Self.parseDate)
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }
}

private struct LemonSqueezyInstance: Decodable {
    var id: String
}

private struct LemonSqueezyMeta: Decodable {
    var productID: Int?
    var customerEmail: String?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case customerEmail = "customer_email"
    }
}

private struct LemonSqueezyErrorResponse: Decodable {
    var error: String
}

struct PlaceholderLicenseAPIClient: LicenseAPIClientProtocol {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard licenseKey.uppercased().hasPrefix("SB-") else {
            throw LicenseAPIError.invalidLicense
        }
        return LicenseActivationResponse(
            licenseKey: licenseKey,
            instanceID: UUID().uuidString,
            token: UUID().uuidString,
            email: nil,
            expiresAt: nil,
            validatedAt: .now
        )
    }

    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse {
        try await Task.sleep(nanoseconds: 250_000_000)
        return LicenseActivationResponse(
            licenseKey: "",
            instanceID: instanceID,
            token: token,
            email: nil,
            expiresAt: nil,
            validatedAt: .now
        )
    }

    func deactivate(instanceID: String, token: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}

enum LicenseAPIError: LocalizedError {
    case invalidLicense
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidLicense: "That license key was not accepted."
        case .serverMessage(let message): message
        }
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    private let logger = Logger(subsystem: "StudyBoxes", category: "License")
    private let apiClient: LicenseAPIClientProtocol
    private let userDefaults: UserDefaults
    private let clock: () -> Date
    private let secretStore: LicenseSecretStore
    private let metadataSigner: LicenseMetadataSigner
    private let offlineGraceDays = 14

    private var lastResolvedPlan: EntitlementPlan = .free

    @Published private(set) var state: LicenseState = .unlicensed {
        didSet {
            if state != .validating {
                lastResolvedPlan = EntitlementPlan.forLicenseState(state)
            }
        }
    }

    var plan: EntitlementPlan {
        state == .validating ? lastResolvedPlan : EntitlementPlan.forLicenseState(state)
    }

    init(
        apiClient: LicenseAPIClientProtocol = LemonSqueezyLicenseAPIClient(),
        keychain: LicenseKeychainProtocol = SystemLicenseKeychain(),
        userDefaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init
    ) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.clock = clock
        let secretStore = LicenseSecretStore(keychain: keychain)
        self.secretStore = secretStore
        self.metadataSigner = LicenseMetadataSigner(secretStore: secretStore)
        loadStoredState()
        lastResolvedPlan = EntitlementPlan.forLicenseState(state)
    }

    func activate(licenseKey: String) async {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .error(message: "Enter a license key.")
            return
        }

        state = .validating
        do {
            let response = try await apiClient.activate(licenseKey: trimmed)
            try store(response)
            state = .licensed(email: response.email, expiresAt: response.expiresAt)
        } catch LicenseAPIError.invalidLicense {
            state = .invalid
        } catch {
            applyOfflineGraceOrError(error)
        }
    }

    func validateStoredLicense() async {
        guard let credentials = try? secretStore.credentials() else {
            state = .unlicensed
            return
        }

        state = .validating
        do {
            let response = try await apiClient.validate(instanceID: credentials.instanceID, token: credentials.token)
            try store(response)
            state = .licensed(email: response.email, expiresAt: response.expiresAt)
        } catch {
            applyOfflineGraceOrError(error)
        }
    }

    func deactivate() async {
        let credentials = try? secretStore.credentials()
        state = .validating

        if let credentials {
            do {
                try await apiClient.deactivate(instanceID: credentials.instanceID, token: credentials.token)
            } catch {
                logger.warning("License deactivate request failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        clearStoredLicense()
        state = .unlicensed
    }

    private func loadStoredState() {
        guard let metadata = passiveStoredMetadata() else {
            state = .unlicensed
            return
        }

        if let expiresAt = metadata.expiresAt, expiresAt < clock() {
            state = .expired
        } else {
            state = .licensed(email: metadata.email, expiresAt: metadata.expiresAt)
        }
    }

    private func passiveStoredMetadata() -> LicenseMetadata? {
        guard let metadata = LicenseMetadataStore.load(from: userDefaults), metadata.isLicensed else {
            return nil
        }
        guard LicenseMetadataStore.signature(in: userDefaults) != nil else {
            return nil
        }
        return metadata
    }

    private func store(_ response: LicenseActivationResponse) throws {
        try secretStore.saveLicenseResponse(response)
        let metadata = licenseMetadata(from: response)
        LicenseMetadataStore.save(
            metadata,
            to: userDefaults
        )
        let signature = try metadataSigner.signature(for: metadata)
        LicenseMetadataStore.saveSignature(signature, to: userDefaults)
    }

    private func trustedStoredMetadata() -> LicenseMetadata? {
        guard let metadata = LicenseMetadataStore.load(from: userDefaults), metadata.isLicensed else {
            return nil
        }

        if let signature = LicenseMetadataStore.signature(in: userDefaults) {
            guard metadataSigner.isValidSignature(signature, for: metadata) else {
                logger.warning("Stored license metadata signature is invalid.")
                return nil
            }
            return metadata
        }

        guard hasStoredLicenseSecrets() else {
            logger.warning("Unsigned license metadata was ignored because license secrets are missing.")
            return nil
        }

        if let signature = try? metadataSigner.signature(for: metadata) {
            LicenseMetadataStore.saveSignature(signature, to: userDefaults)
        }
        return metadata
    }

    private func licenseMetadata(from response: LicenseActivationResponse) -> LicenseMetadata {
        LicenseMetadata(
                isLicensed: true,
                email: response.email,
                expiresAt: response.expiresAt,
                validatedAt: response.validatedAt
        )
    }

    private func applyOfflineGraceOrError(_ error: Error) {
        if error is LicenseNetworkTrustError {
            state = .error(message: error.localizedDescription)
            return
        }

        if let lastValidated = trustedStoredMetadata()?.validatedAt,
           let graceUntil = Calendar.current.date(byAdding: .day, value: offlineGraceDays, to: lastValidated),
           graceUntil > clock() {
            state = .offlineGrace(until: graceUntil)
        } else {
            state = .error(message: error.localizedDescription)
        }
    }

    private func hasStoredLicenseSecrets() -> Bool {
        (try? secretStore.credentials()) != nil
    }

    private func clearStoredLicense() {
        secretStore.clear()
        LicenseMetadataStore.clear(in: userDefaults)
    }
}

import XCTest
@testable import StudyBoxes

@MainActor
final class LicenseManagerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var testDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        testDefaultsSuiteName = "StudyBoxesTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        testDefaults = nil
        testDefaultsSuiteName = nil
        super.tearDown()
    }

    func testEntitlementPlansMapLicenseStates() {
        XCTAssertEqual(EntitlementPlan.forLicenseState(.unlicensed), .free)
        XCTAssertEqual(EntitlementPlan.forLicenseState(.expired), .free)
        XCTAssertEqual(EntitlementPlan.forLicenseState(.invalid), .free)
        XCTAssertEqual(EntitlementPlan.forLicenseState(.error(message: "No network")), .free)
        XCTAssertEqual(EntitlementPlan.forLicenseState(.licensed(email: nil, expiresAt: nil)), .pro)
        XCTAssertEqual(EntitlementPlan.forLicenseState(.offlineGrace(until: Date(timeIntervalSince1970: 1000))), .pro)
    }

    func testFreePlanAllowsOnlyOneTotalStudyBoxIncludingArchived() {
        XCTAssertTrue(EntitlementRules.canCreateStudyBox(currentBoxCount: 0, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canCreateStudyBox(currentBoxCount: 1, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canCreateStudyBox(currentBoxCount: 2, plan: .free).isAllowed)
        XCTAssertTrue(EntitlementRules.canCreateStudyBox(currentBoxCount: 10, plan: .pro).isAllowed)

        XCTAssertTrue(EntitlementRules.canStartSession(totalBoxCount: 1, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canStartSession(totalBoxCount: 2, plan: .free).isAllowed)
        XCTAssertTrue(EntitlementRules.canUnarchiveStudyBox(totalBoxCount: 1, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUnarchiveStudyBox(totalBoxCount: 2, plan: .free).isAllowed)
    }

    func testFreePlanBlocksProFeaturesButAllowsExportAndTasks() {
        XCTAssertTrue(EntitlementRules.canUse(.tasks, plan: .free).isAllowed)
        XCTAssertTrue(EntitlementRules.canUse(.backupExport, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUse(.nonBlankTemplates, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUse(.calendarFeeds, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUse(.backupImport, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUse(.windowLayoutManagement, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUse(.focusModes, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canUse(.desktopSpaces, plan: .free).isAllowed)
        XCTAssertTrue(EntitlementRules.canUse(.focusModes, plan: .pro).isAllowed)
        XCTAssertTrue(EntitlementRules.canUse(.desktopSpaces, plan: .pro).isAllowed)
    }

    func testFreePlanLimitsResourcesToThree() {
        XCTAssertTrue(EntitlementRules.canAddResource(currentResourceCount: 2, plan: .free).isAllowed)
        XCTAssertFalse(EntitlementRules.canAddResource(currentResourceCount: 3, plan: .free).isAllowed)
        XCTAssertTrue(EntitlementRules.canAddResource(currentResourceCount: 20, plan: .pro).isAllowed)
        XCTAssertTrue(EntitlementRules.canAddResource(currentResourceCount: 1_000, plan: .pro).isAllowed)
    }

    func testProPlanAllowsUnlimitedBatchResources() {
        XCTAssertTrue(
            EntitlementRules.canAddResources(
                currentResourceCount: 0,
                additionalResourceCount: 100,
                plan: .pro
            ).isAllowed
        )
        XCTAssertTrue(
            EntitlementRules.canAddResources(
                currentResourceCount: 1_000,
                additionalResourceCount: 250,
                plan: .pro
            ).isAllowed
        )
        XCTAssertFalse(
            EntitlementRules.canAddResources(
                currentResourceCount: 1,
                additionalResourceCount: 3,
                plan: .free
            ).isAllowed
        )
    }

    func testFreePlanUsesOnlyFirstThreeEnabledResources() {
        let box = StudyBox(name: "Physics")
        box.resources = (0..<5).map { index in
            StudyResource(
                box: box,
                title: "Resource \(index)",
                type: .website,
                urlString: "https://example.com/\(index)",
                orderIndex: index,
                enabledByDefault: index != 1
            )
        }

        XCTAssertEqual(
            EntitlementRules.enabledResources(for: box, plan: .free).map(\.title),
            ["Resource 0", "Resource 2", "Resource 3"]
        )
        XCTAssertEqual(
            EntitlementRules.enabledResources(for: box, plan: .pro).map(\.title),
            ["Resource 0", "Resource 2", "Resource 3", "Resource 4"]
        )
    }

    func testFreePlanSanitizesSessionOptions() {
        let options = SessionStartOptions(
            plannedMinutes: 50,
            openResources: true,
            hideDistractions: true,
            quitDistractions: true,
            enforceFocus: true,
            restoreWindowLayout: true,
            keepDisplayAwake: true,
            focusMode: .strictFocus,
            prepareDesktopSpaces: true
        )

        let free = EntitlementRules.sanitizedSessionOptions(options, plan: .free)
        XCTAssertTrue(free.openResources)
        XCTAssertFalse(free.hideDistractions)
        XCTAssertFalse(free.quitDistractions)
        XCTAssertFalse(free.enforceFocus)
        XCTAssertFalse(free.restoreWindowLayout)
        XCTAssertFalse(free.prepareDesktopSpaces)
        XCTAssertEqual(free.focusMode, .off)

        XCTAssertEqual(EntitlementRules.sanitizedSessionOptions(options, plan: .pro).resolvedFocusMode, .strictFocus)
        XCTAssertTrue(EntitlementRules.sanitizedSessionOptions(options, plan: .pro).prepareDesktopSpaces)
    }

    func testEmptyLicenseKeyShowsInputError() async {
        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: MemoryLicenseKeychain(),
            userDefaults: testDefaults
        )

        await manager.activate(licenseKey: "   ")

        XCTAssertEqual(manager.state, .error(message: "Enter a license key."))
    }

    func testActivateStoresLicensedState() async {
        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: MemoryLicenseKeychain(),
            userDefaults: testDefaults
        )

        await manager.activate(licenseKey: "SB-TEST")

        XCTAssertEqual(manager.state, .licensed(email: "student@example.com", expiresAt: nil))
    }

    func testInvalidLicenseMovesToInvalidState() async {
        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: MemoryLicenseKeychain(),
            userDefaults: testDefaults
        )

        await manager.activate(licenseKey: "BAD")

        XCTAssertEqual(manager.state, .invalid)
    }

    func testDeactivateClearsLicenseState() async {
        let keychain = MemoryLicenseKeychain()
        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        await manager.activate(licenseKey: "SB-TEST")
        await manager.deactivate()

        XCTAssertEqual(manager.state, .unlicensed)
    }

    func testValidateWithoutStoredLicenseReturnsUnlicensed() async {
        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: MemoryLicenseKeychain(),
            userDefaults: testDefaults
        )

        await manager.validateStoredLicense()

        XCTAssertEqual(manager.state, .unlicensed)
    }

    func testStoredExpiredLicenseLoadsExpiredState() async {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: ExpiringLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )
        await activatingManager.activate(licenseKey: "SB-TEST")
        keychain.resetCounts()

        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults,
            clock: { Date(timeIntervalSince1970: 200) }
        )

        XCTAssertEqual(manager.state, .expired)
    }

    func testUnsignedStoredMetadataWithoutKeychainTokensIsRejected() {
        LicenseMetadataStore.save(
            LicenseMetadata(
                isLicensed: true,
                email: "attacker@example.com",
                expiresAt: nil,
                validatedAt: Date(timeIntervalSince1970: 100)
            ),
            to: testDefaults
        )

        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: MemoryLicenseKeychain(),
            userDefaults: testDefaults
        )

        XCTAssertEqual(manager.state, .unlicensed)
    }

    func testPassiveStartupDoesNotTouchKeychainForSignedMetadata() async {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )
        await activatingManager.activate(licenseKey: "SB-TEST")
        keychain.resetCounts()

        let reloadedManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        XCTAssertEqual(reloadedManager.state, .licensed(email: "student@example.com", expiresAt: nil))
        XCTAssertEqual(keychain.loadCount, 0)
    }

    func testValidationFailureUsesOfflineGraceWhenLastValidationIsRecent() async {
        let keychain = MemoryLicenseKeychain()
        try? keychain.save("instance", for: "license.instanceID")
        try? keychain.save("token", for: "license.token")
        LicenseMetadataStore.save(
            LicenseMetadata(
                isLicensed: true,
                email: nil,
                expiresAt: nil,
                validatedAt: Date(timeIntervalSince1970: 1000)
            ),
            to: testDefaults
        )

        let manager = LicenseManager(
            apiClient: ThrowingLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults,
            clock: { Date(timeIntervalSince1970: 1_100) }
        )

        await manager.validateStoredLicense()

        guard case .offlineGrace(let until) = manager.state else {
            return XCTFail("Expected offline grace, got \(manager.state)")
        }
        XCTAssertTrue(until > Date(timeIntervalSince1970: 1_100))
    }

    func testValidationFailureWithoutGraceShowsError() async {
        let keychain = MemoryLicenseKeychain()
        try? keychain.save("instance", for: "license.instanceID")
        try? keychain.save("token", for: "license.token")
        LicenseMetadataStore.save(
            LicenseMetadata(
                isLicensed: true,
                email: nil,
                expiresAt: nil,
                validatedAt: Date(timeIntervalSince1970: 1000)
            ),
            to: testDefaults
        )

        let manager = LicenseManager(
            apiClient: ThrowingLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults,
            clock: { Date(timeIntervalSince1970: 1_000 + 15 * 86_400) }
        )

        await manager.validateStoredLicense()

        XCTAssertEqual(manager.state, .error(message: "Network unavailable"))
    }

    func testOfflineGraceStillAppliesAfterEightDays() async {
        let keychain = MemoryLicenseKeychain()
        try? keychain.save("instance", for: "license.instanceID")
        try? keychain.save("token", for: "license.token")
        LicenseMetadataStore.save(
            LicenseMetadata(
                isLicensed: true,
                email: nil,
                expiresAt: nil,
                validatedAt: Date(timeIntervalSince1970: 1_000)
            ),
            to: testDefaults
        )

        let manager = LicenseManager(
            apiClient: ThrowingLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults,
            clock: { Date(timeIntervalSince1970: 1_000 + 8 * 86_400) }
        )

        await manager.validateStoredLicense()

        guard case .offlineGrace(let until) = manager.state else {
            return XCTFail("Expected offline grace, got \(manager.state)")
        }
        XCTAssertTrue(until > Date(timeIntervalSince1970: 1_000 + 8 * 86_400))
    }

    func testStoredLicenseMetadataLoadsWhenSignedAndKeychainTokensExist() async {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )
        await activatingManager.activate(licenseKey: "SB-TEST")
        keychain.resetCounts()

        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        XCTAssertEqual(manager.state, .licensed(email: "student@example.com", expiresAt: nil))
        XCTAssertEqual(keychain.loadCount, 0)
    }

    func testActivationStoresLicenseSecretsAsSingleBundledKeychainItem() async {
        let keychain = MemoryLicenseKeychain()
        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        await manager.activate(licenseKey: "SB-TEST")

        XCTAssertEqual(manager.state, .licensed(email: "student@example.com", expiresAt: nil))
        XCTAssertTrue(keychain.contains(key: LicenseSecretStore.bundleKey))
        XCTAssertFalse(keychain.contains(key: "license.key"))
        XCTAssertFalse(keychain.contains(key: "license.instanceID"))
        XCTAssertFalse(keychain.contains(key: "license.token"))
        XCTAssertFalse(keychain.contains(key: "license.metadataSigningKey"))
    }

    func testBundledLicenseSecretsAreLoadedFromOneKeychainRecord() async throws {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )
        await activatingManager.activate(licenseKey: "SB-TEST")
        keychain.resetCounts()

        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        XCTAssertEqual(manager.state, .licensed(email: "student@example.com", expiresAt: nil))
        XCTAssertEqual(keychain.loadCounts[LicenseSecretStore.bundleKey], nil)
        XCTAssertNil(keychain.loadCounts["license.instanceID"])
        XCTAssertNil(keychain.loadCounts["license.token"])
        XCTAssertNil(keychain.loadCounts["license.metadataSigningKey"])
    }

    func testDeniedBundledLicenseReadIsNotRetriedDuringSameRun() throws {
        let keychain = DenyingLicenseKeychain(status: errSecUserCanceled)
        let store = LicenseSecretStore(keychain: keychain)

        XCTAssertNil(try? store.credentials())
        XCTAssertNil(try? store.credentials())

        XCTAssertEqual(keychain.loadCounts[LicenseSecretStore.bundleKey], 1)
        XCTAssertNil(keychain.loadCounts["license.instanceID"])
        XCTAssertNil(keychain.loadCounts["license.token"])
        XCTAssertNil(keychain.loadCounts["license.metadataSigningKey"])
    }

    func testLegacyLicenseSecretsMigrateToBundledKeychainItem() async throws {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )
        await activatingManager.activate(licenseKey: "SB-TEST")

        let bundled = try XCTUnwrap(keychain.load(for: LicenseSecretStore.bundleKey))
        try keychain.save("SB-TEST", for: "license.key")
        try keychain.save("instance", for: "license.instanceID")
        try keychain.save("token", for: "license.token")
        let decoded = try XCTUnwrap(LicenseSecretStore.decode(bundled))
        try keychain.save(decoded.metadataSigningKey, for: "license.metadataSigningKey")
        try keychain.delete(for: LicenseSecretStore.bundleKey)
        keychain.resetCounts()

        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        await manager.validateStoredLicense()

        XCTAssertEqual(manager.state, .licensed(email: "student@example.com", expiresAt: nil))
        XCTAssertTrue(keychain.contains(key: LicenseSecretStore.bundleKey))
        XCTAssertFalse(keychain.contains(key: "license.key"))
        XCTAssertFalse(keychain.contains(key: "license.instanceID"))
        XCTAssertFalse(keychain.contains(key: "license.token"))
        XCTAssertFalse(keychain.contains(key: "license.metadataSigningKey"))
    }

    func testLegacyLicenseSecretsDoNotUseBulkKeychainLoadOnStartup() async throws {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )
        await activatingManager.activate(licenseKey: "SB-TEST")

        let bundled = try XCTUnwrap(keychain.load(for: LicenseSecretStore.bundleKey))
        try keychain.save("SB-TEST", for: "license.key")
        try keychain.save("instance", for: "license.instanceID")
        try keychain.save("token", for: "license.token")
        let decoded = try XCTUnwrap(LicenseSecretStore.decode(bundled))
        try keychain.save(decoded.metadataSigningKey, for: "license.metadataSigningKey")
        try keychain.delete(for: LicenseSecretStore.bundleKey)
        keychain.resetCounts()

        let manager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults
        )

        await manager.validateStoredLicense()

        XCTAssertEqual(manager.state, .licensed(email: "student@example.com", expiresAt: nil))
        XCTAssertEqual(keychain.loadManyCallCount, 0)
    }

    func testLemonSqueezyActivateEncodesFormAndMapsResponse() async throws {
        var capturedRequest: URLRequest?
        let client = LemonSqueezyLicenseAPIClient(
            configuration: LicenseConfiguration(productID: 1019393, checkoutURL: URL(string: "https://example.com/buy")!),
            hostTrustChecker: StaticLicenseHostTrustChecker(resolvedAddresses: ["8.8.8.8"]),
            performRequest: { request in
                capturedRequest = request
                return (
                    Data(Self.lemonActivateResponse(productID: 1019393).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let response = try await client.activate(licenseKey: "LS-123")

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/activate")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(data: try XCTUnwrap(capturedRequest?.httpBody), encoding: .utf8)
        XCTAssertEqual(body, "license_key=LS-123&instance_name=Study%20Boxes")
        XCTAssertEqual(response.licenseKey, "LS-123")
        XCTAssertEqual(response.instanceID, "instance-1")
        XCTAssertEqual(response.token, "LS-123")
        XCTAssertEqual(response.email, "student@example.com")
        XCTAssertNil(response.expiresAt)
    }

    func testLemonSqueezyValidateUsesStoredLicenseKeyAndInstanceID() async throws {
        var capturedBody: String?
        let client = LemonSqueezyLicenseAPIClient(
            configuration: LicenseConfiguration(productID: 1019393, checkoutURL: URL(string: "https://example.com/buy")!),
            hostTrustChecker: StaticLicenseHostTrustChecker(resolvedAddresses: ["8.8.8.8"]),
            performRequest: { request in
                capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
                return (
                    Data(Self.lemonValidateResponse(productID: 1019393).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let response = try await client.validate(instanceID: "instance-1", token: "LS-123")

        XCTAssertEqual(capturedBody, "license_key=LS-123&instance_id=instance-1")
        XCTAssertEqual(response.instanceID, "instance-1")
        XCTAssertEqual(response.token, "LS-123")
        XCTAssertEqual(response.email, "student@example.com")
    }

    func testLemonSqueezyRejectsWrongProduct() async throws {
        let client = LemonSqueezyLicenseAPIClient(
            configuration: LicenseConfiguration(productID: 1019393, checkoutURL: URL(string: "https://example.com/buy")!),
            hostTrustChecker: StaticLicenseHostTrustChecker(resolvedAddresses: ["8.8.8.8"]),
            performRequest: { request in
                (
                    Data(Self.lemonActivateResponse(productID: 42).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        do {
            _ = try await client.activate(licenseKey: "LS-123")
            XCTFail("Expected wrong product to be rejected")
        } catch LicenseAPIError.invalidLicense {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected invalidLicense, got \(error)")
        }
    }

    func testLemonSqueezyRejectsInactiveExpiredAndDisabledStatuses() async throws {
        for status in ["inactive", "expired", "disabled"] {
            let client = LemonSqueezyLicenseAPIClient(
                configuration: LicenseConfiguration(productID: 1019393, checkoutURL: URL(string: "https://example.com/buy")!),
                hostTrustChecker: StaticLicenseHostTrustChecker(resolvedAddresses: ["8.8.8.8"]),
                performRequest: { request in
                    (
                        Data(Self.lemonActivateResponse(productID: 1019393, status: status).utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    )
                }
            )

            do {
                _ = try await client.activate(licenseKey: "LS-123")
                XCTFail("Expected \(status) to be rejected")
            } catch LicenseAPIError.invalidLicense {
                XCTAssertTrue(true)
            } catch {
                XCTFail("Expected invalidLicense for \(status), got \(error)")
            }
        }
    }

    func testLemonSqueezyRejectsLoopbackLicenseHostBeforeRequest() async throws {
        let client = LemonSqueezyLicenseAPIClient(
            configuration: LicenseConfiguration(productID: 1019393, checkoutURL: URL(string: "https://example.com/buy")!),
            hostTrustChecker: StaticLicenseHostTrustChecker(resolvedAddresses: ["127.0.0.1"]),
            performRequest: { request in
                XCTFail("Request should not be sent when the license host resolves to \(request.url?.host ?? "unknown").")
                return (
                    Data(Self.lemonValidateResponse(productID: 1019393).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        do {
            _ = try await client.validate(instanceID: "instance-1", token: "LS-123")
            XCTFail("Expected suspicious host resolution to be rejected")
        } catch LicenseNetworkTrustError.blockedHost(let host, let address) {
            XCTAssertEqual(host, "api.lemonsqueezy.com")
            XCTAssertEqual(address, "127.0.0.1")
        } catch {
            XCTFail("Expected blockedHost, got \(error)")
        }
    }

    func testSuspiciousNetworkFailureDoesNotUseOfflineGrace() async {
        let keychain = MemoryLicenseKeychain()
        let activatingManager = LicenseManager(
            apiClient: FakeLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults,
            clock: { Date(timeIntervalSince1970: 1_000) }
        )
        await activatingManager.activate(licenseKey: "SB-TEST")

        let manager = LicenseManager(
            apiClient: SuspiciousLicenseAPIClient(),
            keychain: keychain,
            userDefaults: testDefaults,
            clock: { Date(timeIntervalSince1970: 1_100) }
        )

        await manager.validateStoredLicense()

        XCTAssertEqual(
            manager.state,
            .error(message: "Study Boxes could not reach the licensing service because local network settings appear to be blocking it.")
        )
    }
}

private extension LicenseManagerTests {
    static func lemonActivateResponse(productID: Int, status: String = "active") -> String {
        """
        {
          "activated": true,
          "error": null,
          "license_key": {
            "id": 1,
            "status": "\(status)",
            "key": "LS-123",
            "activation_limit": 3,
            "activation_usage": 1,
            "created_at": "2026-05-01T12:00:00.000000Z",
            "expires_at": null
          },
          "instance": {
            "id": "instance-1",
            "name": "Study Boxes",
            "created_at": "2026-05-01T12:00:00.000000Z"
          },
          "meta": {
            "product_id": \(productID),
            "product_name": "Study Boxes Pro",
            "customer_email": "student@example.com"
          }
        }
        """
    }

    static func lemonValidateResponse(productID: Int, status: String = "active") -> String {
        """
        {
          "valid": true,
          "error": null,
          "license_key": {
            "id": 1,
            "status": "\(status)",
            "key": "LS-123",
            "activation_limit": 3,
            "activation_usage": 1,
            "created_at": "2026-05-01T12:00:00.000000Z",
            "expires_at": null
          },
          "instance": {
            "id": "instance-1",
            "name": "Study Boxes",
            "created_at": "2026-05-01T12:00:00.000000Z"
          },
          "meta": {
            "product_id": \(productID),
            "product_name": "Study Boxes Pro",
            "customer_email": "student@example.com"
          }
        }
        """
    }
}

private struct FakeLicenseAPIClient: LicenseAPIClientProtocol {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        guard licenseKey.hasPrefix("SB-") else {
            throw LicenseAPIError.invalidLicense
        }
        return LicenseActivationResponse(
            licenseKey: licenseKey,
            instanceID: "instance",
            token: "token",
            email: "student@example.com",
            expiresAt: nil,
            validatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse {
        LicenseActivationResponse(
            licenseKey: "SB-TEST",
            instanceID: instanceID,
            token: token,
            email: "student@example.com",
            expiresAt: nil,
            validatedAt: Date(timeIntervalSince1970: 200)
        )
    }

    func deactivate(instanceID: String, token: String) async throws {}
}

private struct ExpiringLicenseAPIClient: LicenseAPIClientProtocol {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        LicenseActivationResponse(
            licenseKey: licenseKey,
            instanceID: "instance",
            token: "token",
            email: nil,
            expiresAt: Date(timeIntervalSince1970: 100),
            validatedAt: Date(timeIntervalSince1970: 50)
        )
    }

    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse {
        LicenseActivationResponse(
            licenseKey: "SB-TEST",
            instanceID: instanceID,
            token: token,
            email: nil,
            expiresAt: Date(timeIntervalSince1970: 100),
            validatedAt: Date(timeIntervalSince1970: 50)
        )
    }

    func deactivate(instanceID: String, token: String) async throws {}
}

private final class MemoryLicenseKeychain: LicenseKeychainProtocol {
    private var storage: [String: String] = [:]
    private(set) var loadCount = 0
    private(set) var loadCounts: [String: Int] = [:]
    private(set) var loadManyCallCount = 0

    func save(_ secret: String, for key: String) throws {
        storage[key] = secret
    }

    func load(for key: String) throws -> String? {
        loadCount += 1
        loadCounts[key, default: 0] += 1
        return storage[key]
    }

    func loadMany(for keys: [String]) throws -> [String: String] {
        loadManyCallCount += 1
        var secrets: [String: String] = [:]
        for key in keys {
            if let secret = try load(for: key) {
                secrets[key] = secret
            }
        }
        return secrets
    }

    func delete(for key: String) throws {
        storage.removeValue(forKey: key)
    }

    func contains(key: String) -> Bool {
        storage[key] != nil
    }

    func resetCounts() {
        loadCount = 0
        loadCounts = [:]
        loadManyCallCount = 0
    }
}

private final class DenyingLicenseKeychain: LicenseKeychainProtocol {
    private let status: OSStatus
    private(set) var loadCounts: [String: Int] = [:]

    init(status: OSStatus) {
        self.status = status
    }

    func save(_ secret: String, for key: String) throws {}

    func load(for key: String) throws -> String? {
        loadCounts[key, default: 0] += 1
        throw KeychainError.unhandledStatus(status)
    }

    func delete(for key: String) throws {}
}

private struct ThrowingLicenseAPIClient: LicenseAPIClientProtocol {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        throw TestLicenseError.networkUnavailable
    }

    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse {
        throw TestLicenseError.networkUnavailable
    }

    func deactivate(instanceID: String, token: String) async throws {
        throw TestLicenseError.networkUnavailable
    }
}

private struct SuspiciousLicenseAPIClient: LicenseAPIClientProtocol {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        throw LicenseNetworkTrustError.blockedHost(host: "api.lemonsqueezy.com", address: "127.0.0.1")
    }

    func validate(instanceID: String, token: String) async throws -> LicenseActivationResponse {
        throw LicenseNetworkTrustError.blockedHost(host: "api.lemonsqueezy.com", address: "127.0.0.1")
    }

    func deactivate(instanceID: String, token: String) async throws {
        throw LicenseNetworkTrustError.blockedHost(host: "api.lemonsqueezy.com", address: "127.0.0.1")
    }
}

private struct StaticLicenseHostTrustChecker: LicenseHostTrustChecking {
    var resolvedAddresses: [String]

    func resolvedAddresses(for host: String) throws -> [String] {
        resolvedAddresses
    }
}

private enum TestLicenseError: LocalizedError {
    case networkUnavailable

    var errorDescription: String? {
        "Network unavailable"
    }
}

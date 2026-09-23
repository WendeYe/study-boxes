import XCTest
@testable import StudyBoxes

@MainActor
final class DiagnosticsServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "StudyBoxesTests.Diagnostics.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCrashReportingDefaultsToOffAndPersists() {
        let diagnostics = DiagnosticsService(userDefaults: defaults)
        XCTAssertFalse(diagnostics.crashReportingEnabled)

        diagnostics.crashReportingEnabled = true

        let reloaded = DiagnosticsService(userDefaults: defaults)
        XCTAssertTrue(reloaded.crashReportingEnabled)
    }

    func testDiagnosticReportIncludesAllowedTechnicalMetadata() {
        let context = DiagnosticReportContext(
            appVersion: "1.0",
            appBuild: "42",
            bundleIdentifier: "com.studyboxes.StudyBoxes",
            macOSVersion: "Version 15.0",
            architecture: "arm64",
            licensePlan: "Pro",
            accessibilityTrusted: true,
            crashReportingEnabled: false
        )

        let report = DiagnosticReportWriter.makeReport(
            context: context,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.contains("Version: 1.0"))
        XCTAssertTrue(report.contains("Build: 42"))
        XCTAssertTrue(report.contains("Bundle ID: com.studyboxes.StudyBoxes"))
        XCTAssertTrue(report.contains("macOS: Version 15.0"))
        XCTAssertTrue(report.contains("Architecture: arm64"))
        XCTAssertTrue(report.contains("License plan: Pro"))
        XCTAssertTrue(report.contains("Accessibility trusted: yes"))
        XCTAssertTrue(report.contains("Crash reporting enabled: no"))
    }

    func testDiagnosticReportDoesNotIncludeSensitiveRepresentativeValues() {
        let context = DiagnosticReportContext(
            appVersion: "1.0",
            appBuild: "42",
            bundleIdentifier: "com.studyboxes.StudyBoxes",
            macOSVersion: "Version 15.0",
            architecture: "arm64",
            licensePlan: "Free",
            accessibilityTrusted: false,
            crashReportingEnabled: true
        )

        let report = DiagnosticReportWriter.makeReport(context: context)
        let forbiddenValues = [
            "Operating Systems",
            "Attempt one past exam section",
            "https://moodle.example/course/view.php?id=123",
            "/Users/kogu/Documents/private.pdf",
            "SB-SECRET-LICENSE",
            "student@example.com",
            "calendar-token"
        ]

        for value in forbiddenValues {
            XCTAssertFalse(report.contains(value), "Report should not contain \(value)")
        }
    }

    func testDiagnosticsConfigurationUsesSentryDSNAndReleaseShape() {
        let configuration = DiagnosticsConfiguration.current()

        XCTAssertTrue(configuration.dsn.contains("ingest.de.sentry.io"))
        XCTAssertTrue(configuration.releaseName.contains("@"))
        XCTAssertTrue(configuration.releaseName.contains("+"))
        XCTAssertFalse(configuration.environment.isEmpty)
    }
}

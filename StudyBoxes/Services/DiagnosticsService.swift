import AppKit
import Foundation
import os

#if canImport(Sentry)
import Sentry
#endif

struct DiagnosticsConfiguration: Equatable {
    static let bundledDSN = "https://0c558e2895cbb31e3695b67273294bb3@o4511315421888512.ingest.de.sentry.io/4511315435716688"

    var dsn: String
    var environment: String
    var releaseName: String

    static func current(bundle: Bundle = .main) -> DiagnosticsConfiguration {
        let bundleID = bundle.bundleIdentifier ?? "com.studyboxes.StudyBoxes"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let dsn = bundle.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? bundledDSN

        #if DEBUG
        let environment = "debug"
        #else
        let environment = "production"
        #endif

        return DiagnosticsConfiguration(
            dsn: dsn,
            environment: environment,
            releaseName: "\(bundleID)@\(version)+\(build)"
        )
    }
}

struct DiagnosticReportContext: Equatable {
    var appVersion: String
    var appBuild: String
    var bundleIdentifier: String
    var macOSVersion: String
    var architecture: String
    var licensePlan: String
    var accessibilityTrusted: Bool
    var crashReportingEnabled: Bool

    @MainActor
    static func current(
        bundle: Bundle = .main,
        licensePlan: EntitlementPlan,
        crashReportingEnabled: Bool
    ) -> DiagnosticReportContext {
        DiagnosticReportContext(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            bundleIdentifier: bundle.bundleIdentifier ?? "com.studyboxes.StudyBoxes",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architectureName,
            licensePlan: licensePlan.title,
            accessibilityTrusted: PermissionManager.isAccessibilityTrusted,
            crashReportingEnabled: crashReportingEnabled
        )
    }

    private static var architectureName: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

enum DiagnosticReportWriter {
    static func makeReport(context: DiagnosticReportContext, generatedAt: Date = .now) -> String {
        let generatedAtString = ISO8601DateFormatter().string(from: generatedAt)
        return """
        Study Boxes Diagnostic Report
        Generated: \(generatedAtString)

        App
        Version: \(context.appVersion)
        Build: \(context.appBuild)
        Bundle ID: \(context.bundleIdentifier)

        System
        macOS: \(context.macOSVersion)
        Architecture: \(context.architecture)

        Entitlements
        License plan: \(context.licensePlan)

        Permissions
        Accessibility trusted: \(context.accessibilityTrusted ? "yes" : "no")

        Diagnostics
        Crash reporting enabled: \(context.crashReportingEnabled ? "yes" : "no")

        Privacy
        This report intentionally excludes study box names, task titles, notes, URLs, file paths, app/window lists, license keys, email addresses, tokens, and calendar feed links.
        """
    }
}

@MainActor
final class DiagnosticsService: ObservableObject {
    static let shared = DiagnosticsService()

    static let crashReportingEnabledKey = "diagnostics.crashReportingEnabled"

    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "StudyBoxes", category: "Diagnostics")
    private var hasConfiguredProvider = false

    @Published var crashReportingEnabled: Bool {
        didSet {
            userDefaults.set(crashReportingEnabled, forKey: Self.crashReportingEnabledKey)
            configureCrashReportingIfNeeded()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.crashReportingEnabled = userDefaults.bool(forKey: Self.crashReportingEnabledKey)
    }

    func configureCrashReportingIfNeeded(configuration: DiagnosticsConfiguration = .current()) {
        guard crashReportingEnabled else { return }
        guard !hasConfiguredProvider else { return }
        guard !configuration.dsn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("Crash reporting is enabled, but Sentry DSN is empty.")
            return
        }

        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.environment = configuration.environment
            options.releaseName = configuration.releaseName
            options.sendDefaultPii = false
            options.enableNetworkBreadcrumbs = false
            options.maxBreadcrumbs = 20
            options.tracesSampleRate = 0
            options.beforeSend = { event in
                UserDefaults.standard.bool(forKey: Self.crashReportingEnabledKey) ? event : nil
            }
        }
        hasConfiguredProvider = true
        logger.info("Sentry crash reporting configured for \(configuration.environment, privacy: .public).")
        #else
        logger.warning("Crash reporting is enabled, but Sentry is not linked.")
        #endif
    }

    func diagnosticReport(licensePlan: EntitlementPlan? = nil) -> String {
        DiagnosticReportWriter.makeReport(context: .current(
            licensePlan: licensePlan ?? LicenseManager.shared.plan,
            crashReportingEnabled: crashReportingEnabled
        ))
    }

    func writeDiagnosticReport(to url: URL, licensePlan: EntitlementPlan? = nil) throws {
        try diagnosticReport(licensePlan: licensePlan).write(to: url, atomically: true, encoding: .utf8)
    }
}

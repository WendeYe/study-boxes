import XCTest
@testable import StudyBoxes

final class URLValidatorTests: XCTestCase {
    func testNormalizesBareDomainToHTTPS() {
        XCTAssertEqual(URLValidator.normalizedURLString("example.com"), "https://example.com")
    }

    func testKeepsQueryParametersAndDecodesHTMLAmpersands() {
        let input = "https://aulaglobal.uc3m.es/calendar/export_execute.php?userid=123&amp;preset_time=monthnext"

        XCTAssertEqual(
            URLValidator.normalizedURLString(input),
            "https://aulaglobal.uc3m.es/calendar/export_execute.php?userid=123&preset_time=monthnext"
        )
    }

    func testRejectsNonWebSchemesAndMissingHosts() {
        XCTAssertNil(URLValidator.normalizedURLString("file:///Users/test/file.pdf"))
        XCTAssertNil(URLValidator.normalizedURLString("https://"))
        XCTAssertNil(URLValidator.normalizedURLString(""))
    }

    func testTrimsWhitespaceAndRejectsMalformedHosts() {
        XCTAssertEqual(URLValidator.normalizedURLString("  https://example.com/path  "), "https://example.com/path")
        XCTAssertNil(URLValidator.normalizedURLString("nota url"))
        XCTAssertNil(URLValidator.normalizedURLString("https://exa mple.com"))
    }
}

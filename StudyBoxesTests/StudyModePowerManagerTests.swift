import IOKit.pwr_mgt
import XCTest
@testable import StudyBoxes

@MainActor
final class StudyModePowerManagerTests: XCTestCase {
    func testBeginStudyModeCreatesOneAssertionOnly() {
        let client = FakePowerAssertionClient()
        let manager = StudyModePowerManager(client: client)

        manager.beginStudyMode()
        manager.beginStudyMode()

        XCTAssertTrue(manager.isPreventingDisplaySleep)
        XCTAssertEqual(client.createdReasons.count, 1)
        XCTAssertTrue(client.releasedAssertions.isEmpty)
    }

    func testEndStudyModeReleasesAssertionAndIsIdempotent() {
        let client = FakePowerAssertionClient()
        let manager = StudyModePowerManager(client: client)

        manager.beginStudyMode()
        manager.endStudyMode()
        manager.endStudyMode()

        XCTAssertFalse(manager.isPreventingDisplaySleep)
        XCTAssertEqual(client.releasedAssertions, [1])
    }

    func testFailedAssertionDoesNotReportActivePrevention() {
        let client = FakePowerAssertionClient(nextAssertionID: nil)
        let manager = StudyModePowerManager(client: client)

        manager.beginStudyMode()

        XCTAssertFalse(manager.isPreventingDisplaySleep)
        XCTAssertTrue(client.releasedAssertions.isEmpty)
    }
}

private final class FakePowerAssertionClient: PowerAssertionClient {
    var createdReasons: [String] = []
    var releasedAssertions: [IOPMAssertionID] = []
    var nextAssertionID: IOPMAssertionID?

    init(nextAssertionID: IOPMAssertionID? = 1) {
        self.nextAssertionID = nextAssertionID
    }

    func createAssertion(reason: String) -> IOPMAssertionID? {
        createdReasons.append(reason)
        return nextAssertionID
    }

    func releaseAssertion(_ assertionID: IOPMAssertionID) {
        releasedAssertions.append(assertionID)
    }
}

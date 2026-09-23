import Foundation
import IOKit.pwr_mgt
import os

protocol PowerAssertionClient {
    func createAssertion(reason: String) -> IOPMAssertionID?
    func releaseAssertion(_ assertionID: IOPMAssertionID)
}

struct SystemPowerAssertionClient: PowerAssertionClient {
    func createAssertion(reason: String) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        return result == kIOReturnSuccess ? assertionID : nil
    }

    func releaseAssertion(_ assertionID: IOPMAssertionID) {
        IOPMAssertionRelease(assertionID)
    }
}

@MainActor
final class StudyModePowerManager {
    static let shared = StudyModePowerManager()

    private let logger = Logger(subsystem: "StudyBoxes", category: "Power")
    private let client: PowerAssertionClient
    private var assertionID: IOPMAssertionID?

    init(client: PowerAssertionClient = SystemPowerAssertionClient()) {
        self.client = client
    }

    var isPreventingDisplaySleep: Bool {
        assertionID != nil
    }

    func beginStudyMode() {
        guard assertionID == nil else { return }

        if let assertionID = client.createAssertion(reason: "Study Boxes active study session") {
            self.assertionID = assertionID
        } else {
            logger.warning("Could not create display sleep prevention assertion.")
        }
    }

    func endStudyMode() {
        guard let assertionID else { return }
        client.releaseAssertion(assertionID)
        self.assertionID = nil
    }

    deinit {
        if let assertionID {
            client.releaseAssertion(assertionID)
        }
    }
}

import AppKit
import XCTest
@testable import StudyBoxes

@MainActor
final class WindowLayoutManagerTests: XCTestCase {
    func testClampedFrameReturnsOriginalWhenNoScreensAreAvailable() {
        let frame = CGRect(x: -50, y: -25, width: 300, height: 200)

        XCTAssertEqual(WindowLayoutManager.clampedFrame(frame, to: []), frame)
    }

    func testClampedFrameKeepsOversizedFrameInsideVisibleScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let visible = screen.visibleFrame
        let offscreen = CGRect(
            x: visible.maxX + 5_000,
            y: visible.maxY + 5_000,
            width: visible.width * 2,
            height: visible.height * 2
        )

        let clamped = WindowLayoutManager.clampedFrame(offscreen, to: [screen])

        XCTAssertLessThanOrEqual(clamped.width, visible.width)
        XCTAssertLessThanOrEqual(clamped.height, visible.height)
        XCTAssertGreaterThanOrEqual(clamped.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(clamped.minY, visible.minY)
        XCTAssertLessThanOrEqual(clamped.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(clamped.maxY, visible.maxY)
    }
}

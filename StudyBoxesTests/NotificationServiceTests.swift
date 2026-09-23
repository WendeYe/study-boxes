import XCTest
import UserNotifications
@testable import StudyBoxes

final class NotificationServiceTests: XCTestCase {
    func testNotificationPermissionStatusMapsSystemAuthorizationStates() {
        let enabled = NotificationPermissionStatus.from(.authorized)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.canDeliverAlerts)
        XCTAssertFalse(enabled.canRequestInApp)
        XCTAssertEqual(enabled.description, "Notifications are on.")

        let notDetermined = NotificationPermissionStatus.from(.notDetermined)
        XCTAssertFalse(notDetermined.isEnabled)
        XCTAssertFalse(notDetermined.canDeliverAlerts)
        XCTAssertTrue(notDetermined.canRequestInApp)

        let denied = NotificationPermissionStatus.from(.denied)
        XCTAssertFalse(denied.isEnabled)
        XCTAssertFalse(denied.canDeliverAlerts)
        XCTAssertFalse(denied.canRequestInApp)
        XCTAssertEqual(denied.description, "Notifications are blocked in System Settings.")
    }

    func testDateOnlyDeadlinesUseMorningReminderTime() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 12
        components.hour = 0
        components.minute = 0
        let dueDate = try XCTUnwrap(Calendar.current.date(from: components))

        let reminder = try XCTUnwrap(NotificationService.reminderDate(for: dueDate, daysBefore: 1))
        let reminderComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
        XCTAssertEqual(reminderComponents.day, 11)
        XCTAssertEqual(reminderComponents.hour, 9)
        XCTAssertEqual(reminderComponents.minute, 0)
    }

    func testTodayDateOnlyDeadlineSchedulesSoonIfMorningHasPassed() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let noon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))

        let reminder = try XCTUnwrap(NotificationService.reminderDate(for: today, daysBefore: 0, now: noon))
        XCTAssertEqual(Int(reminder.timeIntervalSince(noon)), 60)
    }

    func testTestNotificationFeedbackDoesNotClaimDeliveryWhenAlertsAreDisabled() {
        let status = NotificationPermissionStatus(
            isEnabled: true,
            canRequestInApp: false,
            description: "Notifications are allowed, but banners are turned off for Study Boxes.",
            canDeliverAlerts: false
        )

        let feedback = NotificationService.testNotificationFeedback(
            status: status,
            didSchedule: false,
            schedulingError: nil
        )

        XCTAssertEqual(
            feedback,
            "Notifications are allowed, but banners are turned off for Study Boxes. Open Notification Settings and turn on banners for Study Boxes."
        )
    }
}

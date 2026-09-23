import Foundation
import SwiftData

@Model
final class WindowLayout: Identifiable {
    @Attribute(.unique) var id: UUID
    var box: StudyBox?
    var appBundleID: String
    var appName: String
    var capturedPID: Int?
    var windowTitle: String?
    var windowNumber: Int?
    var axRole: String?
    var axSubrole: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var screenFrameX: Double?
    var screenFrameY: Double?
    var screenFrameWidth: Double?
    var screenFrameHeight: Double?
    var visibleFrameX: Double?
    var visibleFrameY: Double?
    var visibleFrameWidth: Double?
    var visibleFrameHeight: Double?
    var screenIdentifier: String?
    var orderIndex: Int
    var isMinimized: Bool = false
    var isFullScreen: Bool = false
    var createdAt: Date

    init(
        id: UUID = UUID(),
        box: StudyBox? = nil,
        appBundleID: String,
        appName: String,
        capturedPID: Int? = nil,
        windowTitle: String? = nil,
        windowNumber: Int? = nil,
        axRole: String? = nil,
        axSubrole: String? = nil,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        screenFrameX: Double? = nil,
        screenFrameY: Double? = nil,
        screenFrameWidth: Double? = nil,
        screenFrameHeight: Double? = nil,
        visibleFrameX: Double? = nil,
        visibleFrameY: Double? = nil,
        visibleFrameWidth: Double? = nil,
        visibleFrameHeight: Double? = nil,
        screenIdentifier: String? = nil,
        orderIndex: Int = 0,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.box = box
        self.appBundleID = appBundleID
        self.appName = appName
        self.capturedPID = capturedPID
        self.windowTitle = windowTitle
        self.windowNumber = windowNumber
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.screenFrameX = screenFrameX
        self.screenFrameY = screenFrameY
        self.screenFrameWidth = screenFrameWidth
        self.screenFrameHeight = screenFrameHeight
        self.visibleFrameX = visibleFrameX
        self.visibleFrameY = visibleFrameY
        self.visibleFrameWidth = visibleFrameWidth
        self.visibleFrameHeight = visibleFrameHeight
        self.screenIdentifier = screenIdentifier
        self.orderIndex = orderIndex
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.createdAt = createdAt
    }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

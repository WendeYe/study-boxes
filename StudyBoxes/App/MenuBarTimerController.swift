import AppKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class MenuBarTimerController: NSObject {
    static let shared = MenuBarTimerController()
    static let appStatusSymbolName = "books.vertical"

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hostingController: NSHostingController<AnyView>?
    private var timer: Timer?
    private var startedAt: Date?
    private var boxName: String?
    private var displayMode: MenuBarDisplayMode = UserPreferencesService.shared.menuBarDisplayMode
    private var activeStatusItemLength: CGFloat?

    private override init() {}

    var isRunning: Bool {
        startedAt != nil
    }

    func ensureStatusItemVisible() {
        configureStatusItemIfNeeded()
        updateTitle()
    }

    func configure(appState: AppState, modelContainer: ModelContainer) {
        configureStatusItemIfNeeded()

        let rootView = AnyView(
            MenuBarRootView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController

        self.hostingController = hostingController
        self.popover = popover
        updateTitle()
    }

    func start(startedAt: Date, boxName: String, displayMode: MenuBarDisplayMode) {
        self.startedAt = startedAt
        self.boxName = boxName
        self.displayMode = displayMode
        activeStatusItemLength = Self.activeStatusItemLength(boxName: boxName, displayMode: displayMode)
        configureStatusItemIfNeeded()
        configureTimerIfNeeded()
        updateTitle()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        boxName = nil
        activeStatusItemLength = nil
        updateTitle()
    }

    func updateDisplayMode(_ displayMode: MenuBarDisplayMode) {
        self.displayMode = displayMode
        if startedAt != nil {
            activeStatusItemLength = Self.activeStatusItemLength(boxName: boxName, displayMode: displayMode)
        }
        updateTitle()
    }

    static func title(startedAt: Date, now: Date, boxName: String?, displayMode: MenuBarDisplayMode) -> String? {
        switch displayMode {
        case .iconOnly:
            nil
        case .timer:
            DurationFormatter.clock(now.timeIntervalSince(startedAt))
        case .boxNameAndTimer:
            "\(boxName?.nilIfBlank ?? "Study") \(DurationFormatter.clock(now.timeIntervalSince(startedAt)))"
        }
    }

    private func configureStatusItemIfNeeded() {
        if let item = statusItem, item.button != nil {
            item.isVisible = true
            return
        }

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = nil
            button.toolTip = "Study Boxes"
        }
        statusItem = item
        updateButtonImage()
    }

    private func configureTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTitle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateTitle(now: Date = .now) {
        configureStatusItemIfNeeded()

        guard let button = statusItem?.button else { return }
        defer {
            refreshPopoverAnchorIfNeeded()
        }

        guard let startedAt else {
            statusItem?.length = NSStatusItem.squareLength
            updateButtonImage()
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Study Boxes"
            return
        }

        updateButtonImage()
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = nil
        button.toolTip = "Active Study Boxes session"

        guard let title = Self.title(startedAt: startedAt, now: now, boxName: boxName, displayMode: displayMode) else {
            statusItem?.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        statusItem?.length = activeStatusItemLength ?? Self.activeStatusItemLength(boxName: boxName, displayMode: displayMode)
        button.imagePosition = .imageLeading
        button.attributedTitle = Self.attributedTitle(" \(title)")
    }

    static func activeStatusItemLength(boxName: String?, displayMode: MenuBarDisplayMode) -> CGFloat {
        switch displayMode {
        case .iconOnly:
            return NSStatusItem.squareLength
        case .timer:
            return 92
        case .boxNameAndTimer:
            let title = "\(boxName?.nilIfBlank ?? "Study") 88:88:88"
            let measuredWidth = ceil((title as NSString).size(withAttributes: [
                .font: NSFont.menuBarFont(ofSize: 0)
            ]).width)
            return min(max(measuredWidth + 34, 132), 190)
        }
    }

    static func statusImageSymbolName(isRunning: Bool) -> String {
        appStatusSymbolName
    }

    static func attributedTitle(_ title: String) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: NSFont.systemFontSize,
                    weight: .regular
                ),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    static func statusImage(isRunning: Bool) -> NSImage? {
        let description = isRunning ? "Active Study Boxes session" : "Study Boxes"

        if let image = NSImage(
            systemSymbolName: Self.statusImageSymbolName(isRunning: isRunning),
            accessibilityDescription: description
        )?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) {
            image.isTemplate = true
            return image
        }

        let image = [
            "book.closed",
            "rectangle.stack"
        ].lazy.compactMap { symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        }.first
        image?.isTemplate = true
        return image ?? menuBarTemplateImage(accessibilityDescription: description)
    }

    private func updateButtonImage() {
        guard let button = statusItem?.button else { return }
        button.image = Self.statusImage(isRunning: isRunning)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = nil
    }

    private static func menuBarTemplateImage(accessibilityDescription: String) -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            let lineWidth: CGFloat = 1.45
            let cornerRadius: CGFloat = 1.6
            let bookRects = [
                NSRect(x: rect.minX + 3.0, y: rect.minY + 3.0, width: 3.6, height: 12.0),
                NSRect(x: rect.minX + 7.2, y: rect.minY + 2.4, width: 3.6, height: 13.2),
                NSRect(x: rect.minX + 11.4, y: rect.minY + 4.0, width: 3.6, height: 10.8)
            ]

            for bookRect in bookRects {
                let path = NSBezierPath(roundedRect: bookRect, xRadius: cornerRadius, yRadius: cornerRadius)
                path.lineWidth = lineWidth
                path.stroke()
            }

            let shelf = NSBezierPath()
            shelf.move(to: NSPoint(x: rect.minX + 2.6, y: rect.minY + 2.3))
            shelf.line(to: NSPoint(x: rect.maxX - 2.6, y: rect.minY + 2.3))
            shelf.lineWidth = lineWidth
            shelf.stroke()
            return true
        }
        image.accessibilityDescription = accessibilityDescription
        image.isTemplate = true
        return image
    }

    private func refreshPopoverAnchorIfNeeded() {
        guard let popover, popover.isShown, let button = statusItem?.button else { return }
        popover.positioningRect = button.bounds
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            refreshPopoverAnchorIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

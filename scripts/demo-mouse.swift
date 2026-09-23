#!/usr/bin/env swift

import CoreGraphics
import Foundation

enum DemoRoute: String, CaseIterable {
    case focusHUD = "focus-hud"
    case idleMenu = "idle-menu"
    case library = "library"
    case createBox = "create-box"
}

enum AnchorMode: String {
    case current
    case screen
}

struct DemoOptions {
    var route: DemoRoute = .focusHUD
    var anchorMode: AnchorMode = .current
    var countdownSeconds = 5
    var speed = 1.0
    var dryRun = false
    var listRoutes = false
    var locateMouse = false
}

struct DemoRouteDefinition {
    let route: DemoRoute
    let title: String
    let size: CGSize
    let notes: String
    let steps: [DemoStep]
}

enum DemoStep {
    case move(String, CGFloat, CGFloat, TimeInterval)
    case pause(TimeInterval)
}

func parseOptions() -> DemoOptions {
    var options = DemoOptions()
    var args = Array(CommandLine.arguments.dropFirst())

    if let first = args.first, !first.hasPrefix("--") {
        guard let route = DemoRoute(rawValue: first) else {
            fail("Unknown route: \(first)")
        }
        options.route = route
        args.removeFirst()
    }

    var index = 0
    while index < args.count {
        let arg = args[index]

        switch arg {
        case "--help", "-h":
            printUsageAndExit()
        case "--list":
            options.listRoutes = true
        case "--dry-run":
            options.dryRun = true
        case "--locate":
            options.locateMouse = true
        case "--anchor":
            index += 1
            guard index < args.count, let anchorMode = AnchorMode(rawValue: args[index]) else {
                fail("--anchor requires current or screen")
            }
            options.anchorMode = anchorMode
        case "--countdown":
            index += 1
            guard index < args.count, let seconds = Int(args[index]) else {
                fail("--countdown requires a number")
            }
            options.countdownSeconds = max(0, seconds)
        case "--speed":
            index += 1
            guard index < args.count, let speed = Double(args[index]), speed > 0 else {
                fail("--speed requires a positive number")
            }
            options.speed = speed
        default:
            if let value = arg.dropPrefix("--anchor="), let anchorMode = AnchorMode(rawValue: String(value)) {
                options.anchorMode = anchorMode
            } else if let value = arg.dropPrefix("--countdown="), let seconds = Int(value) {
                options.countdownSeconds = max(0, seconds)
            } else if let value = arg.dropPrefix("--speed="), let speed = Double(value), speed > 0 {
                options.speed = speed
            } else {
                fail("Unknown option: \(arg)")
            }
        }

        index += 1
    }

    return options
}

func routeDefinition(for route: DemoRoute) -> DemoRouteDefinition {
    switch route {
    case .focusHUD:
        return DemoRouteDefinition(
            route: route,
            title: "Active Focus HUD",
            size: CGSize(width: 820, height: 840),
            notes: "Place the pointer on the top-left corner of the open Focus HUD popover.",
            steps: [
                .move("session title and focus mode", 0.28, 0.11, 0.65),
                .move("elapsed timer", 0.82, 0.12, 0.65),
                .pause(0.25),
                .move("current task", 0.36, 0.34, 0.80),
                .move("task metadata", 0.25, 0.42, 0.55),
                .move("Done action", 0.83, 0.42, 0.65),
                .pause(0.25),
                .move("up next", 0.36, 0.57, 0.70),
                .move("quick actions", 0.52, 0.67, 0.75),
                .move("end session", 0.50, 0.76, 0.70),
                .pause(0.25),
                .move("library and settings", 0.26, 0.94, 0.75),
                .move("quit", 0.88, 0.94, 0.65)
            ]
        )
    case .idleMenu:
        return DemoRouteDefinition(
            route: route,
            title: "Idle Menu Bar Launcher",
            size: CGSize(width: 790, height: 540),
            notes: "Place the pointer on the top-left corner of the open idle menu-bar popover.",
            steps: [
                .move("title", 0.19, 0.10, 0.55),
                .move("primary start button", 0.50, 0.27, 0.75),
                .pause(0.25),
                .move("recent study boxes", 0.36, 0.50, 0.80),
                .move("session lengths", 0.88, 0.50, 0.65),
                .pause(0.20),
                .move("library", 0.20, 0.91, 0.65),
                .move("settings", 0.38, 0.91, 0.55),
                .move("quit", 0.86, 0.91, 0.60)
            ]
        )
    case .library:
        return DemoRouteDefinition(
            route: route,
            title: "Library Overview",
            size: CGSize(width: 1500, height: 1010),
            notes: "Place the pointer on the top-left corner of the Library window content.",
            steps: [
                .move("active boxes sidebar", 0.16, 0.39, 0.75),
                .move("weekly summary", 0.55, 0.18, 0.80),
                .pause(0.20),
                .move("study box grid", 0.43, 0.40, 0.85),
                .move("second study box", 0.73, 0.40, 0.70),
                .move("library setup actions", 0.84, 0.29, 0.75),
                .move("create button", 0.28, 0.05, 0.70),
                .move("settings", 0.96, 0.06, 0.70)
            ]
        )
    case .createBox:
        return DemoRouteDefinition(
            route: route,
            title: "Create Study Box",
            size: CGSize(width: 1220, height: 900),
            notes: "Place the pointer on the top-left corner of the Create Study Box sheet.",
            steps: [
                .move("template picker", 0.20, 0.24, 0.75),
                .move("coding project template", 0.50, 0.42, 0.75),
                .move("language template", 0.78, 0.42, 0.65),
                .pause(0.20),
                .move("name field", 0.56, 0.58, 0.80),
                .move("type and due date", 0.25, 0.70, 0.70),
                .move("appearance", 0.20, 0.82, 0.70),
                .move("create and start", 0.84, 0.95, 0.85)
            ]
        )
    }
}

func printUsageAndExit() -> Never {
    print("""
    Usage:
      swift scripts/demo-mouse.swift [route] [options]

    Routes:
      focus-hud    Active Focus HUD popover
      idle-menu    Idle menu-bar launcher popover
      library      Library window
      create-box   Create Study Box sheet

    Options:
      --anchor current|screen   current = use the current pointer as the route top-left. Default: current
      --countdown 5             seconds before movement starts. Default: 5
      --speed 0.85              lower is slower, higher is faster. Default: 1.0
      --dry-run                 print coordinates without moving the pointer
      --locate                  print the current pointer location and exit
      --list                    list route sizes and setup notes

    Recommended:
      1. Open the Study Boxes screen you want to capture.
      2. Put the pointer on the top-left corner of that popover/window/sheet.
      3. Start recording in CleanShot X or QuickTime.
      4. Run this script with the matching route.
    """)
    exit(0)
}

func printRouteList() {
    for route in DemoRoute.allCases {
        let definition = routeDefinition(for: route)
        print("\(definition.route.rawValue): \(definition.title)")
        print("  Canvas: \(Int(definition.size.width))x\(Int(definition.size.height))")
        print("  Setup: \(definition.notes)")
    }
}

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n\n", stderr)
    printUsageAndExit()
}

func mainDisplayBounds() -> CGRect {
    CGDisplayBounds(CGMainDisplayID())
}

func currentMouseLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? CGPoint(x: mainDisplayBounds().midX, y: mainDisplayBounds().midY)
}

func routeFrame(for definition: DemoRouteDefinition, options: DemoOptions) -> CGRect {
    switch options.anchorMode {
    case .current:
        let origin = currentMouseLocation()
        return CGRect(origin: origin, size: definition.size)
    case .screen:
        return mainDisplayBounds()
    }
}

func point(x: CGFloat, y: CGFloat, in frame: CGRect) -> CGPoint {
    CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
}

func easeInOutCubic(_ t: Double) -> Double {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

func postMove(to point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func moveSmoothly(to destination: CGPoint, duration: TimeInterval) {
    let start = currentMouseLocation()
    let frameRate = 60.0
    let steps = max(1, Int(duration * frameRate))

    for step in 0...steps {
        let progress = easeInOutCubic(Double(step) / Double(steps))
        let x = Double(start.x) + (Double(destination.x - start.x) * progress)
        let y = Double(start.y) + (Double(destination.y - start.y) * progress)
        postMove(to: CGPoint(x: x, y: y))
        Thread.sleep(forTimeInterval: 1.0 / frameRate)
    }
}

func locateMouseAndExit() -> Never {
    let location = currentMouseLocation()
    let bounds = mainDisplayBounds()
    let relativeX = (location.x - bounds.minX) / bounds.width
    let relativeY = (location.y - bounds.minY) / bounds.height
    print("Mouse: x=\(Int(location.x)) y=\(Int(location.y))")
    print(String(format: "Screen relative: x=%.3f y=%.3f", Double(relativeX), Double(relativeY)))
    exit(0)
}

func run(_ options: DemoOptions) {
    if options.listRoutes {
        printRouteList()
        return
    }

    if options.locateMouse {
        locateMouseAndExit()
    }

    let definition = routeDefinition(for: options.route)
    let frame = routeFrame(for: definition, options: options)

    print("Route: \(definition.title) (\(definition.route.rawValue))")
    print("Anchor: \(options.anchorMode.rawValue)")
    print("Frame: x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))")
    print("Speed: \(options.speed)")

    if options.dryRun {
        for step in definition.steps {
            switch step {
            case let .move(label, x, y, duration):
                let destination = point(x: x, y: y, in: frame)
                print("Move: \(label) -> x=\(Int(destination.x)) y=\(Int(destination.y)) duration=\(duration / options.speed)s")
            case let .pause(duration):
                print("Pause: \(duration / options.speed)s")
            }
        }
        return
    }

    print("Starting in \(options.countdownSeconds)s. Start recording now.")
    if options.countdownSeconds > 0 {
        for remaining in stride(from: options.countdownSeconds, through: 1, by: -1) {
            print("\(remaining)...")
            Thread.sleep(forTimeInterval: 1)
        }
    }

    for step in definition.steps {
        switch step {
        case let .move(label, x, y, duration):
            print("Move: \(label)")
            moveSmoothly(to: point(x: x, y: y, in: frame), duration: duration / options.speed)
        case let .pause(duration):
            Thread.sleep(forTimeInterval: duration / options.speed)
        }
    }

    print("Route complete.")
}

private extension String {
    func dropPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}

run(parseOptions())

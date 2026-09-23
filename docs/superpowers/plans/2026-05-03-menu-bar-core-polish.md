# Menu Bar Core Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shipped daily workflow feel more menu-bar-first and less duplicated without introducing new product surfaces.

**Architecture:** Keep the existing SwiftUI/AppKit menu bar stack. Add small pure helpers where behavior can be unit-tested, then update the menu bar active session controls and timer presentation.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, SwiftData.

---

### Task 1: Document And Test Startup/Menu-Bar Policies

**Files:**
- Modify: `StudyBoxes/App/AppState.swift`
- Modify: `StudyBoxesTests/AppStateTests.swift`

- [x] **Step 1: Add tests for launch and active status message policy**

Add tests proving that the Library is closed on startup only after onboarding, and that routine menu bar status messages remain hidden.

- [x] **Step 2: Run targeted tests and verify failure**

Run: `xcodebuild -scheme StudyBoxes -only-testing:StudyBoxesTests/AppStateTests test`

Expected: compile failure until the new policy helpers exist.

- [x] **Step 3: Add pure policy helpers**

Add `AppWindowController.shouldCloseInitialDashboardWindowAfterLaunch(hasCompletedOnboarding:)` and `MenuBarStatusMessagePolicy.shouldDisplay(_:)`.

- [x] **Step 4: Re-run targeted tests**

Run: `xcodebuild -scheme StudyBoxes -only-testing:StudyBoxesTests/AppStateTests test`

Expected: pass.

### Task 2: Simplify Active Menu Bar Controls

**Files:**
- Modify: `StudyBoxes/Views/MenuBar/MenuBarRootView.swift`

- [x] **Step 1: Replace duplicate setup/resource actions**

Make the active session action row use a single `Resources` control. It opens all resources when clicked, and exposes individual resources through a menu when available. Keep `Task`, `Detach`, and `More`.

- [x] **Step 2: Move rarely used active controls into More**

Keep `Pause Strict Focus` visible when active. Keep `Show Hidden Apps` and `Quit Study Boxes` in `More`. Do not duplicate resource controls inside `More`.

- [x] **Step 3: Use centralized status message policy**

Replace local prefix filtering with `MenuBarStatusMessagePolicy.shouldDisplay(_:)`.

### Task 3: Stabilize Menu Bar Timer Presentation

**Files:**
- Modify: `StudyBoxes/App/MenuBarTimerController.swift`
- Modify: `StudyBoxesTests/AppStateTests.swift`

- [x] **Step 1: Add a test for fixed active status item width**

Assert timer and box-name timer modes use reserved widths independent of the current elapsed string.

- [x] **Step 2: Apply monospaced attributed menu bar titles**

Set an attributed status title using a monospaced digit font while preserving the existing fixed-width status item behavior.

### Task 4: Verify

**Files:**
- No code changes.

- [x] **Step 1: Run targeted tests**

Run: `xcodebuild -scheme StudyBoxes -only-testing:StudyBoxesTests/AppStateTests test`

- [x] **Step 2: Run full unit tests**

Run: `xcodebuild -scheme StudyBoxes test`

- [x] **Step 3: Run Debug build**

Run: `xcodebuild -scheme StudyBoxes -configuration Debug build`

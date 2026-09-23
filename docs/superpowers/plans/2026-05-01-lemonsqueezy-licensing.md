# Lemon Squeezy Licensing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace placeholder local license activation with direct Lemon Squeezy License API activation, validation, deactivation, and checkout routing.

**Architecture:** Keep `LicenseManager` as the UI-facing state machine and inject a production Lemon Squeezy client as its default dependency. Centralize product ID and checkout URL in a small configuration type, and preserve the existing Keychain/UserDefaults storage split.

**Tech Stack:** Swift, SwiftUI, Foundation `URLSession`, Keychain, XCTest.

---

### Task 1: Add Lemon Squeezy Client Tests

**Files:**
- Modify: `StudyBoxesTests/LicenseManagerTests.swift`

- [ ] Add tests for request form encoding, response mapping, product validation, and license status rejection.
- [ ] Run `xcodebuild -project StudyBoxes.xcodeproj -scheme StudyBoxes -configuration Debug -derivedDataPath .build/DerivedData test -only-testing:StudyBoxesTests/LicenseManagerTests` and confirm new tests fail before implementation.

### Task 2: Implement Lemon Squeezy API Client

**Files:**
- Modify: `StudyBoxes/Services/LicenseManager.swift`

- [ ] Add `LicenseConfiguration`.
- [ ] Add `LemonSqueezyLicenseAPIClient`.
- [ ] Map Lemon Squeezy activation, validation, and deactivation responses into `LicenseActivationResponse`.
- [ ] Preserve `PlaceholderLicenseAPIClient` for tests only.
- [ ] Run focused license tests and confirm pass.

### Task 3: Wire Production Defaults And Checkout UI

**Files:**
- Modify: `StudyBoxes/Services/LicenseManager.swift`
- Modify: `StudyBoxes/Views/Settings/LicenseView.swift`

- [ ] Make `LicenseManager.shared` use the Lemon Squeezy client by default.
- [ ] Add Buy Pro button opening the checkout URL.
- [ ] Remove placeholder “Purchases are not connected” copy.
- [ ] Keep activation, validation, and deactivation UI behavior.

### Task 4: Update Docs And Verify

**Files:**
- Modify: `docs/Distribution.md`
- Modify: `docs/ManualVerification.md`

- [ ] Document Lemon Squeezy product ID and checkout URL.
- [ ] Document that no Lemon Squeezy API secret is shipped in the app.
- [ ] Run focused license tests.
- [ ] Run full test suite.
- [ ] Run Debug build.

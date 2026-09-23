# Study Boxes Agent Guide

## Product Context

Study Boxes is a commercial, direct-download macOS productivity app built with Swift, SwiftUI, SwiftData, AppKit, and macOS system APIs. It is intentionally non-sandboxed because it needs to orchestrate the user workspace: launch apps/resources, capture and restore window layouts, and optionally enforce a focus mode during a study session.

## Current Known State

- SwiftData foundation exists: `StudyBox`, `StudyResource`, and related persistence.
- `ResourceLauncher` exists and uses `NSWorkspace`.
- `DistractionManager` and `WindowLayoutManager` may contain partial implementations.
- `SessionManager` coordinates starting and ending study sessions.
- `KeychainService.swift` exists and should be reused for secrets/tokens.
- The app is distributed outside the Mac App Store.

## Before Editing

1. Inspect the repository structure.
2. Read this file, README/project documentation, existing tests, and relevant source files.
3. Discover the Xcode scheme using `xcodebuild -list`.
4. Identify the correct build/test command. Prefer:
   - `xcodebuild -scheme "<SCHEME>" -configuration Debug build`
   - existing test commands if tests are present.
5. Do not make broad architectural rewrites unless necessary.
6. Preserve existing public APIs where possible.
7. Keep changes small, reviewable, and idiomatic Swift.
8. Use `os.Logger` or the project logging pattern for diagnostics.
9. Prefer `@MainActor` for observable UI-facing managers.
10. If the repo has no test target, add focused unit tests where practical; otherwise add clearly documented manual verification steps.

## Safety and Product Constraints

- Do not use force-kill APIs for distraction blocking.
- Do not terminate system-critical apps, Finder, Study Boxes itself, password managers, security tools, accessibility tools, or System Settings.
- Focus enforcement must be explicitly opt-in and reversible.
- Provide an emergency stop/pause path.
- Never hardcode real API keys, private keys, appcast secrets, license secrets, or production endpoints.
- Use placeholders and configuration points for commercial services.
- Treat saved process IDs as temporary, not stable app identity.
- Do not require Screen Recording permission unless the implementation actually needs protected window titles/content.
- If a requested feature requires a permission, fail gracefully and guide the user.

## Technical References

- `CGWindowListCopyWindowInfo` can return information about windows in the current user session.
- Accessibility APIs are required for moving/resizing other apps' windows.
- Use `AXIsProcessTrustedWithOptions` for Accessibility permission checks/prompts.
- Sparkle 2 should use `SPUStandardUpdaterController`; do not build new integration around deprecated `SUUpdater`.
- Direct-download macOS distribution requires Developer ID signing, hardened runtime, notarization, and release packaging.

## Epics

### Epic 1: Full Window Management

Replace the stubbed `WindowLayoutManager` with real macOS window capture and restore behavior.

Acceptance criteria:
- Capture visible, standard user windows for a `StudyBox`.
- Store enough metadata to restore windows after apps relaunch.
- Restore uses current app identity, not stale saved PIDs.
- Restore waits for launched apps to expose windows before attempting placement.
- Restore handles missing apps, unavailable windows, minimized windows, full-screen windows, and multi-display changes gracefully.
- Build succeeds.
- Tests or manual verification steps are added.

### Epic 2: Opt-In Focus Enforcement

Upgrade `DistractionManager` from simple hiding to explicit, safe, opt-in focus enforcement.

Acceptance criteria:
- The user must explicitly enable strict focus enforcement.
- The app observes newly launched apps during an active session.
- Non-allowed user apps are politely terminated using `NSRunningApplication.terminate()`.
- Protected/system apps are never terminated.
- The observer is removed when the session ends.
- There is an emergency stop/pause route.
- Build succeeds.
- Tests or manual verification steps are added.

### Epic 3: Permissions and Accessibility Onboarding

Build a user-friendly onboarding flow for permissions required by window management.

Acceptance criteria:
- `PermissionManager` publishes current Accessibility trust state.
- UI reacts when permission is granted or revoked.
- Onboarding explains why permission is needed.
- The user can open the correct System Settings pane.
- The app does not attempt AX window restore without permission.
- Build succeeds.
- Tests or manual verification steps are added.

### Epic 4: Commercial Readiness

Prepare the direct-download non-sandboxed app for commercial distribution.

Acceptance criteria:
- Project settings/documentation reflect non-sandboxed direct distribution.
- Sparkle 2 integration is started correctly or documented if dependency modification is not possible.
- License manager stub is implemented cleanly with Keychain persistence.
- License UI exists.
- No secrets are hardcoded.
- Build succeeds.
- Tests or manual verification steps are added.

## Final Report Requirements

At the end of implementation work, provide:

1. Files changed
2. Major behavior added
3. Build/test commands run
4. Test results
5. Manual verification checklist
6. Known limitations
7. Follow-up tasks

Do not claim success unless the build/test command actually succeeded. If something cannot be completed because of missing project structure, signing permissions, or unavailable local macOS permissions, implement the safe portion and document the exact blocker.

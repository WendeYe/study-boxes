# Study Boxes

Study Boxes is a native macOS app for getting back into a subject without rebuilding your workspace every time. A Study Box keeps the files, folders, apps, links, tasks, and notes for one course or project together, then opens the setup when you are ready to study.

It started as a way to remove the small bits of friction that make it easy to put studying off: finding the right exercise sheet, reopening an editor, remembering which task was next, and clearing unrelated apps out of the way.

## What it does

- Keeps a separate workspace for each course, exam, assignment, or project.
- Opens enabled apps, files, folders, and websites together.
- Tracks tasks, session notes, study time, and recent progress.
- Imports deadlines from Moodle, Blackboard, and generic ICS feeds.
- Offers optional app-level focus controls and best-effort window restore.
- Runs locally without an account or cloud backend.

Study Boxes does not inspect browser tabs, scrape course pages, or force quit apps. Calendar feed URLs are stored in Keychain, and Accessibility access is only needed for window arrangement features.

## Requirements

- macOS 14 or later
- Xcode with the macOS 14 SDK or later

## Build

Open `StudyBoxes.xcodeproj` in Xcode and run the `StudyBoxes` scheme, or use:

```sh
xcodebuild \
  -project StudyBoxes.xcodeproj \
  -scheme StudyBoxes \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  build
```

Run the test suite with:

```sh
xcodebuild \
  -project StudyBoxes.xcodeproj \
  -scheme StudyBoxes \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  test
```

## Project structure

- `StudyBoxes/App`: app lifecycle and shared state
- `StudyBoxes/Models`: SwiftData models
- `StudyBoxes/Services`: sessions, resources, focus controls, calendars, backups, licensing, and updates
- `StudyBoxes/Views`: SwiftUI screens grouped by feature
- `StudyBoxesTests`: unit and integration tests
- `docs`: distribution notes, manual checks, and the public website

## Status

Study Boxes is under active development. The direct-download release still requires Developer ID signing, notarization, a production Sparkle appcast, and final release testing on a clean Mac. See `docs/Distribution.md` and `docs/ManualVerification.md` for the current release checklist.

## Privacy

Study data stays on the Mac. The repository must not contain personal exports, private calendar links, license keys, signing material, or diagnostic reports.

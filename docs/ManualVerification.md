# Manual Verification

Use the `StudyBoxes` scheme:

```sh
xcodebuild -project StudyBoxes.xcodeproj -scheme StudyBoxes -configuration Debug -derivedDataPath .build/DerivedData build
xcodebuild -project StudyBoxes.xcodeproj -scheme StudyBoxes -configuration Debug -derivedDataPath .build/DerivedData test
```

The `StudyBoxesTests` target covers URL validation, ICS parsing, tasks/sessions, resources, notifications, backup import/export, licensing, desktop Spaces planning, window layout helpers, focus rules, restore snapshots, onboarding state, templates, and resume selection.

## First Run

- Delete the app's local data or run a fresh build.
- Launch Study Boxes and confirm the first-run onboarding appears.
- Create a Study Box from each template: Weekly course, Exam prep, Assignment, Coding project, and Language study.
- Confirm each template shows its own resource fields: course materials, exam prep materials, assignment materials, coding project workspace, or language practice materials.
- For Coding project, choose a real code editor app and optional terminal/tool app; confirm they are saved as app resources with bundle metadata when available.
- For Language study, add an optional Anki link and choose a real practice app plus dictionary/listening resources if relevant.
- For Exam prep, add an optional Anki link and confirm it is saved as an Anki resource, not a generic website.
- Add an optional website, file, folder, app, and first task during onboarding where the selected template offers those fields.
- Confirm invalid website input shows a clear error and does not create a broken resource.
- Use Skip and confirm it does not create data.
- Use Start first session and confirm the session opens immediately.

## Template Creation

- After onboarding is complete, click New Study Box from the sidebar plus button and toolbar.
- Confirm both entry points open the same template-first creator with Blank, Weekly course, Exam prep, Assignment, Coding project, and Language study.
- Select a template and confirm name, type, due date, appearance, default session length, focus mode, startup options, resources, and starter tasks can be customized before creation.
- Confirm generated starter tasks can be renamed, removed, and added before creation.
- Confirm selected URL/file/folder/app resources can be cleared before creation.
- Create a Coding project and confirm optional app resources are saved and launchable when a real app was chosen.
- Create a Language study or Exam prep box with an Anki link and confirm it appears as an Anki resource.
- Use Create and Start and confirm the session starts from the menu bar without opening the Focus HUD automatically.

## Anki Resources

- Add a resource and choose Anki.
- Leave the Anki link blank, save it with a deck label, and confirm Open Now launches the Anki app when Anki is installed.
- Add an `anki://` link and confirm it saves without being converted to a web URL.
- Add an AnkiWeb `https://ankiweb.net/...` link and confirm it opens in the browser.
- Enter invalid text such as `nota url` and confirm saving is blocked with a clear Anki-link error.
- On a Mac without Anki installed, confirm the editor shows a lightweight install hint with Open Anki Website.
- Confirm Study Boxes never claims to inspect decks, cards, review counts, or individual browser tabs.

## Menu Bar Sessions

- Finish a session with notes and at least one unfinished task.
- Open the menu bar item and confirm the top action starts the most recently studied active box.
- Pin three Study Boxes and confirm they appear under Pinned, with up to three other boxes under Recent.
- Start a session from the menu bar and confirm Study Space does not open until Show Study Space is chosen.
- Click Show Focus HUD repeatedly during the same active session and confirm the existing Study Space window is focused instead of creating duplicates.
- During an active session, confirm the menu bar exposes the current task first with Mark Done and Skip actions before secondary window controls.
- During an active session, confirm Study Setup is a menu with Open All plus enabled launchable resources or commands.
- Confirm Open Library opens the setup/library window.

## Library Window

- Confirm the Library window opens to Study Boxes and progress context, not a large Resume Study panel.
- Select a Study Box and confirm the detail view scrolls naturally without duplicated nested scrolling or doubled outer padding.
- Confirm Calendar Feeds and Schedule Reminders are available from the Library content area, not the primary toolbar.
- Confirm Settings opens directly to practical preferences without beta or commercial status copy at the top.

## Session End

- Start a session, mark tasks done and skipped, add notes, then end it.
- Start a session from the Library and confirm the Library window closes after the session starts, leaving Study Space as the only session UI.
- Start a session from the menu bar while Library is open and confirm the Library closes even when Study Space is not opened automatically.
- Confirm the active session clears from the menu bar timer and the app state.
- If Study Space is open, confirm it behaves as a compact floating Focus HUD rather than a second library view: current task first, short up-next list under Details, setup status under Details, notes collapsed by default, and End Session.
- Confirm Show Focus HUD from the menu bar opens or focuses the compact Study Space, while Study Setup launches the box resources without opening the Library.
- If Study Space is open after ending, confirm it shows a lightweight ended/restored summary.
- If Study Boxes is not frontmost, or restore has issues, confirm notification feedback is delivered when notifications are allowed.
- Use Start another session and confirm the normal start flow appears.

## Break And Posture Reminders

- Open Settings > Sessions and confirm Break and posture reminders are enabled by default with a 25 min interval.
- Change the interval to 20, 30, or 45 min and confirm the preference persists after reopening Settings.
- Start a session, mark a task done before the interval elapses, and confirm no reminder appears.
- After the interval elapses since session start or the last reminder, mark a task done and confirm a lightweight break/posture prompt appears in the Focus HUD if it is open.
- Confirm the active menu bar session also shows the pending prompt with Take Break, Posture Check, and Skip Break Reminder actions.
- Confirm Take Break, Posture Check, and Skip all clear the pending prompt without pausing focus mode or starting a break timer.
- Confirm checking off several tasks quickly only shows one reminder until another full interval has elapsed.
- Confirm skipped tasks do not trigger break/posture reminders.
- Put Study Boxes in the background, complete a task after the interval, and confirm a notification is requested/delivered only when notifications are allowed.
- End the session with a pending prompt and confirm the prompt is cleared.

## Backup

- Open Settings > Backup and safety.
- Export JSON and confirm the file is written.
- Import JSON and confirm Study Boxes asks for confirmation before inserting data.
- Confirm private calendar feed URLs are not included in the JSON export.
- Confirm ordinary website links and local file paths may be present in the JSON export.

## Privacy And Diagnostics

- Open Settings > Privacy and diagnostics.
- Confirm Share crash reports is off by default.
- Enable Share crash reports and restart the app; confirm it remains enabled.
- Disable Share crash reports and restart the app; confirm it remains disabled.
- Click Create Diagnostic Report..., save the report, and inspect it.
- Confirm the report includes app version, build, bundle ID, macOS version, architecture, license plan, Accessibility status, and crash reporting status.
- Confirm the report does not include study box names, task titles, notes, URLs, file paths, app/window lists, license keys, email, tokens, or calendar feed links.
- Archive a release candidate, set `SENTRY_AUTH_TOKEN`, and run `scripts/upload-sentry-dsyms.sh` with `ARCHIVE_PATH` pointing at the `.xcarchive`.
- Confirm Sentry shows uploaded debug files for org `study-box` and project `study-macos`.

## Window Layout

- Grant Accessibility permission from Settings > Permissions.
- Open Finder, Preview, Safari or Chrome, and VS Code.
- Select a Study Box and click Capture Layout.
- Move windows.
- Enable Restore window layout for the Study Box.
- Start a session and confirm windows are restored best-effort.
- Revoke Accessibility permission and confirm restore is blocked with explanatory UI.

## Desktop Spaces

- Edit a Pro Study Box and enable Prepare desktop Spaces.
- Set the minimum to at least 3 desktops.
- Add two app resources and assign them to different desktops.
- Start a session with Open study setup enabled and confirm Study Boxes keeps existing desktops, creates missing desktops best effort, and places the assigned app windows onto the configured desktops when macOS allows it.
- On a Mac with multiple displays and separate Spaces enabled, place one assigned app on the built-in display and another on an external display before starting the session; confirm each app is moved to the requested desktop number on the display where its window opened instead of being sent to the primary display's desktop list.
- If one display has fewer available desktops than requested, confirm Study Boxes leaves those unmatched windows where they are and reports that some windows stayed on their original display.
- Set a resource target higher than the minimum and confirm Study Boxes still prepares enough desktops for that app.
- Disable Prepare desktop Spaces and confirm the desktop assignment controls stay saved on resources but no desktop preparation runs at session start.
- Start the same box on Free and confirm the session starts normally while desktop Space preparation is ignored and contextual Pro messaging remains visible in setup and editing UI.

## Focus Controls

- Set Focus Mode to Off; launching another normal app should not close it.
- Set Focus Mode to Hide Apps and start a session; unrelated apps should hide, the menu should offer Show Hidden Apps, and ending the session should show them again.
- Set Focus Mode to Quit Apps and start a session; the pre-flight sheet should list only apps that will be asked to quit.
- Confirm the pre-flight sheet explicitly says browser windows can be restored, but individual tabs are never inspected or restored.
- End the Quit Apps session and confirm only apps Study Boxes affected are relaunched, with visible non-minimized window frames restored best-effort when Accessibility is available.
- Set Focus Mode to Strict Focus and start a session; initial cleanup should ask unrelated apps to quit, and newly launched distractions should be blocked.
- Launch Finder and System Settings; they should never be terminated.
- Use the menu bar Pause Strict Focus action and confirm only newly launched app blocking stops.
- Confirm newly blocked apps are recorded as blocked events but are not restored at session end.
- Revoke Accessibility permission and confirm Quit Apps and Strict Focus request permission contextually, while Hide Apps still works.
- If an app refuses normal termination because of unsaved work, confirm it is not force quit and is hidden as fallback.
- Leave a window minimized before the session and confirm it remains minimized after restore.
- Restart Study Boxes with a pending or failed restore snapshot and confirm Restore Previous Apps... appears only in the menu bar or Focus settings.

## Reminders

- Create a pending task due today with a date-only deadline.
- Use Schedule Reminders.
- Confirm notification permission is requested if not already granted.
- Confirm the result message reports scheduled reminders or blocked permissions clearly.

## Licensing

- Open Settings > License.
- Confirm an unlicensed app shows the Free plan.
- Click Buy Pro and confirm it opens the Lemon Squeezy checkout for Study Boxes Pro.
- On Free, confirm only one total Study Box can be created; archived boxes still count, and extra existing boxes remain viewable/exportable/deletable but sessions and unarchive are blocked until reduced to one or Pro is active.
- On Free, confirm Blank Study Box creation works and non-Blank templates remain visible with a Pro badge but route to License.
- On Free, confirm tasks, notes, one-box sessions, the menu bar timer, basic notifications, break/posture reminders, backup export, and up to three resources continue to work.
- On Free, confirm adding a fourth resource is blocked and automatic study setup opens only the first three enabled resources.
- On Free, confirm Calendar Feeds, backup import, session history/advanced stats, window layout capture/restore, Hide Apps, Quit Apps, and Strict Focus show contextual Pro messaging.
- On Free, set a box to Pro-only focus/window settings while licensed, deactivate, then start a session and confirm startup is sanitized to no focus mode and no window restore while the saved settings remain on the box.
- Enter a Lemon Squeezy test purchase license key for product `1019393`.
- Confirm the app shows the Pro plan.
- On Pro, confirm multiple boxes, templates, Calendar Feeds, backup import, session history, window layout capture/restore, and focus modes are available.
- Restart and confirm stored state loads.
- Deactivate and confirm state returns to Free.
- Enter a wrong, expired, disabled, or wrong-product key and confirm Invalid license.

## Updates

- Open Settings > Updates.
- Click Check for Updates.
- In the debug build without Sparkle linked, confirm the UI explains that Sparkle 2 and the appcast must be configured before shipping.

# Study Boxes Website Demo Data

Use `StudyBoxes-website-demo.backup.json` when capturing website screenshots and GIFs.

Recommended capture setup:

1. Create a clean app data run.
2. Activate Pro or use a debug build where backup import is available.
3. Open `Settings -> Backup and safety -> Import Backup JSON`.
4. Import `docs/showcase/StudyBoxes-website-demo.backup.json`.
5. Use these boxes for website assets:
   - `Probability P2` for the Library and pricing screenshots.
   - `Operating Systems` for the menu HUD and Study Space screenshots.
   - `Spanish B2` for a color contrast screenshot.
   - `SwiftUI Project` for Pro/focus/workspace restore screenshots.

Do not capture personal browser tabs, real file paths, private calendar URLs, license keys, or account names.

## Smooth Cursor Demo Recording

Use `scripts/run-demo-mouse.sh` to automate smooth cursor movement while you record with CleanShot X or QuickTime. The script does not start or stop recording. It only moves the pointer through a prepared route.

### One-Time Permission

If the cursor does not move, give your terminal app Accessibility permission:

1. Open `System Settings -> Privacy & Security -> Accessibility`.
2. Enable the app running the command, usually Terminal, iTerm, Xcode, or Codex.
3. Quit and reopen that terminal app if macOS still blocks movement.

### Recommended Clips

Capture short clips, then trim them. Short, specific GIFs usually look better on a sales page than one long walkthrough.

1. `idle-menu`: menu-bar first workflow. Show the quick start button and recent Study Boxes.
2. `focus-hud`: active session workflow. Show timer, current task, next task, and session actions.
3. `library`: setup/library workflow. Show saved boxes, weekly stats, and setup actions.
4. `create-box`: template workflow. Show template choice, details, appearance, and Create.

### Recording Steps

1. Open Study Boxes and prepare the exact screen you want to record.
2. Open the popover, window, or sheet for the clip.
3. Put the mouse pointer on the top-left corner of the visible popover/window/sheet. This is the route anchor.
4. Start a CleanShot X screen recording around only the relevant UI.
5. Run the matching command from the project folder.
6. Stop recording after the route finishes.
7. Trim the beginning/end, export MP4 for the website, and create a short GIF only when needed.

Commands:

```sh
cd "/Users/kogu/Documents/New project 2"

./scripts/run-demo-mouse.sh --list
./scripts/run-demo-mouse.sh focus-hud --countdown 5 --speed 0.85
./scripts/run-demo-mouse.sh idle-menu --countdown 5 --speed 0.90
./scripts/run-demo-mouse.sh library --countdown 5 --speed 0.85
./scripts/run-demo-mouse.sh create-box --countdown 5 --speed 0.85
```

Run a coordinate preview without moving the cursor:

```sh
./scripts/run-demo-mouse.sh focus-hud --dry-run
```

If anchoring is awkward, use the full screen instead:

```sh
./scripts/run-demo-mouse.sh focus-hud --anchor screen --countdown 5
```

### CleanShot X Settings

Use these defaults for app-store-style website media:

- Record at 60 fps if available.
- Show the cursor.
- Crop tightly around the app UI, with a little background margin.
- Hide desktop icons and unrelated menu bar extras where possible.
- Use the clean demo backup data only.
- Keep each final clip around 6-12 seconds.
- Prefer MP4 on the website. Use GIF only for tiny looping moments.

### Suggested Shot List

1. Hero visual: `idle-menu`, 8 seconds, menu-bar popover centered, Buy/Download page can use this as the main product proof.
2. Feature row: `focus-hud`, 10 seconds, active Probability or Operating Systems session.
3. Feature row: `create-box`, 8 seconds, template and appearance customization.
4. Feature row: `library`, 8 seconds, saved boxes and stats.

Keep the cursor path calm. The route is meant to guide the eye, not demonstrate every click.

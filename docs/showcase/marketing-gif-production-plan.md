# Study Boxes Marketing GIF Production Plan

## Goal

Turn the two CleanShot recordings into a small set of polished marketing loops for `wendeye.com`, launch posts, and short social clips. The hero story is: a student is doom-scrolling, then uses Study Boxes to start the right study setup in two clicks.

## Source Assets

- `/Users/kogu/Desktop/CleanShot 2026-05-03 at 05.01.45.mp4`
  - Use for the hero concept: YouTube distraction, menu bar icon, Study Boxes Focus HUD.
  - Keep the YouTube footage as context, but blur the actual video content enough that the viewer sees "doom-scroll" without focusing on the specific creator.
- `/Users/kogu/Desktop/CleanShot 2026-05-03 at 05.05.22.mp4`
  - Use for support clips: Library overview, Study Box detail, Create Study Box template flow, appearance/session defaults.
- `docs/showcase/StudyBoxes-website-demo.backup.json`
  - Use this clean demo data for re-records.
- `scripts/run-demo-mouse.sh`
  - Use this for smooth fake cursor movement during clean re-records.

## Product Message

Primary message:

> From doom-scrolling to studying in 2 clicks.

Supporting messages:

- Start a saved study setup from the menu bar.
- Keep each course, exam, assignment, or project separate.
- Save resources, tasks, reminders, timer, and focus settings once.
- Use focus modes when a session needs stronger boundaries.
- Local-first study data; browser tabs stay private.

## Reference Style

Use the current Mac app demo language:

- Smooth cursor movement with visible click feedback.
- Short, loopable clips instead of a long walkthrough.
- Zoom or crop toward the active UI after each click.
- Clean desktop, hidden clutter, no real private data.
- Native macOS controls should remain visible enough to signal "real Mac app".
- Prefer MP4 for the website; export GIF only where a platform requires GIF.

Avoid:

- Long captions explaining the app.
- Overly theatrical transitions.
- Showing private browser tabs, personal file paths, usernames, account names, or license data.
- Letting the YouTube content become the point of the clip.

## Deliverables

### 1. Hero: Doom Scroll To Study

Purpose: website hero, Product Hunt/social launch, top of feature page.

Story:

1. Start on YouTube Shorts or a similar scroll feed.
2. Fake cursor glides from the feed toward the Study Boxes menu bar icon.
3. Click 1 opens the Study Boxes menu.
4. Camera smoothly zooms toward the menu.
5. Click 2 starts `Operating Systems`.
6. Distraction fades, hides, or is pushed into the background.
7. Focus HUD appears with timer and current task.
8. End on a stable frame that can loop cleanly.

Recommended copy overlay:

- Frame 1: `Doom-scrolling?`
- Frame 2: `Start the right setup in 2 clicks`
- End frame: `Now studying: Operating Systems`

Editing notes:

- Keep the clip 6-9 seconds.
- Add two subtle click rings, not loud animated bursts.
- Use a 1.15x-1.35x zoom after the menu bar click.
- Blur the YouTube video area before adding zooms, cursor treatment, or copy overlays.
- If the raw clip is reused, crop away unrelated terminal/browser clutter where possible.
- Best version should be re-recorded with clean demo state and a controlled YouTube-like distraction page.

Exports:

- `hero-doom-scroll-to-study.mp4`: 1440 px wide, 30 fps, H.264, muted loop.
- `hero-doom-scroll-to-study.gif`: 900-1100 px wide, 12-15 fps, optimized palette.
- `hero-doom-scroll-to-study-square.mp4`: 1080x1080.
- `hero-doom-scroll-to-study-vertical.mp4`: 1080x1920, cursor-follow crop.

### 2. Menu Bar Launcher

Purpose: feature section near "Set it up once. Start from the menu bar."

Story:

1. Open Study Boxes from the menu bar.
2. Cursor moves to the main start button.
3. Click starts a recent Study Box.
4. Focus HUD appears or session timer starts.

Capture command:

```sh
./scripts/run-demo-mouse.sh idle-menu --countdown 5 --speed 0.90
```

Recommended copy overlay:

- `One menu bar action`
- `Your study setup opens`

Exports:

- `menu-bar-launcher.mp4`
- `menu-bar-launcher.gif`

### 3. Library Overview

Purpose: show that the app is not just a timer.

Story:

1. Show Study Boxes Library with clean demo boxes.
2. Cursor visits weekly stats.
3. Cursor visits saved boxes.
4. Cursor visits setup actions.

Capture command:

```sh
./scripts/run-demo-mouse.sh library --countdown 5 --speed 0.85
```

Recommended copy overlay:

- `Each subject gets its own box`
- `Tasks, resources, and defaults stay organized`

Exports:

- `library-overview.mp4`
- `library-overview.gif`

### 4. Create Study Box

Purpose: show onboarding/setup simplicity.

Story:

1. Open Create Study Box.
2. Cursor visits templates.
3. Cursor picks or highlights `Exam prep`, `Weekly course`, or `Coding project`.
4. Cursor moves through name, type, icon/color, session defaults.
5. End on `Create and Start`.

Capture command:

```sh
./scripts/run-demo-mouse.sh create-box --countdown 5 --speed 0.85
```

Recommended copy overlay:

- `Start from a template`
- `Customize the setup before studying`

Exports:

- `create-study-box.mp4`
- `create-study-box.gif`

### 5. Focus HUD

Purpose: show the active study experience after launch.

Story:

1. Active session HUD is open.
2. Cursor visits timer, current task, task actions, resources, and End Session.
3. Optional click on Done or Resources if the state is prepared.
4. End on timer running with the current task visible.

Capture command:

```sh
./scripts/run-demo-mouse.sh focus-hud --countdown 5 --speed 0.85
```

Recommended copy overlay:

- `Current task first`
- `Resources and focus controls stay nearby`

Exports:

- `focus-hud.mp4`
- `focus-hud.gif`

## Re-Record Workflow

1. Import clean demo data from `docs/showcase/StudyBoxes-website-demo.backup.json`.
2. Hide desktop icons and unrelated menu bar extras.
3. Use a neutral or Study Boxes-compatible wallpaper.
4. Open only the windows needed for the clip.
5. Crop tightly around the relevant app UI with 8-12 percent breathing room.
6. Enable cursor recording.
7. Enable click highlights in CleanShot X if available.
8. Place the cursor at the route anchor described in `docs/showcase/README.md`.
9. Start recording.
10. Run the matching `scripts/run-demo-mouse.sh` command.
11. Stop recording one second after the route completes.
12. Trim dead air at the beginning and end.
13. Add subtle zoom/pan if the final crop is small.
14. Export MP4 first, then GIF fallback.

## Post-Production Settings

Cursor:

- Use a large but believable macOS arrow cursor.
- Add click rings at 65-80 percent opacity.
- Use two rings in the hero clip only: menu bar icon and start button.
- Hide the cursor when it is static and not guiding attention.

Motion:

- Use ease-in-out cursor movement.
- Use 150-250 ms click pauses.
- Use 1.15x-1.35x zooms for detail moments.
- For vertical social export, use cursor-follow crop rather than shrinking the whole desktop.

Visual treatment:

- Prefer native app windows over mockups.
- Keep rounded macOS windows and shadows visible.
- Use warm dark backgrounds that match the existing Study Boxes brand.
- Keep overlay text minimal and outside important UI.

YouTube blur treatment:

- Blur only the moving video/content area, not the browser chrome, YouTube controls, or the Study Boxes UI.
- Keep enough structure visible to communicate "scroll feed" quickly.
- Use a 16-24 px Gaussian blur or equivalent.
- Add a slight dark overlay if the blurred video still pulls too much attention.
- Apply the blur before crop/zoom so the blurred region stays aligned during the edit.
- Do not blur the cursor, menu bar icon, Study Boxes menu, or Focus HUD.

GIF optimization:

```sh
ffmpeg -i input.mp4 -vf "fps=15,scale=1000:-1:flags=lanczos,palettegen" palette.png
ffmpeg -i input.mp4 -i palette.png -filter_complex "fps=15,scale=1000:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" output.gif
```

Website MP4 export:

```sh
ffmpeg -i input.mov -vf "scale=1440:-2" -r 30 -an -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow output.mp4
```

Example FFmpeg region blur for a draft hero export:

```sh
ffmpeg -i hero-raw.mp4 -filter_complex "[0:v]split[base][blur];[blur]crop=w:h:x:y,boxblur=18:2[blurred];[base][blurred]overlay=x:y" -an -c:v libx264 -pix_fmt yuv420p -crf 20 hero-blurred.mp4
```

Replace `x:y:w:h` with the YouTube video content rectangle after choosing the final crop.

## QA Checklist

- Hero shows exactly two clear clicks from distraction to focus.
- YouTube/distraction context is recognizable, blurred, and not the main subject.
- Cursor does not jitter, jump, or move too fast.
- Click rings line up with visible UI state changes.
- Text overlays do not cover app controls.
- No private data, account names, file paths, browser tabs, license keys, or personal notifications are visible.
- GIF loops without an obvious flash or hard cut.
- MP4 loops smoothly when autoplayed muted.
- Mobile crop still shows the cursor, click target, and resulting UI.
- File sizes are practical for the web page.

## Recommended Sequence

1. Build the hero clip first because it defines the launch story.
2. Build the Focus HUD clip second because it proves the result of the hero click.
3. Build Library and Create Study Box clips as supporting sections.
4. Export MP4s and test them in the website layout.
5. Create GIF fallbacks only after the MP4s feel right.

## Known Limitations

- The current YouTube clip includes unrelated content and should be treated as a draft unless cropped, blurred, or re-recorded.
- The current app walkthrough is useful, but clean re-records will look more intentional because cursor motion and click timing can be controlled.
- GIF quality will be worse than MP4 for dark UI gradients and subtle shadows; MP4 should be the primary website format.

# Adding the Widget Extension target for Live Activities

The Live Activity Swift code is already written and lives in `HyroxappWidget/`.
To finish wiring it up, the Widget Extension target needs to be created inside
Xcode (this is one of those operations where Xcode's UI is dramatically safer
than hand-editing `project.pbxproj`).

Follow these exact steps. The whole thing takes ~5 minutes.

---

## 1. Add the Widget Extension target

1. Open `Hyroxapp.xcodeproj` in Xcode.
2. **File → New → Target…**
3. Pick the **iOS** tab.
4. Search for **Widget Extension** and select it. Click **Next**.
5. Fill in:
   - **Product Name:** `HyroxappWidget`
   - **Team:** the same paid Apple Developer team as the main app
   - **Bundle Identifier:** Xcode auto-fills as
     `com.praanshuadiga.hyroxapp.HyroxappWidget` — leave that.
   - **Language:** Swift
   - **Include Live Activity:** **UNCHECK** (we provide our own)
   - **Include Configuration App Intent:** **UNCHECK**
6. Click **Finish**.
7. When Xcode prompts "Activate HyroxappWidget scheme?" → click **Activate**.

Xcode will create a `HyroxappWidget/` folder with template files
(`HyroxappWidget.swift`, `HyroxappWidgetBundle.swift`, `Info.plist`,
`AppIntent.swift`, etc.).

## 2. Replace the templated Swift files with ours

The folder we created (also named `HyroxappWidget/`) already has the two
files we need:

- `HyroxappWidgetBundle.swift` — the `@main` entry
- `RaceLiveActivity.swift` — the lock screen + Dynamic Island UI

In Xcode:

1. **Delete** the templated `HyroxappWidget.swift` (the home-screen widget
   stub) — choose **Move to Trash**. We don't ship a home-screen widget.
2. **Delete** the templated `AppIntent.swift` if present — we don't use it.
3. **Replace** the templated `HyroxappWidgetBundle.swift` with the one
   from our `HyroxappWidget/` folder. Easiest way: in Finder, drag our
   `HyroxappWidgetBundle.swift` and `RaceLiveActivity.swift` into the
   Xcode project navigator (drop them on the `HyroxappWidget` group).
   When prompted:
   - **Copy items if needed:** UNCHECK (the files already live in the
     right folder relative to the project)
   - **Added folders:** Create groups
   - **Add to targets:** **CHECK only `HyroxappWidget`** — do NOT add
     them to `Hyroxapp` (the main app)
4. If Xcode put both versions in the project, delete the templated one
   (right-click → Delete → Move to Trash).

## 3. Add `RaceActivityAttributes` to BOTH targets

This file is the contract between the main app (which starts/updates
activities) and the widget extension (which renders them). It lives in
`Hyroxapp/Shared/RaceActivityAttributes.swift`.

1. Click on `RaceActivityAttributes.swift` in the Project Navigator.
2. Open the **File Inspector** (right pane).
3. Under **Target Membership**, check **both `Hyroxapp` AND `HyroxappWidget`**.

The same file now compiles into both bundles. ActivityKit requires this — the
attributes type's identity must match between the activity-starting target and
the activity-rendering target.

## 4. Add `Theme.swift` to the widget target too

The widget views reference `Color.accent`, `Color.warning`, and
`Color.success`. Those live in `Hyroxapp/Shared/Theme.swift`.

1. Click on `Theme.swift`.
2. **File Inspector → Target Membership → check `HyroxappWidget`** (in
   addition to the existing `Hyroxapp` membership).

If the build still fails on color resolution, also add `Theme.swift` is
the only Theme — the additional Color extensions all live in that one file.

## 5. Verify the Embed App Extensions phase

When you added the Widget Extension target, Xcode automatically added an
**Embed App Extensions** build phase to the main `Hyroxapp` target. To
verify:

1. Select the **Hyroxapp** target (top of the editor when project is open).
2. Open the **Build Phases** tab.
3. You should see **Embed App Extensions** listed with `HyroxappWidget.appex`
   inside it.

If it's missing:

1. Click the **+** in the Build Phases bar → **New Copy Files Phase**.
2. Set **Destination:** `Plugins and Foundation Extensions`.
3. Click **+** in the new phase → add `HyroxappWidget.appex`.

## 6. Build and run

1. Select the **Hyroxapp** scheme (not HyroxappWidget — that's only for
   widget previewing).
2. Build for your physical iPhone (Live Activities don't show on the
   simulator's lock screen reliably).
3. Run the app, start a race.
4. Lock the phone — the race timer should appear on the lock screen.
5. On a Dynamic Island device (iPhone 14 Pro and newer), the timer also
   shows in the island. Long-press the island for the expanded view.

## Troubleshooting

- **"NSSupportsLiveActivities not in Info.plist"** at runtime: The pbxproj
  already has `INFOPLIST_KEY_NSSupportsLiveActivities = YES` — make sure
  you're building Debug or Release configuration of the iOS app, not a
  custom one.

- **"areActivitiesEnabled returns false"**: User-level toggle. Settings →
  Hyroxapp → Live Activities → on. Activities also won't fire when
  Low Power Mode is on.

- **Widget displays "Cannot find type 'Color' in scope"**: `Theme.swift`
  needs to be added to the `HyroxappWidget` target membership (Step 4).

- **Race timer shows wrong elapsed**: ContentState is updated only on
  state changes (advance / pause / resume / etc.) by design, so the budget
  isn't burned. The TICKING is rendered by SwiftUI's `Text(_:style:)`
  timer view — if that's wrong, the issue is `state.timerStart` not
  `state.frozenElapsed`. Check `currentLiveActivityState()` in
  `RaceViewModel.swift`.

- **"WCSession" or "Watch" errors during widget build**: The widget target
  doesn't need any of the Watch sync files. If Xcode auto-added them as a
  side effect of folder dragging, uncheck their `HyroxappWidget`
  membership in the File Inspector.

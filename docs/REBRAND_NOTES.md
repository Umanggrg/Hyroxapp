# Rebrand: Hyroxapp → Trakr

Captured during the rebrand pass that moved the app's brand identity from "Hyroxapp" to "Trakr" to avoid HYROX™ trademark exposure (HYROX is registered to HYROX GmbH; we have no affiliation).

## What changed

**Bundle identifiers** (pbxproj):
- iOS: `com.praanshuadiga.hyroxapp` → `com.praanshuadiga.trakr`
- Tests: `.tests` → `.trakr.tests`
- UITests: `.uitests` → `.trakr.uitests`
- Watch: `.watchkitapp` → `.trakr.watchkitapp`
- Watch's `WKCompanionAppBundleIdentifier` updated to match

**App display name** (Info.plist):
- Added `CFBundleDisplayName = Trakr` so the home-screen icon label and App Store listing show "Trakr" regardless of the internal target name `Hyroxapp`

**Usage descriptions** (Info.plist):
- All four (HealthShare, HealthUpdate, PhotoLibrary, LocalNetwork) now say "Trakr" instead of "Hyroxapp"

**User-facing wordmarks** (Swift):
- `Text("HYROXAPP")` → `Text("TRAKR")` on:
  - SettingsView About section
  - WhatsNewView header
  - RaceShareCardView footer pill
  - MonthlyRecapShareCardView footer
  - YearlyRecapShareCardView footer
  - ProfileShareCardView footer

**Onboarding copy**:
- Step title `"Welcome to HYROX"` → `"Welcome to Trakr"`
- Welcome subtitle: removed "for HYROX athletes" framing in favor of "for the modern hybrid athlete"

**Documentation**:
- `CLAUDE.md` — title and §1 reframed; new §0 captures the trademark stance explicitly
- `docs/PRIVACY.md` — every "Hyroxapp" → "Trakr"; added "not affiliated with HYROX GmbH" disclaimer at the top
- `docs/TESTFLIGHT_CHECKLIST.md` — bundle ID + brand references updated; tester invite copy reworded to drop "HYROX training companion" framing
- `Hyroxapp/PrivacyInfo.xcprivacy` and `HyroxappWatch Watch App/PrivacyInfo.xcprivacy` — comment refs updated

## What was deliberately NOT changed

**Folder + target names**: The internal Xcode target names (`Hyroxapp`, `HyroxappTests`, `HyroxappUITests`, `HyroxappWidget`, `HyroxappWatch Watch App`), file names (`HyroxappApp.swift`, `HyroxappAppDelegate.swift`), and Swift class/struct names (`HyroxappApp`, `HyroxappAppDelegate`, `HyroxappWidgetBundle`) are unchanged. These don't appear in the App Store listing or to users — they're internal scaffolding. Renaming them requires Xcode UI work (target rename, file rename, scheme update) which is fragile in pbxproj and best done in a guided session post-license-activation.

**"HYROX" used descriptively**: Kept in places where it describes the race format athletes train for (descriptive fair use, like Strava saying "5K"):
- `Text("HYROX RACE")` as the race-mode label on RaceCardView (the race format being logged)
- "HYROX simulation," "16-segment HYROX format" in code comments
- "Roxzone" terminology (HYROX-coined but widely used in the community)
- Default race title `race.name = "HYROX Race"` when no custom title set
- Privacy policy: "HYROX™ is a registered trademark of HYROX GmbH" disclaimer

The line: **branding** uses Trakr; **race-format descriptors** can use HYROX as long as we don't claim affiliation. This matches the user's explicit guidance: "We can have a racemode as Hyrox style named but everything else, lets make the changes."

## Remaining cleanup items (post-license-activation)

1. **Rename Xcode target** `Hyroxapp` → `Trakr` via Xcode's Inspector. This auto-renames the scheme, the `.app` build product name, and most internal references. Test targets and Watch target follow the same pattern.
2. **Rename folder** `Hyroxapp/` → `Trakr/` and `HyroxappWatch Watch App/` → `Trakr Watch App/`. Update `INFOPLIST_FILE` path in pbxproj.
3. **Rename Swift files** `HyroxappApp.swift` → `TrakrApp.swift`, `HyroxappAppDelegate.swift` → `TrakrAppDelegate.swift`, `HyroxappWidgetBundle.swift` → `TrakrWidgetBundle.swift`. Update class/struct names + `@main` attribute.
4. **Update comments** referencing "Hyroxapp" throughout the codebase (search-and-replace pass). Cosmetic; doesn't affect compliance.
5. **Update `Notification.Name` strings** like `"HyroxappQuickActionTriggered"` to `"TrakrQuickActionTriggered"`. Since these are internal in-process IDs, this is purely cosmetic.

None of these are gating for TestFlight upload — App Store reviewers see only `CFBundleDisplayName`, `CFBundleIdentifier`, and the user-facing UI, all of which now say Trakr.

## Why this matters

HYROX GmbH actively enforces their trademark. App names containing "HYROX" — even with prefixes/suffixes — risk Apple removing the app at HYROX's request, plus potential cease-and-desist or trademark infringement claims. Choosing a fully distinct brand ("Trakr") and using "HYROX" only as a descriptive term for the race format is the legally defensible position. The disclaimer in `docs/PRIVACY.md` and `CLAUDE.md §0` makes the relationship (or lack thereof) explicit.

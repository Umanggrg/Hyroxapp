# App Store Screenshot Plan — §31 Volt Rebrand

Capture checklist for reshooting App Store listing screenshots after the
coral → Volt lime rebrand. The existing screenshots in App Store
Connect bake the old coral chrome — they must be reshot before the
next public submission so the listing matches what users install.

This doc captures which screens to shoot, what marketing copy frames
them, and the export specs Apple requires. It's a marketing-ops
playbook, not a code task.

## Apple's required screenshot sizes

As of iOS 18 / App Store Connect today, Apple accepts a single
master size and auto-scales to the rest. The required masters are:

| Display class | Size | Used for |
| :---- | :---- | :---- |
| **iPhone 6.9"** (15 Pro Max, 16 Pro Max) | 1290 × 2796 | Primary listing image |
| **iPhone 6.5"** (older Pro Max line) | 1284 × 2778 | Legacy, derived from 6.9" |
| **iPad 13"** (M-series) | 2064 × 2752 | iPad listing — skip if no iPad-specific UI work |

Apple lets you upload up to 10 screenshots per size. We use the first
5–6 strategically; the rest get filled in over time.

## The 6 hero screenshots (in order — most-impactful first)

App Store users scroll past your first 2 screenshots in ~3 seconds.
Lead with what's unique. Save the deeper analytics for slots 4-6.

### 1. Live race coaching — the headline differentiator

**Screen to capture:** RaceView in-progress cathedral mid-race.
Show the live HR chip with HOLD or PUSH coaching cue firing, the
big timer, Pace Ghost showing "-0:08 ahead," HR zone bar lit up to
Z3-Z4. Ideally captured around station 4-5 so there's real history
behind the splits.

**Frame copy (text overlay above the screenshot):**
*"The first HYROX app that coaches you mid-race."*

**Why it's #1:** This is the moment that doesn't exist in ROXFIT,
Intervals Pro, Strava, or Apple Fitness. Lead with it.

### 2. Post-race Engine Score reveal

**Screen to capture:** RaceSummaryView or RaceDetail with the
EngineScore card visible — composite number (0-100), tier label
(Building / Steady / Elite), 4-bar sub-score breakdown.

**Frame copy:**
*"Engine Score — finally know whether your race actually got better."*

**Why #2:** Headline number every athlete will screenshot and
share. Tracks the Whoop-strain positioning.

### 3. Any-HR-source pairing — the Garmin wedge

**Screen to capture:** Settings → Devices → ExternalHRPairingSheet
mid-scan with a discovered Garmin device in the list. Make sure
the trade-off footnote is visible at the bottom of the frame.

**Frame copy:**
*"Pair Apple Watch, Garmin, Polar, Wahoo, or any Bluetooth HR
monitor."*

**Why #3:** Real TAM expansion. Every competitor assumes Apple
Watch. We don't.

### 4. HR zones bar + per-station HR analytics

**Screen to capture:** RaceDetail HR tab, showing the full-width
zone bar, HR drift chart, per-station HR boundaries (entry / end
/ recovery 30s+60s).

**Frame copy:**
*"Per-station HR. Per-run drift. The data the Watch alone can't
surface."*

**Why #4:** Convinces the data-nerd athlete (the early-adopter
profile) that Trakrr's analytics layer is deeper than the alternative.

### 5. Compromised running + run degradation

**Screen to capture:** Profile → RunDegradationTrendView OR
RaceDetail Runs tab showing the 8-run pace decline with the
compromised running insight overlay.

**Frame copy:**
*"See exactly which station hurts your next run."*

**Why #5:** A genuinely actionable coaching insight. HYROX
athletes recognize the pain immediately.

### 6. HYROX Score + Profile

**Screen to capture:** ProfileView with HYROXScore + EngineScore
trend chart + recent races visible. The "this is your athlete
identity" moment.

**Frame copy:**
*"Your HYROX identity, in one number."*

**Why #6:** Closes the loop — the user understands Trakrr isn't
just a tracker, it's a long-term performance system.

## App Store listing copy refresh

Beyond the screenshots, the listing's text fields need a Volt-era pass.

### App Store subtitle (30 chars, displays under app name)

Current: *something coral-era; refresh*
New: **`Race Smarter for HYROX`** (22 chars — under budget, focus
on the headline benefit)

### Promotional text (170 chars, can update without re-review)

> Trakrr is the HYROX-specific race tracker that coaches you in
> real time. Live HR zones, drift detection, Engine Score, and
> 8-run breakdown. Works with any Bluetooth HR monitor.

### App Store description (4000 chars)

Lead paragraph:

> Trakrr is built for HYROX athletes who train with intent. Live
> race coaching guides you mid-race with HOLD / SLOW / PUSH cues
> based on your personal HR baseline. Post-race, Engine Score and
> per-station drift analytics tell you what actually changed —
> not just whether you got faster.

Feature list bullets:

* Live race timer with always-visible coaching cues
* Engine Score (0-100) — Whoop-strain equivalent for HYROX
* Per-station HR boundaries (entry / end / 30s recovery / 60s recovery)
* Compromised Running analysis across all 8 runs
* HR drift + aerobic decoupling tracking
* Pair Apple Watch, Garmin (broadcast mode), Polar H10, Wahoo
  TICKR, HRM-Pro Plus, or any standard Bluetooth HR monitor
* Free Run mode for tracking outdoor + indoor easy runs
* Apple Watch companion with 3-page race nav
* Live Activity on the lock screen + Dynamic Island
* Auto-counted Wall Ball reps on Apple Watch
* AirPods Pro 3 running economy metrics (cadence, vertical osc.)
* HYROX Score composite — your performance identity in one number

### Keywords (100 chars total)

> hyrox,hybrid fitness,sled push,wall balls,race,heart rate,
> coaching,engine score,split,training

Trim as needed to stay under 100 char budget.

## How to actually capture the screenshots

1. **Use the iPhone 15 Pro Max simulator** (or 16 Pro Max) at
   1290 × 2796 native resolution. This is the master size Apple
   scales down from.
2. **Pre-seed test data.** Run the app on the sim, complete 6-8
   races so History is populated, the trend charts have real
   data, and Engine Score has enough history to display.
3. **Hide the simulator's status bar** with the
   `xcrun simctl status_bar` command, or use Apple's
   `SimulatorScreenshotHelper` to drop a clean status bar at
   capture time:
   ```sh
   xcrun simctl status_bar booted override --time "9:41" \
     --batteryState charged --batteryLevel 100 --wifiBars 3 \
     --cellularBars 4 --cellularMode lte
   ```
4. **Capture via** ⌘ + S in Simulator (saves to Desktop as PNG)
   or via `xcrun simctl io booted screenshot ~/Desktop/shot.png`.
5. **Add the frame copy overlay** in Figma / Sketch / Photoshop.
   Keep the device frame off — Apple wants the raw screen, not a
   device-framed marketing shot. The text overlay sits above the
   screen content within the 1290 × 2796 canvas.
6. **Upload via** App Store Connect → App Information → Media
   Assets → Screenshots.

## Marketing copy lock list

Every public surface should match this Volt-era language now that
the brand is settled:

* **App name:** Trakrr
* **Tagline:** Race smarter for HYROX
* **Pitch:** *"The first HYROX app that coaches you mid-race."*
* **Differentiator:** *"Trakrr works with Apple Watch, Garmin, Polar,
  Wahoo, or any Bluetooth heart rate monitor."*

When in doubt, lead with live coaching, then Engine Score, then
broad HR-source support, then the analytics layer.

## Companion script

`docs/generate_app_icons.py` regenerates the AppIcon PNGs from hex
values if we ever shift the brand color again. Edit the
`render_icon(bg_hex, triangle_hex, out_path)` calls in `main()` and
re-run. Drops PNGs in the cwd; copy them into
`Hyroxapp/Assets.xcassets/AppIcon.appiconset/` and the Watch +
Widget catalogs.

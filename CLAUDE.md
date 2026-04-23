# HYROX App — Project Context for Claude Code

> This document is the source of truth for what we're building and how. Read it before generating code. When in doubt, prioritize what's written here over generic best practices.

---

## 1. What We're Building

A native iOS app (with watchOS companion in a later phase) for HYROX and functional fitness athletes. Think **"Strava for HYROX"** — a competitive performance ecosystem, not a generic workout logger.

**One-line pitch:** The app HYROX athletes open before, during, and after every race to track, compete, and prove performance.

**Primary user (v0.1):** Me. I'm training for HYROX. I will use this app during my actual training sessions. If it doesn't work for me personally, nothing else matters.

**Target users (v1+):** HYROX athletes globally who currently use spreadsheets, Notes app, or Roxfit (which has poor UX).

---

## 2. Core Philosophy

### Build Principles
- **Dogfood first, scale later.** v0.1 ships to me alone. No backend, no auth, no leaderboards. Just: does this help me train?
- **Ruthless scope discipline.** The brief has 7+ pillars. MVP has 2. The rest is v2+.
- **Race Mode is the product.** Everything else is supporting cast. If Race Mode isn't excellent, nothing else matters.
- **Apple-level UX is a hard requirement, not aspiration.** No React Native, no hybrid hacks. Native Swift/SwiftUI throughout.

### Anti-Patterns to Reject
- Spreadsheet-style logging UIs
- Heavy manual input during workouts
- Generic fitness tracker vibes (no step-counter nostalgia)
- Light mode as default
- Cluttered screens with too many metrics at once

---

## 3. Tech Stack (Committed Decisions)

| Layer | Choice | Why |
|---|---|---|
| iOS app | **Swift + SwiftUI** | Native, Apple-level UX, no RN bridge pain |
| watchOS app (v2) | **SwiftUI for watchOS** | Only real option; shares code with iOS |
| Local persistence | **SwiftData** (iOS 17+) | Modern, first-party, simpler than Core Data |
| Cloud backend (v2) | **Supabase** | Solo-friendly; auth + Postgres + storage + realtime in one |
| Health integration | **HealthKit + WorkoutKit** | Required; no alternatives exist |
| Motion / sensors (v2) | **CoreMotion** | For station auto-detection on Watch |
| Min deployment target | **iOS 17.0** | SwiftData requires it; gives modern SwiftUI APIs |
| Dev environment | **Xcode + Claude Code in terminal** | Xcode for build/run/preview, Claude Code for writing |

**Rejected options (don't suggest these):**
- React Native / Expo — kills Watch experience
- Flutter — same reason
- Firebase — Supabase is better fit for Postgres-shaped data and solo workflow
- Core Data — SwiftData is the replacement, use it

---

## 4. Current Phase: v0.1 (Personal MVP)

**Goal:** A working iPhone app I can use during my own HYROX training this month.

### v0.1 Scope — BUILD THIS

1. **Race Mode (the headline feature)**
   - One-tap "Start Race" from home screen
   - Guided flow through all 8 HYROX stations in order:
     1. 1km Run
     2. Sled Push (50m)
     3. 1km Run
     4. Sled Pull (50m)
     5. 1km Run
     6. Burpee Broad Jumps (80m)
     7. 1km Run
     8. Rowing (1000m)
     9. 1km Run
     10. Farmers Carry (200m)
     11. 1km Run
     12. Sandbag Lunges (100m)
     13. 1km Run
     14. Wall Balls (75/100 reps)
   - **Note:** A real HYROX race is 8 runs + 8 workouts alternating. The station list above is correct. Total 16 segments.
   - Giant always-visible total timer
   - Single large "Next Station" button advances to next segment and logs the split
   - Minimal other interaction during a race
   - On finish: show total time + all splits

2. **Workout History (local only)**
   - List of past races, newest first
   - Tap to see splits for that race
   - Shows PB indicator if it's a new best

3. **Profile (minimal)**
   - PB total time
   - Number of races completed
   - That's it for now

### v0.1 Out of Scope — DO NOT BUILD

- ❌ User accounts / auth
- ❌ Backend / cloud sync
- ❌ Leaderboards (global, local, friends — none)
- ❌ Social feed
- ❌ Segments / micro-challenges
- ❌ Achievements / badges
- ❌ Apple Watch app
- ❌ HealthKit integration (yes, even this — waits for v1)
- ❌ AI insights
- ❌ Freeform workout logging

If I ask for any of these during v0.1, push back and remind me we're scoped to Race Mode + History + Profile.

### v1 (After v0.1 Works For Me)
- Supabase auth + cloud sync for races
- HealthKit integration (write workouts, read HR)
- Basic global leaderboard
- Polish pass on animations

### v2 (After v1 Has Real Users)
- Apple Watch app (this is a big milestone, separate planning)
- Social feed
- Segments
- Achievements
- Station auto-detection (ML)

---

## 5. Design System

### Tone
Dark, confident, athletic. Not cutesy. Not corporate. Closer to Whoop + Strava + Apple Fitness than to Nike Training Club.

### Color Palette
Use a semantic color system, defined once in an `Theme.swift` extension on `Color`:

- `Color.background` — near-black, `#0A0A0B`
- `Color.surface` — slightly lighter, `#141416`
- `Color.surfaceElevated` — `#1C1C1F`
- `Color.textPrimary` — off-white, `#F5F5F7`
- `Color.textSecondary` — `#8E8E93`
- `Color.accent` — HYROX-inspired coral/red, `#FF3B30` (adjust as we tune)
- `Color.success` — `#32D74B` (for PBs, splits beating targets)
- `Color.warning` — `#FF9F0A` (for slow splits)

**Dark mode only for v0.1.** No light mode. Don't waste time on it.

### Typography
System font (SF Pro) throughout. Hierarchy:
- **Timer display:** `.system(size: 72, weight: .bold, design: .rounded)` — monospaced digits (`.monospacedDigit()`)
- **Station name (active):** `.largeTitle.weight(.bold)`
- **Section headers:** `.title2.weight(.semibold)`
- **Body:** `.body`
- **Metadata:** `.footnote.foregroundStyle(.secondary)`

Always use `.monospacedDigit()` on numeric displays that update live — prevents jitter.

### Layout Principles
- Generous padding (24pt default screen margin)
- One primary action per screen
- Large tap targets — **minimum 60pt height** for in-race buttons (hands are sweaty, shaky, tired)
- Information hierarchy: timer > station > split > everything else

### Motion
Subtle. Spring animations for state changes, not flashy transitions. Respect `Reduce Motion` accessibility setting.

---

## 6. Critical UX Requirements (from the brief)

These are non-negotiable. Flag any generated code that violates these:

1. **Must work smoothly during workouts (low interaction).** If a flow requires more than one tap per station during a race, it's wrong.
2. **Timer must never stop, never lag, never drift.** Use a `Date`-based timer (store start time, compute elapsed on each tick), NOT an incrementing counter. Counters drift.
3. **Screen must stay awake during a race.** `UIApplication.shared.isIdleTimerDisabled = true` while race is active, restore on finish.
4. **State must survive app backgrounding.** If the user accidentally swipes home mid-race, the race state must persist and resume correctly. Store race state to SwiftData on every station transition.
5. **Button targets must be huge.** 60pt minimum, 80pt preferred for in-race actions.
6. **Typography on the race screen must be readable at arm's length, mid-sprint, in bright light.** Err on bigger.

---

## 7. Architecture Notes

### Project Structure (target)
```
HyroxApp/
├── HyroxAppApp.swift              # App entry
├── Models/
│   ├── Race.swift                 # A completed or in-progress race
│   ├── Station.swift              # Enum of the 16 segments
│   ├── Split.swift                # A single station's elapsed time
│   └── RaceState.swift            # In-progress state (for persistence)
├── Features/
│   ├── Race/
│   │   ├── RaceView.swift         # The main race screen
│   │   ├── RaceViewModel.swift    # @Observable view model
│   │   ├── RaceEngine.swift       # Pure logic: state machine, timing
│   │   └── RaceSummaryView.swift  # Post-race summary
│   ├── History/
│   │   ├── HistoryView.swift
│   │   └── RaceDetailView.swift
│   └── Profile/
│       └── ProfileView.swift
├── Shared/
│   ├── Theme.swift                # Color + font extensions
│   ├── Components/                # Reusable SwiftUI views (buttons, cards)
│   └── Extensions/
└── Resources/
    └── Assets.xcassets
```

### Keep the Race Engine Pure
`RaceEngine.swift` should be pure Swift — no SwiftUI, no SwiftData, no `@Observable`. Just a state machine that takes inputs ("start race", "advance station", "pause", "finish") and returns state. This makes it:
- Unit testable
- Reusable on watchOS later (huge deal — don't skip this)
- Easy to reason about

The `RaceViewModel` wraps the engine and bridges it to SwiftUI/SwiftData.

### Timer Implementation
Use `Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()` for UI updates. But **do not** accumulate elapsed time by adding 0.05 each tick — that drifts. Instead, store `raceStartDate: Date` and compute `Date().timeIntervalSince(raceStartDate)` on every tick. Same pattern for station splits.

### State Persistence
On every station transition:
1. Update the in-memory `RaceState`
2. Write it to SwiftData
3. If the app is killed and relaunched, on launch check for an unfinished `RaceState` and offer to resume

---

## 8. Coding Conventions

- **Swift 6 strict concurrency** — we're targeting a modern codebase, embrace it
- **`@Observable` over `ObservableObject`** — we're on iOS 17+
- **SwiftUI over UIKit** — no UIKit unless we hit a specific wall (e.g., haptics require `UIImpactFeedbackGenerator` which is fine)
- **Prefer value types (structs) over classes** unless identity matters
- **One view per file** when views are non-trivial
- **No force unwraps (`!`)** in production code paths. Use `guard let` / `if let`.
- **Naming:** verbs for functions (`startRace()`, `advanceStation()`), nouns for properties

### SwiftUI Specifics
- Compose with small subviews rather than one giant `body`
- Extract modifiers into custom `ViewModifier`s when reused 3+ times
- Use `@Environment` for things like color scheme, size class
- Previews for every non-trivial view (use `#Preview` macro)

---

## 9. About the Person Building This (Me)

- **Name:** Umang, based in Florida
- **Day job:** Deloitte Technology (agile/SAFe practices)
- **Side projects:** Zavvo Group ad work, BBSM app proposal, YouTube channel
- **iOS experience:** New to Swift and Xcode. Comfortable with web/React ecosystem.
- **HYROX:** Actively training. Will test the app during real sessions.
- **Time budget:** Evenings and weekends. Realistic ~10 hrs/week.
- **Goal:** Ship a working v0.1 I personally use in 4-6 weeks.

### What I need from Claude Code
- Teach as you build. When you use a Swift/SwiftUI feature I might not know (`@Observable`, property wrappers, modifiers), add a brief comment explaining it.
- Generate runnable code, not sketches. I want to hit ⌘R and see something work.
- When I ask for a feature, if it violates v0.1 scope, tell me and suggest we defer it.
- When there's a meaningful architectural choice, name it and recommend one — don't make me choose in a vacuum.
- If I ask for something that'll bite later (e.g., timer using a drifting counter), push back.

---

## 10. Definition of Done for v0.1

I can say v0.1 is done when all of these are true:

- [ ] I can open the app and start a race in one tap from the home screen
- [ ] The timer runs accurately for a full 90-minute race without drift
- [ ] I can advance through all 16 segments with single-tap transitions
- [ ] Splits are captured accurately for each segment
- [ ] On finish, I see a summary with total time and all splits
- [ ] The race is saved and appears in History
- [ ] If I background the app mid-race and come back, the race resumes correctly
- [ ] If the app is force-killed mid-race and relaunched, I'm offered to resume
- [ ] The Profile screen shows my PB and race count
- [ ] The app runs on my physical iPhone (not just simulator)
- [ ] I've used it during at least one real HYROX training session and it didn't fail me

When all 11 checkboxes are true, we move to v1 planning. Not before.

---

## 11. Open Questions to Revisit

These are things we haven't decided yet but will need to soon:

- Exact station distances for the "simulation" mode when I'm training at a gym without the full HYROX setup (e.g., if I don't have a sled, do I time a substitute movement?)
- How to handle the 1km runs when indoors vs outdoors (GPS only works outdoors)
- Whether the 75 vs 100 wall ball count depends on gender/division (it does in real HYROX)
- Whether to offer a "Doubles" race mode variant

Don't build for these yet — just flagging for future.

---

## 12. How to Use This Document

- **Start of every Claude Code session:** point at this file
- **When I ask for a feature:** check it against §4 scope before building
- **When designing UI:** reference §5 design system
- **When writing code:** follow §8 conventions
- **When in doubt:** ask me. Better to clarify than guess wrong.

This file is living. Update it as decisions change.

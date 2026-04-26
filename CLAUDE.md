# HYROX App — Project Context for Claude Code

> This document is the source of truth for what we're building and how. Read it before generating code. When in doubt, prioritize what's written here over generic best practices.

---

## 1. What We're Building

A native iOS app (with watchOS companion in a later phase) for HYROX and functional fitness athletes. Think **"Strava for HYROX"** — a competitive performance ecosystem AND a social network for HYROX athletes, not a generic workout logger.

**One-line pitch:** The app HYROX athletes open before, during, and after every race to track, compete, share, and prove performance.

**Primary user (v0.1):** Me. I'm training for HYROX. I will use this app during my actual training sessions. If it doesn't work for me personally, nothing else matters.

**Target users (v1+):** HYROX athletes globally who currently use spreadsheets, Notes app, or Roxfit (which has poor UX).

### The Dual Nature of This App

This is simultaneously:
1. **A performance tool** — precise, fast, low-friction during workouts
2. **A social network** — identity, feed, comparison, community post-workout

Strava nails this duality. The app is quiet and utilitarian during a run, then transforms into a social feed after. We want the same feel.

### Explicit non-goals

- **No GPS tracking.** The 1km runs are manual start/stop. HYROX is an indoor-first race format; GPS tracking would only matter for outdoor run training, and keeping it out of scope simplifies the tracking layer, battery cost, and privacy surface. Distance (when it matters) is entered manually or derived from station rules.
- **Not a generic fitness / workout logger.** Freeform lifting, yoga, running-for-running's-sake aren't the target. HYROX-shaped workouts only.

---

## 2. Core Philosophy

### Build Principles
- **Dogfood first, scale later.** v0.1 ships to me alone. No backend, no auth, no leaderboards. Just: does this help me train?
- **Ruthless scope discipline.** The brief has 7+ pillars. MVP has 2-3. The rest is v2+.
- **Race Mode is the product.** Everything else is supporting cast. If Race Mode isn't excellent, nothing else matters.
- **Apple-level UX is a hard requirement, not aspiration.** No React Native, no hybrid hacks. Native Swift/SwiftUI throughout.
- **Build UI like the social features already exist.** Even in v0.1, screens should look like they belong in a social app — because they will be one. No throwaway UI.

### Anti-Patterns to Reject
- Spreadsheet-style logging UIs
- Heavy manual input during workouts
- Generic fitness tracker vibes (no step-counter nostalgia)
- Light mode as default
- Cluttered screens with too many metrics at once
- UI that "works for now" but will need to be rebuilt when social ships

---

## 3. Tech Stack (Committed Decisions)

| Layer | Choice | Why |
|---|---|---|
| iOS app | **Swift + SwiftUI** | Native, Apple-level UX, no RN bridge pain |
| watchOS app (v2) | **SwiftUI for watchOS** | Only real option; shares code with iOS |
| Local persistence | **SwiftData** (iOS 17+) | Modern, first-party, simpler than Core Data |
| Cloud backend (v1) | **Supabase** | Solo-friendly; auth + Postgres + storage + realtime in one |
| Realtime sync (v2 Duo Mode) | **Supabase Realtime** (Postgres changes over WebSocket) | Already in the stack; no new infra needed |
| Health integration | **HealthKit + WorkoutKit** | Required; no alternatives exist |
| Motion / sensors (v2) | **CoreMotion** | For station auto-detection on Watch |
| Min deployment target | **iOS 17.0** | SwiftData requires it; gives modern SwiftUI APIs |
| Dev environment | **Xcode + Claude Code in terminal** | Xcode for build/run/preview, Claude Code for writing |

**Rejected options (don't suggest these):**
- React Native / Expo — kills Watch experience
- Flutter — same reason
- Firebase — Supabase is better fit for Postgres-shaped data and solo workflow
- Core Data — SwiftData is the replacement, use it
- WebSockets built from scratch for Duo Mode — use Supabase Realtime

---

## 4. Phased Scope

### v0.1 — Personal MVP (Current Phase)

**Goal:** A working iPhone app I can use during my own HYROX training this month.

**BUILD THIS:**

1. **Race Mode (the headline feature)**
   - One-tap "Start Race" from home screen
   - Guided flow through all HYROX stations in order:
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
   - **Note:** A real HYROX race is 8 runs + 8 workouts alternating. Total 16 segments.
   - Giant always-visible total timer
   - Single large "Next Station" button advances and logs the split
   - Minimal other interaction during a race
   - On finish: show total time + all splits

2. **Workout History (local only)**
   - Feed-style list of past races, newest first
   - Card design (foreshadowing the social feed) — each race shows as a card with total time, key stats, date
   - Tap to see splits for that race
   - PB indicator if it's a new best

3. **Profile (identity layer, minimal)**
   - PB total time
   - Number of races completed
   - Placeholder for avatar, username, bio (we'll fill in later but the layout exists)
   - Stats grid — race count, PB, avg time, total stations completed
   - Think "Strava profile page, but for one user who has no followers yet"

**DO NOT BUILD in v0.1:**
- ❌ User accounts / auth
- ❌ Backend / cloud sync
- ❌ Leaderboards (global, local, friends — none)
- ❌ Social feed (layout hints yes, actual feed no)
- ❌ Segments / micro-challenges
- ❌ Achievements / badges
- ❌ Apple Watch app
- ❌ HealthKit integration (even this — waits for v1)
- ❌ AI insights
- ❌ Freeform workout logging
- ❌ Duo Mode / partner sync
- ❌ Following / followers / friends

If I ask for any of these during v0.1, push back and remind me we're scoped to Race Mode + History + Profile.

---

### v1 — Connected & Competitive (After v0.1 Works For Me)

- Supabase auth + cloud sync for races
- User profiles become real (username, avatar upload, bio)
- HealthKit integration (write workouts, read HR)
- Basic global leaderboard
- Basic social feed (see other users' race cards, like, comment)
- Follow/unfollow users
- Polish pass on animations

### v2 — Full Social + Watch + Duo

- **Apple Watch companion** — **partially done**. Phone↔Watch bidirectional sync architecture is shipped: phone pushes `RaceStateSnapshot` on every race event via `WCSession.updateApplicationContext`; Watch renders live from it. Watch's Next Station button sends `WatchAction.advance` via `sendMessage`; iPhone receives it and advances the race. Verified end-to-end on the iPhone+Watch simulator pair. **Still open**: hold-to-finish on Watch final station, real-hardware install validated on watchOS 26+ (current free-dev-account + Apple Watch SE on watchOS 11 blocks the companion install with a generic "could not install" error, but the code is proven correct on sim). Ship once tested on newer Watch.
- **Detailed per-station race summary** (Roxfit-style) — per-station breakdown view with: this-station's split vs your PB for that station, pace curve, HR curve (see below), comparison to your last N races. Accessed by tapping any split row in History detail. Needs `SwiftCharts` framework. 2-3 sessions.
- **HealthKit read integration** — currently we only *write* races to Health. Add HR (and eventually active calories, VO2 max) *read* during a race, storing samples on each `Split`. Minimum: HKHealthStore read auth for `.heartRate`, query current HR at each station advance, display avg/max HR per split in the summary. Deeper: continuous HR sampling via `HKAnchoredObjectQuery` during the race, HR curve rendering via SwiftCharts, zone breakdowns (Z1–Z5 time in zone). ~1 session for basic capture + display, ~1 more for charts + zones.
- **Duo Mode** (see §4.5 below — real-time partner sync)
- **Custom Workout Builder** — let users define their own station sequences (shortened sessions, strength-focused days, conditioning circuits) beyond the official 16-segment race. Template save + reuse. Opens the door to the "Training Blocks" pattern from §13.2.
- **Hyrox Performance Score** — per-athlete rollup on Profile: Strength, Endurance, Engine (cardio capacity). Derived from historical station performance relative to division benchmarks. Strava's "fitness score" equivalent for HYROX.
- **Fatigue / effort insights** — post-race narrative callouts: "You slowed down 18% after Station 5," "Your HR peaks highest during lunges." Needs continuous HR sampling + comparison against prior races. Requires the HR charts work first.
- **Challenges + streaks** — time-boxed goals ("7-day HYROX streak," "improve sled push time by 10% this month"). Displayed on Profile, surfaced in the feed.
- **Manual reps / distance entry per station** — for stations where the user didn't do the full prescribed work (e.g. partial rep count due to injury, or a different sled distance at a non-standard gym). Logs what actually happened, not just what was prescribed.
- **Voice / haptic cues on station transitions** — "Next: Sled Push" announced via TTS or audio ping, plus distinct haptic patterns per station category (run vs. heavy workout vs. cardio). Matters most on Watch where the screen isn't always visible.
- **Shareable workout cards** — Instagram-story-ready visual of a completed race. Clean typography, hero time, key stats, branded. One-tap share from summary.
- Segments / micro-challenges (fastest sled push, etc.)
- Achievements / badges
- Station auto-detection (ML)
- Richer social feed (photos, comments threads, mentions)

---

### 4.5 — Duo Mode Specification (v2 Feature, Design Intent Only for v0.1)

HYROX has an official **Doubles** format where two athletes complete the race together, splitting work at each workout station. This app will support this natively.

**Core concept:** Two users' phones (or Watches) are paired for a single race. The timer is synchronized across both devices. Both users can advance stations. Splits and total time are attributed to the pair.

**User flow (planned):**
1. User A starts a race, selects "Duo"
2. User A is shown a shareable code or QR
3. User B opens app, taps "Join Duo," enters code
4. Both devices show a "Waiting for partner" confirmation screen
5. Either user taps "Start" — timer begins synchronized on both devices
6. Either user can tap "Next Station" — advancement propagates to both devices in realtime
7. Race finishes, summary shows on both devices identically, saves to both accounts

**Technical approach (preliminary, don't build yet):**
- Use **Supabase Realtime** (Postgres CDC over WebSocket)
- A `duo_race` row in Postgres with fields for `start_time`, `current_station`, `splits[]`, `status`
- Both clients subscribe to changes on that row
- Either client can write `advance_station` events; server updates `current_station`; both clients receive the update
- Use server-authoritative timing (`start_time` is stored server-side on race start; clients compute elapsed from that) — this avoids clock drift between devices

**Hard edge cases to solve before shipping Duo Mode:**
- One partner loses connection mid-race — what happens? (probably: local timer continues, sync resumes when reconnected, conflicts resolved by server timestamp order)
- One partner's battery dies — other can finish solo, race saves to both with note
- Both partners tap "Next Station" within milliseconds — server de-duplicates
- Disagreement on when to advance — tie goes to the earlier tap

**For v0.1 only:** Do NOT implement any of this. But when designing the Race Mode UI, leave room for a "Solo / Duo" toggle on the start screen. Grey it out for now with a "Coming soon" label. This forces us to design the pattern even if we don't wire it up.

---

## 5. Design System (Strava-Inspired)

### Tone
Dark, confident, athletic, social. The feel we're going for is **Strava's dark mode meets Whoop's data density meets Apple Fitness' typography.** Not cutesy. Not corporate. Not "bro science" either — clean, earned confidence.

### Reference Apps (Study These)
- **Strava** — feed layout, segment leaderboards, activity cards, profile page structure, kudos/comment patterns
- **Apple Fitness** — ring animations, workout summary cards, typography scale
- **Whoop** — dense data visualization on dark backgrounds, recovery/strain scoring
- **Gentler Streak** — soft, confident tone for a fitness social app

Study how Strava structures:
- Activity cards (hero stat, supporting stats, social actions pinned to bottom)
- The post-activity summary screen (map-sized hero, splits below)
- Segment leaderboards (position, name, time, gap to leader)
- Profile pages (avatar + name + follow count top, stats grid middle, recent activities bottom)

We will borrow these patterns liberally.

### Color Palette
Defined once in a `Theme.swift` extension on `Color`:

- `Color.background` — near-black, `#0A0A0B`
- `Color.surface` — slightly lighter (cards), `#141416`
- `Color.surfaceElevated` — `#1C1C1F`
- `Color.textPrimary` — off-white, `#F5F5F7`
- `Color.textSecondary` — `#8E8E93`
- `Color.textTertiary` — `#636366`
- `Color.accent` — HYROX-inspired coral/red, `#FF3B30`
- `Color.accentDim` — muted accent for secondary actions, `#FF3B30` at 60% opacity
- `Color.success` — `#32D74B` (PBs, splits beating targets, positive deltas)
- `Color.warning` — `#FF9F0A` (slow splits, negative deltas)
- `Color.divider` — `#2C2C2E` (hairline borders, card separators)

**Dark mode only for v0.1.** No light mode.

### Typography
System font (SF Pro) throughout. Hierarchy:
- **Timer display:** `.system(size: 72, weight: .bold, design: .rounded)` — monospaced digits (`.monospacedDigit()`)
- **Hero stat on cards (e.g., total time):** `.system(size: 44, weight: .bold, design: .rounded)` — monospaced
- **Station name (active):** `.largeTitle.weight(.bold)`
- **Section headers:** `.title2.weight(.semibold)`
- **Card title (e.g., race name):** `.headline`
- **Body:** `.body`
- **Metadata (date, location, splits labels):** `.footnote.foregroundStyle(.secondary)`
- **Caps labels (section headers inside cards, Strava-style):** `.caption2.weight(.bold).tracking(0.5).textCase(.uppercase)`

Always use `.monospacedDigit()` on numeric displays that update live or that compare across rows (leaderboards, split tables) — prevents jitter and misalignment.

### Layout Principles
- Generous padding (24pt default screen margin, 16pt inside cards)
- **Cards are the primary UI unit** — think Strava's activity cards. Rounded (12pt radius), `Color.surface` background, subtle shadow only if elevated
- One primary action per screen
- Large tap targets — **minimum 60pt height** for in-race buttons (sweaty, shaky hands). 44pt minimum elsewhere.
- Information hierarchy: hero stat > supporting stats > metadata > social actions

### Card Anatomy (Strava-inspired, core pattern)
Every race in History, every item in the future feed, follows this shape:

```
┌────────────────────────────────────┐
│ [avatar] Username · 2h ago         │  ← header
│                                    │
│ HYROX Race                         │  ← title
│                                    │
│  1:14:32                           │  ← hero stat (large, monospaced)
│  Total Time                        │
│                                    │
│ ┌──────┬──────┬──────┐             │
│ │ 5:42 │ 3:21 │ 12m  │             │  ← supporting stats (3-up grid)
│ │ Best │ Wall │ Dist │             │
│ │ Run  │ Ball │      │             │
│ └──────┴──────┴──────┘             │
│                                    │
│ 🏆 New PB                          │  ← badges (inline)
│                                    │
│ ─────────────────────────────────  │
│ ♥ 12  💬 3  📤                    │  ← social actions (v1+; hidden in v0.1)
└────────────────────────────────────┘
```

In v0.1, the social actions row is absent. In v1+, it appears. But the rest of the card is identical — which means the v0.1 History cards become feed cards in v1 with almost no rework.

### Motion
Subtle. Spring animations for state changes (`.spring(response: 0.4, dampingFraction: 0.8)`). Respect `Reduce Motion` accessibility setting. No bouncy, playful, Duolingo-style motion.

---

## 6. Critical UX Requirements (from the brief)

These are non-negotiable. Flag any generated code that violates these:

1. **Must work smoothly during workouts (low interaction).** If a flow requires more than one tap per station during a race, it's wrong.
2. **Timer must never stop, never lag, never drift.** Use a `Date`-based timer (store start time, compute elapsed on each tick), NOT an incrementing counter. Counters drift.
3. **Screen must stay awake during a race.** `UIApplication.shared.isIdleTimerDisabled = true` while race is active, restore on finish.
4. **State must survive app backgrounding.** If the user accidentally swipes home mid-race, the race state must persist and resume correctly. Store race state to SwiftData on every station transition.
5. **Button targets must be huge.** 60pt minimum, 80pt preferred for in-race actions.
6. **Typography on the race screen must be readable at arm's length, mid-sprint, in bright light.** Err on bigger.
7. **Social UI must not leak into performance UI.** During a race, no kudos, no notifications, no badges popping up. The race screen is a cathedral — silent and focused. Social appears in History, Profile, and (future) Feed.

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
│   ├── RaceMode.swift             # Enum: .solo, .duo (duo disabled in v0.1)
│   └── RaceState.swift            # In-progress state (for persistence)
├── Features/
│   ├── Race/
│   │   ├── RaceView.swift         # The main race screen
│   │   ├── RaceViewModel.swift    # @Observable view model
│   │   ├── RaceEngine.swift       # Pure logic: state machine, timing
│   │   ├── RaceStartView.swift    # Pre-race screen with Solo/Duo toggle
│   │   └── RaceSummaryView.swift  # Post-race summary
│   ├── History/
│   │   ├── HistoryView.swift      # Feed-style list of past races
│   │   ├── RaceCardView.swift     # The Strava-style card (reused in feed later)
│   │   └── RaceDetailView.swift
│   └── Profile/
│       ├── ProfileView.swift
│       ├── ProfileHeaderView.swift
│       └── StatsGridView.swift
├── Shared/
│   ├── Theme.swift                # Color + font extensions
│   ├── Components/                # Reusable SwiftUI views (buttons, cards, stat tiles)
│   └── Extensions/
└── Resources/
    └── Assets.xcassets
```

### Keep the Race Engine Pure
`RaceEngine.swift` is pure Swift — no SwiftUI, no SwiftData, no `@Observable`. Just a state machine that takes inputs ("start race", "advance station", "pause", "finish") and returns state. This makes it:
- Unit testable
- Reusable on watchOS later
- **Reusable for Duo Mode later** — the engine doesn't care if advancement came from this device or a partner's device
- Easy to reason about

The `RaceViewModel` wraps the engine and bridges it to SwiftUI/SwiftData.

### Build Reusable Components Early
`RaceCardView` in particular — this is the card that lives in History in v0.1 and becomes the feed card in v1. Design it to accept props: `race`, `showSocialActions: Bool` (defaulting to false in v0.1, true in v1 feed). Same component, flagged behavior.

Same for `StatTile`, `StatGrid`, `SectionHeader` — build them as reusable components in `Shared/Components/` from the start.

### Timer Implementation
Use `Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()` for UI updates. But **do not** accumulate elapsed time by adding 0.05 each tick — that drifts. Instead, store `raceStartDate: Date` and compute `Date().timeIntervalSince(raceStartDate)` on every tick. Same pattern for station splits.

### State Persistence
On every station transition:
1. Update the in-memory `RaceState`
2. Write it to SwiftData
3. If the app is killed and relaunched, on launch check for an unfinished `RaceState` and offer to resume

### Duo Mode Architecture (v2 — do NOT build in v0.1)
When we get there, the pattern is:
- `RaceEngine` stays local, unchanged
- A `DuoSyncService` wraps it, subscribing to Supabase Realtime changes and pushing local state changes up
- The ViewModel doesn't know if it's solo or duo — the engine is the same, only the input source differs
- This is only possible because we kept the engine pure from day one. Do not skip that.

---

## 8. Coding Conventions

- **Swift 6 strict concurrency** — we're targeting a modern codebase, embrace it
- **`@Observable` over `ObservableObject`** — we're on iOS 17+
- **SwiftUI over UIKit** — no UIKit unless we hit a specific wall (haptics via `UIImpactFeedbackGenerator` is fine)
- **Prefer value types (structs) over classes** unless identity matters
- **One view per file** when views are non-trivial
- **No force unwraps (`!`)** in production code paths. Use `guard let` / `if let`.
- **Naming:** verbs for functions (`startRace()`, `advanceStation()`), nouns for properties

### SwiftUI Specifics
- Compose with small subviews rather than one giant `body`
- Extract modifiers into custom `ViewModifier`s when reused 3+ times
- Use `@Environment` for things like color scheme, size class
- Previews for every non-trivial view (use `#Preview` macro)
- Build reusable components (`RaceCardView`, `StatTile`) generically from day one — they'll be reused across History, Profile, and future Feed

---

## 9. About the Person Building This (Me)

- **Name:** Umang, based in Florida
- **Day job:** Deloitte Technology (agile/SAFe practices)
- **Side projects:** Zavvo Group ad work, BBSM app proposal, YouTube channel
- **iOS experience:** New to Swift and Xcode. Comfortable with web/React ecosystem.
- **HYROX:** Actively training, including Doubles format. Will test the app during real sessions.
- **Time budget:** Evenings and weekends. Realistic ~10 hrs/week.
- **Goal:** Ship a working v0.1 I personally use in 4-6 weeks.

### What I need from Claude Code
- Teach as you build. When you use a Swift/SwiftUI feature I might not know (`@Observable`, property wrappers, modifiers), add a brief comment explaining it.
- Generate runnable code, not sketches. I want to hit ⌘R and see something work.
- When I ask for a feature, if it violates v0.1 scope, tell me and suggest we defer it.
- When there's a meaningful architectural choice, name it and recommend one — don't make me choose in a vacuum.
- If I ask for something that'll bite later (e.g., timer using a drifting counter, or a UI that won't extend to the social feed), push back.

---

## 10. Definition of Done for v0.1

v0.1 is done when all of these are true:

- [ ] I can open the app and start a race in one tap from the home screen
- [ ] A "Duo" option exists on the start screen but is greyed out with "Coming soon"
- [ ] The timer runs accurately for a full 90-minute race without drift
- [ ] I can advance through all 16 segments with single-tap transitions
- [ ] Splits are captured accurately for each segment
- [ ] On finish, I see a summary with total time and all splits
- [ ] The race is saved and appears in History as a Strava-style card
- [ ] The History screen feels like a social feed (just with only my activity in it)
- [ ] If I background the app mid-race and come back, the race resumes correctly
- [ ] If the app is force-killed mid-race and relaunched, I'm offered to resume
- [ ] The Profile screen shows my PB, race count, and a stats grid
- [ ] The app runs on my physical iPhone (not just simulator)
- [ ] I've used it during at least one real HYROX training session and it didn't fail me

When all checkboxes are true, we move to v1 planning. Not before.

---

## 11. Open Questions to Revisit

Things we haven't decided yet but will need to soon:

- Exact station distances for the "simulation" mode when training at a gym without the full HYROX setup (e.g., if I don't have a sled, do I time a substitute movement?) — partially addressed by the **Custom Workout Builder** roadmap item in §4 v2.
- ~~How to handle the 1km runs when indoors vs outdoors (GPS only works outdoors)~~ — **resolved**: no GPS at all (see §1 non-goals). All runs are manual start/stop regardless of indoor/outdoor. The athlete controls the timer, not a location sensor.
- ~~Whether the 75 vs 100 wall ball count depends on gender/division~~ — **resolved**: `Division` setting on `UserProfile`, `Station.target(for:)` renders the correct count.
- For Duo Mode: does each partner get credited with the full race, or does the UI distinguish who did which work?
- For social feed: is it chronological, algorithmic, or filterable (friends / local / global)?
- Privacy: can a user set races to private? Per-race or global default?
- Near-term iPhone-only slice: **race notes** ("how did this feel?" text field on `RaceSummaryView`, editable later in `RaceDetailView`, persisted on `Race.notes`). ~30 min, ungated by anything.
- Tooling constraint: Apple Watch companion install on **free-tier dev account + older Watch hardware (Apple Watch SE on watchOS 11)** consistently fails with a generic "could not install at this time" error even with correct Embed Watch Content build phase. Code is proven correct on the iPhone+Watch simulator pair. Re-test on watchOS 26+ hardware when available (friend's device or newer personal Watch) before concluding the companion ships. Paid Apple Developer Program ($99/yr) likely also resolves it.

Don't build for these yet — just flagging.

---

## 12. How to Use This Document

- **Start of every Claude Code session:** point at this file
- **When I ask for a feature:** check it against §4 scope before building
- **When designing UI:** reference §5 design system, specifically the Strava-inspired patterns
- **When building reusable components:** remember they need to extend to v1/v2 features (social feed, Duo Mode) without rework
- **When writing code:** follow §8 conventions
- **When in doubt:** ask me. Better to clarify than guess wrong.

This file is living. Update it as decisions change.

---

## 13. Vision / Feature Backlog

A structured dump of the bigger product vision — Strava × HYROX, station-based, no GPS, real-time effort + HR, social + competitive. This section is an **idea pool**, not a commitment. Items promote into §4 phased scope when we decide to ship them; until then they live here as reference for design decisions (e.g. "does today's change leave room for future challenges / streaks?").

Status legend for each bullet below:
- 🟢 **done** — in the current build, usable today
- 🟡 **partial** — architecture in place, more work needed
- ⚪ **idea** — not started

### 13.1 — Workout tracking (Watch + iPhone)

The athlete's primary in-session experience.

- 🟢 Start a HYROX workout session (Race Mode) from home screen in one tap
- 🟢 Pre-loaded official HYROX stations (16 segments, race order)
- 🟢 Time per station (split capture)
- 🟢 Tap to move to next station
- 🟢 Always-visible total timer + segment timer
- 🟢 Mid-race splits peek (view completed splits without leaving race)
- 🟢 Hold-to-finish on final station (safety against mis-tap)
- 🟢 Screen stays awake mid-race
- 🟢 Resume after force-kill / backgrounding
- 🟢 Watch companion: phone↔watch live sync (architecture shipped, install on watchOS 26+ TBD)
- 🟢 Heart rate tracking: avg + max per station via HKStatisticsQuery, live HR display mid-race, HR curve chart, zone breakdowns — full stack shipped
- 🟢 Live HR zone chip on RaceView — current zone classification visible mid-race
- 🟢 **Roxzone (transition) tracking** — opt-in two-step advance (end segment → in-roxzone overlay → start next), per-split `roxzoneSeconds` capture, total + average displayed on summary/detail, discipline insight (≤10s tight / ≤20s solid / >20s actionable). HYROX-specific differentiator — every second outside a station counts on race day.
- 🟢 **Live Activities scaffolding** — RaceActivityAttributes + LiveActivityService + widget Swift files all shipped. Pending: Widget Extension target via Xcode UI (see `docs/LIVE_ACTIVITY_SETUP.md`).
- ⚪ **1km Run with manual start/stop** — explicit "Start Run" / "End Run" on the run segments specifically (rather than treating them as generic stations), so athletes can pre-position themselves before starting the timer. Same pattern as Strava's explicit run start.
- 🟢 **Calories burned per station** — HealthKit `.activeEnergyBurned` statistics query alongside HR stats
- ⚪ **Effort level / derived intensity score** — per station + full race rollup. Function of HR (relative to max), station duration, and division benchmark.
- 🟢 **Manual reps / distance / weight input** — `weightKg`, `repsCompleted`, `rpe` per Split. Tap any split row on summary/detail to edit via StationStatsSheet. Powers race-readiness check + race-day weight projection.
- 🟢 **Race-day weight projection** — when training at sub-race weight, linear extrapolation projects the same effort to official HYROX weight (`split.duration × raceWeight / loggedWeight`). Surfaced on StationDetailView hero. Coaching honesty signal.
- 🟢 **Voice / haptic cues on station transitions** — VoiceCueService announces "Next: Sled Push," HR-zone entries also voiced. Toggleable in Settings.
- 🟡 **Auto-timer between transitions** — partial via roxzone tracking (transitions are timed). True rest-interval countdown for training (not race simulation) still TBD.
- 🟢 **Pace indicator mid-race** — real-time "ahead / on pace / behind" chip on RaceView based on naïve split of `targetDuration`. Tier 1 (naïve split) shipped. Tier 2 (benchmarked split using community/division data) pending backend.

  Original two-tier framing kept here for context:
  1. **Naïve split of target** — divide `targetDuration` across the 16 stations, either evenly or weighted by station type (runs get a bigger allotment than sled push). Ships as soon as we commit — no backend required.
  2. **Benchmarked split** (v2+/v3, depends on §13.4 backend + community data) — once Supabase stores enough race history, derive per-station expected times from aggregated splits across the athlete's division. "You're 12 seconds off the average Men's Open athlete on this station." Much more motivating than a flat 1/16th-of-target split.

  Visual sketch: small chevron/arrow on the race screen — green up for ahead, amber flat for on-pace, red down for behind — with a compact `+0:12` / `on pace` / `−0:18` delta vs. expected for the current station. Dependencies: target finish time (shipped), HR/effort capture (in progress), backend historical splits (not started).

### 13.2 — Structured workout modes

Different container types for "do a workout with this app."

- 🟢 **Full HYROX Simulation** (Race Mode) — the 16-segment official format
- 🟢 **Custom Workout Builder** — user-defined station sequences, save as templates, reuse via WorkoutTemplatePickerSheet. Opens the door to half-rox sessions, strength-focused days, any arbitrary subset.
- 🟢 **Training Blocks** — seeded `WorkoutTemplate` rows on first launch cover Strength / Conditioning / Hybrid presets. Picker is part of RaceStartView's Custom flow.
- 🟢 **Race naming + photos** — every race gets an editable title and an optional photo (banner on RaceCardView, hero on share cards, shows up in RaceGalleryView).
- 🟢 **Target finish time per race** — H/M/S wheel picker on RaceStartView, drives pace chip + summary/detail outcome callouts.

### 13.3 — Post-workout analytics

What the athlete sees after tapping Finish.

- 🟢 Race summary with total time + all 16 splits
- 🟢 Race saved to History as a card
- 🟢 PB indicator on cards when a race sets a new PB
- 🟢 Per-race notes ("how did this feel?") — editable from summary + history retroactively
- 🟢 HR per split (avg + max), curve chart, zone breakdowns, station-level comparison — full HR analytics stack shipped
- 🟢 **Detailed per-station breakdown** (Roxfit-style): StationDetailView pushed from any split row — trend chart over all attempts, PB highlight, physiology tiles (avg/max HR, calories), race-day weight projection callout when training under race weight
- 🟢 **Heart rate zones graph** — Z1–Z5 time-in-zone via HRZonesView, integrated into RaceDetailView
- 🟢 **Fatigue curve** — RunFatigueChartView shows back-half slowdown across the 8 runs, surfaces fatigue insight automatically
- 🟢 **Narrative insights** — InsightGenerator pumps PB count, HR peak, compromised running, roxzone discipline, run fatigue into RaceInsightsView. Shown on summary + detail.
- 🟢 **Compromised running analysis** — detects which station hurt the next run most ("Sled Pull cost you — Run 6 was 22% slower"). Cross-race aggregation on Profile.
- 🟢 **Engine impact view** — Profile-level rollup showing which stations consistently compromise the engine.
- ⚪ **Recovery score** — post-workout strain estimate (Whoop-style)
- 🟢 **PBs per station** — StationPersonalBestsView lists best splits per station, surfaced on Profile.
- 🟢 **Weekly / monthly / yearly performance trends** — PerformanceTrendsView, MonthlyRecap, YearlyRecap with shareable cards.
- 🟢 **Performance overload chart** — PerformanceOverloadView surfaces volume + intensity trend on Profile.
- 🟢 **Race comparison view** — side-by-side split tables between two of your own races (HistoryView toolbar).
- 🟢 **Training calendar heatmap** — month-grid on Profile showing race density.
- ⚪ **Fatigue vs performance correlation** — scatter-plot style "when my resting HR is higher, my total race time is X% slower"

### 13.4 — HYROX-specific performance system

The thing that makes this *not* a generic workout logger.

- ⚪ **Station scoring** — each station gets its own score relative to division benchmarks (percentile, or a 0–100 rating)
- 🟢 **HYROX Performance Score** — HyroxPerformanceScoreView on Profile shows the 3-pillar rollup (Strength / Endurance / Engine) using `pillarTheoreticalBest` over historical splits. Updates after every finished race.
- 🟢 **Race-readiness check** — Profile-level diagnostic: is the athlete training at race weights? Driven by `weightKg` + `Division.raceWeight(for:)`.
- 🟢 **Race event countdown** — RaceEvent SwiftData model + ProfileView banner shows "T-N days to your next race." Editable via RaceEventEditSheet.
- ⚪ **Benchmarking** — compare against:
  - Yourself (historical rolling averages)
  - Other users on the platform
  - Division averages (men's/women's × open/pro)
  - (Eventually) official HYROX event times from past races

  Powers the "benchmarked split" tier of the pace indicator in §13.1 — once we can say "the average Men's Open athlete finishes Sled Push in 3:45," the mid-race pace readout stops being an arbitrary 1/16th-of-target and starts being genuinely informative.
- ⚪ **Strain / readiness** — daily check-in using HR variability + sleep data (HealthKit) to tell the athlete if today's a good day for a full simulation vs. a lighter session

### 13.5 — Social layer (Strava-style)

How athletes see each other's work and stay accountable.

- 🟡 Card design foreshadows social feed (RaceCardView structured for future kudos/comments row)
- 🟡 Profile screen (real identity, handle, avatar, bio, social stats placeholders)
- 🟢 **Profile share card** — ProfileShareCardView + share toolbar item exports a branded portrait of the athlete's identity + key stats.
- ⚪ **Feed** — timeline of followed athletes' completed races, auto-posted on finish (opt-in), scrollable RaceCardView with kudos + comments
- ⚪ **Follow / unfollow** — relationship graph, displayed as counts on Profile, drives feed filtering
- ⚪ **Comments** — threaded comments per race, mentions (@athlete)
- ⚪ **Kudos** (Strava's "like" equivalent) — one-tap positive reaction
- 🟢 **Compare own workouts** — RaceComparisonView for side-by-side splits across two of your races. Two-athlete comparison still pending backend.
- 🟢 **Share to Instagram** — RaceShareCardView in both square and 9:16 story formats, ImageRenderer-backed export, format-picker Menu on summary + detail.
- 🟢 **Stories-style recap** — MonthlyRecapView + YearlyRecapView with shareable card variants.
- 🟢 **Race photo gallery** — RaceGalleryView grid of every race that carries a photo.

### 13.6 — Competition + gamification

Structured reasons to keep coming back.

- ⚪ **Leaderboards**:
  - Fastest full HYROX simulation (global, friends, division)
  - Best per-station times (fastest sled push, lowest wall ball time, etc.)
  - Weekly rankings (best race this week)
  Pending backend.
- ⚪ **Challenges** — time-boxed goals the athlete opts into:
  - "7-day HYROX streak" — do something each day
  - "Improve sled push time by 10% this month"
  - "Complete 4 full simulations in 4 weeks"
- 🟢 **Streak tracking** — RaceStreaks helper + StreakBannerView on Profile (current streak, longest streak, days since last race).
- 🟢 **Badges** — Badge enum + BadgeAwarder + BadgesView on Profile. Covers first simulation, elite tiers, consistency streaks.
- ⚪ **Segments / micro-challenges** — like Strava segments but per-station; compete for the fastest Sled Pull within a gym / region / globally
- 🟢 **Quick Actions (3D Touch / long-press home icon)** — "Start Race" shortcut registered, deep-linked into RaceView.
- 🟢 **Local notifications** — opt-in nudges for streak protection, race-event countdown reminders. Settings toggle + scheduling on app launch / race finish.
- 🟢 **Onboarding wizard** — first-launch flow capturing handle, division, max HR. `hasCompletedOnboarding` gate on UserProfile.

### 13.7 — Inspiration + non-negotiables

- **Reference apps**: Strava (feed, segments, kudos), Roxfit (race format, station detail), Whoop (strain/recovery scoring), Apple Fitness (ring animations, summary typography)
- **Strict no-GPS** — runs are manual start/stop (see §1 non-goals)
- **Indoor-first** — HYROX is an indoor race; the app should work on a treadmill or in a garage gym just as well as outdoors
- **Watch is first-class** — for mid-workout interaction, the wrist beats the phone. Architecture already reflects this.

### 13.8 — How items move from §13 into §4

When we commit to building something from this list:
1. Pick a specific item and give it an estimate (sessions of work)
2. Slot it into v1 / v2 / v3 in §4 with a brief scope note
3. Update its status here to 🟡 while in progress, 🟢 when shipped

Don't let §13 grow unchecked — if an idea has been here 6+ months without moving, either commit or prune.

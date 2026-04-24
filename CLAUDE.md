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

- Exact station distances for the "simulation" mode when training at a gym without the full HYROX setup (e.g., if I don't have a sled, do I time a substitute movement?)
- How to handle the 1km runs when indoors vs outdoors (GPS only works outdoors)
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

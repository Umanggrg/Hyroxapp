# Trakrr — Project Context for Claude Code

This document is the source of truth for what we're building and how. Read it before generating code. When in doubt, prioritize what's written here over generic best practices.

---

## 0\. Naming \+ trademark

**Product name:** Trakrr. The app's brand identity is "Trakrr" — that's what users see on the home screen, in App Store listings, and in marketing.

**HYROX™** is a registered trademark of HYROX GmbH and we have no affiliation with them. We use "HYROX" only descriptively — to refer to the race format athletes train for, the way a running app might say "5K" or a cycling app might say "criterium." Specifically:

- ✅ OK: "HYROX-style race format," "Race a HYROX simulation," labeling the 16-station race mode as "HYROX Race" inside the app, naming the canonical 16-segment sequence after how the sport names it.  
- ❌ Not OK: Calling our product "HYROXAPP" or anything that implies we ARE HYROX or are endorsed by them. The app's wordmark, App Store name, marketing copy, and bundle ID say "Trakrr" — never "HYROXAPP" / "HyroxApp."

This matters because pre-paid-developer-account the project was named "Hyroxapp" — internal target/folder names still carry that legacy. Those don't appear in the App Store listing or to users, but should be cleaned up via Xcode UI in a future pass for consistency.

---

## 1\. What We're Building

Trakrr is a native iOS app (with watchOS companion) for hybrid-fitness racers — athletes who train for HYROX-style 16-station events, plus custom workouts, plus their own intervals. Think **"Strava for hybrid fitness"** — a competitive performance ecosystem AND a social network for race-format athletes, not a generic workout logger.

**One-line pitch:** Trakrr is the app racers open before, during, and after every session to track, compete, share, and prove performance.

**Primary user (v0.1):** Me. I'm training for HYROX. I will use this app during my actual training sessions. If it doesn't work for me personally, nothing else matters.

**Target users (v1+):** HYROX athletes globally who currently use spreadsheets, Notes app, or Roxfit (which has poor UX).

### The Dual Nature of This App

This is simultaneously:

1. **A performance tool** — precise, fast, low-friction during workouts  
2. **A social network** — identity, feed, comparison, community post-workout

Strava nails this duality. The app is quiet and utilitarian during a run, then transforms into a social feed after. We want the same feel.

### Explicit non-goals

- **No GPS tracking — for HYROX races.** The 1km runs inside a HYROX race are manual start/stop. HYROX is an indoor-first race format; GPS would add no signal there. Distance for HYROX (when it matters) is entered manually or derived from station rules. **Exception:** the *Free Run* mode (a deliberately separate flow from Race Mode) uses opt-in GPS for outdoor runs and pedometer-only for indoor. Free Run does not pollute HYROX-shaped analytics — it's a parallel surface for athletes who want to track their easy runs without reaching for Strava.
- **Not a generic fitness / workout logger.** Freeform lifting, yoga, calisthenics, etc. aren't the target. HYROX-shaped workouts plus the single Free Run exception above. We are not trying to be Strava — Free Run intentionally has no map, no segments, no kudos; just distance, pace, splits, HR.

---

## 2\. Core Philosophy

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

## 3\. Tech Stack (Committed Decisions)

| Layer | Choice | Why |
| :---- | :---- | :---- |
| iOS app | **Swift \+ SwiftUI** | Native, Apple-level UX, no RN bridge pain |
| watchOS app (v2) | **SwiftUI for watchOS** | Only real option; shares code with iOS |
| Local persistence | **SwiftData** (iOS 17+) | Modern, first-party, simpler than Core Data |
| Cloud backend (v1) | **Supabase** | Solo-friendly; auth \+ Postgres \+ storage \+ realtime in one |
| Realtime sync (v2 Duo Mode) | **Supabase Realtime** (Postgres changes over WebSocket) | Already in the stack; no new infra needed |
| Health integration | **HealthKit \+ WorkoutKit** | Required; no alternatives exist |
| Motion / sensors (v2) | **CoreMotion** | For station auto-detection on Watch |
| Min deployment target | **iOS 17.0** | SwiftData requires it; gives modern SwiftUI APIs |
| Dev environment | **Xcode \+ Claude Code in terminal** | Xcode for build/run/preview, Claude Code for writing |

**Rejected options (don't suggest these):**

- React Native / Expo — kills Watch experience  
- Flutter — same reason  
- Firebase — Supabase is better fit for Postgres-shaped data and solo workflow  
- Core Data — SwiftData is the replacement, use it  
- WebSockets built from scratch for Duo Mode — use Supabase Realtime

---

## 4\. Phased Scope

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
   - **Note:** A real HYROX race is 8 runs \+ 8 workouts alternating. Total 16 segments.  
   - Giant always-visible total timer  
   - Single large "Next Station" button advances and logs the split  
   - Minimal other interaction during a race  
   - On finish: show total time \+ all splits

   

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

If I ask for any of these during v0.1, push back and remind me we're scoped to Race Mode \+ History \+ Profile.

---

### v1 — Connected & Competitive (After v0.1 Works For Me)

- Supabase auth \+ cloud sync for races  
- User profiles become real (username, avatar upload, bio)  
- HealthKit integration (write workouts, read HR)  
- Basic global leaderboard  
- Basic social feed (see other users' race cards, like, comment)  
- Follow/unfollow users  
- Polish pass on animations

### v2 — Full Social \+ Watch \+ Duo

- **Apple Watch companion** — **partially done**. Phone↔Watch bidirectional sync architecture is shipped: phone pushes `RaceStateSnapshot` on every race event via `WCSession.updateApplicationContext`; Watch renders live from it. Watch's Next Station button sends `WatchAction.advance` via `sendMessage`; iPhone receives it and advances the race. Verified end-to-end on the iPhone+Watch simulator pair. **Still open**: hold-to-finish on Watch final station, real-hardware install validated on watchOS 26+ (current free-dev-account \+ Apple Watch SE on watchOS 11 blocks the companion install with a generic "could not install" error, but the code is proven correct on sim). Ship once tested on newer Watch.  
- **Detailed per-station race summary** (Roxfit-style) — per-station breakdown view with: this-station's split vs your PB for that station, pace curve, HR curve (see below), comparison to your last N races. Accessed by tapping any split row in History detail. Needs `SwiftCharts` framework. 2-3 sessions.  
- **HealthKit read integration** — currently we only *write* races to Health. Add HR (and eventually active calories, VO2 max) *read* during a race, storing samples on each `Split`. Minimum: HKHealthStore read auth for `.heartRate`, query current HR at each station advance, display avg/max HR per split in the summary. Deeper: continuous HR sampling via `HKAnchoredObjectQuery` during the race, HR curve rendering via SwiftCharts, zone breakdowns (Z1–Z5 time in zone). \~1 session for basic capture \+ display, \~1 more for charts \+ zones.  
- **Duo Mode** (see §4.5 below — real-time partner sync)  
- **Custom Workout Builder** — let users define their own station sequences (shortened sessions, strength-focused days, conditioning circuits) beyond the official 16-segment race. Template save \+ reuse. Opens the door to the "Training Blocks" pattern from §13.2.  
- **Hyrox Performance Score** — per-athlete rollup on Profile: Strength, Endurance, Engine (cardio capacity). Derived from historical station performance relative to division benchmarks. Strava's "fitness score" equivalent for HYROX.  
- **Fatigue / effort insights** — post-race narrative callouts: "You slowed down 18% after Station 5," "Your HR peaks highest during lunges." Needs continuous HR sampling \+ comparison against prior races. Requires the HR charts work first.  
- **Challenges \+ streaks** — time-boxed goals ("7-day HYROX streak," "improve sled push time by 10% this month"). Displayed on Profile, surfaced in the feed.  
- **Manual reps / distance entry per station** — for stations where the user didn't do the full prescribed work (e.g. partial rep count due to injury, or a different sled distance at a non-standard gym). Logs what actually happened, not just what was prescribed.  
- **Voice / haptic cues on station transitions** — "Next: Sled Push" announced via TTS or audio ping, plus distinct haptic patterns per station category (run vs. heavy workout vs. cardio). Matters most on Watch where the screen isn't always visible.  
- **Shareable workout cards** — Instagram-story-ready visual of a completed race. Clean typography, hero time, key stats, branded. One-tap share from summary.  
- Segments / micro-challenges (fastest sled push, etc.)  
- Achievements / badges  
- Station auto-detection (ML)  
- Richer social feed (photos, comments threads, mentions)

---

### 4.5 — Duo Mode Specification (Tiered Rollout)

HYROX has an official **Doubles** format where two athletes complete the race together, splitting work at each workout station. This app will support this natively, and rolls out in **three tiers** — each builds on the previous, each ships independently, none requires the next.

#### Tier 1 — Co-located Duo via Multipeer Connectivity (CURRENT BUILD)

The 80% case for HYROX Doubles: two athletes physically together at the same gym, tapping in their workout side-by-side. No backend, no auth, no accounts needed.

**Architecture: host-authoritative over Multipeer Connectivity.**

- Apple's `MultipeerConnectivity` framework — peer-to-peer over Bluetooth \+ Wi-Fi Direct, no servers, encrypted by default.  
- Leader (host) owns the `RaceEngine`. Their state is the source of truth.  
- Guest's phone is a remote display \+ remote input. Either side can tap Start / Next / Pause / Finish, but the guest's tap becomes a `requestAdvance` message sent to the host, which mutates the engine and broadcasts the new snapshot back. No "two engines drifting in sync" problem.  
- Snapshot transport reuses `RaceStateSnapshot` (same shape we ship to the watch).

**User flow:**

1. User A taps Duo → "Host". Phone starts advertising.  
2. User B taps Duo → "Join". Phone starts browsing, sees A's name in a list.  
3. B taps A → invitation. A accepts. Both land on a shared "Ready" screen.  
4. Either taps Start — host's engine starts, broadcasts to guest. Both timers begin at the same `startedAt`.  
5. Either taps Next/End/Pause/Finish — host arbitrates, broadcasts. Both screens stay identical.  
6. Race finishes. Saves to BOTH athletes' Histories independently (Race row gets a `partner: String?` field carrying the other athlete's display name).

**Real design decisions to lock in before shipping:**

- *Crediting:* identical times and splits to both athletes' Histories (matches the HYROX Doubles convention).  
- *Disconnect mid-race:* surviving phone keeps racing solo locally with a "partner disconnected" banner. Race saves with a `partnerDisconnectedAt` annotation. No re-pair flow in v1 of Duo.  
- *Watch:* no changes. Each phone's `WatchCompanionService` keeps streaming its own snapshot to its own paired watch — both watches end up showing the same race state because both phones do.

**Hard edge cases:**

- Both partners tap "Next Station" within milliseconds — host's engine processes the first one, second is a no-op against an already-advanced state. Multipeer's \~100–300ms latency makes this rare.  
- Pause arbitration — guest's pause becomes a `requestPause` message; \~200ms window where they could disagree visually. Acceptable for v1; surface a small "syncing…" state if it becomes a problem.

**Estimate:** \~3–4 sessions. None of it requires backend work.

#### Tier 2 — Cloud-backed Duo (requires accounts)

Same UX, different transport. Unlocks "Duo with someone in another city" and survives bad gym Wi-Fi/Bluetooth.

**Requires (in order):**

- Supabase auth (email/Apple Sign-In) — every user has a stable `user_id`.  
- Cloud-synced UserProfile and Race rows (so a duo race saved on one device shows up on the other).  
- Supabase Realtime subscription model — a `duo_race` row in Postgres, both clients subscribe to changes, server-authoritative timing using `start_time` written by whichever client tapped Start first.  
- Pairing flow: either via short-lived 6-character code (typed in by the partner) OR by selecting from a friends list (see Tier 3).  
- Disconnect handling becomes more nuanced — one device offline doesn't mean disconnected, just delayed sync. Server-timestamp-ordered conflict resolution.

**Why this needs accounts:** without a `user_id` you can't write a Race row attributable to a specific athlete, and you can't have a pairing code that survives an app restart.

#### Tier 3 — Friends \+ invitations layer

Builds on Tier 2\. Now that users have accounts and races sync to the cloud, add the social graph.

**Pieces:**

- Follow/unfollow relationships in Supabase (`relationships` table, `from_user_id`, `to_user_id`, `created_at`).  
- Friends list view in Profile.  
- Invite-to-Duo flow — instead of typing a code, pick a follower from your list and tap "Invite to Duo." They get a push notification ("Sarah invited you to Duo race") that deep-links into the race start screen with the invitation pre-loaded.  
- Public profile pages — view another athlete's history, total stats, badges (with privacy controls).

**Why this is its own tier:** the core duo mechanic doesn't need a social graph. Tier 1 \+ Tier 2 already deliver the duo experience. Tier 3 is the layer that makes Duo discoverable and convenient at scale, and naturally pairs with the social feed work that's also in v3+.

**Backlog ordering:** Tier 1 ships now (Multipeer, no backend). Tier 2 is gated on Supabase auth \+ sync, which is the broader v1 work in §4. Tier 3 layers on top of Tier 2 once the social feed is live.

**For Tier 1 only (current build):** the existing greyed-out "Solo / Duo" toggle on the start screen gets un-greyed and wired to the Multipeer flow. The Race model already has a `mode: RaceMode` field (.solo / .duo) — it's been there since v0.1, accommodated for exactly this moment.

---

## 5\. Design System (Strava-Inspired)

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
- Profile pages (avatar \+ name \+ follow count top, stats grid middle, recent activities bottom)

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
- Information hierarchy: hero stat \> supporting stats \> metadata \> social actions

### Card Anatomy (Strava-inspired, core pattern)

Every race in History, every item in the future feed, follows this shape:

┌────────────────────────────────────┐

│ \[avatar\] Username · 2h ago         │  ← header

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

In v0.1, the social actions row is absent. In v1+, it appears. But the rest of the card is identical — which means the v0.1 History cards become feed cards in v1 with almost no rework.

### Motion

Subtle. Spring animations for state changes (`.spring(response: 0.4, dampingFraction: 0.8)`). Respect `Reduce Motion` accessibility setting. No bouncy, playful, Duolingo-style motion.

---

## 6\. Critical UX Requirements (from the brief)

These are non-negotiable. Flag any generated code that violates these:

1. **Must work smoothly during workouts (low interaction).** If a flow requires more than one tap per station during a race, it's wrong.  
2. **Timer must never stop, never lag, never drift.** Use a `Date`\-based timer (store start time, compute elapsed on each tick), NOT an incrementing counter. Counters drift.  
3. **Screen must stay awake during a race.** `UIApplication.shared.isIdleTimerDisabled = true` while race is active, restore on finish.  
4. **State must survive app backgrounding.** If the user accidentally swipes home mid-race, the race state must persist and resume correctly. Store race state to SwiftData on every station transition.  
5. **Button targets must be huge.** 60pt minimum, 80pt preferred for in-race actions.  
6. **Typography on the race screen must be readable at arm's length, mid-sprint, in bright light.** Err on bigger.  
7. **Social UI must not leak into performance UI.** During a race, no kudos, no notifications, no badges popping up. The race screen is a cathedral — silent and focused. Social appears in History, Profile, and (future) Feed.

---

## 7\. Architecture Notes

### Project Structure (target)

HyroxApp/

├── HyroxAppApp.swift              \# App entry

├── Models/

│   ├── Race.swift                 \# A completed or in-progress race

│   ├── Station.swift              \# Enum of the 16 segments

│   ├── Split.swift                \# A single station's elapsed time

│   ├── RaceMode.swift             \# Enum: .solo, .duo (duo disabled in v0.1)

│   └── RaceState.swift            \# In-progress state (for persistence)

├── Features/

│   ├── Race/

│   │   ├── RaceView.swift         \# The main race screen

│   │   ├── RaceViewModel.swift    \# @Observable view model

│   │   ├── RaceEngine.swift       \# Pure logic: state machine, timing

│   │   ├── RaceStartView.swift    \# Pre-race screen with Solo/Duo toggle

│   │   └── RaceSummaryView.swift  \# Post-race summary

│   ├── History/

│   │   ├── HistoryView.swift      \# Feed-style list of past races

│   │   ├── RaceCardView.swift     \# The Strava-style card (reused in feed later)

│   │   └── RaceDetailView.swift

│   └── Profile/

│       ├── ProfileView.swift

│       ├── ProfileHeaderView.swift

│       └── StatsGridView.swift

├── Shared/

│   ├── Theme.swift                \# Color \+ font extensions

│   ├── Components/                \# Reusable SwiftUI views (buttons, cards, stat tiles)

│   └── Extensions/

└── Resources/

    └── Assets.xcassets

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

## 8\. Coding Conventions

- **Swift 6 strict concurrency** — we're targeting a modern codebase, embrace it (see §8.1 for the concrete patterns this implies)  
- **`@Observable` over `ObservableObject`** — we're on iOS 17+  
- **SwiftUI over UIKit** — no UIKit unless we hit a specific wall (haptics via `UIImpactFeedbackGenerator` is fine)  
- **Prefer value types (structs) over classes** unless identity matters  
- **One view per file** when views are non-trivial  
- **No force unwraps (`!`)** in production code paths. Use `guard let` / `if let`.  
- **Naming:** verbs for functions (`startRace()`, `advanceStation()`), nouns for properties

### 8.1 — Concurrency hygiene (the established patterns)

The codebase is built strict-concurrency-clean from the start. Build settings reflect this:

- `SWIFT_VERSION = 5.0` with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on every shipping target (main iOS app, watchOS companion, **and** the Widget extension). The default isolation means new types are MainActor-isolated unless explicitly marked otherwise — match this convention rather than fighting it.
- Zero `@unchecked Sendable`, zero `nonisolated(unsafe)`, zero `@preconcurrency` imports. Don't introduce them. If a type needs Sendable, make its storage actually Sendable; don't paper over with `@unchecked`.
- Every value type in `Hyroxapp/Models/` (Split, Station, Division, RaceMode, RaceKind, HRZone, FreeRunSplit, Badge, HyroxPillar, ThemePreference, Challenge, FreeRunLocationType, FreeRunSplitUnit) is explicitly `Sendable`. Every Watch transport type (RaceStateSnapshot, FreeRunStateSnapshot, WatchAction, WatchControl, WatchHeartRateUpdate, WatchRepCountUpdate) is `Sendable`. Every Supabase DTO (RemoteRace, RemoteFreeRun, RemoteComment, RemoteProfile, RemoteFollow, RemoteReaction, Remote*Profile / Race / RaceStats) is `Sendable`. Match the pattern when adding new value types: `Codable, Equatable, Hashable, Sendable` is the default conformance shape for cross-boundary data.

**Delegate-callback bridge pattern.** Several Apple frameworks (HKWorkoutSession / HKLiveWorkoutBuilder, WCSessionDelegate, CMHeadphoneMotionManager handler, CMBatchedSensorManager handler) call us from arbitrary background queues. The pattern is:
1. Mark the delegate method `nonisolated` so the compiler doesn't complain about the framework calling it off MainActor.
2. Hop to MainActor inside the body via `Task { @MainActor in ... }` before reading or writing any observable state.
3. Capture only Sendable values across the hop; never capture `@Observable` instance state via implicit `self` — use explicit `[weak self]` and re-bind inside the Task.

There are 60+ instances of this pattern in the codebase; new delegate methods should follow it without inventing variants.

**WCSession + WatchConnectivity edges.** When a continuous-sample payload type is added (HR, reps, cadence, etc.), every payload struct ships with a `kind` discriminator constant and a `sampledAt: Date` field. The receiving side de-duplicates by `sampledAt` and rejects out-of-order arrivals. See `WatchHeartRateUpdate` for the canonical shape.

**MainActor-isolated singletons.** `@MainActor @Observable final class Service { static let shared = Service() }` is the standard for app-wide services (SensorSourceRegistry, FollowSyncService, LiveActivityService, HeadphoneMotionService, WatchRepCountingService, WatchWorkoutManager). View code reads them directly; cross-actor reads hop via `Task { @MainActor }`.

### SwiftUI Specifics

- Compose with small subviews rather than one giant `body`  
- Extract modifiers into custom `ViewModifier`s when reused 3+ times  
- Use `@Environment` for things like color scheme, size class  
- Previews for every non-trivial view (use `#Preview` macro)  
- Build reusable components (`RaceCardView`, `StatTile`) generically from day one — they'll be reused across History, Profile, and future Feed

---

## 9\. About the Person Building This (Me)

- **Name:** Umang, based in Florida  
- **Day job:** Deloitte Technology (agile/SAFe practices)  
- **Side projects:** Zavvo Group ad work, BBSM app proposal, YouTube channel  
- **iOS experience:** New to Swift and Xcode. Comfortable with web/React ecosystem.  
- **HYROX:** Actively training, including Doubles format. Will test the app during real sessions.  
- **Time budget:** Evenings and weekends. Realistic \~10 hrs/week.  
- **Goal:** Ship a working v0.1 I personally use in 4-6 weeks.

### What I need from Claude Code

- Teach as you build. When you use a Swift/SwiftUI feature I might not know (`@Observable`, property wrappers, modifiers), add a brief comment explaining it.  
- Generate runnable code, not sketches. I want to hit ⌘R and see something work.  
- When I ask for a feature, if it violates v0.1 scope, tell me and suggest we defer it.  
- When there's a meaningful architectural choice, name it and recommend one — don't make me choose in a vacuum.  
- If I ask for something that'll bite later (e.g., timer using a drifting counter, or a UI that won't extend to the social feed), push back.

---

## 10\. Definition of Done for v0.1

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

## 11\. Open Questions to Revisit

Things we haven't decided yet but will need to soon:

- Exact station distances for the "simulation" mode when training at a gym without the full HYROX setup (e.g., if I don't have a sled, do I time a substitute movement?) — partially addressed by the **Custom Workout Builder** roadmap item in §4 v2.  
- ~~How to handle the 1km runs when indoors vs outdoors (GPS only works outdoors)~~ — **resolved**: no GPS at all (see §1 non-goals). All runs are manual start/stop regardless of indoor/outdoor. The athlete controls the timer, not a location sensor.  
- ~~Whether the 75 vs 100 wall ball count depends on gender/division~~ — **resolved**: `Division` setting on `UserProfile`, `Station.target(for:)` renders the correct count.  
- For Duo Mode: does each partner get credited with the full race, or does the UI distinguish who did which work?  
- For social feed: is it chronological, algorithmic, or filterable (friends / local / global)?  
- Privacy: can a user set races to private? Per-race or global default?  
- Near-term iPhone-only slice: **race notes** ("how did this feel?" text field on `RaceSummaryView`, editable later in `RaceDetailView`, persisted on `Race.notes`). \~30 min, ungated by anything.  
- Tooling constraint: Apple Watch companion install on **free-tier dev account \+ older Watch hardware (Apple Watch SE on watchOS 11\)** consistently fails with a generic "could not install at this time" error even with correct Embed Watch Content build phase. Code is proven correct on the iPhone+Watch simulator pair. Re-test on watchOS 26+ hardware when available (friend's device or newer personal Watch) before concluding the companion ships. Paid Apple Developer Program ($99/yr) likely also resolves it.

Don't build for these yet — just flagging.

---

## 12\. How to Use This Document

- **Start of every Claude Code session:** point at this file  
- **When I ask for a feature:** check it against §4 scope before building  
- **When designing UI:** reference §5 design system, specifically the Strava-inspired patterns  
- **When building reusable components:** remember they need to extend to v1/v2 features (social feed, Duo Mode) without rework  
- **When writing code:** follow §8 conventions  
- **When in doubt:** ask me. Better to clarify than guess wrong.

This file is living. Update it as decisions change.

---

## 13\. Vision / Feature Backlog

A structured dump of the bigger product vision — Strava × HYROX, station-based, no GPS, real-time effort \+ HR, social \+ competitive. This section is an **idea pool**, not a commitment. Items promote into §4 phased scope when we decide to ship them; until then they live here as reference for design decisions (e.g. "does today's change leave room for future challenges / streaks?").

Status legend for each bullet below:

- 🟢 **done** — in the current build, usable today  
- 🟡 **partial** — architecture in place, more work needed  
- ⚪ **idea** — not started

### 13.1 — Workout tracking (Watch \+ iPhone)

The athlete's primary in-session experience.

- 🟢 Start a HYROX workout session (Race Mode) from home screen in one tap  
    
- 🟢 Pre-loaded official HYROX stations (16 segments, race order)  
    
- 🟢 Time per station (split capture)  
    
- 🟢 Tap to move to next station  
    
- 🟢 Always-visible total timer \+ segment timer  
    
- 🟢 Mid-race splits peek (view completed splits without leaving race)  
    
- 🟢 Hold-to-finish on final station (safety against mis-tap)  
    
- 🟢 Screen stays awake mid-race  
    
- 🟢 Resume after force-kill / backgrounding  
    
- 🟢 Watch companion: phone↔watch live sync (architecture shipped, install on watchOS 26+ TBD)  
    
- 🟢 Heart rate tracking: avg \+ max per station via HKStatisticsQuery, live HR display mid-race, HR curve chart, zone breakdowns — full stack shipped  
    
- 🟢 Live HR zone chip on RaceView — current zone classification visible mid-race  
    
- 🟢 **Roxzone (transition) tracking** — opt-in two-step advance (end segment → in-roxzone overlay → start next), per-split `roxzoneSeconds` capture, total \+ average displayed on summary/detail, discipline insight (≤10s tight / ≤20s solid / \>20s actionable). HYROX-specific differentiator — every second outside a station counts on race day.  
    
- 🟢 **Live Activities scaffolding** — RaceActivityAttributes \+ LiveActivityService \+ widget Swift files all shipped. Pending: Widget Extension target via Xcode UI (see `docs/LIVE_ACTIVITY_SETUP.md`).  
    
- 🟢 **1km Run with manual start/stop** — toggle in Settings; when on, run stations open a Start Run overlay that rebases the segment timer when tapped. `RaceEngine.rebaseCurrentSegmentStart(to:)` \+ manual run start UI shipped.  
    
- 🟢 **Calories burned per station** — HealthKit `.activeEnergyBurned` statistics query alongside HR stats  
    
- 🟢 **Effort level / derived intensity score** — full stack shipped. Per-split \+ per-race scores via `RaceStats.effortScore` (HR-time integration). `EffortCategory` enum (Recovery/Moderate/High/VeryHigh) drives per-station chips on StationDetailView, split-row dots on summary/detail, badge on RaceCardView, EffortTrendView line chart \+ EffortDistributionView intensity-mix bar on Profile, and `hardestStationInsight` callout. One concept, surfaced everywhere it adds meaning.  
    
- 🟢 **Manual reps / distance / weight input** — `weightKg`, `repsCompleted`, `rpe` per Split. Tap any split row on summary/detail to edit via StationStatsSheet. Powers race-readiness check \+ race-day weight projection.  
    
- 🟢 **Race-day weight projection** — when training at sub-race weight, linear extrapolation projects the same effort to official HYROX weight (`split.duration × raceWeight / loggedWeight`). Surfaced on StationDetailView hero. Coaching honesty signal.  
    
- 🟢 **Voice / haptic cues on station transitions** — VoiceCueService announces "Next: Sled Push," HR-zone entries also voiced. Toggleable in Settings.  
    
- 🟡 **Auto-timer between transitions** — partial via roxzone tracking (transitions are timed). True rest-interval countdown for training (not race simulation) still TBD.  
    
- 🟢 **Pace indicator mid-race** — real-time "ahead / on pace / behind" chip on RaceView based on naïve split of `targetDuration`. Tier 1 (naïve split) shipped. Tier 2 (benchmarked split using community/division data) pending backend.  
    
  Original two-tier framing kept here for context:  
    
  1. **Naïve split of target** — divide `targetDuration` across the 16 stations, either evenly or weighted by station type (runs get a bigger allotment than sled push). Ships as soon as we commit — no backend required.  
  2. **Benchmarked split** (v2+/v3, depends on §13.4 backend \+ community data) — once Supabase stores enough race history, derive per-station expected times from aggregated splits across the athlete's division. "You're 12 seconds off the average Men's Open athlete on this station." Much more motivating than a flat 1/16th-of-target split.


  Visual sketch: small chevron/arrow on the race screen — green up for ahead, amber flat for on-pace, red down for behind — with a compact `+0:12` / `on pace` / `−0:18` delta vs. expected for the current station. Dependencies: target finish time (shipped), HR/effort capture (in progress), backend historical splits (not started).


- 🟢 **Mid-race predicted finish time** — naive linear extrapolation of current pace (`elapsed × totalSegments / completedSegments`). "Projected H:MM:SS" line under the timer, tinted green when on track to beat target, amber when projecting to miss. Numeric content transition keeps digits smooth as projection updates per tick. Different question than the pace chip: pace says "ahead/behind right now," projected says "when will you actually finish at this rate."

### 13.2 — Structured workout modes

Different container types for "do a workout with this app."

- 🟢 **Full HYROX Simulation** (Race Mode) — the 16-segment official format  
- 🟢 **Custom Workout Builder** — user-defined station sequences, save as templates, reuse via WorkoutTemplatePickerSheet. Opens the door to half-rox sessions, strength-focused days, any arbitrary subset.  
- 🟢 **Training Blocks** — seeded `WorkoutTemplate` rows on first launch cover Strength / Conditioning / Hybrid presets. Picker is part of RaceStartView's Custom flow.  
- 🟢 **Race naming \+ photos** — every race gets an editable title and an optional photo (banner on RaceCardView, hero on share cards, shows up in RaceGalleryView).  
- 🟢 **Target finish time per race** — H/M/S wheel picker on RaceStartView, drives pace chip \+ summary/detail outcome callouts.

### 13.3 — Post-workout analytics

What the athlete sees after tapping Finish.

- 🟢 Race summary with total time \+ all 16 splits  
- 🟢 Race saved to History as a card  
- 🟢 PB indicator on cards when a race sets a new PB  
- 🟢 Per-race notes ("how did this feel?") — editable from summary \+ history retroactively  
- 🟢 HR per split (avg \+ max), curve chart, zone breakdowns, station-level comparison — full HR analytics stack shipped  
- 🟢 **Detailed per-station breakdown** (Roxfit-style): StationDetailView pushed from any split row — trend chart over all attempts, PB highlight, physiology tiles (avg/max HR, calories), race-day weight projection callout when training under race weight  
- 🟢 **Heart rate zones graph** — Z1–Z5 time-in-zone via HRZonesView, integrated into RaceDetailView  
- 🟢 **Fatigue curve** — RunFatigueChartView shows back-half slowdown across the 8 runs, surfaces fatigue insight automatically  
- 🟢 **Narrative insights** — InsightGenerator pumps PB count, HR peak, compromised running, roxzone discipline, run fatigue into RaceInsightsView. Shown on summary \+ detail.  
- 🟢 **Compromised running analysis** — detects which station hurt the next run most ("Sled Pull cost you — Run 6 was 22% slower"). Cross-race aggregation on Profile.  
- 🟢 **Engine impact view** — Profile-level rollup showing which stations consistently compromise the engine.  
- 🟢 **Recovery score (post-race demand)** — `RaceStats.RecoveryDemand` 4-bucket enum (Light / Moderate / Hard / Very Hard) shipped. Computed from effort score \+ 1.5× Z5-minutes weighting. Each bucket carries typical recovery hours range \+ coaching guidance one-liner. Surfaced as `RecoveryEstimateView` card on RaceSummaryView \+ RaceDetailView.  
- 🟢 **Recovery score (HR-drop based)** — separate `RaceStats.RecoveryScore` measuring avg HR drop in the 30s after each station, classified Excellent / Good / Average / Slow at thresholds ≥25 / 15-25 / 10-15 / \<10 bpm. Surfaced on summary \+ detail hero ("Recovery \-23 bpm avg · Good") \+ insight callout for the actionable buckets only (excellent / slow). See §13.11 \#5.  
- 🟡 **Today's readiness signal** — `RaceStats.ReadinessState` 3-state enum (Fresh / Partial / Recovering) computed from most-recent-race recovery demand \+ hours elapsed. `ReadinessBanner` on Profile's Next Up section. Will get richer when §13.8 Tier 3 lands (overnight HRV \+ sleep \+ skin temp). Engine Score (§13.11 \#15) gives the rolling 5-race version of this in the meantime.  
- 🟢 **PBs per station** — StationPersonalBestsView lists best splits per station, surfaced on Profile.  
- 🟢 **Weekly / monthly / yearly performance trends** — PerformanceTrendsView, MonthlyRecap, YearlyRecap with shareable cards.  
- 🟢 **Performance overload chart** — PerformanceOverloadView surfaces volume \+ intensity trend on Profile.  
- 🟢 **Race comparison view** — side-by-side split tables between two of your own races (HistoryView toolbar).  
- 🟢 **Training calendar heatmap** — month-grid on Profile showing race density.  
- ⚪ **Fatigue vs performance correlation** — scatter-plot style "when my resting HR is higher, my total race time is X% slower"

### 13.4 — HYROX-specific performance system

The thing that makes this *not* a generic workout logger.

- ⚪ **Station scoring** — each station gets its own score relative to division benchmarks (percentile, or a 0–100 rating)  
    
- 🟢 **HYROX Performance Score** — HyroxPerformanceScoreView on Profile shows the 3-pillar rollup (Strength / Endurance / Engine) using `pillarTheoreticalBest` over historical splits. Updates after every finished race.  
    
- 🟢 **Race-readiness check** — Profile-level diagnostic: is the athlete training at race weights? Driven by `weightKg` \+ `Division.raceWeight(for:)`.  
    
- 🟢 **Race event countdown** — RaceEvent SwiftData model \+ ProfileView banner shows "T-N days to your next race." Editable via RaceEventEditSheet.  
    
- ⚪ **Benchmarking** — compare against:  
    
  - Yourself (historical rolling averages)  
  - Other users on the platform  
  - Division averages (men's/women's × open/pro)  
  - (Eventually) official HYROX event times from past races


  Powers the "benchmarked split" tier of the pace indicator in §13.1 — once we can say "the average Men's Open athlete finishes Sled Push in 3:45," the mid-race pace readout stops being an arbitrary 1/16th-of-target and starts being genuinely informative.


- 🟢 **Strain / engine quality** — `RaceStats.EngineScore` (0-100) composite rolls drift, recovery, efficiency, and decoupling sub-scores into one tier (Building / Steady / Elite). Athlete-level rollup over the last 5 races, plus a per-race overload \+ insight system. Whoop-strain equivalent for HYROX. See §13.11 \#15-18.  
    
- 🟡 **Daily readiness from overnight body data** — pulling overnight HRV \+ sleep \+ skin temp into a pre-race readiness banner. Queued as Tier 3 of §13.8 sensor roadmap.

### 13.5 — Social layer (Strava-style)

How athletes see each other's work and stay accountable.

- 🟡 Card design foreshadows social feed (RaceCardView structured for future kudos/comments row)  
- 🟡 Profile screen (real identity, handle, avatar, bio, social stats placeholders)  
- 🟢 **Profile share card** — ProfileShareCardView \+ share toolbar item exports a branded portrait of the athlete's identity \+ key stats.  
- ⚪ **Feed** — timeline of followed athletes' completed races, auto-posted on finish (opt-in), scrollable RaceCardView with kudos \+ comments  
- ⚪ **Follow / unfollow** — relationship graph, displayed as counts on Profile, drives feed filtering  
- ⚪ **Comments** — threaded comments per race, mentions (@athlete)  
- ⚪ **Kudos** (Strava's "like" equivalent) — one-tap positive reaction  
- 🟢 **Compare own workouts** — RaceComparisonView for side-by-side splits across two of your races. Two-athlete comparison still pending backend.  
- 🟢 **Share to Instagram** — RaceShareCardView in both square and 9:16 story formats, ImageRenderer-backed export, format-picker Menu on summary \+ detail.  
- 🟢 **Stories-style recap** — MonthlyRecapView \+ YearlyRecapView with shareable card variants.  
- 🟢 **Race photo gallery** — RaceGalleryView grid of every race that carries a photo.  
- 🟢 **Per-race privacy toggle** — `Race.isPrivate` additive field with default `false`. `PrivacyToggleSection` on RaceSummary \+ RaceDetail; lock chip on RaceCardView. Forward-compat for v2 social feed: private races stay out of any future leaderboard / feed automatically. Local History \+ Profile stats always include them.  
- 🟢 **Race tags** — `Race.tagsRaw` CSV-encoded field with `tags: [String]` computed accessor (lowercase canonical, dedupe, max 5). `TagsSection` editor with chip wrap \+ recent-tags suggestion ribbon. Tags surface as compact pills on RaceCardView and as a filter row on HistoryView (composes with preset filters). Forward-compat for v2 cross-athlete tag discovery.

### 13.6 — Competition \+ gamification

Structured reasons to keep coming back.

- ⚪ **Leaderboards**:  
  - Fastest full HYROX simulation (global, friends, division)  
  - Best per-station times (fastest sled push, lowest wall ball time, etc.)  
  - Weekly rankings (best race this week) Pending backend.  
- 🟢 **Challenges** — time-boxed personal goals the athlete picks from preset templates. `Challenge` SwiftData @Model with type / target / dates / completedAt. `ChallengeType` enum (raceCount / fastestRace / streakLength) \+ `ChallengeProgress` evaluator (race-count, sub-time, longest-streak-in-window). `ActiveChallengeBanner` on Profile with progress bar \+ days-remaining \+ auto-completion side effect when fraction hits 100%. `ChallengeSetupSheet` with 6 preset templates ("5 races in 30 days", "Sub-1:30 race in 30 days", "7-day streak", etc.). Single-active-challenge invariant; Replace/Abandon context menu. Forward-compat for v2 social feed (cross-athlete challenges).  
- 🟢 **Streak tracking** — RaceStreaks helper \+ StreakBannerView on Profile (current streak, longest streak, days since last race). Flame icon pulses gently while the streak is active (1.2s ease-in-out loop). Broken streak shows a static dim flame.  
- 🟢 **Streak-at-risk nudge** — `RaceStreaks.isStreakAtRisk` helper \+ `StreakAtRiskBanner` on Profile (active streak with last training \= yesterday). Sharpened notification copy when at-risk vs routine reminder.  
- 🟢 **Badges** — Badge enum \+ BadgeAwarder \+ BadgesView on Profile. Covers first simulation, elite tiers, consistency streaks.  
- ⚪ **Segments / micro-challenges** — like Strava segments but per-station; compete for the fastest Sled Pull within a gym / region / globally  
- 🟢 **Quick Actions (3D Touch / long-press home icon)** — "Start Race" shortcut registered, deep-linked into RaceView.  
- 🟢 **Local notifications** — opt-in nudges for streak protection, race-event countdown reminders. Settings toggle \+ scheduling on app launch / race finish.  
- 🟢 **Onboarding wizard** — first-launch flow capturing handle, division, max HR. `hasCompletedOnboarding` gate on UserProfile.

### 13.7 — Inspiration \+ non-negotiables

- **Reference apps**: Strava (feed, segments, kudos), Roxfit (race format, station detail), Whoop (strain/recovery scoring), Apple Fitness (ring animations, summary typography)  
- **Strict no-GPS** — runs are manual start/stop (see §1 non-goals)  
- **Indoor-first** — HYROX is an indoor race; the app should work on a treadmill or in a garage gym just as well as outdoors  
- **Watch is first-class** — for mid-workout interaction, the wrist beats the phone. Architecture already reflects this.

### 13.8 — Apple Watch sensor roadmap

Where the app could genuinely separate from every other HYROX tracker. Ranked top-to-bottom by impact-per-effort once the paid Apple Developer license is active. Currently the Watch is a mirror \+ remote — every sensor reading the user sees comes from phone HealthKit via WCSession snapshot. These tiers move sensor consumption to the Watch directly.

**Tier 1 — Direct Watch HR streaming** (🟢 shipped)

Watch's `HKWorkoutSession` \+ `HKLiveWorkoutBuilder` collects HR at native \~1Hz. Three transports converge on `currentHeartRateBPM` on the iPhone:

1. **`sendMessage` (live)** — fires when the iPhone app is reachable. Lowest latency.  
2. **`transferUserInfo` (queued)** — fallback when phone is pocketed / locked / asleep. Survives across iPhone wake cycles.  
3. **HK polling (2s)** — third-tier fallback if the Watch is killed entirely. Gated to write only after 10s of Watch silence so it doesn't clobber fresh Watch samples with stale HK data.

Watch-side hardening: throttle-order fix (bogus 0-bpm samples no longer poison the publish window), sample-end de-dup (`didCollectDataOf` re-fires on energy collection don't re-publish stale HR). Phone-side hardening: stale-sample threshold bumped 30s → 90s so transferUserInfo bursts after a pocket cycle land instead of getting rejected wholesale.

Net result: HR ticks throughout a race regardless of phone state (foreground / pocket / locked / asleep). UI chip mirrors via `numericText()` content transition for smooth digit changes. Closes the "stuck at 70 during a jog" bug.

**Tier 2 — IMU rep counting** (\~1 week, ⚪ — headline feature)

Use `CMDeviceMotion` accelerometer \+ gyroscope to auto-count reps for the four rep-based stations. *No other HYROX app does this.* Gestures to detect:

| Station | Motion signature |
| :---- | :---- |
| Wall balls | Up-back-up arm extension cycle, \~2s period |
| Burpee broad jumps | Vertical drop → push-up → jump impulse |
| Sandbag lunges | Alternating L/R foot impulse during steps with held weight |
| Farmer's carry | Step impulses with stable arm position (count steps) |

Phase 1: ship with classical signal processing (band-pass on Z-axis acceleration, peak detection above a tuned threshold). Phase 2: train a small Create ML classifier per station type if signal-processing accuracy plateaus.

Surfaces: optional rep counter chip on the in-race screen for rep stations, post-race auto-fill of `Split.repsCompleted` so the athlete doesn't have to type. Pairs with the existing manual `repsCompleted` field — if the auto-count detects N, athletes can confirm or override.

**Tier 3 — Pre-race readiness from overnight HealthKit** (\~3 sessions, ⚪)

Combines four signals from HealthKit (already on the Watch via overnight tracking) into a readiness score:

- Resting HR vs 30-day baseline  
- HRV ratio (last-night HRV / 30-day average)  
- Sleep duration \+ quality from `HKCategoryTypeIdentifierSleepAnalysis`  
- Skin temperature delta from overnight baseline (S8+/Ultra only)

Surface: enhances the existing `ReadinessBanner` on Profile from "based on last race" to "based on last race \+ last night's body data." Color-coded: green \= race-day ready, amber \= easy session today, coral \= real recovery day.

The Whoop / Oura play. The data is already on the Watch via Apple Health; we just have to read it. Comparable products charge $200–300/year for this; we get it free.

**Tier 4 — Post-race SpO2 \+ skin temp** (\~1 session each, ⚪)

`HKQuantityTypeIdentifierOxygenSaturation` lookup post-race shows the lowest SpO2 reading during the session. Combined with HR peak, it's a real anaerobic-threshold proxy ("Your SpO2 dropped to 92% on Wall Balls — near anaerobic threshold").

Wrist skin temp during a race trends with thermal load. A surge could flag overheating risk on a hot gym day. Both are passive HealthKit reads — minimal code to surface.

Niche but positions the app as performance-grade. SpO2 is Series 6+; skin temp is Series 8+/Ultra.

**Tier 5 — Apple Watch Ultra Action Button** (\~1 session, ⚪)

Configurable physical button on Ultra hardware. Wire it to "advance station" so the athlete can rip through the race with one hardware press, no screen tap. Critical for sweaty hands and gloves. Falls back to no-op on non-Ultra hardware (Series-only users keep tapping).

Implementation: register via `WKExtension` shortcuts; settings toggle for the binding.

**Tier 6 — Auto station advance via motion classification** (deferred — requires Tiers 1–2 first, ⚪)

The most ambitious sensor item. Detect when the athlete transitions from one station to the next based on motion-pattern shift and auto-fire `advance()`. Needs a trained classifier (Create ML or hand-tuned heuristics on running cadence vs. strength patterns).

Risk: false positives ruin a race. False negatives leave the athlete tapping. Ship with a confirmation prompt ("Advance to Sled Push?") rather than silent advance until accuracy is proven on real-world training data.

**Out of scope (intentionally)**

- GPS — see §1 non-goals  
- ECG — irrelevant for racing; requires holding still \+ finger on crown  
- Compass / altimeter — indoor HYROX surfaces don't have meaningful magnetic or elevation signal at the resolutions the sensors provide  
- Voice commands via microphone — battery \+ accuracy concerns; cleaner to use the Action Button \+ screen tap  
- Depth gauge / water temp — wrong sport

**Sequencing once activation lands**

Recommended build order (each tier is independent — can be reordered if user feedback shifts priorities):

1. **Tier 1** — Direct HR. Closes a real correctness gap, fast win.  
2. **Tier 5** — Ultra Action Button. Small lift, noticeable UX win for the subset of users on Ultra hardware.  
3. **Tier 2** — Wall ball rep counting first, then expand to the other three rep stations. The headline feature that shows up in App Store screenshots.  
4. **Tier 3** — Overnight readiness. Turns the Profile readiness banner from useful into compelling.  
5. **Tier 4** — SpO2 \+ skin temp post-race. Performance-grade positioning.  
6. **Tier 6** — Auto station advance. Last, after rep-counting data exists to train on.

### 13.9 — Design \+ motion language (shipped, captured for reference)

The app shares one motion \+ design language across every surface. Documented here so the next person to add a screen knows what to reach for.

- **Spring shape**: `.spring(response: 0.4–0.45, dampingFraction: 0.8–0.85)` — CLAUDE.md §5's canonical motion. Lands with weight, no bounce. Used for entrances, state changes, transitions.  
- **Press feedback**: `.buttonStyle(.pressableCard)` from `Theme.swift` — scales tappable card surfaces to 0.98 on press with a 0.3s spring. Wired into HistoryView, ProfileView card lists, RaceStartView mode chips, RaceView advance button, OnboardingView action row, ChallengeSetupSheet templates.  
- **Scroll appearance**: `.applyScrollAppearTransition()` from `Theme.swift` — children fade \+ scale 0.96 \+ slight blur as they enter the viewport. Wired into ProfileView, HistoryView, RaceDetailView, StationDetailView, RaceComparisonView, MonthlyRecapView, YearlyRecapView. Settings (Form) and RaceSummaryView (custom celebratory cascade) intentionally use their own treatments.  
- **Chart entrances**: line \+ dots fade in via opacity \+ symbol-size on first appear (`PerformanceTrendsView`, `EffortTrendView`). Stacked bars grow from zero width (`HRZonesView`, `EffortDistributionView`).  
- **Numeric / symbol transitions**: `.contentTransition(.numericText())` for live-updating digits (HR BPM, predicted finish, pace delta). `.contentTransition(.symbolEffect(.replace))` for SF Symbol glyph swaps.  
- **Halo / flame pulses**: gentle scale loop (0.95↔1.08, 1.2–1.5s ease-in-out) on `ReadinessBanner` `.fresh` halo and `StreakBannerView` active flame. Off when reduce-motion.  
- **In-race motion**: roxzone overlay slides up from bottom \+ scales to 1.0; station headline scale-fades on advance; pace \+ HR chips crossfade tints across thresholds; HeartbeatIcon pulses at displayed BPM tempo (clamped 0.3s minimum for photosensitivity safety).  
- **Onboarding transitions**: asymmetric directional slides (forward \= trailing edge insertion, backward \= leading), single VStack keyed by step so hero icon \+ body slide as one unit.  
- **Reduce Motion**: every animation gates on `@Environment(\.accessibilityReduceMotion)`. When on, springs become `.none` and dynamic motion is replaced with static reveals or opacity crossfades.

### 13.10 — HR Intelligence Layer (the 18-feature roadmap)

The depth-of-insight layer that separates Trakrr from generic HYROX trackers. Every item below is built on data already captured (HR samples \+ station boundaries \+ run pace) — no new sensors, no backend. All 🟢 shipped.

**Per-race aggregates (\#1-2):**

1. 🟢 **Race-wide avg \+ peak HR** — duration-weighted avg across splits \+ race max. "HR 158 avg · 184 peak" line on RaceSummary \+ RaceDetail hero. Silent when no HR data.  
2. 🟢 **Station HR boundaries** — entry / end / recovery-30s / recovery-60s per Split. `RaceViewModel.attachSegmentStats` \+ delayed Task pattern (70s sleep then HK query for the future-time recovery samples). Surfaced as Boundaries row in StationDetailView's Physiology card.

**Coaching insights (\#3, \#5, \#13):** 3\. 🟢 **Fatigue inflection detection** — finds the specific run where the wheels fell off (\>=8% pace decline pivot), classifies by HR direction (HR-up \= engine cooked, HR-down \= legs cooked but heart settled). Surfaces as narrative insight. 4\. 🟢 **HYROX zone naming** — Easy / Steady / Race / Hard / Redline labels alongside the Z1-Z5 zones, with `HyroxBand` 3-bucket simplification (easy / race / redline) for at-a-glance reading. Used on per-station tags and the live HR chip. 5\. 🟢 **Recovery score (HR-drop)** — avg HR drop in the 30s after each station, classified Excellent / Good / Average / Slow at thresholds ≥25 / 15-25 / 10-15 / \<10 bpm. Hero line \+ insight on actionable buckets only. 6\. 🟢 **Efficiency score** — `(priorBest / thisDuration) / (avgHR / maxHR)`. Per-split \+ race-wide. "Efficiency 1.04 · Strong" hero line \+ insight that flags the worst-efficiency workout station.

**Live coaching (\#7, \#11):** 7\. 🟢 **Live coaching cue** — `RaceStats.CoachingCue` enum (`.hold` / `.slow` / `.push` / `.workout` / `.none`) drives the in-race HR chip pill (HOLD PACE / SLOW DOWN / PUSH HARDER / WORK). Workout stations skip the pace cue (mid-sled-push "slow down" is bad coaching). iPhone \+ Watch, with cue-transition haptic on the wrist. 8\. 🟢 **Personal HR baseline** — IQR (25th/75th percentile) of avg run HR across the last 10 races. Profile card showing the band ("158 – 167 bpm") \+ median target. Powers the in-race coaching cue when ≥8 run-split HR samples exist; falls back to textbook Z3 below that. 9\. 🟢 **Per-station HR signature** — each station type has its own HR fingerprint (sled push lives at one HR, wall balls at another). Box-plot whisker classification (1.5× IQR) detects today's anomalies vs the athlete's history. Callout on StationDetailView fires when HR is meaningfully off ("today's sled push HR was \+12 bpm vs your usual").

**Engine progression (\#8-\#9, \#14):** 10\. 🟢 **Cardiac drift** — avg HR climb across the 8 runs (first half vs second half). HYROX-specific signal — same prescribed work, climbing HR \= engine fading. Three buckets (minimal \<5 / moderate 5-10 / severe \>10 bpm). Hero line \+ insight. 11\. 🟢 **Aerobic decoupling** — pace-per-HR ratio change across run halves. Sport-science classic (Friel/Daniels thresholds: \<5% conditioned / 5-10% moderate gap / \>10% large gap). Distinct from drift — drift watches HR; decoupling normalizes by pace, catching the case where an athlete slows in the back half AND their HR climbs. 12\. 🟢 **HR drift trend on Profile** — cross-race chart of per-race driftBPM over time, reference rule at 5 bpm. Dots tinted by category. Engine progression visible at a glance. 13\. 🟢 **Recovery trend on Profile** — cross-race chart of per-race avg-30s-drop, reference rule at 25 bpm.

**Engine Score system (\#15-\#18):** 14\. 🟢 **Engine Quality composite score** — `RaceStats.EngineScore` (0-100) rolls drift \+ recovery \+ efficiency \+ decoupling sub-scores into one number. Each sub-metric normalized to 0-100 against research-grounded thresholds, then averaged (sub-scores that can't be computed are dropped from the average rather than treated as zero). Tier mapping: \<40 Building / 40-70 Steady / \>70 Elite. 15\. 🟢 **Engine Score Profile card (\#15)** — athlete-level rollup over the last 5 finished races. Hero number \+ tier label \+ 4-bar sub-score breakdown \+ "based on N races" provenance. Whoop-strain equivalent. 16\. 🟢 **Per-race engine score (\#16)** — same composition scoped to one race. "Engine 72 · Steady" line at the top of the post-race HR-derived hero block (above HR / Recovery / Efficiency / Drift / Decoupling). Frames the breakdown lines beneath as the *why* behind the rollup. 17\. 🟢 **Engine Score Trend chart (\#17)** — cross-race chart of per-race engine score over time, sits at the TOP of the Profile trend family. Y-axis bounded 0-100, gridlines at tier boundaries (40, 70). Headline progression metric. 18\. 🟢 **Engine Score insight (\#18)** — `EngineScoreContext` detects all-time-best, breakthrough (10+ above recent avg), or regression (10+ below recent avg) \+ identifies which sub-metric drove the change most. Surfaces as narrative callout: "Best engine race ever — 82\. Recovery led the way." or "Off-day engine — 51, \-12 below your recent average. Drift was the drag."

**Profile trend family (final composition):**

1. Engine Score Trend — am I going Building → Steady → Elite?  
2. Time Trend — am I getting faster?  
3. Effort Trend — am I training harder?  
4. HR Drift Trend — is my engine progressing within races?  
5. Recovery Trend — am I recovering faster between stations?  
6. Intensity Mix — what's the load distribution?

Six complementary fitness adaptation stories, one cohesive design system.

### 13.11 — How items move from §13 into §4

When we commit to building something from this list:

1. Pick a specific item and give it an estimate (sessions of work)  
2. Slot it into v1 / v2 / v3 in §4 with a brief scope note  
3. Update its status here to 🟡 while in progress, 🟢 when shipped

Don't let §13 grow unchecked — if an idea has been here 6+ months without moving, either commit or prune.

---

## 14\. App Navigation Architecture (Locked Decision)

Feed-first tab bar — the app opens to social, like Strava. This drives daily opens even on non-training days.

**Bottom tab bar (5 tabs):**

| Position | Tab | Icon | Purpose |
| :---- | :---- | :---- | :---- |
| 1 (home) | **Feed** | Home | Social activity feed — friends' races, sims, training. The front door. |
| 2 | **Train** | Play circle | Start a race, simulation, quick station, or compromised session. Action hub. |
| 3 | **Dashboard** | Grid 2×2 | Daily readiness, weekly stats, fatigue trends, race countdown. |
| 4 | **History** | Clock | All past races/sims/training. Filterable. PBs. Race-vs-race comparison. |
| 5 | **Profile** | Person circle | Identity, HYROX Score, station strength map, trends, settings. |

**Key UX rules:**

- Feed is Tab 1\. The app opens here by default.  
- Train tab holds all workout entry points (Race Mode, Race Simulation, Quick Station, Compromised Session builder).  
- Dashboard is the "how am I doing today" screen — readiness score, race countdown, training volume, fatigue fingerprint trend.  
- History replaces the current HistoryView but keeps the same card-based design. Filter tabs: All | Races | Sims | Training.  
- Profile keeps all existing profile content (PBs, trends, engine score, challenges, badges, streaks) plus the new HYROX Score card.

**Feed tab detail:**

- Strava-style activity feed of followed athletes' completed races/sims/training  
- Each post \= RaceCardView with athlete header \+ workout type \+ key stats (finish time, degradation %, efficiency score)  
- HYROX-specific reactions: 🔥 Fire, 💪 Strong, ⚡ Fast, 🫡 Respect (replaces generic "kudos")  
- Tap a post → view their full public results  
- "+ Post" button for manual updates / race reflections

**Train tab detail:**

- 4 action cards in a 2×2 grid:  
  - 🏁 Race Mode (hero card, accent border) — live race tracking  
  - 🔄 Race Simulation — full 16-segment training flow  
  - 🏋️ Quick Station — single station work  
  - ⚡ Compromised — custom multi-segment builder  
- Below: "Recommended for you" card from Weakness-to-Workout Engine  
- Below: workout template library (existing Training Blocks \+ new templates)

**Dashboard tab detail:**

- Hero: Readiness Score (0-100, color-coded green/yellow/red) with contributing factors (HRV, sleep, RHR, load)  
- HYROX-specific training recommendation based on readiness  
- Quick stats row: training streak, days until race, race readiness projection  
- Weekly volume: hours, sessions, running distance  
- Fatigue Fingerprint trend: sparkline showing if fatigue cliff is moving later (improving) or earlier (overtraining)

---

## 15\. Apple Watch Race Mode UX (Locked Decision)

The watch is the most constrained screen. The athlete is at 170+ BPM, drenched in sweat, glancing for 1.5 seconds max. Every pixel earns its place.

### Watch Page 1: "Race View" (DEFAULT)

The primary view — what they see 90% of the time during a race.

┌─────────────────────────┐

│  RUN 3          3/8 ▶   │  ← Current segment \+ progress

│                         │

│      4:42               │  ← Segment elapsed time (LARGE)

│                         │

│   \-0:08  ●              │  ← Pace Ghost delta (green=ahead)

│                         │

│  ♥ 168   ▐▐▐▐░░  Z3    │  ← Live HR \+ zone bar

└─────────────────────────┘

- **Current segment**: "RUN 3" or "SLED PUSH" with segment count (3/8 runs, or 2/8 stations)  
- **Segment time**: big, center, impossible to miss — `.system(size: 28, weight: .heavy, design: .rounded)`  
- **Pace Ghost delta**: `+0:12` (behind, red) or `-0:08` (ahead, green) vs target split  
- **Heart rate \+ zone**: compact bar showing position within HYROX zone model (Z1–Z5)

### Watch Page 2: "Splits View" (scroll up via Digital Crown)

┌─────────────────────────┐

│  SPLITS                 │

│  R1  4:38  \-0:02   Z3   │

│  S1  3:12  \+0:05   Z4   │

│  R2  4:41  \+0:01   Z3   │

│  S2  2:48  \-0:12   Z4   │

│  R3  ⏱ ACTIVE           │

└─────────────────────────┘

Quick reference of completed segments — time, vs target, HR zone. Scrollable.

### Watch Page 3: "HR View" (scroll down via Digital Crown)

┌─────────────────────────┐

│  ♥  172 bpm             │

│  ████████████░░░  Z4    │

│                         │

│  Avg: 164  Peak: 186    │

│  Ceiling: 178  ⚠️       │  ← Guardrail ceiling (if set)

│  Recovery: ▼ 8 bpm      │  ← HR drop since last station

└─────────────────────────┘

### Race Awareness System — Alert Overlay

When the coaching engine triggers an alert, the ENTIRE watch face briefly takes over with a full-screen state word \+ haptic pattern. Displays for 2-3 seconds, then auto-returns to Race View.

┌─────────────────────────┐

│                         │

│         ⚠️ SLOW         │  ← Full-screen, 2 seconds

│                         │

│   HR rising too fast    │

│                         │

└─────────────────────────┘

**5 alert states with distinct haptic patterns:**

| State | Color | Haptic | Trigger |
| :---- | :---- | :---- | :---- |
| **HOLD** | Green | Single gentle tap | On pace, stay steady |
| **SLOW** | Amber | Two quick taps | HR rising too fast for this race phase |
| **REDLINE** | Red | Three urgent taps | Above sustainable range, will pay later |
| **RECOVER** | Blue | Long slow pulse | Focus on breathing, let HR drop |
| **PUSH** | Lime/accent | Strong single tap | HR recovered enough, go harder |

**Design principle**: The app does NOT spam alerts. It speaks ONLY when the athlete needs to make a decision. Silence \= you're fine. Final 2 stations suppress "SLOW" alerts (let them empty the tank).

This extends the existing `RaceStats.CoachingCue` enum (§13.10 \#7) with the full-screen takeover UX and richer haptic vocabulary on the Watch.

### Segment Transition Moment

When SmartSplit detects (or the athlete taps) a segment change, the watch shows a brief confirmation:

┌─────────────────────────┐

│                         │

│   ✓ RUN 3 COMPLETE      │

│     4:42  (-0:08)       │

│                         │

│   NEXT: BURPEE BROAD    │

│         JUMPS           │

│                         │

└─────────────────────────┘

Haptic confirmation tap. Holds for 3 seconds, auto-returns to Race View showing the new segment.

---

## 16\. Post-Race Results UX Architecture (Locked Decision)

The post-race results screen uses a **Hybrid** structure: Hero summary (pinned) → horizontally-scrollable insight cards → 5-tab deep dives. Athletes who ship full analytics from v0.1 — data nerds are the early adopters.

### Layer 1: Hero Summary (pinned at top, never scrolls away)

┌──────────────────────────────────┐

│      HYROX Tampa · Men Open      │

│                                  │

│          1:27:32                 │  ← Hero time (massive, center)

│                                  │

│  ┌─ 2:08 ahead ─┐ ┌── PB ──┐   │  ← Green pills

│                                  │

│  ┌────┐ ┌────┐ ┌────┐           │

│  │168 │ │8km │ │3:42│           │  ← Quick stat row

│  │ HR │ │Dist│ │Trans│          │

│  └────┘ └────┘ └────┘           │

└──────────────────────────────────┘

- **Total finish time** — center, massive, monospaced  
- **vs. Target** — green/red pill with delta  
- **vs. PB** — PB badge with animation if new best  
- **Date \+ Division** — contextual metadata  
- **Quick stat row** — 3 compact stats: Avg HR, Distance, Transition total

This stays pinned as they scroll or switch tabs.

### Layer 2: Top Insight Cards (horizontal scroll strip, 3-5 cards)

Auto-curated — the app picks the most actionable insights and surfaces them as compact cards. The algorithm selects from a pool of \~10 possible insight types ranked by impact:

1. **Run Degradation** — "Runs slowed 18% R1→R8. Front-loaded pacing cost \~45s."  
2. **Most Expensive Station** — "Sled Push: fast but costly. \+22 bpm spike hurt Run 5."  
3. **Transition Tax** — "3:42 in transitions. Jogging saves 1:30+."  
4. **HR Drift** — "Avg HR climbed \+14 bpm first→second half. Aerobic base is the limiter."  
5. **New PB** — "New Wall Balls PB: 3:58\!"  
6. **Efficiency Standout** — "SkiErg efficiency up 15% — same time, lower HR cost."  
7. **Recovery Bottleneck** — "HR only dropped 4 bpm after Sled Push. Recovery is limiting pace."  
8. **Pacing Win** — "Negative split\! Runs 5-8 faster than 1-4. Elite pacing."  
9. **Guardrail Compliance** — "Stayed under HR ceiling for 14/16 segments."  
10. **Fatigue Cliff** — "Performance dropped sharply after Station 5\. Matches historical fingerprint."

Each card is tappable → opens the relevant deep-dive tab scrolled to that section. Cards use left-border accent color: green for wins, amber for warnings, red for problems.

### Layer 3: Tab Bar (5 deep-dive tabs)

┌────────┬────────┬──────────┬──────┬───────┐

│Overview│  Runs  │ Stations │  HR  │ Story │

└────────┴────────┴──────────┴──────┴───────┘

**Tab 1: OVERVIEW** — Chronological race timeline. All 16 segments in order, each showing time \+ HR avg \+ color indicator (green/amber/red vs target). Transition times shown as thin bars between segments. Tappable → jump to detail in Runs/Stations tab.

**Tab 2: RUNS** — All 8 runs deep.

- Run Degradation Chart at top (line chart R1-R8 vs target pace line)  
- Run Degradation Score with tier: Elite \<8% / Good \<15% / Needs Work \>15%  
- Individual run cards: pace, cadence, HR avg/peak, vs target, vs previous race  
- "Post-station context" label per run: "Run 5 (after Burpee Broad Jumps)"

**Tab 3: STATIONS** — All 8 stations deep.

- Station Strength Map (radar/spider chart) at top  
- Station Performance Cards, one per station:  
  - Station name \+ time \+ PB indicator  
  - HR at start → HR peak → HR at finish  
  - Efficiency Score (output ÷ HR cost)  
  - Fatigue Impact: "This station added X bpm to your next run's starting HR"  
  - Rep/stroke data (where sensor-detected)  
  - Trend sparkline across last 5 races  
  - Cost-vs-gain insight: "Gained 14s on target but caused 22 bpm spike"

**Tab 4: HR (Heart Rate)** — The engine room.

- Full-race HR curve across all 16 segments  
- HR Zone distribution (donut/bar)  
- HR Drift Score — avg HR stations 1-4 vs 5-8 with delta  
- Between-Station Recovery Table — per-transition HR recovery ranked by quality  
- Guardrail Compliance (if set)  
- Redline Time — total time above 90% max HR

**Tab 5: STORY ("What Went Wrong?")** — The narrative.

- Plain-English story, 3-5 sentences, identifying the turning point, cause, and \#1 fix  
- "Top 3 Opportunities" — ranked list of biggest time-saving fixes  
- "Recommended Workout" — Weakness-to-Workout Engine output targeting \#1 weakness  
- Share button for this summary card

---

## 17\. Sensor-Powered Features — Additions to Backlog

Features identified from deep research into HYROX athlete pain points, competitor analysis (ROXFIT, Intervals Pro, WHOOP, HyroxDataLab), and Apple sensor capabilities. These extend existing §13 backlog items. Status: all ⚪ unless noted.

### 17.1 — New workout tracking features (extends §13.1)

- ⚪ **Pedometer-based indoor distance** — use `CMPedometer` for cadence, step count, and estimated distance on 1km run segments. Works indoors where GPS fails. Apple's step-to-distance calibration is solid for running gait. Does not replace the manual start/stop design (§1 non-goals) but adds distance/cadence data to the split. Station distances (sled 50m, etc.) are standardized — hardcode those, don't try to derive from pedometer.  
    
- ⚪ **Guardrails (per-segment HR ceilings)** — distinct from HR zones. Guardrails are race-phase-aware ceilings personalized from the athlete's history and Fatigue Fingerprint. Examples: "Don't exceed 172 bpm before Station 4," "Sled Push ceiling: 178 bpm," "Remove guardrails after Station 6." Apple Watch displays ceiling number; haptic fires when HR *approaches* the ceiling (not after crossing it). Post-race: "Guardrail Compliance" report — how many segments stayed under ceiling. Implementable with existing HR pipeline \+ per-segment threshold config.  
    
- ⚪ **Race Simulation Mode (enhanced)** — extends existing Race Mode \+ Custom Workout Builder. Pre-built template following official HYROX race flow with training-specific additions: target HR range per segment displayed on watch, transition timer between segments, "next station" haptic countdown, live race completion time prediction. Works on treadmill or outdoors — not GPS-dependent. Post-sim: full race breakdown as if it were an actual event, but tagged as "Simulation" in History. Key training tool for compromised-running practice.  
    
- ⚪ **SmartSplit V1 fallback UX** — for §13.8 Tier 6 (auto station advance), the V1 UX should NOT silently advance. Instead: "Suggested station detected: Wall Balls. Confirm?" — single haptic tap to confirm vs. manually selecting. Reduces friction without requiring perfect ML. The existing manual tap remains primary input; SmartSplit is a suggestion layer.

### 17.2 — New post-workout analytics (extends §13.3)

- ⚪ **Fatigue Fingerprint (longitudinal)** — meta-pattern across ALL tracked races/sims showing the athlete's characteristic breakdown. Different from per-race fatigue inflection (§13.10 \#3): inflection is "what happened today," fingerprint is "who you are as an athlete." Tracks: at which station does this athlete consistently collapse? Does HR spike disproportionately on the same station every time? Do runs degrade linearly or cliff? Visualization: heat map or multi-line chart. Key coaching insight: "Your fatigue cliff moved from Station 5 (March) to Station 7 (May) — 2 stations of improvement." Surfaces on Dashboard as a trend sparkline and on Profile as a detailed view.  
    
- ⚪ **"What Went Wrong?" narrative engine** — dedicated post-race tab (see §16, Tab 5). Rule-based narrative constructor that reads segment data and generates 3-5 plain-English sentences. Identifies: the turning point (where things started going wrong), the cause (which station or pacing error), and the \#1 fix. Below the narrative: "Top 3 Opportunities" ranked list \+ "Recommended Workout" from Weakness-to-Workout Engine. Can evolve to LLM-powered analysis in later versions. This is the strongest retention feature — athletes don't want to interpret charts post-race, they want to be told what happened and what to fix.  
    
- ⚪ **Station Performance Cards (enhanced format)** — extends existing StationDetailView. Each station card shows: time \+ PB indicator \+ trend sparkline, HR at start → HR peak → HR at finish (three-number HR arc), efficiency score, fatigue impact ("added X bpm to next run's starting HR"), cost-vs-gain insight ("Gained 14s on target but caused 22 bpm spike that hurt next run by 8s"). The card answers "was this station worth how hard I went?" not just "how fast was it."  
    
- ⚪ **Between-Station Recovery Score (granular)** — extends existing recovery score (§13.10 \#5). Per-transition metrics: HR drop (bpm) during transition, HR at next run start, time above personal redline (90%+ max HR), recovery speed ranked by station type. Example: "Your recovery after Sled Push is 3x slower than after Wall Balls." Key differentiator: tracks recovery *inside* the workout, not just after.  
    
- ⚪ **Run Degradation Score (explicit metric)** — extends existing RunFatigueChartView. Single percentage metric: (Run 8 pace \- Run 1 pace) / Run 1 pace. Tier classification: Elite \<8%, Good 8-15%, Needs Work \>15%. Surfaced on post-race Runs tab and on Profile as a trend. Coaching: "You degraded 18%. Elite athletes degrade \<8%. Try evening your first 3 runs by 5s each."

### 17.3 — New performance system features (extends §13.4)

- ⚪ **HYROX Score (composite)** — single number (0-1000 scale) as the headline Profile metric. Computed from: best race finish time (weighted by division), station balance (how even the spider chart is), run consistency (low degradation), efficiency scores, training consistency (streak/volume). Updates weekly. Displayed: Profile hero card, leaderboard ranking, percentile badge ("Top 15% Men Open"). This is the "credit score for HYROX fitness" — the number athletes screenshot and share.  
    
- ⚪ **Weakness-to-Workout Engine** — closed-loop system. Step 1: detect \#1 weakness from race/sim data (e.g., "Sled Push creates massive HR spike and destroys next-run recovery"). Step 2: generate targeted workout prescription ("4 rounds: 25m sled push at 80% → 400m run holding Z3. Focus: recover while moving."). Step 3: athlete trains → Trakrr tracks the session → weakness score updates. Surfaced: "Recommended for you" card on Train tab, "Recommended Workout" on post-race Story tab. This is the closed loop that makes users dependent on the platform — recommendations come from *their own data*, not a generic library.

### 17.4 — New social features (extends §13.5)

- ⚪ **HYROX-specific reactions** — replace generic kudos with themed reactions: 🔥 Fire, 💪 Strong, ⚡ Fast, 🫡 Respect. Multiple reactions per post (like Slack). Each reaction has a distinct micro-animation.  
    
- ⚪ **Station Leaderboards** — per-station rankings filterable by friends / age group / division / global. "Fastest Wall Balls in your age group." Enables granular competition beyond just finish time. Requires backend.  
    
- ⚪ **HYROX Score Leaderboard** — ranked by composite score, filterable by division/age/region. Distinct from finish-time leaderboard — rewards consistent training \+ balanced fitness, not just one fast race.  
    
- ⚪ **Shareable race card for social** — a designed summary card with hero time, key insights (degradation %, efficiency, engine score), station strength radar chart, and Trakrr branding. One-tap share to Instagram Stories / WhatsApp / Messages. Extends existing RaceShareCardView with the new metrics.

### 17.5 — Sensor-researched features (from deep research — extends §13.1, §13.3, §13.4, §13.8)

Items identified from researching HYROX athlete pain points (forums, HyroxDataLab 700K+ race analysis, coaching platforms), Apple sensor capabilities (WWDC23 CoreMotion sessions, HealthKit docs), and competitor gaps (ROXFIT, Intervals Pro, Garmin).

- ⚪ **The Predictor — AI Race Time Estimation** — before the athlete steps on the start line, predict their finish time based on training data. Inputs: recent standalone station benchmarks (fresh times), run fitness (recent 1km time trials or training paces), Fatigue Resistance Score from compromised sessions, recovery/readiness trend leading into race week, historical race data (if available). Output: "Based on your training, predicted finish: 1:27:32 ± 3 min. Your strongest segment will be SkiErg. Your biggest risk is Run 6-8 degradation." Accuracy improves with more training data — a v2+ play that gets better at scale. Surfaces on Dashboard in the 7-day pre-race window and on the Race Start screen.  
    
- ⚪ **Pace Ghost enhanced (degradation-aware pacing)** — extends existing pace indicator (§13.1) from naïve 1/16th-of-target split to a degradation-curve-aware pacing model. Key differences from current implementation:  
    
  1. Per-segment targets account for known HYROX degradation: runs 5-8 are expected \~5-10% slower than runs 1-4. The target for Run 1 is NOT the same as Run 8\.  
  2. After each completed segment, remaining targets are recalculated to keep the athlete on track for the overall goal time. If they banked time on SkiErg, the model redistributes — it doesn't just show green forever.  
  3. Optional "ghost race" comparison against a previous personal race — not just a target, but "you're 12 seconds ahead of your Orlando race at this point." Data model: store the pacing profile as an array of 16 target times, each weighted by station type using HyroxDataLab-style degradation curves. Surfaces on Apple Watch Race View as the delta number (§15) and on post-race Overview tab as a "vs plan" column.


- ⚪ **Fatigue Resistance Score (per-station-type)** — extends compromised running analysis (§13.3). When an athlete does compromised training (run → station → run), measure how much the station degrades the subsequent run. Track this per station type across sessions. Example: "Your pace degrades 6% after Wall Balls (great\!) but 22% after Sled Push (needs work)." Each station type gets its own Fatigue Resistance Score (0-100) that improves as the athlete trains compromised sessions targeting that station. Surfaces on Profile as a per-station fatigue resistance chart, and feeds into The Predictor and Weakness-to-Workout Engine.  
    
- ⚪ **SmartSplit algorithm specification** — implementation detail for §13.8 Tier 6 (auto station advance). The primary detection signal is a multi-sensor fusion approach:  
    
  IF (CMPedometer cadence drops from \>150 spm to \<30 spm)  
    
    AND (CMMotionActivityManager changes from "running" to "stationary")  
    
    AND (condition sustained for \>5 seconds)  
    
  THEN → Mark "Run Complete, Station Started"  
    
  Secondary signals for confidence boosting: HR pattern shows characteristic spike-then-plateau at station entry; accelerometer pattern shifts from rhythmic running oscillation to irregular station-specific motion. V1 ships with confirmation prompt ("Advance to Sled Push?") rather than silent advance — false positives ruin a race, so start conservative. SmartSplit is a suggestion layer on top of the existing manual tap, not a replacement.  
    
- ⚪ **Station Signature motion table** — implementation detail for §13.8 Tier 2 (IMU rep counting). Per-station accelerometer/gyroscope signatures for the Create ML classifier:


| Station | Motion Signature (Watch on Wrist) | What to Auto-Track | Detection Difficulty |
| :---- | :---- | :---- | :---- |
| SkiErg (1000m) | Rhythmic pull-down, high Y-axis acceleration, \~2s cycle | Stroke count, stroke rate, estimated distance | Medium — rhythmic, clean signal |
| Sled Push (50m) | Forward lean, continuous low-speed forward motion, suppressed arm swing | Duration, estimated distance via step count | Hard — similar to heavy walking |
| Sled Pull (50m) | Repetitive arm pull motion, stationary feet, cable rhythm | Pull count, cadence | Medium — rhythmic arm motion |
| Burpee Broad Jump (80m) | Explosive vertical drop → push-up → horizontal jump impulse | Rep count, estimated distance per rep | Hard — chaotic multi-phase |
| Rowing (1000m) | Rhythmic pull, seated position (gyro tilt different from standing), \~2s cycle | Stroke count, stroke rate | Medium — similar to SkiErg but gyro tilt distinguishes |
| Farmers Carry (200m) | Walking gait with suppressed arm swing (carrying heavy weight) | Step count → distance, pace | Easy — walking \+ stable arms |
| Sandbag Lunges (100m) | Alternating L/R deep knee bend, slow forward progress, \~3s cycle | Lunge count, pace | Medium — alternating pattern |
| Wall Balls (100 reps) | Repetitive squat-to-throw, high vertical acceleration peaks, \~2s cycle | Rep count (most reliable — clearest accel spike) | Easy — strongest signal of all stations |


  Build order: Wall Balls first (clearest signal), then SkiErg/Rowing (rhythmic), then Farmers Carry (easy walking detection), then remaining stations. Use `CMBatchedSensorManager` at 200Hz during active `HKWorkoutSession`. Phase 1: classical signal processing (band-pass filter on Z-axis, peak detection). Phase 2: Create ML classifier if signal processing accuracy plateaus. Apple's WWDC16 Session 713 explicitly demonstrates rep counting via `CMDeviceMotion.attitude` as a primary CoreMotion use case.

### 17.6 — Platform & hardware integration features (v2+ horizon)

Later-stage features that extend Trakrr from a standalone app into a platform. All ⚪.

- ⚪ **Coach Mode** — coaches see their athletes' data live during races/training. Requires: coach account type, athlete↔coach relationship model, live data streaming via Supabase Realtime. Coach's iPhone shows a multi-athlete dashboard: each athlete's current segment, elapsed time, HR, pace delta, coaching alerts fired. Post-race: coach sees all their athletes' full analytics. This is the B2B play — HYROX-affiliated gyms and coaches pay for coach accounts while athletes stay free.  
    
- ⚪ **Concept2 / SkiErg Bluetooth pairing** — connect directly to Concept2 ergometers (SkiErg, RowErg) via Bluetooth for precise stroke data, distance, pace, and power. Concept2's PM5 monitor supports Bluetooth broadcasting of workout data. This replaces estimated stroke counts from Watch IMU with exact data on the two erg-based stations. Requires: `CoreBluetooth` framework, Concept2 Bluetooth protocol parsing. Surfaces: exact distance/pace on post-race erg station cards, power curve data for advanced analytics.  
    
- ⚪ **Chest strap HR integration** — support external Bluetooth HR monitors (Polar H10, Garmin HRM-Pro Plus) for clinical-grade heart rate during races and training. Wrist-based optical HR on Apple Watch is good but degrades during high-intensity irregular motion (sled push, burpees) — chest straps maintain accuracy. HealthKit handles this transparently if the athlete pairs their chest strap to their iPhone/Watch, but Trakrr should detect and prefer external HR sources when available, and surface "HR source: Polar H10" in the data provenance. Matters for: accurate efficiency scores, reliable coaching alerts, trustworthy recovery metrics.  
    
- ⚪ **Video form analysis** — use iPhone camera \+ on-device Core ML to analyze movement form on station exercises. Post-workout: athlete records a set of wall balls, sled push, etc. The app analyzes: squat depth on wall balls, hip hinge on sled push, stride length on lunges. Surfaces: form score per station, visual overlay showing joint angles, comparison against ideal form. This is a v2+ feature that requires significant ML training data. Initial implementation could be simpler: just recording and timestamping video clips linked to specific stations, with form analysis added later.  
    
- ⚪ **Training plan marketplace** — curated and community-created HYROX training plans purchasable within the app. Plans structured as multi-week programs using the existing workout template system (§13.2). Revenue model: Trakrr takes a percentage of plan sales. Enables: HYROX coaches monetize their programming, athletes get structured periodization, Trakrr generates recurring revenue. Requires: backend, payment processing (StoreKit 2), content moderation.  
    
- ⚪ **LLM-powered "What Went Wrong?" narrative** — evolve the rule-based narrative engine (§17.2) into an AI-generated analysis using on-device or API-based LLM. The current rule-based approach handles the common patterns well, but an LLM can: cross-reference the current race against the athlete's full history, identify subtle multi-variable patterns, generate genuinely personalized coaching language, and adapt its communication style to the athlete's experience level. Could use Apple's on-device Foundation Models (iOS 26+) or an API call to Claude/GPT. V2+ feature — the rule-based engine ships first and provides the training signal for what good narratives look like.

---

## 18\. Sensor Inventory & Product Pillars

Reference for what hardware we have access to, how each sensor maps to HYROX-specific value, and the five hero features that differentiate Trakrr from every competitor.

### 18.1 — Complete Apple Watch Sensor Inventory

Every sensor available on Apple Watch for a watchOS workout app, the framework to access it, and its HYROX use case. For AirPods Pro 3 sensors and the adaptive multi-device sourcing strategy, see §19.

| Sensor | Framework | Data | HYROX Use Case | Min Hardware |
| :---- | :---- | :---- | :---- | :---- |
| **Accelerometer** (3-axis) | CoreMotion (`CMBatchedSensorManager` up to 800Hz, `CMMotionManager` up to 100Hz) | Linear acceleration | Rep counting, station detection, transition detection, movement quality drop-off | Series 1+ (800Hz batched: Series 8+) |
| **Gyroscope** (3-axis) | CoreMotion | Rotation rate, angular velocity | Movement pattern classification, station rhythm signatures, wall ball arc detection | Series 1+ |
| **Magnetometer** | CoreMotion | Magnetic field / compass heading | Indoor orientation (limited value in exhibition halls) | Series 1+ |
| **Barometer** | CoreMotion / `CMAltimeter` | Pressure / relative altitude | Indoor/outdoor detection, elevation changes in multi-level RoxZones | Series 3+ |
| **Optical Heart Rate** (PPG) | HealthKit (`HKLiveWorkoutBuilder`) | HR every \~1s during workouts, HRV | Live HR zones, recovery scoring, strain/efficiency, coaching alerts, drift tracking | Series 1+ |
| **Electrical Heart Sensor** (ECG) | HealthKit | Single-lead ECG, inter-beat intervals | Pre-race HRV analysis only (requires stillness — not usable mid-race) | Series 4+ |
| **Blood Oxygen (SpO2)** | HealthKit | Oxygen saturation % | Post-race anaerobic threshold proxy (§13.8 Tier 4\) | Series 6+ |
| **Skin Temperature** | HealthKit | Wrist temperature delta from overnight baseline | Overnight readiness (§13.8 Tier 3), overheating risk detection | Series 8+ / Ultra |
| **GPS / GNSS** | CoreLocation | Lat/long/altitude/speed | Out of scope — see §1 non-goals. HYROX is indoor-first. | Series 2+ |
| **Pedometer** | `CMPedometer` | Steps, distance, cadence, pace | Indoor 1km run distance, cadence monitoring, transition movement detection | Series 1+ |
| **Motion Activity** | `CMMotionActivityManager` | Walking/running/stationary classification | Auto-detect run vs station vs transition — Apple does this on-chip, no ML needed | Series 1+ |

**Key framework notes for implementation:**

- `CMBatchedSensorManager` (800Hz accel, 200Hz device motion) requires an active `HKWorkoutSession` — this is a workout-centric API. Available on Series 8+ / Ultra. This is what powers rep counting (§13.8 Tier 2).  
- `CMMotionActivityManager` provides real-time activity classification (running/stationary/walking) with zero custom ML — Apple handles it. This is the foundation for SmartSplit auto-detection (§13.8 Tier 6, §17.1).  
- `CMPedometer` works indoors with no GPS. Cadence \+ step count are the primary signals for indoor 1km run tracking (§17.1).  
- All CoreMotion APIs require `NSMotionUsageDescription` in Info.plist.  
- HR during workouts comes from `HKLiveWorkoutBuilder` at \~1Hz. Already shipped via §13.8 Tier 1\.

### 18.2 — Sensor-to-Feature Mapping

How each sensor/data source powers the HYROX-specific features that make Trakrr different.

| Sensor / Data Source | Features It Powers | HYROX Value |
| :---- | :---- | :---- |
| **Optical heart rate** | HR zones (§13.10 \#4), HR drift / cardiac drift (§13.10 \#10), recovery score (§13.10 \#5), efficiency score (§13.10 \#6), engine score (§13.10 \#14-18), live coaching cues / redline alerts (§13.10 \#7, §15), guardrails (§17.1), between-station recovery (§17.2), fatigue fingerprint (§17.2) | Shows effort cost and fatigue progression. The single most important sensor for HYROX — every intelligence feature depends on HR. |
| **Accelerometer** | Rep counting (§13.8 Tier 2), station detection (§13.8 Tier 6), SmartSplit transition detection (§17.1), movement quality / output drop-off | Detects output quality, counts reps, identifies when the athlete is slowing down. Combined with HR, reveals whether a slowdown is fatigue (HR up \+ output down) or pacing (HR controlled \+ output down). |
| **Gyroscope** | Station signature classification (§13.8 Tier 2 \+ Tier 6), movement pattern detection (wall ball arc, ski erg rhythm, row rhythm) | Helps distinguish between stations and detect movement quality. Combined with accelerometer for the Create ML classifier. |
| **Pedometer** | Indoor 1km run distance (§17.1), cadence monitoring, transition movement detection (did athlete walk or jog?) | Creates HYROX-specific structure without GPS. Cadence drop from 150+ to \<30 spm is the primary SmartSplit signal. |
| **Motion Activity** | Run/stationary classification for SmartSplit (§17.1), auto-workout-type detection | Apple's on-chip classifier provides run vs stationary vs walking for free — no custom ML needed for the transition detection layer. |
| **Time / lap markers** | Station splits, transition (roxzone) times (§13.1), race simulation flow (§17.1), pacing (§13.1) | The backbone of all HYROX analytics. Every insight depends on accurate segment boundaries. |
| **Haptic engine** | Coaching alerts / Race Awareness System (§15), segment transitions, pacing nudges | Silent coaching during painful workouts — athletes can't stare at the screen mid-sled-push. Distinct haptic patterns per alert state (§15). |
| **Temperature / HRV / resting HR** (via HealthKit overnight) | Pre-race readiness score (§13.8 Tier 3, §17.1), recovery trends, fatigue fingerprint trends | Helps avoid overtraining. The WHOOP/Oura play — but free, using data already on the Watch via Apple Health. |
| **SpO2** (via HealthKit) | Post-race anaerobic threshold proxy (§13.8 Tier 4\) | "Your SpO2 dropped to 92% on Wall Balls — near anaerobic threshold." Niche but positions the app as performance-grade. |
| **Apple Health workout history** | Fatigue fingerprint (§17.2), efficiency trends, HYROX Score (§17.3), weakness detection (§17.3) | Builds long-term personalization. The more races tracked, the smarter the app gets. |

### 18.3 — Product Pillars (Hero Features)

Five features that make Trakrr feel fundamentally different from ROXFIT, Intervals Pro, Garmin, or generic workout trackers. These are the features that go in App Store screenshots, pitch decks, and landing page headlines.

**Pillar 1: Fatigue Fingerprint**

"Know exactly where your HYROX performance breaks down."

Not "your HR was high" — but "your fatigue point starts after Station 5, your HR keeps rising while your output drops, and your run after Sled Push is where your race collapses." A longitudinal pattern across all your races that reveals who you are as an athlete. (§17.2, built on §13.10 \#3 fatigue inflection)

**Pillar 2: Station Intelligence**

"Every station gets a score, trend, and fix."

Each station gets its own performance card: time, HR arc (start→peak→finish), efficiency score, fatigue impact on the next run, cost-vs-gain insight, trend over time. Not just "Sled Push: 2:15" but "Sled Push: fast but expensive. You gained 14 seconds but caused a 22 bpm spike that hurt your next run." (§17.2, built on existing StationDetailView \+ §13.10 \#6 efficiency \+ §13.10 \#9 per-station HR signature)

**Pillar 3: Recovery Between Efforts**

"See how well you recover while still racing."

Most apps track recovery after a workout. Trakrr tracks recovery *inside* the workout — which is the whole game in HYROX. Per-transition HR recovery metrics, recovery speed ranked by station type, time above redline. "Your HR only dropped 4 bpm after Sled Push before the next run. Recovery is limiting your pace." (§17.2, built on §13.10 \#5 recovery score)

**Pillar 4: Live Race Awareness**

"Your watch tells you when to hold, slow, push, or recover."

Not a passive display of numbers. An active coaching system that fires only when the athlete needs to make a decision. HOLD / SLOW / REDLINE / RECOVER / PUSH — full-screen watch takeover with distinct haptic patterns. Silence means you're fine. (§15, built on §13.10 \#7 coaching cues)

**Pillar 5: What Went Wrong Report**

"After every workout, get the explanation — not just the numbers."

Plain-English 3-5 sentence narrative identifying the turning point, the cause, and the \#1 fix. "You started controlled, but your HR spiked during sled push. Recovery after sled pull was slow, and your pace dropped after station 5\. Biggest opportunity: control early sled effort and improve recovery during runs." Plus Top 3 Opportunities \+ Recommended Workout. (§17.2, built on §13.3 narrative insights)

**Why these five beat "track workouts" and "social feed" as positioning:** These are capabilities no other HYROX app offers. Social feed is table stakes (Strava does it). Workout tracking is table stakes (ROXFIT does it). But no app explains *why* the athlete felt destroyed, coaches them *during* the race via haptics, or builds a longitudinal fatigue identity. These five pillars are why an athlete switches from ROXFIT to Trakrr and never goes back.

### 18.4 — Competitive Moat

Features where Trakrr has a green checkmark and every competitor has a red X.

| Feature | ROXFIT | Intervals Pro | Garmin Native | Strava | WHOOP | Trakrr |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| Auto segment detection | ❌ | ❌ | ❌ | ❌ | N/A | ✅ |
| Live pacing engine w/ degradation curves | ❌ | ❌ | ❌ | Partial | N/A | ✅ |
| Rep/stroke counting (Watch IMU) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| HYROX-specific readiness score | ❌ | ❌ | ❌ | ❌ | Generic | ✅ |
| Transition (RoxZone) time tracking | ❌ | ❌ | Manual | ❌ | N/A | 🟢 shipped |
| Run degradation analysis | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Fatigue-adjusted benchmarks | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Efficiency score (output ÷ HR cost) | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Engine / cardiac drift tracking | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Between-station recovery scoring | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Live coaching cues (HOLD/SLOW/PUSH) | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Narrative post-workout insights | ❌ | ❌ | ❌ | ❌ | ❌ | 🟢 shipped |
| Fatigue fingerprint (longitudinal) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Live redline alerts (haptic coach) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Per-segment HR guardrails | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Weakness-to-workout engine | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Race simulation mode (structured) | Partial | ❌ | ❌ | ❌ | N/A | ✅ |
| Doubles partner sync | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 architecture shipped |
| HYROX Score composite | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| AirPods Pro 3 HR ingestion (no-Watch racing) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (§19) |
| Adaptive multi-device sourcing (Watch + AirPods fusion) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (§19) |
| Running-economy metrics from AirPods (cadence, vertical osc., posture drift) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (§19) |
| Free / no subscription lock | ❌ | ❌ | ✅ | Freemium | ❌ ($30/mo) | ✅ |

Legend: 🟢 \= shipped in current build, ✅ \= planned/in backlog, ❌ \= competitor doesn't offer it.

Six features already shipped that no competitor has. Sixteen more in the pipeline (including three AirPods-derived from §19). This is a defensible moat built on HYROX-specific sensor intelligence, not generic fitness tracking.

---

## 19\. AirPods Integration + Adaptive Sensor Sourcing

Apple shipped **AirPods Pro 3** (fall 2025) with in-ear optical heart rate sensors and motion sensors that are addressable by third-party apps. Combined with iOS 26's HealthKit fan-in (Apple does HR source fusion at the OS level), this opens a path for Trakrr to deliver \~85% of the in-race coaching experience **without an Apple Watch** — and to deliver three running-economy metrics (cadence, vertical oscillation, posture drift) that even Watch-equipped competitors can't surface because the wrist is the wrong place to measure them.

This section is the spec for that integration: what sensors AirPods expose, which Trakrr features they power, the adaptive sensor-sourcing architecture, and the phased roadmap.

### 19.1 — AirPods Pro 3 Sensor Inventory

Every sensor the AirPods family exposes to third-party iOS apps, the framework to access it, and the HYROX features it powers. Parallel to §18.1 for Apple Watch.

| Sensor | Framework | Data | HYROX Use Case | Min Hardware |
| :---- | :---- | :---- | :---- | :---- |
| **In-ear Optical Heart Rate** (PPG) | HealthKit (`HKLiveWorkoutBuilder`) — HR samples appear with `sourceRevision` = AirPods Pro 3 | Continuous HR during workouts, ~1Hz | Every §13.10 HR Intelligence feature (zones, drift, recovery, efficiency, engine score, coaching cues) — same path as Watch HR | **AirPods Pro 3 only** (Apple may extend to future models) |
| **Head Motion** (accel + gyro + magnetometer) | CoreMotion (`CMHeadphoneMotionManager`) — `CMDeviceMotion` at ~50Hz | Attitude (roll/pitch/yaw), rotation rate, user acceleration, gravity, magnetic field | Cadence (spm), vertical oscillation (cm/step), ground contact time (ms), posture pitch drift across race, head-motion rep counting on wall balls / burpees / lunges | AirPods Pro 1+, AirPods 4, AirPods Max — **not** AirPods 2/3 (non-Pro) |
| **Apple-derived Steps + Distance** | HealthKit (Apple writes the samples from in-ear motion processing) | Step count, distance for the workout | Indoor 1km run distance without GPS, fallback when Watch pedometer absent | AirPods Pro 3 |
| **Apple-derived Calories** | HealthKit (Apple computes from HR + motion + health profile) | Active calories burned during workout | Per-station calorie estimates when Watch absent | AirPods Pro 3 |
| **In-ear Detection State** | `AVAudioSession.routeChangeNotification` | Pod inserted / removed events | Failover trigger when athlete removes AirPods mid-race, re-prompt voice cues when pod re-inserted | All AirPods |
| **Audiogram + dB Exposure** | HealthKit (`environmentalAudioExposure`, hearing test results) | Personalized hearing thresholds, cumulative loud-noise exposure | Volume-cap coaching cues per user's hearing profile (minor / accessibility) | AirPods Pro 2 / Pro 3 |
| **Force Sensor / Stem Squeeze** | Not exposed to third parties (system-managed) | — | — | Pro 2 / 4 / Max |

**Key framework notes for implementation:**

- **HR is automatic.** Apple's documentation states: *"If you're wearing an Apple Watch and AirPods Pro 3 during your workout, they work together to provide you with multiple streams of heart rate data for even better coverage. The highest-confidence source in the moment is automatically used to provide heart rate data."* Trakrr's existing `HKLiveWorkoutBuilder` pipeline (§13.8 Tier 1\) ingests these samples without modification. The work is on the UX side — surfacing which device is the active source.

- `CMHeadphoneMotionManager` requires `NSMotionUsageDescription` in Info.plist (same as Watch / iPhone CoreMotion). No new entitlement.  

- `CMHeadphoneMotionManager.isDeviceMotionAvailable` returns `false` for AirPods 2 / 3 (non-Pro) and AirPods that aren't motion-equipped. Capability check is mandatory before subscribing.  

- AirPods Pro 3 HR works **when wearing just one AirPod**. Pro 3 also continues streaming HR to the iPhone even if the audio is routed to a different device (e.g. Apple TV during a workout video).  

- HRV / RR-intervals from AirPods are **not** published to HealthKit as of iOS 26. Avg HR samples are. HRV remains the Watch's domain — relevant for Readiness Banner accuracy.  

- `AVAudioSession.routeChangeNotification` carries the `AVAudioSessionRouteChangeReasonKey` reason — `newDeviceAvailable` / `oldDeviceUnavailable` distinguish insertions from removals.

### 19.2 — Adaptive Sensor Sourcing Architecture

The plumbing that lets Trakrr work transparently across four device profiles. One service owns capability detection; every feature reads from it.

**Service: `SensorSourceRegistry`** (`Shared/SensorSourceRegistry.swift`)

`@Observable` service. Reactive properties for what's connected right now:

- `hasWatch: Bool` — from `WCSession.default.isPaired`
- `watchReachable: Bool` — from `WCSession.default.isReachable`
- `hasAirPodsMotion: Bool` — from `CMHeadphoneMotionManager().isDeviceMotionAvailable`
- `hasAirPodsHR: Bool` — derived: AirPods Pro 3 model name from `AVAudioSession.currentRoute.outputs[].portName`, OR most-recent `HKHeartRateSample.sourceRevision` includes "AirPods"
- `iPhoneInPocket: Bool` — derived from `CMMotionActivityManager` (stationary + low activity confidence)

Computed property `DeviceProfile`:

| Profile | Meaning | What features light up |
| :---- | :---- | :---- |
| `.full` | Watch + AirPods Pro 3 + iPhone | Everything. HR fused across Watch + AirPods. Rep counting can fuse wrist + head IMU. |
| `.watchOnly` | Watch + iPhone, no AirPods or non-motion AirPods | Current pre-AirPods Trakrr. All §13.10 features work. |
| `.airpodsOnly` | AirPods Pro 3 + iPhone, no Watch | All §13.10 HR features work. SpO2 / skin temp / overnight HRV / ECG gone. Watch race surface gone. AirPods-exclusive features (cadence, vertical osc., posture drift) light up. |
| `.minimal` | iPhone only | Race timer + pace ghost + roxzone + Live Activity. No HR-dependent features. |

The registry updates reactively as devices connect / disconnect mid-session. Subscribers re-render via `@Observable`.

**Per-feature capability gates**

Most HR-dependent views already handle `currentHeartRateBPM: Int?` being nil — render a placeholder. What needs to change:

- **HR source attribution chip** — when HR is present, render a tiny glyph next to the BPM number indicating Watch vs AirPods vs fused. Live race screen, Watch race page (mirror), Live Activity HR chip (when fused).
- **Pre-race source check on TrainHubView** — small status row above the action grid: "Sensors ready: Apple Watch · AirPods Pro 3". Tap → sheet detail listing what each device contributes. Sets expectations before the athlete taps Start Race.
- **Mid-race fallover banner** — when source changes mid-race (Watch disconnects, AirPods inserted, etc.), 2s banner: *"HR source switched to AirPods Pro 3"*. Quiet, informative, no haptic.
- **Post-race source provenance block** — on RaceSummary + RaceDetail Overview tab: *"HR · 187 samples from Apple Watch + 62 from AirPods Pro 3 (fused) · Motion · AirPods Pro 3 · Calories · iPhone derived"*. Trust through transparency.

### 19.3 — Feature-by-Device Viability Matrix

Authoritative reference for which Trakrr features work across each `DeviceProfile`. 🟢 fully functional · 🟡 degraded · 🔴 unavailable.

| Feature | iPhone only | iPhone + Watch | iPhone + AirPods Pro 3 | iPhone + Watch + AirPods Pro 3 |
| :---- | :----: | :----: | :----: | :----: |
| Race timer / pace ghost / predicted finish | 🟢 | 🟢 | 🟢 | 🟢 |
| Roxzone (transition) tracking | 🟢 | 🟢 | 🟢 | 🟢 |
| Live Activity (lock screen + Dynamic Island) | 🟢 | 🟢 | 🟢 | 🟢 |
| HR chip + zones (live) | 🔴 | 🟢 | 🟢 | 🟢 fused |
| Coaching cues (HOLD / SLOW / PUSH / WORK) | 🔴 | 🟢 | 🟢 | 🟢 fused |
| HR Drift / Cardiac Drift | 🔴 | 🟢 | 🟢 | 🟢 |
| Recovery Score (post-race) | 🔴 | 🟢 | 🟢 | 🟢 |
| Recovery tile (in-race, 30s drop) | 🔴 | 🟢 | 🟢 | 🟢 |
| Engine Score composite + sub-scores | 🔴 | 🟢 | 🟢 | 🟢 |
| Efficiency Score (output ÷ HR cost) | 🔴 | 🟢 | 🟢 | 🟢 |
| Aerobic decoupling | 🔴 | 🟢 | 🟢 | 🟢 |
| HR zone time-in-zone breakdown | 🔴 | 🟢 | 🟢 | 🟢 |
| Calories per station | 🔴 | 🟢 | 🟢 (Apple computes) | 🟢 |
| Steps / distance on 1km runs | 🟡 if carried | 🟢 | 🟢 (Apple computes) | 🟢 |
| Cadence (live spm) | 🟡 if carried | 🟢 via Watch pedometer | 🟢 via custom `CMHeadphoneMotionManager` | 🟢 fused |
| Vertical oscillation (running economy) | 🔴 | 🟡 wrist is bad position | 🟢 head is ideal position | 🟢 |
| Posture drift fatigue signal | 🔴 | 🔴 | 🟢 unique to AirPods | 🟢 |
| Ground contact time | 🔴 | 🟡 | 🟢 | 🟢 |
| Guardrails (per-segment HR ceilings) | 🔴 | 🟢 | 🟢 | 🟢 |
| SpO2 per station | 🔴 | 🟢 Series 6+ | 🔴 | 🟢 Watch only |
| Skin temperature | 🔴 | 🟢 S8+/Ultra | 🔴 | 🟢 Watch only |
| Overnight HRV → richer Readiness Banner | 🔴 | 🟢 | 🟡 avg HR only, no RR-intervals from AirPods today | 🟢 Watch primary |
| ECG / clinical-grade HR | 🔴 | 🟢 S4+ | 🔴 | 🟢 Watch only |
| Watch race surface (3-page nav + alert overlay) | 🔴 | 🟢 | 🔴 | 🟢 |
| Hold-to-finish wrist gesture | 🔴 | 🟢 | 🔴 | 🟢 |
| Voice cue audio output | 🟡 phone speaker | 🟡 phone speaker | 🟢 in ears | 🟢 in ears |
| Rep counting (IMU on rep stations) | 🔴 | 🟡 §13.8 Tier 2 — wrist-positioned | 🟡 head motion good for wall balls + burpees, weaker for sled push | 🟢 fused = highest confidence |

**The big takeaway:** an athlete with iPhone + AirPods Pro 3 alone gets ~85% of Trakrr's value plus three running-economy metrics (vertical oscillation, posture drift, ground contact) that the Watch can't deliver well. The hard losses (SpO2, skin temp, ECG, overnight HRV) are clinical / recovery-tier metrics — important but not the headline in-race experience.

### 19.4 — Phase 10 Roadmap (AirPods Integration)

Phased rollout. Each phase ships independently and stays useful in isolation.

| Phase | Scope | Effort | Status |
| :---- | :---- | :---- | :---- |
| **10 A** | Update CLAUDE.md (this section). | ~2 hrs | 🟡 in progress |
| **10 B** | `SensorSourceRegistry` service + `DeviceProfile` enum. Reactive capability detection, no UI yet. | ~2 days | ⚪ |
| **10 C** | HR source attribution glyph on live race screen + Watch race page mirror. Reads `HKHeartRateSample.sourceRevision`. | ~1 day | ⚪ |
| **10 D** | Post-race source provenance block on RaceSummary + RaceDetail Overview tab. | ~1 day | ⚪ |
| **10 E** | Pre-race sensor check on TrainHubView (status row + tap-for-detail sheet). | ~1 day | ⚪ |
| **10 F** | Mid-race HR-source fallover banner. | ~1 day | ⚪ |
| **10 G** | Verify build across all four DeviceProfile scenarios. | ~½ day | ⚪ |
| **10 H** | Live cadence (spm) from `CMHeadphoneMotionManager`. Band-pass filter Z-axis impact, peak detect, publish to RaceViewModel.currentCadenceSPM. Render alongside HR chip. | ~3 days | ⚪ |
| **10 I** | Vertical oscillation as post-race running-economy metric. Z-axis displacement math, new "Running Economy" section on Race detail Runs tab. | ~3 days | 🟢 shipped |
| **10 J** | Posture drift fatigue insight. Read `attitude.pitch` through race, compute first-half vs second-half delta, surface as narrative insight. | ~2 days | 🟢 shipped |
| **10 K** | Ground contact time (running-economy completer). | ~1-2 weeks | ⚪ |
| **10 L** | Multi-sensor rep count fusion — combine Watch IMU (§13.8 Tier 2) + AirPods head motion + confidence scoring. Gated on Tier 2 shipping first. | ~1 week | ⚪ |

**Sub-phases 10 A–G ship the adaptive sourcing layer (the "Trakrr works with Watch, AirPods, or both" wedge).** That alone is marketable as: *"the first iOS HYROX app that doesn't require an Apple Watch."*

**Sub-phases 10 H–L ship the AirPods-exclusive metrics (the "Trakrr gives you running-economy data the Watch can't" wedge).** That positions the app against Stryd / Garmin Forerunner in the running-economy category at a $0 hardware cost.

### 19.5 — What's automatic vs custom

| Feature | Automatic via HealthKit | Custom Trakrr code |
| :---- | :---- | :---- |
| Watch HR | ✅ (existing) | — |
| AirPods Pro 3 HR | ✅ (Apple does fusion at OS layer) | — |
| AirPods-derived steps / distance / calories | ✅ (Apple writes to HealthKit) | — |
| Source attribution UI | — | Read `HKHeartRateSample.sourceRevision`, render glyph |
| Cadence (spm) | ❌ Apple writes step *count*, not rolling cadence | Custom: band-pass filter on `CMHeadphoneMotionManager` accel data |
| Vertical oscillation | ❌ Apple doesn't compute | Custom: peak-to-peak Z-axis displacement |
| Ground contact time | ❌ | Custom: impact spike → reversal interval |
| Posture drift across race | ❌ | Custom: continuous `attitude.pitch` log → first-half / second-half delta |

**Pattern:** Apple handles the data ingestion layer. Trakrr's value-add is the **HYROX-specific interpretation** of that data — the metrics, the coaching insights, the narrative, the comparison-against-baselines. Same playbook as the existing HR Intelligence layer (§13.10).

### 19.6 — Strategic positioning

Right now every competitor HYROX app (ROXFIT, Intervals Pro, Garmin native, Strava) assumes Apple Watch. An athlete without a Watch has no path to engine analytics.

Trakrr being the first to say *"bring your AirPods Pro 3 and we'll give you 85% of the HYROX coaching experience"* is a real wedge. Plus the three running-economy metrics (vertical oscillation, posture drift, ground contact) that even Watch-equipped competitors can't surface — because the wrist is the wrong place to measure them.

It's not just a feature add. It's an addressable-market expansion + a defensible technical moat.

---

## 20\. Garmin + External HR Monitor Integration

A meaningful slice of HYROX athletes wear Garmins (Forerunner, Fenix, Epix, Instinct) and won't buy an Apple Watch. Today they can't use Trakrr's coaching layer at all — every HR-derived insight (zones, drift, recovery, efficiency, engine score, coaching cues, guardrails) requires HR samples on the wrist or in the ears. This section is the integration plan that opens Trakrr to Garmin-equipped athletes and, as a side effect, to anyone wearing a standards-compliant BLE chest strap (Polar H10, Wahoo TICKR, HRM-Pro Plus, etc.).

### 20.1 — Three integration paths

Garmin support isn't one decision; it's three independent ones, layered. Strava — which has the most mature Garmin integration of any consumer fitness app — implements all three. For Trakrr the sequencing matters more than the destination:

| Path | What it is | What it unlocks | Effort | When to ship |
| :---- | :---- | :---- | :---- | :---- |
| **A** | CoreBluetooth + standard BLE Heart Rate Service GATT profile | Live HR during race + Free Run. Powers every HR-derived feature in §13.10 | ~1.5 weeks + Phase 28 (~3-4 days) | First — gates everything else |
| **B** | Garmin Health API (server-to-server cloud sync) | Post-race enrichment with Garmin's running dynamics, pace curves, GPS, calories | 2-4 weeks dev + 1-6 months partner approval | After Path A demonstrates Garmin user adoption |
| **C** | Native Connect IQ watch app (MonkeyC) | On-watch race UI parity with Apple Watch (race nav, advance, alert overlay) | 3-6 weeks initial + perpetual maintenance | Only after sustained Garmin user signal |

**The lesson from Strava.** Paths complement rather than compete. Strava's cloud sync (their Path B equivalent) handles 95% of user value — link Garmin Connect once, workouts appear in the Strava feed minutes after the watch syncs. Their Connect IQ app (their Path C equivalent) exists for the specific subset who want segment alerts at the wrist; most Strava-on-Garmin users never install it.

Trakrr's center of gravity is opposite Strava's. Strava's value is post-workout aggregation. Trakrr's value is during the race — live HR zones, coaching cues, drift detection, guardrails. So **Path A (live HR) is more critical for us than Strava's cloud sync was for them.** Path C is potentially more justifiable later, though — HYROX athletes glance at their wrist during runs more than Strava's average user — but only if real adoption data justifies the maintenance burden.

### 20.2 — Path A: BLE HR broadcast (the wedge)

Every modern Garmin watch ships with a built-in "Broadcast Heart Rate" feature. When enabled, the watch advertises itself as a standard BLE peripheral using the **Heart Rate Service GATT profile** (UUID `0x180D`, HR Measurement characteristic UUID `0x2A37`). Same standard Polar H10, Wahoo TICKR, HRM-Pro Plus, Suunto, Coros watches all speak. iOS handles it natively via `CoreBluetooth` — **no Garmin SDK, no developer account, no partner program**.

**What we'd build (~1.5 weeks total):**

- **`ExternalHRService`** (`@MainActor @Observable`) — CoreBluetooth wrapper. Scans for HRS-advertising peripherals, presents a discovery list, persists the user's pick as a paired device, subscribes to HR Measurement, publishes BPM samples through the same callback shape `HeadphoneMotionService` and the Watch transport already use. ~2 days.
- **Pairing UI** — new `ExternalHRPairingSheet` accessible from Settings → Devices and TrainHubView's sensor row. Scan list, tap-to-pair, paired-device persistence on additive `UserProfile.pairedHRDeviceUUID: String?` + `pairedHRDeviceName: String?` fields. Re-pair flow when the device goes missing. ~2 days.
- **`SensorSourceRegistry` extension** — add `.externalBLE(displayName: String)` to the existing HR source enum alongside `.appleWatch`, `.airpodsPro3`, `.fused`. Source attribution glyph (likely SF Symbol `dot.radiowaves.left.and.right`). Update `lastHRSource` ranking — chest strap > Garmin watch in broadcast > AirPods Pro 3 > Apple Watch optical on quality, but freshness still arbitrates within a 5-second window. ~2 days.
- **Ingest wiring** — both `RaceViewModel.ingestHeartRate(_:)` and `FreeRunViewModel.ingestHeartRateBPM(_:at:)` already accept BPM+timestamp from arbitrary sources (Phase 27 made this universal). Just one more producer registered with the service. ~1 day.
- **Background polish** — `bluetooth-central` UIBackgroundModes capability, reconnect-on-foreground logic, denied-permission UX, source provenance row on RaceSummary + FreeRunSummary. ~1 day.
- **Real-device verification** — test against at least one BLE HR strap. ~1 day.

Required Info.plist additions: `NSBluetoothAlwaysUsageDescription`. No new entitlements.

**User-facing setup flow:**

1. On the Garmin watch: settings → sensors → broadcast HR (or hold the watch face button → broadcast HR shortcut). Watch screen shows broadcasting state + small Bluetooth icon.
2. In Trakrr: Settings → Devices → Pair external HR monitor → scan finds the watch by name → tap to pair → done.
3. Going forward: Trakrr auto-reconnects on every race / Free Run start. No re-pairing needed unless the device changes.

**Trade-offs to be upfront about in the pairing UI:**

- Most Garmin watches disable their own workout recording while broadcasting HR. The athlete picks: record on Trakrr (with Garmin as HR source) OR record on Garmin (no Trakrr coaching). Not both.
- Background BLE on iOS is fragile. If the athlete pockets the phone during a long sled push and the OS suspends CoreBluetooth, HR may drop until the screen wakes. Apple Watch HR doesn't have this issue because it routes through WCSession + WatchKit, which have different background guarantees.
- HRS profile is HR-only. No pace, no cadence, no distance, no calories from Garmin via this path. (Distance still works — phone pedometer + GPS handles it.)
- HRV is gone for most Garmin watches over HRS. Chest straps like Polar H10 do broadcast RR-intervals via the extended HRS characteristics — handle those if/when we add HRV-based features.
- iPhone battery drain from continuous BLE is real (~10-15% over a 90-min race). Not deal-breaker, but surface in the pairing UI so it's not a surprise.

**Companion phase — Phase 28 (in-app HR series for Race).** Path A delivers a live HR stream, but post-race analytics today re-query HealthKit for per-segment HR aggregates. With Garmin (no Apple Watch), HK isn't being written to at race-grade density. We need to mirror the Phase 27 pattern from Free Run onto Race: in-memory `[HRSample]` buffer on `RaceViewModel`, persisted to `Race.hrSeriesData: Data?` (additive externalStorage field, JSON-encoded `[FreeRunHRSample]` or a rename to a shared `HRSample` type), and per-split HR aggregates computed from the persisted series when present (falling through to HK queries for pre-Phase-28 races). ~3-4 days. **Path A is incomplete without Phase 28** — without it, the live coaching works but the post-race intelligence layer is degraded for Garmin users.

### 20.3 — Path B: Garmin Health API (post-race enrichment)

The cloud-to-cloud path Strava uses for 95% of their Garmin integration. When a Garmin watch syncs a workout to Garmin Connect (via Garmin Connect Mobile or WiFi), Garmin's webhook fires to our backend, which pulls the full workout payload (per-second pace curve, HR samples, GPS route, lap data, running dynamics like vertical oscillation and ground contact time, calories, training effect) and stores it linked to the athlete's account. Workout-matching logic correlates Garmin workouts to Trakrr races by overlapping time windows.

**Prerequisites:**

- Apply to the Garmin Health API partner program. Approval is selective — Garmin curates access to manage cloud load. Strava is a "Premier" partner; new applicants land in lower tiers initially. Process: weeks to months from application to approval.
- Build a backend webhook receiver. Trakrr currently uses Supabase for auth + sync but has no general-purpose webhook infrastructure. We'd need an Edge Function (or equivalent) that authenticates the Garmin webhook callback, fetches the workout payload via OAuth-on-behalf-of, normalizes it, and writes to a `garmin_workouts` table linked to the Trakrr user.
- Build the OAuth flow on iOS: "Link your Garmin Connect account to Trakrr."
- Build workout-matching logic + post-hoc enrichment of the `Race` row (or attach the Garmin workout as a sibling record displayed alongside).

**What it unlocks that Path A doesn't:**

- True running dynamics — vertical oscillation, ground contact, vertical ratio, stride length — computed by the Garmin watch's onboard IMU. Strava-Garmin users see these in their feed; Trakrr-Garmin users would too.
- Per-second pace curve from Garmin's GPS (more accurate than iPhone GPS during a race day where the phone may be in a pocket).
- Calories computed via Garmin's TrainingPeaks-grade algorithms (more accurate than HR-only estimation).
- Lap data — if the athlete pressed lap on their watch (which they typically wouldn't during HYROX, but the data's there for free runs).

**What it doesn't unlock:**

- Live coaching. Path B is strictly post-workout — workouts sync to Garmin Connect after the watch session ends, then to our backend. Useless for during-race cues.
- Anything during the race itself.

**Verdict:** worth pursuing in parallel with Path A — start the partner application clock immediately even if we don't build the backend right away. Ship the backend once partner approval lands AND Path A has demonstrated meaningful Garmin user adoption.

### 20.4 — Path C: Connect IQ companion app (deferred)

A native Garmin watch app written in MonkeyC, distributed via the Connect IQ Store, providing race UI parity with Trakrr's Apple Watch companion: three-page race nav, advance/pause/end controls, alert overlay (HOLD/SLOW/PUSH/REDLINE), segment transition moment.

**Costs:**

- Garmin developer account: free
- Connect IQ SDK + simulator + VS Code extension: free
- Connect IQ Store distribution: free, no listing fees, lighter approval than App Store
- **Real-device test hardware: $250-450 for one Forerunner, $1500+ for cross-model coverage (Forerunner + Fenix + Venu).** This is the actual money cost.
- MonkeyC ramp-up: 1-2 weeks for a competent developer (statically-typed, vaguely Pascal-flavored, not deeply weird but unfamiliar)
- Initial app dev: 3-6 weeks for stripped-down Apple Watch parity
- **Ongoing maintenance: ~10-20% of one developer's time perpetually** — SDK breaking changes, model-specific UI quirks, firmware-specific bug reports

**iPhone-side architecture:**

A new `GarminCompanionService` mirrors the existing `WatchCompanionService` — same message-passing shape, same `RaceStateSnapshot` payload shape (would need a JSON-serializable variant since Connect IQ messages cap at ~512 bytes), same action enum. The link uses Garmin's **Connect IQ Mobile SDK** — an iOS framework we'd embed as a dependency. Apps like Strava, Spotify, Bose, and IFTTT all use it. It abstracts the BLE channel that Garmin Connect Mobile already operates and exposes a discovery + message-passing API.

**User-facing setup friction is the real cost.** For Path A alone, the user installs Trakrr and pairs a watch. Done. For Path C, the user must:

1. Install **Trakrr** from the App Store
2. Install **Trakrr CIQ** from the Connect IQ Store (on the watch)
3. Install **Garmin Connect Mobile** on the iPhone (required for the Connect IQ Mobile SDK link to function, even if the user doesn't otherwise want it)
4. Pair the watch through Garmin Connect Mobile via standard iOS Bluetooth settings
5. Authorize Trakrr in Garmin Connect Mobile's permissions

Three apps, multiple touchpoints, one experience. Strava users tolerate it because Strava is universal. For a niche HYROX app, that's real adoption friction.

**Decision criteria for when to build Path C:**

- Path A has shipped and we have at least 1000 Garmin-equipped Trakrr users actively training
- Survey / qualitative signal that those users specifically want a wrist race surface (rather than being content with phone + HR strap)
- Capacity to commit to perpetual maintenance — not a one-time build

Until those conditions hit, Path C is speculation. Solo-built apps that ship two watch stacks neither of which is polished is the failure mode to avoid.

### 20.5 — Sensor sourcing architecture extension

The `SensorSourceRegistry` (§19.2) and the `DeviceProfile` enum extend cleanly:

- New HR source variant: `.externalBLE(displayName: String)` alongside `.appleWatch`, `.airpodsPro3`, `.fused`.
- New device-profile entries:
  - `.externalHROnly` — iPhone + paired BLE HR strap, no Watch, no motion-capable AirPods
  - `.fullWithExternal` — iPhone + Apple Watch + AirPods Pro 3 + BLE HR strap (rare but possible — athlete who wants chest-strap-grade HR alongside their Watch)
- Fusion ranking: chest strap > Garmin watch in broadcast mode > AirPods Pro 3 > Apple Watch optical, but freshness arbitrates within a 5-second window (the existing rule).
- Source attribution glyph picks an SF Symbol per source: `applewatch`, `airpodspro`, `dot.radiowaves.left.and.right` for external BLE.
- Source provenance on RaceSummary / FreeRunSummary already iterates sources and renders a row per active source; just slot the new variant in.

### 20.6 — Feature viability matrix (Garmin user, no Apple Watch)

Assuming Path A + Phase 28 shipped, no Connect IQ app:

| Feature category | iPhone + Garmin BLE | iPhone + Apple Watch | Difference |
| :---- | :----: | :----: | :---- |
| Race timer / station advance / roxzone / pace ghost / Live Activity | 🟢 | 🟢 | None |
| Free Run timer / distance / splits | 🟢 | 🟢 | None |
| Live HR + zone bar + zone label | 🟢 | 🟢 | None |
| Live coaching cues (HOLD/SLOW/PUSH/REDLINE/RECOVER) | 🟢 | 🟢 | None |
| Guardrails (per-segment HR ceilings) | 🟢 | 🟢 | None |
| All §13.10 HR Intelligence post-race analytics (drift / recovery / efficiency / engine score) | 🟢 | 🟢 | None — both consume the same in-app HR series |
| HYROX Score composite | 🟢 | 🟢 | None |
| All social features (feed / follow / kudos / public profile) | 🟢 | 🟢 | None |
| Watch race UI (3-page nav / alert overlay / segment transition) | 🔴 | 🟢 | Apple Watch only |
| Hold-to-finish wrist gesture | 🔴 | 🟢 | Apple Watch only |
| IMU rep counting (Wall Balls / Burpees / Lunges / Farmers) | 🔴 | 🟢 | Apple Watch only (§13.8 Tier 2) |
| SpO2 per station | 🔴 | 🟢 | Apple Watch Series 6+ only |
| Skin temperature | 🔴 | 🟢 | Apple Watch Series 8+/Ultra only |
| Wrist ECG | 🔴 | 🟢 | Apple Watch Series 4+ only |
| Overnight HRV → richer Readiness Banner (§13.8 Tier 3) | 🔴 | 🟢 | Apple Watch only (chest straps may carry RR-intervals but no overnight wear) |
| Vertical oscillation, posture drift, ground contact | 🟡 | 🟡 | AirPods-driven; both surfaces same |
| Live cadence | 🟡 | 🟡 | AirPods-driven; both surfaces same |
| Voice cues | 🟢 | 🟢 | Phone speaker or AirPods, Watch not required |
| Path B post-race enrichment (running dynamics from Garmin) | 🟢 (if shipped) | 🔴 | Garmin-only feature once Path B lands |

**Bottom line:** ~90% feature parity. The lost 10% — wrist race surface, IMU rep counting, Watch-sensor-specific tiers (SpO2/temp/ECG/overnight HRV) — is well-defined and shippable as "Apple Watch users additionally get..."

### 20.7 — Phased roadmap (Phase 28+)

| Phase | Scope | Effort | Status | Gates |
| :---- | :---- | :---- | :---- | :---- |
| **28** | In-app HR series for Race — mirror Phase 27 onto `Race` model + `RaceViewModel`. Prerequisite for Path A's value on HYROX races. | ~3-4 days | ⚪ | None — can ship independent of Garmin work |
| **29** | Path A: `ExternalHRService` + pairing UI + `SensorSourceRegistry` extension + ingest wiring. | ~1.5 weeks | ⚪ | Phase 28 shipped |
| **30** | Path A polish — background mode, reconnect, source provenance row, multi-source fallover UX. | ~3-4 days | ⚪ | Phase 29 shipped |
| **31** | Apply for Garmin Health API partner program. No code; just the application + paperwork. | ~1 day + 1-6 month wait | ⚪ | None — start clock immediately |
| **32** | Path B: backend webhook receiver + OAuth + workout-matching + Race row enrichment. | ~3 weeks | ⚪ | Phase 31 approval + sustained Garmin user adoption signal from Phase 29-30 |
| **33** | Path C decision gate — survey Garmin users on wrist race surface demand, evaluate build cost vs benefit. | ~1 week analysis | ⚪ | ≥1000 active Garmin users on Trakrr |
| **34** | Path C: Trakrr CIQ MonkeyC app — race screen, advance, alert overlay. Distributed via Connect IQ Store. | ~3-6 weeks initial + perpetual maintenance | ⚪ | Phase 33 green-light |

### 20.8 — Strategic positioning

**The framing for App Store / marketing / website should be:**

> *"Trakrr works with Apple Watch, Garmin, Polar, Wahoo, or any Bluetooth heart rate monitor. Apple Watch users additionally get the wrist race screen and automatic rep counting on Wall Balls."*

This positions Trakrr as the most universal HYROX app while giving Apple Watch users a real extra-credit story. It's honest, broad, and explicitly captures the user-friction reality: an athlete with their existing kit (any modern smartwatch or chest strap) can use Trakrr today.

**Comparison to Strava's positioning:** Strava says "compatible with 100+ devices" because their value is post-workout aggregation and they truly are device-agnostic. Trakrr's positioning is the same shape but tighter — we're a coaching platform, so we emphasize the live HR layer rather than the full feature set. The same "any BLE strap" pattern Strava uses in their device-pairing flow is what Trakrr ships in Path A.

**Defensible moat against ROXFIT, Intervals Pro, and generic HYROX apps:** none of them have shipped Path A, let alone Paths B and C. Most assume Apple Watch (or Garmin's first-party Connect IQ workouts) and break for users with the wrong device. Path A is a real wedge that broadens Trakrr's addressable market by a meaningful multiple — every HYROX-format athlete with any HR source becomes a candidate user.

**Sequencing discipline (the §13.11 promotion rule applied):** Path A goes into §4 v1+ scope once Phase 27 (continuous HR capture for Free Run) verifies clean on real device. Path B's application starts in parallel with Path A's dev. Path C stays in the §13 backlog as ⚪ idea-tier until adoption signal justifies the maintenance commitment. Don't promote out of order.  

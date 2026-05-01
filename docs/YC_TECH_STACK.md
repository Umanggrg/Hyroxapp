# YC Application — Tech Stack Answer

A drafted answer to "What is your tech stack?" tuned for a YC-style application. Two versions below — a tight one for the form's character cap, and a longer one if a follow-up prompt asks for more detail.

---

## Short version (~1,200 chars, fits most YC fields)

Trakrr is a native iOS app with an Apple Watch companion, built in Swift 6 with strict concurrency and SwiftUI throughout. On-device persistence is SwiftData (iOS 17+). Live race state syncs phone↔watch over WatchConnectivity and phone↔phone for Duo Mode over Apple's MultipeerConnectivity (peer-to-peer, no backend, encrypted by default). Health data integrates via HealthKit + WorkoutKit — heart-rate sampling, active-energy reads, workouts written back to Apple Health. Live Activities surface the race timer on the Lock Screen and Dynamic Island via ActivityKit + WidgetKit.

The planned v1 backend is Supabase (Postgres + Auth + Realtime + Storage) — solo-founder-friendly economics, easy path to cloud-synced Duo Mode and a social feed. CoreMotion + Create ML (on-device) is queued for sensor-based rep counting on the Watch — a feature no other hybrid-fitness app offers.

A single founder built the entire codebase (10K+ LOC across iPhone, Watch, and Widget targets, 300+ shipped tasks) in evenings and weekends, pair-programming every line with Claude (Anthropic's model) via Claude Code. No third-party analytics, ads, or trackers. Privacy Manifest declares zero data collection. Native-first because hybrid-fitness racing demands sub-second sensor latency that React Native and Flutter can't deliver.

---

## Long version (if YC asks for more detail)

### Mobile (shipped)

- **Swift 6 with strict concurrency**, SwiftUI throughout. No UIKit except for haptics (`UIImpactFeedbackGenerator`).
- **SwiftData** for on-device persistence — modern, first-party, replaces Core Data. iOS 17+ minimum deployment target.
- **@Observable** macro for reactive view models; pure-Swift `RaceEngine` state machine kept transport-agnostic so the same engine drives solo races, the Watch mirror, and Multipeer Duo Mode broadcasts.
- **SwiftCharts** for trend visualizations — HR zones, fatigue curves, performance overload, weekly/monthly/yearly recaps.

### Apple frameworks

- **HealthKit + WorkoutKit** — heart-rate sampling and active-energy reads during a race; finished races write back as `HKWorkout` so they appear in Apple Fitness alongside other activity.
- **WatchConnectivity (WCSession)** — bidirectional iPhone ↔ Apple Watch sync via a shared `RaceStateSnapshot` Codable struct shipped over `updateApplicationContext` and `sendMessage`.
- **MultipeerConnectivity** — peer-to-peer Duo Mode for HYROX Doubles. Two iPhones at the same gym pair over Bluetooth + Wi-Fi Direct, encrypted by default, zero backend required.
- **ActivityKit + WidgetKit** — Live Activities surface the race timer on the Lock Screen and Dynamic Island.
- **CoreMotion** (planned) — accelerometer + gyroscope-based rep counting for wall balls, sandbag lunges, burpee broad jumps, and farmer's carry.

### Planned backend (v1, post-MVP)

- **Supabase** — Postgres + Auth + Realtime (WebSocket) + Storage in one. Chosen for solo-founder economics; supports the eventual social feed, leaderboards, follower graph, and cloud-backed Duo Mode (athletes in different cities, over cellular).
- **Sign in with Apple** for auth.
- **Create ML** (on-device) for the gesture classifier behind sensor-based rep counting. Trained per-station, runs locally, no model data leaves the device.

### Testing + tooling

- **Swift Testing** (`@Test`, `@Suite`) for unit tests; **XCTest** for UI tests.
- **TestFlight** for beta distribution.
- **Xcode + Git**, with **Privacy Manifest** (`PrivacyInfo.xcprivacy`) declaring zero data collection — required for all App Store submissions since Spring 2024.

### AI coding tools

The entire codebase was pair-programmed with **Claude (Anthropic's Claude Sonnet) via Claude Code** — architecture, every shipped feature, motion language, copy review, privacy compliance, and the recent rebrand from "Hyroxapp" to "Trakrr" to avoid HYROX™ trademark exposure. No third-party AI/ML SDKs in the shipping app itself; the only ML is Apple's Create ML, on-device.

### Why native, why this stack

Hybrid-fitness racing demands the kind of sub-second sensor latency, deep HealthKit + Watch integration, and Apple-fluent UX that cross-platform frameworks (React Native, Flutter) can't match. Native is also what makes the Watch a first-class surface rather than an afterthought — for mid-race interaction, the wrist beats the phone every time.

Supabase as the planned backend keeps fixed costs near zero through MVP while supporting the eventual social and competitive layer. Claude Code is the force multiplier that lets a single founder move at small-team velocity: 10K+ lines of production Swift across iPhone, Watch, and Widget targets, hundreds of components, comprehensive motion + accessibility polish — built solo, in evenings and weekends.

### Notable architecture decisions

- **Snapshot-based sync.** One `RaceStateSnapshot` Codable struct ships over both WCSession (to the Watch) and MultipeerConnectivity (to a duo partner). Receivers reconstruct state identically. The same shape powers Live Activities.
- **Host-authoritative Duo Mode.** Either partner can tap Start / Next / Finish, but the guest's tap becomes a `requestAdvance` message; the host's engine is the source of truth and broadcasts the new state back. Avoids two engines drifting in sync.
- **Swift 6 strict concurrency.** `@MainActor` / `nonisolated` split around delegate callbacks that fire from background queues (Multipeer's `MCSession`, `WCSession`). No data races at compile time.
- **Reduce Motion respected throughout.** Every animation gates on `@Environment(\.accessibilityReduceMotion)` so vestibular-sensitive users get the full app without motion.
- **Privacy by architecture, not policy.** No analytics SDK, no crash reporter beyond Apple's anonymous MetricKit, no ad networks, no tracking. Health data and race history never leave the device. The Privacy Manifest declares this honestly; the App Store submission asserts no encryption export compliance.

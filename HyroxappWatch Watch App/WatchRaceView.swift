import SwiftUI

// Live race screen for the watchOS companion app.
//
// Reads `WatchRaceClient.shared.snapshot` via `@Environment` and renders
// one of three states:
//   - `.waiting`   — no snapshot received yet (launched before the phone
//                    pushed anything, or paired phone not reachable).
//   - `.inProgress` — live race: computes its own timer from
//                     `snapshot.startedAt` every frame via TimelineView,
//                     shows current station + target + advance button.
//   - `.finished`   — frozen final time (from `endedAt - startedAt`),
//                     labeled "Finished".
// A separate `notStarted` phase rolls into `.waiting` visually — an
// idle phone with no active race looks the same to the athlete as a
// watch that hasn't heard from the phone yet.
//
// The watch does NOT own race state. Every field rendered here comes
// from the snapshot pushed by the phone. The only thing the watch
// computes locally is elapsed time (to avoid per-frame pushes eating
// the battery and network).
//
// Design language carries the same brand identity as the iOS app:
// the 16-bar fingerprint motif, coral chip + glow on the station/
// timer hero, white-on-coral button (`Color.onAccent` for the
// brand contract). Tuned for 41–49mm Watch faces — no filler,
// every Spacer earns its place. watchOS is dark-only so we don't
// need light-mode plumbing here; `Color.background` falls back
// to the dark hex on watchOS automatically.
struct WatchRaceView: View {

    @Environment(WatchRaceClient.self) private var client

    // Reduce-motion accessibility setting — collapses the alert
    // overlay's spring entrance into a hard cut for users who've
    // enabled it. Same convention every animated surface in the
    // app uses; see §13.9 design language doc.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Tracks the last seen coaching cue so we can fire a haptic on
    // every transition (hold→slow, push→hold, etc.) without firing
    // continuously on every snapshot push at the same cue. Stored as
    // the enum's rawValue String because @State + Equatable on
    // associated-value-free enums is fine, but rawValue makes the
    // initial-state encoding unambiguous and decouples this State
    // from the enum itself in case its cases get reordered later.
    //
    // Initialized to nil so the very first cue we receive doesn't
    // fire a haptic on its own — we only buzz on actual transitions
    // mid-race, not on race start.
    @State private var lastCueRaw: String?

    // The currently-displayed Race Awareness alert overlay (§15).
    // Set when the coaching cue transitions; cleared automatically
    // by an attached Task after `alertOverlayDuration`. Renders
    // full-screen on top of the in-progress TabView when non-nil.
    @State private var activeAlertCue: RaceStats.CoachingCue?

    // Last-seen guardrail state. State-machine that ensures the
    // anticipatory haptic fires ONCE when HR first enters the
    // approach band, and doesn't repeat continuously while HR
    // sits in the band. Re-fires only after HR drops below
    // approach and re-enters. Same per-transition firing pattern
    // as the existing `lastCueRaw` state for coaching cues.
    @State private var lastGuardrailState: GuardrailState = .silent

    // Handle to the pending dismiss-the-overlay task so we can
    // cancel it if a new cue transition fires before the current
    // overlay times out. Without cancellation, two rapid
    // back-to-back transitions would have their dismiss tasks
    // race against each other.
    @State private var alertDismissTask: Task<Void, Never>?

    // Segment Transition Moment state (§15 phase 3). Track the
    // last station index we saw on the snapshot so we can detect
    // an advance — when the index changes, we know a segment
    // just completed and we should celebrate the moment.
    //
    // Stored as Int? so the very first snapshot we see (race
    // start) doesn't trigger a transition overlay — we have no
    // previous index to compare to, so transitionFromIndex stays
    // nil until the second snapshot lands.
    @State private var lastStationIndex: Int?
    @State private var activeTransitionOverlay: TransitionOverlayState?
    @State private var transitionDismissTask: Task<Void, Never>?

    // Bundles the data the segment-transition overlay needs into
    // one optional. Using a struct rather than three nullable
    // strings keeps the `if let` render path readable.
    private struct TransitionOverlayState: Equatable {
        let completedStationLabel: String
        let completedDuration: TimeInterval
        let nextStationLabel: String
    }

    // §15 segment transition overlay duration. 2.4s matches the
    // alert overlay duration so the athlete sees consistent
    // pacing on every full-screen takeover; long enough for a
    // sweaty glance, short enough to clear before the next
    // segment timer needs the glance budget.
    private static let transitionOverlayDuration: TimeInterval = 2.4

    // How long the full-screen alert overlay sticks around before
    // auto-dismissing. §15 says 2-3 seconds; 2.4s lands in the
    // middle — long enough for a sweaty glance to register but
    // short enough that the athlete isn't blocked from seeing
    // their timer when they actually want to look at it.
    private static let alertOverlayDuration: TimeInterval = 2.4

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            // Free Run takes precedence — when the iPhone is
            // pushing a free-run snapshot, render that surface
            // and ignore any stale race state (the two are
            // mutually exclusive on the iPhone side; clearing
            // is handled by `WatchRaceClient.ingest`).
            if let freeRun = client.freeRunSnapshot,
               freeRun.phase != .notStarted {
                WatchFreeRunView(snapshot: freeRun)
            } else if let snapshot = client.snapshot {
                // Switch on phase. The `case` bindings pull the snapshot into
                // each branch so we can pass concrete values to the subviews
                // without having to unwrap optional fields everywhere.
                switch snapshot.phase {
                case .inProgress:
                    inProgressView(snapshot: snapshot)
                case .paused:
                    pausedView(snapshot: snapshot)
                case .inRoxzone:
                    roxzoneView(snapshot: snapshot)
                case .finished:
                    finishedView(snapshot: snapshot)
                case .notStarted:
                    waitingView
                }
            } else {
                waitingView
            }

            // §15 Race Awareness System overlay — full-screen
            // takeover for 2-3s on every actionable cue
            // transition. Sits in the same ZStack as the phase
            // views so the underlying timer continues ticking
            // beneath it; auto-dismisses via a Task scheduled in
            // `handleCoachingCueChange`. Animation is gentle
            // (200ms spring) so the entrance lands with weight
            // rather than blasts.
            if let alertCue = activeAlertCue {
                WatchAlertOverlay(cue: alertCue)
                    .zIndex(1)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.85),
                        value: activeAlertCue
                    )
            }

            // §15 Segment Transition Moment — fires on every
            // station advance, briefly celebrating the just-
            // completed segment before stepping out of the way
            // for the new station's timer. zIndex(2) places it
            // above the alert overlay so a transition that
            // happens to coincide with a cue change wins (the
            // transition is the more important moment — the cue
            // overlay can fire again on the next sample).
            if let transition = activeTransitionOverlay {
                WatchSegmentTransitionOverlay(
                    completedStationLabel: transition.completedStationLabel,
                    completedDuration: transition.completedDuration,
                    nextStationLabel: transition.nextStationLabel
                )
                .zIndex(2)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.85),
                    value: activeTransitionOverlay
                )
            }
        }
        .onChange(of: client.snapshot?.currentStationIndex) { _, newIndex in
            handleStationIndexChange(to: newIndex)
        }
        // Self-heal HKWorkoutSession state from the snapshot phase.
        // This is the resilience fix for "HR not showing" — if the
        // iPhone's `sendControl(.startWorkout)` was dropped because
        // the Watch app wasn't reachable at race-start (sendMessage
        // silently fails when isReachable == false), the Watch
        // never started its HK session and HR samples never flowed.
        // The snapshot `updateApplicationContext` IS queued and
        // delivered when the Watch app comes up — so by the time
        // we observe `phase == .inProgress`, we have everything we
        // need to start the session locally, backdated to the
        // snapshot's `startedAt`. WatchWorkoutManager.start guards
        // against double-start, so this is idempotent against the
        // happy-path case where the control DID arrive.
        .onChange(of: client.snapshot?.phase) { _, newPhase in
            synchronizeWorkoutSession(forPhase: newPhase)
        }
        // Also sync on first appearance — the Watch app may launch
        // straight into a mid-race state (snapshot already pending
        // from the activation callback) and we need to start the
        // HK session even though no `.onChange` will fire for that
        // initial value.
        .onAppear {
            synchronizeWorkoutSession(forPhase: client.snapshot?.phase)
        }
        // Guardrail state watcher — fires the anticipatory
        // haptic when HR enters the approach band (§17.1). The
        // computed `currentGuardrailState` reads the latest HR
        // (local Watch source preferred) against the snapshot's
        // ceiling/approach thresholds. State-machine in
        // `handleGuardrailStateChange` ensures we buzz ONCE per
        // entry into the band, not continuously while in it.
        .onChange(of: currentGuardrailState) { _, newState in
            handleGuardrailStateChange(to: newState)
        }
        // Coaching-cue transition haptic. Computes the current cue
        // from the snapshot; when it changes (and we're mid-race),
        // fires a haptic distinct to the new state so the athlete
        // feels the shift without looking at the wrist:
        //   • .hold (you found race pace)        → success haptic
        //   • .slow (above sustainable pace)     → failure / warning
        //   • .push (below race pace, more gas)  → light click
        //   • .workout / .none (no actionable signal) → silent
        //
        // The only-mid-race gate is important: we don't want a buzz
        // on the very first HR sample after race start (.none → .hold
        // is fine but .none → .slow shouldn't startle), nor on
        // race-end transitions when the snapshot phase flips to
        // .finished. Both are handled by the `lastCueRaw == nil`
        // first-fire skip + by only computing the cue while phase
        // is .inProgress.
        .onChange(of: currentCoachingCueRaw) { _, newRaw in
            handleCoachingCueChange(to: newRaw)
        }
    }

    // Re-derives the current coaching cue from whatever the latest
    // snapshot says. Returns the rawValue String for use as a
    // .onChange identity (Equatable, plist-friendly). Returns nil
    // outside an active race so the .onChange handler can skip
    // pre-race / post-race phase transitions.
    private var currentCoachingCueRaw: String? {
        guard let snapshot = client.snapshot,
              snapshot.phase == .inProgress
        else { return nil }
        // Prefer the local Watch HR (zero-latency, sourced
        // directly from the active workout builder) over the
        // snapshot HR (phone-roundtrip, ~1-3s slower). This
        // means cue transitions + the alert overlay fire on
        // the wrist as soon as the underlying sample changes,
        // not after the iPhone has bounced it back.
        guard let hr = WatchWorkoutManager.shared.currentHeartRateBPM
            ?? snapshot.currentHeartRateBPM else {
            return nil
        }
        // Centralized cue resolver on RaceStateSnapshot uses the
        // personal HR band carried on the snapshot when present
        // (athlete-specific Z3 from RaceStats.personalHRBaseline)
        // and falls back to textbook Z3 when not — same logic
        // as the iPhone race screen.
        return snapshot.coachingCue(forCurrentHR: hr).rawValue
    }

    private func handleCoachingCueChange(to newRaw: String?) {
        defer { lastCueRaw = newRaw }
        // First-ever cue we see this race — no haptic, no overlay.
        // The athlete is just settling in; buzzing or taking over
        // the screen on the first BPM sample would be noise, not
        // signal.
        guard lastCueRaw != nil else { return }
        guard let newRaw, let newCue = RaceStats.CoachingCue(rawValue: newRaw) else { return }

        // Haptic side. Distinct pattern per cue so the wrist
        // signals "what just happened" before the eye reaches
        // the watch face.
        switch newCue {
        case .hold:
            // You hit the zone — affirming double-tap.
            Haptics.success()
        case .slow:
            // Pull back — failure pattern is the strongest "stop"
            // signal watchOS exposes without going to .notification
            // (which is too loud for an in-race nudge).
            Haptics.warning()
        case .push:
            // Gentle "more gas" tap. Light click, easy to miss
            // mid-stride which is the right tradeoff — pushing is
            // less urgent than pulling back.
            Haptics.impact(.light)
        case .workout, .none:
            // Workout stations and no-cue states get no buzz. Mid
            // sled push the wrist is loaded; an unsolicited tap
            // there reads as a malfunction, not coaching.
            break
        }

        // Visual side — §15 Race Awareness alert overlay. Fire
        // the full-screen takeover for actionable cues only;
        // workout/none silently skip (matches the haptic
        // suppression above). Auto-dismiss after the §15
        // 2-3 second window.
        guard newCue.shouldShowAlertOverlay else { return }

        // §15 final-2-stations SLOW suppression — we've stopped
        // coaching "pull back" at this point in the race so the
        // athlete can empty the tank. HOLD and PUSH still fire
        // (affirmation + motivator, not a brake). The earlier
        // haptic stage of this method DID still fire on .slow,
        // which is intentional — the silent buzz is acceptable
        // continuity, but the full-screen takeover would
        // visually nag.
        if let snapshot = client.snapshot,
           newCue == .slow,
           shouldSuppressSlowAlert(snapshot: snapshot) {
            return
        }

        showAlertOverlay(cue: newCue)
    }

    // Display the alert overlay for the configured duration,
    // then clear it. Cancels any in-flight dismiss task so
    // back-to-back cue changes (rare but possible — push → hold
    // within a few seconds during a Z3 brush) don't fight each
    // other for the screen.
    private func showAlertOverlay(cue: RaceStats.CoachingCue) {
        alertDismissTask?.cancel()
        activeAlertCue = cue
        alertDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.alertOverlayDuration))
            guard !Task.isCancelled else { return }
            activeAlertCue = nil
        }
    }

    // §17.1 Guardrail state derivation. Reads the latest HR
    // (local Watch source preferred, snapshot fallback) against
    // the snapshot's per-segment ceiling + approach thresholds.
    // Returns `.silent` when any input is missing — the haptic
    // handler treats `.silent` transitions as "no signal," so
    // missing data means no spurious buzzing.
    private var currentGuardrailState: GuardrailState {
        guard let snapshot = client.snapshot,
              snapshot.phase == .inProgress else { return .silent }
        let hr = WatchWorkoutManager.shared.currentHeartRateBPM
            ?? snapshot.currentHeartRateBPM
        guard let hr,
              let ceiling = snapshot.segmentHRCeiling,
              let approach = snapshot.segmentHRApproachThreshold,
              hr > 0 else { return .silent }
        if hr >= ceiling { return .aboveCeiling }
        if hr >= approach { return .approaching }
        return .silent
    }

    // Anticipatory haptic firing on guardrail transitions
    // (§17.1). Buzzes ONCE when HR enters a new band:
    //   • silent → approaching: warning haptic ("you're about
    //     to cross the ceiling")
    //   • approaching → aboveCeiling: stronger heavy haptic
    //     ("you're past the ceiling")
    //   • Any → silent: no haptic ("good, you came back down")
    //
    // Re-firing only on transitions (not while in a band) is the
    // §17.1 design principle: silence = you're fine; we speak
    // only when state changes.
    private func handleGuardrailStateChange(to newState: GuardrailState) {
        defer { lastGuardrailState = newState }
        // First-ever state we see this race — no haptic; the
        // race has just started and we don't know if the
        // athlete is settling in.
        guard newState != lastGuardrailState else { return }

        switch newState {
        case .approaching:
            // Crossing into the approach band — anticipatory.
            // Distinct from the cue-change haptics above so the
            // athlete can tell "approaching ceiling" apart from
            // "zone changed."
            Haptics.warning()
        case .aboveCeiling:
            // Crossed the ceiling — stronger signal. Reactive
            // rather than anticipatory at this point.
            Haptics.impact(.heavy)
        case .silent:
            // Came back below approach — no haptic, just
            // visual chip color change.
            break
        }
    }

    // Watcher for `currentStationIndex` changes on the snapshot.
    // When the index changes (any direction) AND we have a
    // previous index to compare to, fire the §15 Segment
    // Transition Moment overlay celebrating the just-completed
    // segment. Skipped on the very first snapshot of a race
    // (no previous index) and on race-end transitions where
    // the snapshot phase flips to .finished (separate UX —
    // the finishedView already handles celebration).
    private func handleStationIndexChange(to newIndex: Int?) {
        defer { lastStationIndex = newIndex }

        // Need both old and new — first snapshot of a race
        // gives lastStationIndex == nil, skip until next.
        guard let previousIndex = lastStationIndex,
              let newIndex,
              previousIndex != newIndex,
              let snapshot = client.snapshot else { return }

        // Skip if the race ended — the finished view celebrates
        // the whole race; layering a "RUN 8 COMPLETE → NEXT:"
        // overlay on top would conflict.
        guard snapshot.phase == .inProgress else { return }

        // Pull the just-completed split's data. The host adds
        // splits in chronological order, so the most-recent
        // split is the one we just finished.
        guard let completedSplit = snapshot.splits.last else { return }
        let completedStation = Station(rawValue: completedSplit.stationRaw)
        let completedLabel = completedStation?.displayName ?? "STATION"
        let completedDuration = completedSplit.endedAt.timeIntervalSince(completedSplit.startedAt)

        // The new station the athlete is about to start. Pulled
        // from the snapshot's currentStation accessor (it
        // resolves the new index back through Station(rawValue:)).
        let nextLabel = snapshot.currentStation?.displayName ?? "—"

        showTransitionOverlay(
            completed: completedLabel,
            duration: completedDuration,
            next: nextLabel
        )
    }

    private func showTransitionOverlay(
        completed: String,
        duration: TimeInterval,
        next: String
    ) {
        transitionDismissTask?.cancel()
        activeTransitionOverlay = TransitionOverlayState(
            completedStationLabel: completed,
            completedDuration: duration,
            nextStationLabel: next
        )
        // Add a subtle haptic on top of whatever the existing
        // advance flow fires — the success pattern reinforces
        // the celebratory moment.
        Haptics.success()
        transitionDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.transitionOverlayDuration))
            guard !Task.isCancelled else { return }
            activeTransitionOverlay = nil
        }
    }

    // Sync the Watch's HKWorkoutSession state with whatever the
    // snapshot says about the race phase. Idempotent — calling it
    // when the session is already in the right state is a no-op
    // (WatchWorkoutManager guards both start and end).
    //
    // This is the resilience layer for the "Watch app wasn't
    // reachable when iPhone tapped Start" failure mode:
    //
    //   1. iPhone fires `sendControl(.startWorkout)` via
    //      sendMessage — REQUIRES `session.isReachable == true`.
    //   2. iPhone fires `updateApplicationContext(snapshot)` —
    //      QUEUED, delivered whenever the Watch app next runs.
    //
    // If the Watch app is asleep at step 1, the start command is
    // dropped (sendMessage doesn't queue). The snapshot still
    // arrives at step 2 when the user raises their wrist, so the
    // Watch UI shows the race state — but the HK session was
    // never created and no HR samples flow.
    //
    // This method closes that gap: when we OBSERVE a phase that
    // implies a session should be running, we start one locally
    // backdated to the snapshot's `startedAt`. HKWorkoutSession
    // accepts a past start date — Apple's docs use that exact
    // pattern for "athlete forgot to start the workout" UX.
    //
    // Symmetric on the end side: if we observe `.finished` while
    // we still have an active session (e.g. the iPhone's
    // `.endWorkout` was dropped), we end the session.
    private func synchronizeWorkoutSession(forPhase phase: RaceStateSnapshot.Phase?) {
        let manager = WatchWorkoutManager.shared

        switch phase {
        case .inProgress, .inRoxzone, .paused:
            // A race is running. We should have an active HK
            // session. Start one if we don't (backdated to the
            // snapshot's startedAt so the duration is accurate).
            guard let startedAt = client.snapshot?.startedAt else { return }
            guard !manager.isWorkoutActive else { return }
            manager.handle(.startWorkout(at: startedAt))

        case .finished:
            // Race ended. End any session we've still got open.
            // Idempotent — handle() guards against ending a
            // non-active session.
            guard manager.isWorkoutActive else { return }
            manager.handle(.endWorkout(at: client.snapshot?.endedAt ?? Date()))

        case .notStarted, .none:
            // No race. If we somehow have a leftover session
            // (e.g. crash + relaunch), discard it.
            guard manager.isWorkoutActive else { return }
            manager.handle(.discardWorkout)
        }
    }

    // §15 final-2-stations SLOW suppression. The design
    // principle: let the athlete empty the tank in the closing
    // stretch without "pull back" coaching. Hold + Push still
    // fire (they're affirmations or motivators, not nags),
    // SLOW gets silenced.
    private func shouldSuppressSlowAlert(snapshot: RaceStateSnapshot) -> Bool {
        let stationsRemaining = snapshot.totalStations - snapshot.completedStationsCount
        return stationsRemaining <= 2
    }

    // MARK: - In-progress

    // Live race layout per CLAUDE.md §15 — three pages stacked
    // vertically, navigable via the Digital Crown:
    //
    //   Page 0: Splits  (scroll up)   — completed segments list
    //   Page 1: Race    (default)     — segment + big timer + pace + HR
    //   Page 2: HR      (scroll down) — engine-room detail
    //
    // We use `TabView(.page)` — on watchOS this is exactly the
    // crown-paginated vertical UX §15 specifies (Apple Workouts
    // uses the same pattern). `selection: .constant(1)`
    // initializes on the Race page; the user can crown up to
    // Splits or down to HR from there.
    //
    // The TabView re-evaluates on every snapshot push, so all
    // three pages stay in sync with the host's race state. Each
    // page owns its own TimelineView for ticking (independent of
    // sibling pages) so off-screen pages don't drain battery
    // re-rendering hidden content.
    private func inProgressView(snapshot: RaceStateSnapshot) -> some View {
        TabView(selection: .constant(1)) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                WatchRaceSplitsPage(snapshot: snapshot, now: context.date)
            }
            .tag(0)

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                WatchRaceMainPage(
                    snapshot: snapshot,
                    now: context.date,
                    onAdvance: { Self.handleAdvanceTap() },
                    isFinalStation: isFinalStation(snapshot: snapshot),
                    holdToFinishButton: AnyView(holdToFinishButton)
                )
            }
            .tag(1)

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                WatchRaceHRPage(snapshot: snapshot)
            }
            .tag(2)
        }
        .tabViewStyle(.page)
    }

    // Fire the advance action from the Race page's button. Sits
    // here rather than inline on the page so the WCSession plumbing
    // stays in WatchRaceView's existing button machinery.
    private static func handleAdvanceTap() {
        Haptics.impact(.medium)
        WatchRaceClient.shared.send(.advance)
    }

    // True when the upcoming advance would close the race —
    // the athlete is currently on the last segment, so the next
    // tap on the button finishes (rather than progresses to a
    // new segment). Mirrors the same check on the iPhone's
    // RaceView.
    private func isFinalStation(snapshot: RaceStateSnapshot) -> Bool {
        snapshot.completedStationsCount + 1 == snapshot.totalStations
    }

    // MARK: - Paused

    // Race is frozen — phone is in .paused state. The watch
    // shows the elapsed time at the moment of pause, dimmed,
    // with a "PAUSED" chip and a hint that resume is on the
    // phone (the Watch doesn't have a resume affordance yet —
    // the phone owns the pause/resume gesture so the owner of
    // the action sees the result).
    //
    // No TimelineView here — the timer is frozen, so we just
    // render once. That also saves a tiny bit of battery while
    // the user is dealing with the interruption.
    private func pausedView(snapshot: RaceStateSnapshot) -> some View {
        let frozen: TimeInterval = {
            guard let start = snapshot.startedAt,
                  let pause = snapshot.pausedAt
            else { return 0 }
            return pause.timeIntervalSince(start)
        }()

        return VStack(spacing: 6) {
            // Same fingerprint at the top — completed bars stay
            // lit, current bar still glows. Visual continuity
            // with the running state so the user knows they're
            // in the same race, just paused.
            WatchFingerprintProgress(
                completedCount: snapshot.completedStationsCount,
                currentIndex: snapshot.currentStationIndex,
                totalCount: snapshot.totalStations
            )
            .frame(height: 18)
            .padding(.horizontal, 4)
            .opacity(0.55)

            // Pause chip — textSecondary tint signals "passive
            // state, nothing's happening." No coral — coral
            // means action and there's nothing actionable
            // here from the wrist.
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("PAUSED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.surfaceElevated)
            )

            Spacer(minLength: 2)

            Text(RaceStats.format(frozen))
                .font(WatchMetrics.font(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                // Dimmer than the running state's textPrimary —
                // textSecondary signals "frozen / inactive."
                .foregroundStyle(Color.textSecondary)

            if let station = snapshot.currentStation {
                Text("on \(station.displayName)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            // Resume button — wrist parity with the iPhone's
            // pause/resume gesture. Tap fires `.resume` to the
            // phone; phone calls viewModel.resumeRace, which
            // shifts the timer forward by the pause duration so
            // existing elapsed-time math keeps working. Phone's
            // broadcast then flips the snapshot phase back to
            // .inProgress and the watch routes back to its
            // running view.
            Button {
                Haptics.success()
                WatchRaceClient.shared.send(.resume)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(WatchMetrics.font(size: 13, weight: .heavy))
                    Text("Resume")
                        .font(WatchMetrics.font(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: WatchMetrics.dim(38))
                .background(
                    LinearGradient(
                        colors: [Color.accent, Color.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.accent.opacity(0.35), radius: 10, y: 0)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    // MARK: - In Roxzone

    // Athlete just ended a segment; transition timer is running
    // until they tap to start the next station. Mirrors the
    // iOS roxzone overlay's visual language: amber-tinted
    // timer with a soft glow, "IN ROXZONE" caps chip, the
    // upcoming station's name as the up-next hint, and a
    // start-next button.
    //
    // Same `.advance` action as the regular Next Station
    // button — on the phone side, the engine's
    // `startNextSegment` handler interprets that correctly
    // when the engine state is .inRoxzone.
    private func roxzoneView(snapshot: RaceStateSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let transitionElapsed = snapshot.currentSegmentStartedAt
                .map { context.date.timeIntervalSince($0) } ?? 0

            VStack(spacing: 6) {
                WatchFingerprintProgress(
                    completedCount: snapshot.completedStationsCount,
                    currentIndex: snapshot.currentStationIndex,
                    totalCount: snapshot.totalStations
                )
                .frame(height: 18)
                .padding(.horizontal, 4)

                // Amber chip — same `Color.warning` token used
                // for transition-time treatments throughout the
                // app. Reads as "you're in a meaningful but
                // off-station state."
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .heavy))
                    Text("IN ROXZONE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.0)
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.warning.opacity(0.16))
                )

                Spacer(minLength: 2)

                // Transition time hero — amber instead of the
                // textPrimary used during a station, signaling
                // "this is non-work time, keep moving."
                Text(RaceStats.format(transitionElapsed))
                    .font(WatchMetrics.font(size: 38, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.warning)
                    .shadow(color: Color.warning.opacity(0.35), radius: 10, y: 0)

                if let station = snapshot.currentStation {
                    Text("Up next · \(station.displayName)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 2)

                // Start-next button — same coral CTA, different
                // label and icon. Sends `.advance`; phone routes
                // it to `startNextSegment` based on engine state.
                Button {
                    Haptics.impact(.medium)
                    WatchRaceClient.shared.send(.advance)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(WatchMetrics.font(size: 13, weight: .heavy))
                        Text("Start \(snapshot.currentStation?.displayName ?? "Next")")
                            .font(WatchMetrics.font(size: 14, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchMetrics.dim(38))
                    .background(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.accent.opacity(0.4), radius: 10, y: 0)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private func stationHeader(snapshot: RaceStateSnapshot) -> some View {
        VStack(spacing: 3) {
            // Station counter — coral pill so it reads as "you are
            // here" rather than passive metadata. Same caps-tracked
            // typography as the iOS app's section headers, scaled
            // for the watch viewport.
            Text("STATION \(snapshot.completedStationsCount + 1) OF \(snapshot.totalStations)")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.accent.opacity(0.15))
                )

            Text(snapshot.currentStation?.displayName ?? "—")
                .font(WatchMetrics.font(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Station target uses the user's division (from the snapshot)
            // so wall balls renders 75 reps / 100 reps correctly on the
            // watch too — no need for the watch to know about UserProfile.
            if let station = snapshot.currentStation {
                Text(station.target(for: snapshot.division))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func timerDisplay(snapshot: RaceStateSnapshot, now: Date) -> some View {
        // Compute elapsed locally from startedAt so the watch ticks in
        // sync with the phone without per-second pushes. `startedAt` is
        // always present in inProgress snapshots — but we guard with ??
        // for safety.
        let total = snapshot.startedAt.map { now.timeIntervalSince($0) } ?? 0
        let segment = snapshot.currentSegmentStartedAt.map { now.timeIntervalSince($0) } ?? 0

        return VStack(spacing: 2) {
            Text(RaceStats.format(total))
                .font(WatchMetrics.font(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                // Subtle coral underglow — same brand language as
                // the iOS hero finish moment, dialed for the
                // smaller viewport.
                .shadow(color: Color.accent.opacity(0.35), radius: 10, y: 0)

            HStack(spacing: 8) {
                Text(RaceStats.format(segment))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                // HR chip — small heart + bpm digits + coaching cue
                // color. Mirrors the iPhone race screen's live HR chip
                // so the wrist surface speaks the same language. Cue
                // is computed locally from the snapshot fields the
                // phone already sends (HR, max HR, current station) —
                // no schema change needed. Tint follows the cue:
                // green hold, red slow, blue push, zone-color on
                // workout stations (no pace cue mid-sled-push).
                //
                // HR source priority: local Watch builder first
                // (zero-latency), snapshot fallback. See
                // `WatchRaceMainPage.heartRateBar` for the rationale
                // — this chip exists in the legacy timer display
                // surface (paused/roxzone views), so it shares the
                // same source-priority logic.
                //
                // The cue itself drives a haptic on transition further
                // down via `.onChange(of: coachingCue)` — that's
                // attached at the inProgressView level so the haptic
                // fires once per state change rather than per frame.
                if let hr = WatchWorkoutManager.shared.currentHeartRateBPM
                    ?? snapshot.currentHeartRateBPM {
                    let zone = HRZone.zone(for: hr, maxBPM: snapshot.maxHeartRate)
                    // Personalized cue when the snapshot carries
                    // the personal HR band (RaceStats.personalHR-
                    // Baseline IQR bounds); textbook Z3 fallback
                    // when not. Centralized in
                    // `RaceStateSnapshot.coachingCue(forCurrentHR:)`
                    // so iPhone + Watch classify identically.
                    let cue = snapshot.coachingCue(forCurrentHR: hr)
                    let cueColor: Color = {
                        switch cue {
                        case .hold:    return Color.success
                        case .slow:    return Color.accent
                        case .push:    return Color(hex: 0x5B9BD5)
                        case .workout, .none: return zone.color
                        }
                    }()
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9, weight: .heavy))
                        Text("\(Int(hr.rounded()))")
                            .font(.system(size: 11, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(cueColor)
                }

                // Effort chip — running HR-time integration across
                // every completed split with HR data. Mirrors the
                // post-race "Effort N · HR-time" line iOS shows on
                // RaceSummaryView, but truncated to fit the wrist:
                // bolt icon + integer value. Nil for the first
                // station (no completed splits yet) and for races
                // run without any HR data — chip simply doesn't
                // render in those cases.
                if let effort = RaceStats.effortScore(
                    forSplits: snapshot.splits,
                    maxHR: snapshot.maxHeartRate
                ) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .heavy))
                        Text("\(Int(effort.rounded()))")
                            .font(.system(size: 11, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.warning)
                }
            }
        }
    }

    // MARK: - Finished

    private func finishedView(snapshot: RaceStateSnapshot) -> some View {
        let total: TimeInterval = {
            guard let start = snapshot.startedAt, let end = snapshot.endedAt else {
                return 0
            }
            return end.timeIntervalSince(start)
        }()

        return VStack(spacing: 8) {
            // Filled fingerprint — every bar lit, signal that the
            // race is complete without needing to read text.
            WatchFingerprintProgress(
                completedCount: snapshot.totalStations,
                currentIndex: snapshot.totalStations - 1,
                totalCount: snapshot.totalStations
            )
            .frame(height: 18)
            .padding(.horizontal, 4)

            // Success chip — green tint signals "done" emotionally
            // before the eye reads the time.
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 10, weight: .heavy))
                Text("FINISHED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.success)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.success.opacity(0.16))
            )

            Text(RaceStats.format(total))
                .font(WatchMetrics.font(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .shadow(color: Color.success.opacity(0.35), radius: 10, y: 0)

            Text("\(snapshot.completedStationsCount) of \(snapshot.totalStations) stations")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Waiting / idle

    // Shown when no snapshot has arrived yet, OR the phone reports
    // `.notStarted` (no race active). Visually identical for both —
    // from the athlete's perspective, nothing's happening yet.
    private var waitingView: some View {
        VStack(spacing: 10) {
            // Dim fingerprint at the top — empty bars, signals the
            // race shape is ready but nothing is filled yet. Same
            // motif the user sees during a race, but at idle weight.
            WatchFingerprintProgress(
                completedCount: 0,
                currentIndex: -1,
                totalCount: 16
            )
            .frame(height: 14)
            .opacity(0.35)
            .padding(.horizontal, 6)

            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: WatchMetrics.dim(48), height: WatchMetrics.dim(48))
                Image(systemName: "iphone.gen3")
                    .font(WatchMetrics.font(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }

            VStack(spacing: 2) {
                Text("Ready")
                    .font(WatchMetrics.font(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text("Start a race on iPhone")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Advance button

    // On tap: fire a light haptic for immediate tactile confirmation
    // ("your tap was seen"), then send the advance action to the paired
    // iPhone. The iPhone's `RaceViewModel.advance()` handles the state
    // transition; the resulting state change propagates back to the
    // Watch via the application-context push, updating this view's
    // `snapshot` within 1-2 seconds.
    //
    // No hold-to-finish on Watch yet — the phone still requires it on
    // the final station, so the Watch's tap on station 16 is a safety
    // risk if mistapped. Worth addressing in a polish pass; for MVP we
    // rely on the user being deliberate with their wrist.
    // Compact pause button shown in the in-progress header next
    // to the fingerprint. Sends `.pause` to the phone; phone calls
    // viewModel.pauseRace, which freezes the engine timer and
    // broadcasts a .paused snapshot back. Watch then routes to
    // the pausedView with its Resume button.
    //
    // Sized to 24pt so it doesn't crowd the fingerprint. Same
    // surface treatment as the existing chips so it reads as a
    // peer of the brand element next to it.
    private var pauseButton: some View {
        Button {
            Haptics.warning()
            WatchRaceClient.shared.send(.pause)
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pause race")
    }

    private var advanceButton: some View {
        Button {
            Haptics.impact(.medium)
            WatchRaceClient.shared.send(.advance)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(WatchMetrics.font(size: 13, weight: .heavy))
                Text("Next Station")
                    .font(WatchMetrics.font(size: 14, weight: .heavy, design: .rounded))
            }
            // Brand contract: white-on-coral for primary CTAs.
            // Color.onAccent stays fixed across modes (and on
            // watchOS the whole app is dark-only anyway, but the
            // token keeps the call site consistent with iOS).
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: WatchMetrics.dim(38))
            .background(
                LinearGradient(
                    colors: [Color.accent, Color.accent.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.accent.opacity(0.4), radius: 10, y: 0)
        }
        .buttonStyle(.plain)
    }

    // Watch-tuned variant of the iPhone's `HoldToConfirmButton`.
    // Same gesture pattern + 1.5s hold + per-frame TimelineView
    // progress, but scaled to the 38pt button height we use on
    // the wrist. Delivered inline rather than as a shared
    // component because:
    //   • iOS HoldToConfirmButton is iOS-target-only (UIKit-touched)
    //   • watch dimensions differ enough that a parameterized
    //     version would still need watch-specific call sites
    //   • the only consumer here is this single button — extracting
    //     it pays off only if a second use case appears.
    //
    // Sends the same `.advance` action as the regular button on
    // confirm — the phone closes the race when it receives an
    // advance on the final segment.
    private var holdToFinishButton: some View {
        WatchHoldToFinishButton {
            WatchRaceClient.shared.send(.advance)
        }
    }
}

// MARK: - Hold-to-finish (watch-tuned)

// Press-and-hold confirmation button for the Watch's final-station
// case. Mirrors the iOS `HoldToConfirmButton` semantics:
//   • finger down → fill grows left-to-right over `holdDuration` (1.5s)
//   • release before completion → fill snaps back to empty, no fire
//   • completion → success haptic + onConfirm callback exactly once
//
// Differences from iOS:
//   • 38pt height instead of 80pt (Watch viewport)
//   • 14pt label instead of 24pt
//   • No reduce-motion text quantization here — Watch users
//     experience this less and the button is smaller; if needed,
//     it can be added by mirroring the iOS quantizedLabel logic.
struct WatchHoldToFinishButton: View {

    let onConfirm: () -> Void

    private let holdDuration: TimeInterval = 1.5

    @State private var pressStartedAt: Date?
    @State private var didConfirm = false

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let p = progress(at: context.date)

                ZStack(alignment: .leading) {
                    // Base — same coral gradient as the regular
                    // advance button so the visual identity carries
                    // through. The gesture is the new behavior, not
                    // the appearance.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.accent, Color.accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Progress fill — darkens the button left-to-right
                    // as the hold progresses. At p == 1 the whole
                    // surface is overlaid; visual cue that "you're
                    // there" before the haptic + onConfirm fires.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: proxy.size.width * CGFloat(p))
                        .animation(
                            // Snap-back when finger lifts before
                            // completion. While holding, the
                            // TimelineView's per-frame progress is
                            // already smooth — no extra animation.
                            pressStartedAt == nil ? .easeOut(duration: 0.2) : nil,
                            value: p
                        )

                    HStack(spacing: 4) {
                        Spacer()
                        Image(systemName: "flag.checkered")
                            .font(WatchMetrics.font(size: 13, weight: .heavy))
                        Text("Hold to Finish")
                            .font(WatchMetrics.font(size: 14, weight: .heavy, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(Color.onAccent)
                }
                .contentShape(Rectangle())
                .gesture(
                    // `minimumDistance: 0` is the trick that turns
                    // DragGesture into a press-detect — fires
                    // onChanged the instant the finger touches.
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressStartedAt == nil {
                                pressStartedAt = Date()
                                didConfirm = false
                            }
                        }
                        .onEnded { _ in
                            pressStartedAt = nil
                        }
                )
                .onChange(of: p) { _, newValue in
                    // Latch on confirm so we don't double-fire if
                    // the parent doesn't dismiss us instantly.
                    if newValue >= 1.0, !didConfirm, pressStartedAt != nil {
                        didConfirm = true
                        Haptics.success()
                        onConfirm()
                        pressStartedAt = nil
                    }
                }
            }
        }
        .frame(height: WatchMetrics.dim(38))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.accent.opacity(0.4), radius: 10, y: 0)
    }

    private func progress(at now: Date) -> Double {
        guard let start = pressStartedAt else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1.0, max(0.0, elapsed / holdDuration))
    }
}

// MARK: - Fingerprint progress bar

// 16-bar progress strip that doubles as the brand fingerprint motif.
// Each bar's HEIGHT is fixed by the same hand-tuned rhythm used on
// the app icon and HeroBackdrop watermark — so the silhouette of
// the strip reads as the brand even at a glance, no matter which
// bars are lit. Each bar's COLOR encodes race progress:
//
//   • completed (index < completedCount)         → solid coral
//   • current   (index == currentIndex)          → coral with glow
//   • upcoming  (index > currentIndex)           → dim surfaceElevated
//
// Pure decoration on the iOS app; here it's load-bearing — at one
// glance the athlete sees both "what race is this" (the shape)
// AND "where am I" (the fill).
struct WatchFingerprintProgress: View {

    let completedCount: Int
    let currentIndex: Int
    let totalCount: Int

    // Heights normalized 0.0–1.0, same rhythm as the brand
    // fingerprint. Even indices are runs (R1 R2…), odd are
    // workouts. We slice to `totalCount` so non-16 races (half-rox,
    // custom workouts) still render cleanly.
    private static let heights: [CGFloat] = [
        0.55, 0.85, 0.50, 0.95, 0.55, 0.92, 0.60, 0.78,
        0.65, 0.88, 0.65, 0.72, 0.70, 0.82, 0.72, 1.00
    ]

    private func height(at index: Int) -> CGFloat {
        // Wrap (defensive) — for races > 16 segments, repeat the
        // rhythm rather than show flat bars at the tail.
        Self.heights[index % Self.heights.count]
    }

    private func color(at index: Int) -> Color {
        if index < completedCount {
            return Color.accent
        } else if index == currentIndex {
            return Color.accent
        } else {
            return Color.surfaceElevated
        }
    }

    var body: some View {
        GeometryReader { geo in
            let n = max(totalCount, 1)
            let gap: CGFloat = 2
            let totalGap = gap * CGFloat(n - 1)
            let barWidth = (geo.size.width - totalGap) / CGFloat(n)
            let barRadius = max(barWidth * 0.4, 1)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<n, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barRadius)
                        .fill(color(at: i))
                        .frame(
                            width: barWidth,
                            height: max(geo.size.height * height(at: i), 3)
                        )
                        // Current bar gets a soft glow so the
                        // active station stands out without a
                        // larger size or a different hue.
                        .shadow(
                            color: i == currentIndex
                                ? Color.accent.opacity(0.7)
                                : Color.clear,
                            radius: i == currentIndex ? 4 : 0,
                            y: 0
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

#Preview {
    WatchRaceView()
        .environment(WatchRaceClient.shared)
}

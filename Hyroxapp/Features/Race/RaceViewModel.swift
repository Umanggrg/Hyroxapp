import Foundation
import SwiftData
#if canImport(Auth)
// Required for property access on `AuthService.shared.user?.id`.
// Swift's implicit-member-access rule needs the defining
// submodule (Auth, part of supabase-swift) imported in any file
// that touches the User type's members — same gotcha
// ContentView hits, same fix.
import Auth
#endif

// View-model bridge between the pure `RaceEngine` and SwiftUI, now also the
// bridge into SwiftData persistence.
//
// On every state-changing action (`startRace`, `advance`, finish-on-advance),
// we mirror the engine's state onto a persisted `Race` row and `save()`. That
// way an app-kill at any point — even mid-segment — leaves a consistent row
// that we can resume from on next launch.
//
// Timer-driven UI updates still live in the view (`TimelineView(.periodic)`);
// this class stays tick-free so it's cheap to read and has no runloop state
// to tear down.
@MainActor
@Observable
final class RaceViewModel {

    // MARK: - State owned by the VM

    // Underlying state machine — single source of truth for race logic.
    private(set) var engine = RaceEngine()

    // The persisted row mirroring `engine`. `nil` between races.
    private(set) var activeRace: Race?

    // An unfinished race discovered on launch. While non-nil, the view shows
    // a Resume / Discard prompt instead of the pre-race screen.
    private(set) var pendingResume: Race?

    // Live-polled heart rate during an active race. `nil` outside of
    // an active race, when HealthKit isn't authorized, when no Watch
    // is streaming samples, or simply between poll ticks before the
    // first sample arrives. UI reads this and renders a small "165
    // bpm" chip on the race screen when present.
    //
    // Intentionally separate from the per-split `heartRateAvgBPM` /
    // `heartRateMaxBPM` statistics — this is the LATEST instantaneous
    // reading, those are historical per-segment aggregates.
    private(set) var currentHeartRateBPM: Double?

    /// §19.4 Phase 10H — live cadence in steps-per-minute,
    /// derived from AirPods Pro 1+ / 4 / Max head motion via
    /// `HeadphoneMotionService`. Nil when AirPods aren't in
    /// the audio route, when the athlete isn't running, or
    /// during the first ~2 seconds while the rolling buffer
    /// fills. Read this property on the live race screen +
    /// post-race summary; it's the cadence chip data source.
    var currentCadenceSPM: Int? {
        HeadphoneMotionService.shared.currentCadenceSPM
    }

    // Handle to the background polling Task so we can cancel it when
    // the race finishes, the user abandons, or the Race view
    // disappears. Nil outside of an active race.
    private var heartRatePollTask: Task<Void, Never>?

    // Athlete's max heart rate, used to classify the live HR into
    // a zone (Z1...Z5) for display on the Live Activity. Set by
    // RaceView via .onAppear / .onChange of the user profile so
    // the value tracks any in-app edits to "Max HR" in Settings.
    // Defaults to 190 — a reasonable population average for adults
    // 30-40 — until the profile loads.
    var maxHeartRate: Int = 190

    // Pre-race countdown state — used to render a 3-2-1-GO overlay
    // on RaceView between the user tapping "Start Race" and the
    // engine timer actually beginning. `countdownValue` is the
    // current number on screen (3 → 2 → 1 → 0/"GO"); a Task ticks
    // it down once per second. Both nil when no countdown is
    // active. UI reads `isCountingDown` to decide whether to show
    // the overlay.
    private(set) var countdownValue: Int?
    private var countdownTask: Task<Void, Never>?

    // §14 — the RaceKind requested for the race currently being
    // counted down toward. Captured at startRaceWithCountdown
    // time so the tap-to-skip affordance (which can be invoked
    // from RaceView's overlay without knowing the original kind
    // call site's params) restores it correctly. Cleared once
    // the race actually starts.
    private var pendingKind: RaceKind = .race

    var isCountingDown: Bool { countdownValue != nil }

    // How often we poll HealthKit for current HR during a race. The
    // poll is the THIRD-TIER fallback behind two Watch transports
    // (sendMessage when reachable + transferUserInfo always). It
    // fires only when neither Watch path has delivered, typically
    // when the Watch app is killed or HealthKit auth was denied.
    //
    // Tuned 5s → 2s → 1s. WCSession is now reliable enough that
    // polling rarely needs to write — the watchSampleAge gate
    // suppresses the polled write when the Watch streamed
    // anything in the last 10s. So a 1s cadence isn't actually
    // 1Hz of HK queries in practice; it's 1Hz of "should I fill
    // a gap?" checks, most of which short-circuit on the gate.
    //
    // The user-perceived latency win: when the Watch path DOES
    // drop (locker, killed, denied auth) and polling kicks in,
    // a fresh sample lands ≤1s after it appears in HK rather
    // than waiting up to 2s.
    private static let heartRatePollInterval: TimeInterval = 1

    // MARK: - ModelContext plumbing

    // Held as a weak reference to the injected environment context. Assigned
    // by the view on appear — before that point the VM operates in memory
    // only (fine for previews / tests).
    private var modelContext: ModelContext?

    func bindModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Live Activity bridging

    // Build the current ActivityKit ContentState from engine +
    // active race. Returns nil when there's nothing to publish
    // (notStarted / no active race) so callers can early-exit.
    //
    // Single source of truth for "what does the lock screen
    // show right now" — every state transition (start, advance,
    // pause, resume, endSegment, startNextSegment, finish)
    // calls this and pushes the result.
    #if canImport(ActivityKit)
    private func currentLiveActivityState() -> RaceActivityAttributes.ContentState? {
        guard activeRace != nil else { return nil }

        // Resolve the current station for display. Falls back
        // to the last station's name on a finished race so the
        // lock screen still shows a sensible final state.
        let station = engine.currentStation
            ?? engine.sequence[safe: max(0, engine.splits.count - 1)]
        let stationName = station?.displayName ?? "Race"
        let stationIndex = (station?.rawValue ?? 0) + 1

        // Round HR to the nearest integer for display. nil when
        // HealthKit is denied or no sensor is publishing — the
        // widget skips rendering the HR chip in that case.
        let hr: Int? = currentHeartRateBPM.map { Int($0.rounded()) }

        // Pre-compute the zone (Z1...Z5) on this side so the widget
        // doesn't need to import HRZone or know the athlete's max
        // HR. Only meaningful when bpm is non-nil — widget treats
        // nil as "no zone chip."
        let hrZone: Int? = currentHeartRateBPM.map {
            HRZone.zone(for: $0, maxBPM: maxHeartRate).rawValue
        }

        // Target finish time — drives the lock-screen pace ghost
        // line. Threaded through every ContentState construction
        // below so the widget always has the data when it's
        // available, regardless of which phase the race is in
        // when the next push happens.
        let targetDuration = activeRace?.targetDuration

        switch engine.state {
        case .notStarted:
            return nil
        case .inProgress(let raceStart, let segStart, _):
            return RaceActivityAttributes.ContentState(
                phase: .running,
                timerStart: raceStart,
                segmentStart: segStart,
                currentStationIndex: stationIndex,
                totalStations: engine.sequence.count,
                currentStationName: stationName,
                currentHR: hr,
                currentHRZone: hrZone,
                targetDuration: targetDuration
            )
        case .paused(let raceStart, let segStart, _, let pausedAt):
            return RaceActivityAttributes.ContentState(
                phase: .paused,
                timerStart: raceStart,
                segmentStart: segStart,
                frozenElapsed: pausedAt.timeIntervalSince(raceStart),
                frozenSegmentElapsed: pausedAt.timeIntervalSince(segStart),
                currentStationIndex: stationIndex,
                totalStations: engine.sequence.count,
                currentStationName: stationName,
                currentHR: hr,
                currentHRZone: hrZone,
                targetDuration: targetDuration
            )
        case .inRoxzone(let raceStart, _, let roxStart):
            return RaceActivityAttributes.ContentState(
                phase: .inRoxzone,
                timerStart: raceStart,
                segmentStart: roxStart,  // segment timer hidden in roxzone view
                roxzoneStart: roxStart,
                currentStationIndex: stationIndex,
                totalStations: engine.sequence.count,
                currentStationName: stationName,
                currentHR: hr,
                currentHRZone: hrZone,
                targetDuration: targetDuration
            )
        case .finished(let raceStart, let endedAt, _):
            return RaceActivityAttributes.ContentState(
                phase: .finished,
                timerStart: raceStart,
                segmentStart: raceStart,
                frozenElapsed: endedAt.timeIntervalSince(raceStart),
                frozenSegmentElapsed: 0,
                currentStationIndex: stationIndex,
                totalStations: engine.sequence.count,
                currentStationName: stationName,
                currentHR: hr,
                currentHRZone: hrZone,
                targetDuration: targetDuration
            )
        }
    }

    // Push the current state to the live activity. Cheap when
    // no activity is running (the service early-exits).
    private func pushLiveActivityUpdate() {
        guard let state = currentLiveActivityState() else { return }
        LiveActivityService.shared.update(state)
    }
    #endif

    // MARK: - Race state snapshot
    //
    // Builds the engine's current state into a transport-friendly
    // `RaceStateSnapshot`. Single source of truth for both the watch
    // (WCSession path) and the duo bridge (Multipeer path). Returns
    // nil for `.notStarted` so callers can early-exit.
    //
    // `division` and `maxHR` are passed in rather than read from a
    // stored property because the VM doesn't own profile state
    // semantically — that's a UserProfile concern. Both call
    // sites (RaceView for watch sync, DuoRaceController for duo
    // broadcast) have the user's profile already and pass them
    // through.
    func makeRaceStateSnapshot(
        division: Division,
        maxHR: Int = 190,
        personalHRBaseline: RaceStats.PersonalHRBaseline? = nil,
        targetDuration: TimeInterval? = nil,
        guardrailHistory: [Race] = [],
        coachingCuesEnabled: Bool? = nil
    ) -> RaceStateSnapshot? {
        let phase: RaceStateSnapshot.Phase
        let startedAt: Date?
        let segmentStartedAt: Date?
        let endedAt: Date?
        let pausedAt: Date?

        switch engine.state {
        case .notStarted:
            return nil
        case .inProgress(let raceStart, let segStart, _):
            phase = .inProgress
            startedAt = raceStart
            segmentStartedAt = segStart
            endedAt = nil
            pausedAt = nil
        case .paused(let raceStart, let segStart, _, let pauseStart):
            phase = .paused
            startedAt = raceStart
            segmentStartedAt = segStart
            endedAt = nil
            pausedAt = pauseStart
        case .inRoxzone(let raceStart, _, let roxStart):
            phase = .inRoxzone
            startedAt = raceStart
            segmentStartedAt = roxStart
            endedAt = nil
            pausedAt = nil
        case .finished(let raceStart, let raceEnd, _):
            phase = .finished
            startedAt = raceStart
            segmentStartedAt = nil
            endedAt = raceEnd
            pausedAt = nil
        }

        // currentStation is nil after a race finishes (no next
        // station to point at). Fall back to the last station's
        // index so the receiver still shows the final station name.
        let stationIndex: Int
        if let station = currentStation {
            stationIndex = station.rawValue
        } else {
            stationIndex = max(0, totalSegments - 1)
        }

        // Serialize the engine's current splits so the duo guest
        // can reconstruct a Race row when the race finishes.
        // Watch path doesn't read this; only the duo bridge does.
        let serializedSplits = engine.splits.map(SerializedSplit.init(from:))

        // Guardrail thresholds — personalized from history when
        // 3+ samples exist for the current station, falls back
        // to textbook Z4-Z5 boundaries otherwise. Recomputed on
        // every snapshot push so the Watch sees fresh ceilings
        // as the race advances through stations.
        let guardrail: RaceStats.Guardrail? = {
            guard let station = currentStation else { return nil }
            return RaceStats.guardrail(
                for: station,
                across: guardrailHistory,
                excludingRace: activeRace
            ) ?? RaceStats.textbookGuardrail(forMaxHR: maxHR)
        }()

        return RaceStateSnapshot(
            phase: phase,
            startedAt: startedAt,
            currentSegmentStartedAt: segmentStartedAt,
            currentStationIndex: stationIndex,
            completedStationsCount: completedSegmentsCount,
            totalStations: totalSegments,
            divisionRaw: division.rawValue,
            endedAt: endedAt,
            pausedAt: pausedAt,
            splits: serializedSplits,
            currentHeartRateBPM: currentHeartRateBPM,
            maxHeartRate: maxHR,
            personalHRLowerQuartile: personalHRBaseline?.lowerQuartile,
            personalHRUpperQuartile: personalHRBaseline?.upperQuartile,
            targetDuration: targetDuration ?? activeRace?.targetDuration,
            segmentHRApproachThreshold: guardrail?.approachThreshold,
            segmentHRCeiling: guardrail?.ceiling,
            coachingCuesEnabled: coachingCuesEnabled
        )
    }

    // MARK: - Derived state (same surface as before)

    // True for both in-progress and paused — both states represent
    // an "active race" from the UI's perspective (the race screen is
    // showing, just the timer's frozen). Used for show/hide logic
    // around the race screen itself.
    var isRacing: Bool {
        switch engine.state {
        case .inProgress, .paused, .inRoxzone: return true
        default: return false
        }
    }

    // True only when actively paused. UI uses this to swap the Pause
    // button for a Resume button and overlay a "PAUSED" indicator.
    var isPaused: Bool { engine.isPaused }

    // True while in Roxzone (between segments). UI shows a
    // distinct overlay when this is set.
    var isInRoxzone: Bool { engine.isInRoxzone }

    // Live transition timer for the in-roxzone overlay.
    func currentRoxzoneElapsed(at date: Date) -> TimeInterval {
        engine.currentRoxzoneElapsed(at: date)
    }

    var isFinished: Bool { engine.isFinished }
    var hasStarted: Bool { isRacing || isFinished }

    var currentStation: Station?   { engine.currentStation }
    var upcomingStation: Station?  { engine.upcomingStation }
    var splits: [Split]            { engine.splits }
    var sequence: [Station]        { engine.sequence }
    var totalSegments: Int         { engine.sequence.count }
    var completedSegmentsCount: Int { engine.splits.count }

    var finalTime: TimeInterval {
        guard case .finished(let start, let end, _) = engine.state else { return 0 }
        return end.timeIntervalSince(start)
    }

    func elapsed(at date: Date) -> TimeInterval {
        engine.elapsed(at: date)
    }

    func currentSegmentElapsed(at date: Date) -> TimeInterval {
        engine.currentSegmentElapsed(at: date)
    }

    // MARK: - Launch-time resume lookup

    // Find the most recently created unfinished race, if any, so the view can
    // prompt the user to resume it. Called on view-appear.
    //
    // Skipped when we're already tracking a race — otherwise switching tabs
    // mid-race would re-find the live race and flash the resume prompt over
    // the in-progress UI.
    func checkForResumableRace() {
        guard activeRace == nil else { return }
        guard let modelContext else { return }

        // `#Predicate` is SwiftData's compile-time-checked query DSL — much
        // safer than NSPredicate string literals. Here we want races whose
        // `endedAt` is still nil (i.e. not yet finished).
        var descriptor = FetchDescriptor<Race>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let unfinished = try? modelContext.fetch(descriptor).first {
            pendingResume = unfinished
        }
    }

    // User tapped Resume on the launch prompt.
    func resumePending() {
        guard let race = pendingResume else { return }
        engine = RaceEngine(sequence: race.sequence, state: race.engineState)
        // Restore the pending-roxzone transition time so a force-
        // killed mid-segment-after-roxzone resume picks up where
        // it left off and attaches the correct duration to the
        // next-completed split.
        engine.pendingRoxzoneSeconds = race.pendingRoxzoneSeconds
        activeRace = race
        pendingResume = nil
        // If multiple unfinished races accumulated from prior force-kills
        // (we only ever offer the most recent), delete the older orphans
        // so History stays clean and future checkForResumableRace calls
        // don't fish up stale rows.
        purgeOrphanedUnfinishedRaces(excluding: race)
        // Resume the live-HR polling loop — the user's still racing,
        // they still want to see their current bpm on screen.
        startHeartRatePolling()
    }

    // User tapped Discard on the launch prompt.
    func discardPending() {
        guard let race = pendingResume else { return }
        modelContext?.delete(race)
        pendingResume = nil
        // Discard also cleans up any even older orphans — the user has
        // signaled they don't want any unfinished race to persist.
        purgeOrphanedUnfinishedRaces(excluding: nil)
        saveContextSilently()
    }

    // Delete every unfinished (`endedAt == nil`) race except optionally
    // the one being actively resumed. Called after both resume and
    // discard flows to keep storage tidy — a single athlete should never
    // have more than one unfinished race in flight at a time.
    //
    // `except` is the one race we want to keep; pass `nil` on discard to
    // wipe everything unfinished.
    private func purgeOrphanedUnfinishedRaces(excluding except: Race?) {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Race>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        guard let allUnfinished = try? modelContext.fetch(descriptor) else { return }

        for race in allUnfinished where race.id != except?.id {
            modelContext.delete(race)
        }
        saveContextSilently()
    }

    // MARK: - Actions

    // Begin a race. Defaults to the full 16-segment HYROX sequence so
    // the standard "Start Race" button keeps its zero-config behavior.
    // Pass an explicit `sequence` to run a custom workout — a shortened
    // session, a strength-focused circuit, a repeating pattern — and
    // the engine handles advance/finish naturally because it already
    // parameterizes on the segment list.
    //
    // Pass `targetDuration` to record a finish-time goal ("beat 1:30:00").
    // Engine itself is target-unaware; this value lives on the Race
    // row and views read it for display/comparison.
    //
    // Empty `sequence` is a no-op (nothing to start). Callers should
    // validate before calling; the guard here is defensive.
    // Begin the race with a 3-2-1-GO countdown. Schedules a Task
    // that ticks `countdownValue` from 3 → 2 → 1 → nil at 1-second
    // intervals, calling `startRace` on the final tick to actually
    // begin the engine. The view layer fires voice cues + haptics
    // off `countdownValue` changes via `.onChange`.
    //
    // If `countdownEnabled` is false on the user's profile, this
    // skips the countdown entirely and starts the race immediately
    // — the start screen passes the flag in. Idempotent guard
    // against double-tap during an in-flight countdown.
    func startRaceWithCountdown(
        sequence: [Station] = Station.raceSequence,
        targetDuration: TimeInterval? = nil,
        countdownEnabled: Bool,
        defaultPrivate: Bool = false,
        liveActivityEnabled: Bool = true,
        kind: RaceKind = .race
    ) {
        guard !isCountingDown, !isRacing else { return }

        // §14 — capture kind so the skip-tap path (which can be
        // invoked from RaceView's overlay without re-passing the
        // params) preserves it. Set BEFORE the no-countdown short-
        // circuit so even direct startRace fallthroughs see it.
        // Cleared at race start by startRace itself.
        pendingKind = kind

        guard countdownEnabled else {
            startRace(
                sequence: sequence,
                targetDuration: targetDuration,
                defaultPrivate: defaultPrivate,
                liveActivityEnabled: liveActivityEnabled,
                kind: kind
            )
            return
        }

        countdownValue = 3

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 3 → 2 → 1 ticks. After each second decrement; when
            // we hit 0 the GO state shows briefly before the
            // engine actually starts. Cancellation-aware so a
            // skip-tap can shortcut to startRace immediately.
            for next in [2, 1, 0] {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.countdownValue = next
            }
            // Hold "GO" briefly so the athlete sees it before the
            // race screen takes over. 0.5s is short enough not to
            // feel laggy, long enough to register.
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }

            self.countdownValue = nil
            self.startRace(
                sequence: sequence,
                targetDuration: targetDuration,
                defaultPrivate: defaultPrivate,
                liveActivityEnabled: liveActivityEnabled,
                kind: kind
            )
        }
    }

    // Skip the countdown — used by the tap-to-skip affordance on
    // the overlay. Cancels the in-flight tick task and starts the
    // race immediately. No-op when no countdown is in progress.
    //
    // The skip needs the same sequence + target the original
    // request used; we stash them on the task closure via captures
    // since the countdown is short-lived enough that re-passing
    // through state would bloat the API. The overlay calls this
    // only as a fast-forward of the existing call — preserving
    // the original parameters is up to the caller (which holds
    // them in @State on RaceStartView).
    func skipCountdown(
        sequence: [Station] = Station.raceSequence,
        targetDuration: TimeInterval? = nil,
        defaultPrivate: Bool = false,
        liveActivityEnabled: Bool = true,
        kind: RaceKind? = nil
    ) {
        guard isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = nil
        // §14 — prefer the kind passed by the caller (RaceStartView
        // knows what it requested), fall back to the kind stashed
        // by `startRaceWithCountdown` (RaceView's overlay skip tap
        // doesn't carry the kind explicitly). Default `.race`
        // only when both are absent.
        startRace(
            sequence: sequence,
            targetDuration: targetDuration,
            defaultPrivate: defaultPrivate,
            liveActivityEnabled: liveActivityEnabled,
            kind: kind ?? pendingKind
        )
    }

    func startRace(
        sequence: [Station] = Station.raceSequence,
        targetDuration: TimeInterval? = nil,
        defaultPrivate: Bool = false,
        liveActivityEnabled: Bool = true,
        kind: RaceKind = .race
    ) {
        guard !sequence.isEmpty else { return }

        let now = Date()
        engine = RaceEngine(sequence: sequence)
        engine.start(at: now)

        let race = Race(
            startedAt: now,
            currentSegmentStartedAt: now,
            sequence: engine.sequence,
            targetDuration: targetDuration
        )
        // Apply Settings → Privacy → "default new races private."
        // The athlete can still flip this on the summary screen
        // if they want this race public after all. Race init
        // doesn't take isPrivate as a param to keep that signature
        // tight; setting it post-init is equivalent.
        race.isPrivate = defaultPrivate
        // §14 — categorize the race based on which Train hub card
        // the athlete tapped. Default `.race` covers the Race Mode
        // path + any legacy call sites that haven't been updated.
        race.kind = kind
        // Clear the pendingKind stash — the race has started, so
        // any future startRaceWithCountdown call will re-set this
        // afresh. (Defensive: a stale value here can't hurt since
        // it's only consulted by skipCountdown which is gated on
        // isCountingDown, but cleaner state is cleaner state.)
        pendingKind = .race
        modelContext?.insert(race)
        activeRace = race
        saveContextSilently()
        // Kick off the live-HR polling loop. Runs independently of
        // the per-split HR stats — this feeds the on-screen "current
        // bpm" readout, not the historical per-station aggregates.
        startHeartRatePolling()

        // Tell the Watch to start its HKWorkoutSession. Watch begins
        // collecting HR + active-energy samples, the race becomes
        // a real HKWorkout (saved to Health on race finish for
        // Activity ring credit + Apple Fitness visibility), and the
        // Watch app stays awake with screen-off because workout
        // sessions extend runtime on watchOS. Bails silently if no
        // Watch is paired — the iOS-side HealthKit fallback covers
        // that case.
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.sendControl(.startWorkout(at: now))
        #endif

        // Kick off the Live Activity (lock screen + Dynamic
        // Island race timer). Initial state from the engine
        // we just started. Failures are silent — the in-app
        // race UI is the source of truth, the activity is
        // additive.
        //
        // Settings → "Live Activity" toggle gates this entirely.
        // Off → no lock-screen race timer at all. The flag is
        // captured at start time; flipping the setting mid-race
        // doesn't retroactively kill / spawn an activity.
        #if canImport(ActivityKit)
        if liveActivityEnabled, let state = currentLiveActivityState() {
            let attributes = RaceActivityAttributes(
                raceName: race.name.isEmpty ? "HYROX Race" : race.name
            )
            LiveActivityService.shared.start(
                attributes: attributes,
                contentState: state
            )
        }
        #endif
    }

    // End the current segment and enter Roxzone. Two-tap-advance
    // path (used when roxzoneEnabled is on). Closes the segment
    // with a Split, transitions the engine to .inRoxzone where
    // the transition timer counts up until startNextSegmentRace
    // is called.
    //
    // Single-tap-advance users never call this — they use
    // `advance()` directly which keeps the existing semantics.
    func endSegmentRace() {
        let wasInProgress = !engine.isFinished
        let endedAt = Date()
        engine.endSegment(at: endedAt)
        // §13.8 Tier 2 — same advance-time rep stamp as `advance()`.
        // endSegment is the roxzone-mode counterpart that closes a
        // station before the transition timer starts. Either path
        // appends the same Split shape; rep counting needs to fire
        // on both.
        stampLatestRepCountOnJustClosedSplit()
        let newSplitIndex = engine.splits.count - 1
        persistActiveRace()

        // If endSegment was called on the FINAL segment, engine
        // flipped to .finished — mirror to HealthKit once.
        if wasInProgress, engine.isFinished {
            saveFinishedRaceToHealthKit()

            // Tell the Watch to end + finalize its HKWorkoutSession.
            // The resulting HKWorkout is persisted on the Watch side,
            // earning Activity ring credit + Apple Fitness visibility.
            // No-op when no Watch is paired.
            #if canImport(WatchConnectivity)
            WatchCompanionService.shared.sendControl(.endWorkout(at: endedAt))
            #endif
        }

        attachSegmentStats(to: newSplitIndex)
    }

    // Begin the next segment after a Roxzone. Computes + stashes
    // the roxzone duration on the engine so the next segment's
    // split picks it up at completion.
    func startNextSegmentRace() {
        engine.startNextSegment(at: Date())
        persistActiveRace()
    }

    // Pause an in-progress race. Freezes the timer at the current
    // elapsed time, stops the live HR poll, and persists the pause
    // moment to SwiftData so the paused state survives app kill.
    func pauseRace() {
        engine.pause(at: Date())
        persistActiveRace()
        // No reason to keep polling HR while the race is frozen —
        // the chip would just show a stale value. Restart on resume.
        stopHeartRatePolling()

        // Tell the Watch to pause its HKWorkoutSession so sample
        // collection halts — Activity ring time stops accumulating
        // while paused, matching the engine's view that no race
        // time is being earned.
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.sendControl(.pauseWorkout)
        #endif
    }

    // Resume a paused race. Engine shifts startedAt forward by the
    // pause duration so existing elapsed-time math keeps working;
    // persistence + HR polling come back online.
    func resumeRace() {
        engine.resume(at: Date())
        persistActiveRace()
        startHeartRatePolling()

        // Tell the Watch to resume its HKWorkoutSession. Sample
        // collection picks back up; Activity ring time accumulates
        // again.
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.sendControl(.resumeWorkout)
        #endif
    }

    // Rebase the current segment's start timestamp to `now`. Used
    // by the manual-run-start UI on RaceView — the athlete advances
    // into a run, gets a "Start Run" overlay, and tapping that
    // button calls this so the segment's recorded duration is just
    // the run time (no pre-positioning delay). Total race time
    // keeps ticking through the delay; only the segment timer
    // restarts. No-op outside of an active in-progress race.
    func rebaseCurrentSegment(at now: Date) {
        engine.rebaseCurrentSegmentStart(to: now)
        persistActiveRace()
    }

    func advance() {
        // Detect the transition to `.finished` so we can mirror the race out
        // to HealthKit exactly once (not on every advance).
        let wasFinished = engine.isFinished
        let advancedAt = Date()
        engine.advance(at: advancedAt)
        // §13.8 Tier 2 — stamp the latest Watch rep count onto the
        // just-closed Split if its station matches. Has to run
        // BEFORE persistActiveRace so the SwiftData write captures
        // the rep count alongside everything else the persist
        // mirrors. The method handles the manual-override case
        // (doesn't clobber a user-typed value) and clears
        // latestWatchRepUpdate so a stale value doesn't bleed
        // into a future advance.
        stampLatestRepCountOnJustClosedSplit()
        // Capture the index of the split that `engine.advance` just appended
        // so the async HR patch can find and update it below. Must be read
        // before `persistActiveRace` because that's a sync write; the HR
        // task is what races the user forward.
        let newSplitIndex = engine.splits.count - 1
        persistActiveRace()

        if !wasFinished, engine.isFinished {
            saveFinishedRaceToHealthKit()

            // Same as endSegmentRace: tell the Watch its workout
            // session is done. The Watch finalizes the HKWorkout
            // and Activity ring credit posts.
            #if canImport(WatchConnectivity)
            WatchCompanionService.shared.sendControl(.endWorkout(at: advancedAt))
            #endif

            rehydrateSegmentStatsAfterFinish()

            // Push to Supabase. Captured race + auth user ID
            // off the main actor's hot path so the finish UI
            // doesn't block on a network round-trip. Errors
            // are swallowed inside RaceSyncService — next
            // launch's pullAndReconcile catches anything that
            // didn't make it. Skips silently when the user
            // isn't authenticated (offline-only mode).
            #if canImport(UIKit)
            if let race = activeRace,
               let userID = AuthService.shared.user?.id.uuidString {
                Task { @MainActor in
                    await RaceSyncService.pushFinishedRace(
                        race,
                        userID: userID
                    )
                }
            }
            #endif
        }

        // Fire-and-forget: fetch segment-window stats from HealthKit
        // (HR avg/max + active calories, in parallel) and patch them
        // onto the just-completed split. Runs in the background so
        // the UI transition to the next station is instant (no
        // 100–300ms HealthKit query latency between tap and advance).
        // If no metrics are available the split keeps its nil values
        // and the UI omits them.
        attachSegmentStats(to: newSplitIndex)
    }

    // Apply manually-entered station stats (weight, reps, RPE) to
    // the split at the given index. Used by StationStatsSheet to
    // persist edits made post-race on the summary screen, where
    // the engine is the authoritative source of split data.
    //
    // For HISTORICAL races (RaceDetailView, after the VM has
    // released the active race), edits go directly to Race.splits
    // via @Bindable — that path doesn't go through this method.
    func updateStationStats(
        splitIndex: Int,
        weightKg: Double?,
        repsCompleted: Int?,
        rpe: Int?
    ) {
        engine.setStationStats(
            weightKg: .some(weightKg),
            repsCompleted: .some(repsCompleted),
            rpe: .some(rpe),
            atSplitIndex: splitIndex
        )
        persistActiveRace()
    }

    // MARK: - Segment stats capture (HR + calories)

    // Query HealthKit for HR avg/max + active calories over the
    // just-completed segment's time window, and patch the split at
    // `index` with the result. The two queries run in parallel via
    // `async let` to minimize the latency before stats appear on
    // screen. Re-persists afterwards so the Race row in SwiftData
    // carries the segment metrics through to History.
    //
    // The segment window is read from the split itself (its startedAt
    // and endedAt) rather than passed in — the engine already has the
    // authoritative timestamps by the time this runs, and reading
    // them here keeps the capture path robust to any future changes
    // in how advance is invoked.
    //
    // Guarded `#if canImport(HealthKit)` so macOS builds — which lack
    // HealthKit — compile without the query path at all.
    private func attachSegmentStats(to index: Int) {
        // §19 Phase 10I — synchronously stamp the current
        // vertical-oscillation rolling avg onto the just-ended
        // split when it's a run segment. Done BEFORE the
        // async HK task below so the snapshot is taken at
        // segment-end time, before the rolling avg drifts
        // into the next segment's motion pattern. Split's
        // HR-stats builders (withSegmentStats, withRecovery
        // Stats, etc.) preserve verticalOscCmAvg through
        // subsequent patches.
        //
        // Routes through `engine.setVerticalOscillation` (not
        // direct array mutation) because Split is a value
        // type — engine.splits returns a copy, so mutating it
        // wouldn't reach the engine's internal state.
        if engine.splits.indices.contains(index),
           engine.splits[index].station.kind == .run,
           let osc = HeadphoneMotionService.shared.currentVerticalOscillationCm {
            engine.setVerticalOscillation(osc, atSplitIndex: index)
        }

        #if canImport(HealthKit)
        // Read the segment bounds on the current actor before hopping
        // into the async Task — avoids capturing mutable engine state
        // across a suspension point.
        guard engine.splits.indices.contains(index) else { return }
        let split = engine.splits[index]
        let segmentStart = split.startedAt
        let segmentEnd = split.endedAt

        // `@MainActor` on the Task pins the whole closure to MainActor
        // after the parallel HealthKit queries resume — safe to mutate
        // the engine directly without an extra MainActor.run hop.
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Run all queries in parallel — HR aggregate, entry HR,
            // end HR, and calories sum are independent. Sequential
            // awaits would 4x the wall-clock latency before the
            // station's stats appear on screen.
            async let heartRate = HealthKitService.shared.heartRateStats(
                from: segmentStart,
                to: segmentEnd
            )
            async let entryHR = HealthKitService.shared.heartRate(at: segmentStart)
            async let endHR = HealthKitService.shared.heartRate(at: segmentEnd)
            async let calories = HealthKitService.shared.activeCalories(
                from: segmentStart,
                to: segmentEnd
            )
            // HR std dev — pacing-quality signal computed from
            // individual samples in the window. Parallel with the
            // other queries; another HK round-trip but cheap when
            // run concurrently.
            async let hrStdDev = HealthKitService.shared.heartRateStdDev(
                from: segmentStart,
                to: segmentEnd
            )
            // SpO2 minimum — §13.8 Tier 4 anaerobic-threshold
            // proxy. Watch Series 6+ only; older Watches return
            // nil and the StationDetailView line silently hides.
            async let spo2Min = HealthKitService.shared.lowestOxygenSaturation(
                from: segmentStart,
                to: segmentEnd
            )
            let hr = await heartRate
            let entry = await entryHR
            let end = await endHR
            let kcal = await calories
            let stdDev = await hrStdDev
            let spo2 = await spo2Min

            // Skip the persist round-trip if HealthKit had nothing
            // for this segment — common for indoor sessions without
            // a Watch streaming any of these metrics.
            guard hr.avg != nil || hr.max != nil || entry != nil || end != nil || kcal != nil || stdDev != nil || spo2 != nil else {
                return
            }

            self.engine.setSegmentStats(
                heartRateAvg: hr.avg,
                heartRateMax: hr.max,
                heartRateEntry: entry,
                heartRateEnd: end,
                heartRateStdDev: stdDev,
                lowestSpO2: spo2,
                activeCalories: kcal,
                atSplitIndex: index
            )
            self.persistActiveRace()
        }

        // Schedule a delayed recovery-HR capture. The 30s and 60s
        // post-segment samples don't exist at advance-time — we wait
        // 70 seconds (60s + 10s buffer for HealthKit to receive the
        // Watch's last live-workout sample) then query for HR at
        // segmentEnd+30 and segmentEnd+60. Patches the split via a
        // separate engine.setRecoveryStats call so the original
        // setSegmentStats above can land immediately without
        // blocking on a 70s sleep.
        //
        // Fire-and-forget Task — if the user kills the app or starts
        // a new race within the window, the Task is cancelled and
        // recovery data simply doesn't get captured for that split.
        // Acceptable: missing recovery data is harmless (UI hides
        // the field), and forcing the capture to complete would
        // require background-mode plumbing for marginal benefit.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(70))
            guard let self else { return }
            guard self.engine.splits.indices.contains(index) else { return }

            async let recovery30 = HealthKitService.shared.heartRate(
                at: segmentEnd.addingTimeInterval(30)
            )
            async let recovery60 = HealthKitService.shared.heartRate(
                at: segmentEnd.addingTimeInterval(60)
            )
            let r30 = await recovery30
            let r60 = await recovery60

            // Skip the persist if HealthKit had nothing — common
            // when the user finished their workout and took the
            // Watch off, or when phone reachability dropped.
            guard r30 != nil || r60 != nil else { return }

            self.engine.setRecoveryStats(
                heartRateRecovery30s: r30,
                heartRateRecovery60s: r60,
                atSplitIndex: index
            )
            self.persistActiveRace()
        }
        #endif
    }

    // Re-query HealthKit for per-segment physiology AFTER the race
    // finishes — closes the "physiology missing on most stations"
    // gap reported during dogfooding.
    //
    // Why this is needed:
    //   • `HKLiveWorkoutBuilder` buffers HR / calorie / SpO2
    //     samples internally during an active workout session and
    //     ONLY writes them to `HKHealthStore` when `finishWorkout`
    //     is called.
    //   • `attachSegmentStats(to:)` runs at segment-end (mid-
    //     race) and queries HK directly — but the samples for
    //     that segment are still buffered on the Watch, so the
    //     query returns nothing for most stations.
    //   • The only stations that got physiology mid-race were
    //     ones that happened to overlap the Watch's passive
    //     ambient HR sampling (5-15 min cadence), which writes
    //     to HK independently of the workout session.
    //
    // After race-end:
    //   • The phone sends `.endWorkout` to the Watch.
    //   • The Watch's session delegate calls
    //     `builder.finishWorkout` which flushes every buffered
    //     sample to HKHealthStore.
    //   • iCloud Health propagates the samples back to the
    //     iPhone in ~5-8 seconds (the propagation delay between
    //     Watch HK writes and iPhone HK reads).
    //
    // This method waits 8 seconds (median of that propagation
    // window — long enough that finishWorkout has completed and
    // samples have reached the iPhone, short enough that the user
    // can see physiology on the summary the moment they arrive).
    // Then it re-runs `attachSegmentStats(to:)` for every split.
    //
    // Idempotent: `attachSegmentStats` overwrites whatever values
    // exist on the split, so a station that DID get HR mid-race
    // simply gets refreshed with the same data; one that didn't
    // gets populated for the first time.
    private func rehydrateSegmentStatsAfterFinish() {
        #if canImport(HealthKit)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }

            // Re-query each split independently. attachSegmentStats
            // is already designed for parallel HK queries per
            // split; calling it sequentially here is fine because
            // the queries within each call run concurrently and
            // there are at most 16 splits.
            for index in self.engine.splits.indices {
                self.attachSegmentStats(to: index)
            }
        }
        #endif
    }

    // Called from the Done button on the finished-summary screen. Keeps the
    // race row (it's complete — belongs in History), clears VM state, ready
    // for the next race.
    func finishSession() {
        // End the Live Activity BEFORE we tear down the engine
        // so we can capture the final state for the lock-screen
        // "FINISHED" ribbon. iOS keeps the activity visible for
        // ~4h after end with `.default` dismissal so the athlete
        // can glance at their finish time without unlocking.
        #if canImport(ActivityKit)
        let finalState = currentLiveActivityState()
        LiveActivityService.shared.end(finalState: finalState)
        #endif

        engine.reset()
        activeRace = nil
        stopHeartRatePolling()
        cancelCountdown()
    }

    // Drop any in-flight countdown — used by finishSession +
    // abandon for cleanup. No-op when no countdown is active.
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = nil
    }

    // Wireframe §03.4 "End race here, save partial." End an
    // in-progress race EARLY and persist it with however many
    // segments the athlete actually completed. Distinct from
    // `abandon()` (which throws the row away) and `advance()` on
    // the final station (which finishes a complete race).
    //
    // Routes through `engine.forceFinish(at:)` which closes the
    // currently-active segment as a real-elapsed Split and stamps
    // the engine state to `.finished`. We then mirror that state
    // onto the persisted Race row + tear down the Live Activity /
    // Watch session the same way a natural finish does.
    //
    // Downstream views can detect a partial race by comparing
    // `splits.count` to `totalSegments`.
    func endEarlyAndSave() {
        guard let race = activeRace, !race.isFinished else { return }
        let now = Date()

        engine.forceFinish(at: now)
        // §13.8 Tier 2 — stamp Watch rep count onto the closing
        // segment's Split if applicable. forceFinish appends a
        // closing-segment Split the same way advance does, so the
        // rep-counting stamp pattern fires identically.
        stampLatestRepCountOnJustClosedSplit()

        // Mirror engine state onto the Race row using the same path
        // a natural finish takes. This stamps `endedAt` and
        // captures any closing-segment Split the engine just
        // appended.
        persistActiveRace()

        // Write the partial race to HealthKit + rehydrate HR/cal
        // segment stats so the History card has the same data
        // surface a complete race does. Partial races still
        // represent real work; they belong in Health.
        saveFinishedRaceToHealthKit()
        rehydrateSegmentStatsAfterFinish()

        // End the Live Activity with a final state, same as a
        // natural finish so the lock-screen ribbon shows
        // "FINISHED" (and the athlete sees their partial total
        // time briefly there).
        #if canImport(ActivityKit)
        let finalState = currentLiveActivityState()
        LiveActivityService.shared.end(finalState: finalState)
        #endif

        // Tell the Watch the workout's done so it can finalize
        // the HKWorkoutSession to HealthKit.
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.sendControl(.endWorkout(at: now))
        #endif

        // Push to Supabase so the partial race lands in the
        // feed (if not marked private). Same fire-and-forget
        // pattern the natural-finish path uses.
        #if canImport(UIKit)
        if let userID = AuthService.shared.user?.id.uuidString {
            Task { @MainActor in
                await RaceSyncService.pushFinishedRace(race, userID: userID)
            }
        }
        #endif

        stopHeartRatePolling()
        cancelCountdown()
    }

    // Abandon an in-progress race, removing its persisted row. Not wired into
    // v0.1 UI yet but available for a future "cancel race" affordance.
    func abandon() {
        if let race = activeRace, !race.isFinished {
            modelContext?.delete(race)
            saveContextSilently()
        }

        // Kill the Live Activity immediately on abandon — no
        // final state, immediate dismissal — because the race
        // didn't really happen. We don't want a stale cancelled
        // race haunting the lock screen.
        #if canImport(ActivityKit)
        LiveActivityService.shared.end(finalState: nil)
        #endif

        // Tell the Watch to discard its HKWorkoutSession (vs end
        // + finalize). No HKWorkout is persisted, no Activity ring
        // credit, no clutter in Apple Health from races that didn't
        // actually happen.
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.sendControl(.discardWorkout)
        #endif

        engine.reset()
        activeRace = nil
        stopHeartRatePolling()
        cancelCountdown()
    }

    // MARK: - Persistence

    // Mirror the engine's current state onto `activeRace` and save. Called
    // after every state-changing event so the persisted row is always a
    // faithful snapshot of the live engine.
    private func persistActiveRace() {
        guard let race = activeRace else { return }

        switch engine.state {
        case .notStarted:
            break
        case .inProgress(let startedAt, let segStart, let splits):
            race.startedAt = startedAt
            race.endedAt = nil
            race.splits = splits
            race.currentSegmentStartedAt = segStart
            // Clear pausedAt — coming OUT of paused via resume()
            // shifts timestamps forward and lands us back in
            // .inProgress, at which point the Race row should no
            // longer carry the pause marker.
            race.pausedAt = nil
            // Roxzone is closed when we're in progress; the
            // pending duration moves to Race.pendingRoxzoneSeconds
            // mirror so a force-kill mid-segment-after-roxzone
            // doesn't lose the transition time.
            race.roxzoneStartedAt = nil
            race.pendingRoxzoneSeconds = engine.pendingRoxzoneSeconds
        case .paused(let startedAt, let segStart, let splits, let pausedAt):
            race.startedAt = startedAt
            race.endedAt = nil
            race.splits = splits
            race.currentSegmentStartedAt = segStart
            race.pausedAt = pausedAt
            race.roxzoneStartedAt = nil
            race.pendingRoxzoneSeconds = engine.pendingRoxzoneSeconds
        case .inRoxzone(let startedAt, let splits, let roxzoneStartedAt):
            race.startedAt = startedAt
            race.endedAt = nil
            race.splits = splits
            race.currentSegmentStartedAt = nil
            race.pausedAt = nil
            race.roxzoneStartedAt = roxzoneStartedAt
            // No pending roxzone yet — it's mid-roxzone, the
            // duration will be computed on startNextSegment.
            race.pendingRoxzoneSeconds = nil
        case .finished(let startedAt, let endedAt, let splits):
            race.startedAt = startedAt
            race.endedAt = endedAt
            race.splits = splits
            race.currentSegmentStartedAt = nil
            race.pausedAt = nil
            race.roxzoneStartedAt = nil
            race.pendingRoxzoneSeconds = nil
            // §19.2 — stamp the dominant HR source for this
            // race so the SourceProvenanceCard renders on
            // RaceDetailView for historical races (not just
            // live on RaceSummary). Snapshot the registry's
            // lastHRSource at finish; if a fallover happened
            // mid-race, this captures whichever source was
            // active at the end. Future v2: track all sources
            // used during the race rather than just the last.
            if race.hrSourcePrimary == nil {
                let source = SensorSourceRegistry.shared.lastHRSource
                if source != .unknown {
                    race.hrSourcePrimary = source.shortLabel
                }
            }

            // §19.4 Phase 10J — drain the AirPods head-pitch
            // sample buffer and compute first-half vs second-
            // half posture drift in degrees. Stamped here (in
            // the `.finished` branch) so it runs once per race
            // finish, alongside the HR source attribution above.
            //
            // Idempotency gate: only stamp when the race has no
            // drift value yet. persistActiveRace can fire again
            // after `attachSegmentStats` (HK queries patching
            // splits async), and `flushPitchSamples()` clears
            // its buffer on read — without the nil-gate, the
            // second call would overwrite the real drift with
            // nil because the buffer is now empty.
            //
            // Same gate works for re-finish edge cases (e.g.
            // endEarlyAndSave on an already-finished race —
            // shouldn't happen given the guard at the top of
            // endEarlyAndSave, but defensive).
            if race.posturePitchDriftDegrees == nil {
                let pitchSamples = HeadphoneMotionService.shared.flushPitchSamples()
                if let drift = RaceStats.posturePitchDriftDegrees(
                    forPitchSamples: pitchSamples
                ) {
                    race.posturePitchDriftDegrees = drift
                }
            }
        }

        saveContextSilently()

        // Every state change persisted → also push to the
        // Live Activity. ActivityKit budget per-update is the
        // bottleneck (not network), but every persist is a real
        // user-driven event (advance/pause/resume/etc.) so we'd
        // want to publish those anyway.
        #if canImport(ActivityKit)
        pushLiveActivityUpdate()
        #endif
    }

    // The default ModelContainer autosaves periodically, but we force-save
    // after every race event so a mid-segment app-kill loses at most a few
    // hundred ms rather than whatever was buffered. `try?` is acceptable
    // because an in-memory engine still holds the true state — the next save
    // will catch up.
    private func saveContextSilently() {
        try? modelContext?.save()
    }

    // MARK: - Watch-sourced HR ingestion

    // Track the most recent HR sample timestamp from the Watch so we
    // can reject out-of-order arrivals (WCSession can queue + reorder
    // when the phone is briefly unreachable). Initialized in the
    // distant past so the first sample always wins.
    private var lastWatchHRSampleAt: Date = .distantPast

    // Maximum age of a Watch HR sample we'll accept. Samples
    // older than this get rejected as stale.
    //
    // Bumped from 30s → 90s after the transferUserInfo fallback
    // path landed (phone-side ingest now receives queued samples
    // that can be 30-60s old when the phone wakes from a pocket
    // cycle / lock state). 30s rejected those samples wholesale,
    // leaving the chip stuck at the last live-streamed value.
    // 90s accepts queued bursts while still discarding genuinely
    // old samples (e.g. from a previous race that somehow gets
    // replayed by the OS's WCSession layer).
    private static let watchHRStaleThreshold: TimeInterval = 90

    // MARK: - Watch-sourced rep counting (§13.8 Tier 2)

    // §13.8 Tier 2 — public computed view of the latest Watch
    // rep count for SwiftUI consumption. Returns the count ONLY
    // when the latest update's stationRaw matches the current
    // station (otherwise it's a stale value from the last station
    // and shouldn't render). Nil before the first update of a
    // station OR when the athlete isn't on a rep-counting station.
    //
    // RaceView reads this to render the live REPS stat tile.
    // Backed by the observable `latestWatchRepUpdate` so SwiftUI
    // dependency tracking re-renders when it changes.
    var currentRepCount: Int? {
        guard let update = latestWatchRepUpdate,
              update.stationRaw == currentStation?.rawValue
        else { return nil }
        return update.count
    }

    // The most recent rep count update we've accepted from the
    // Watch's WatchRepCountingService. Holds the count for whichever
    // station the Watch was last counting for. Used at engine.advance
    // time to auto-fill Split.repsCompleted when the just-completed
    // station matches `stationRaw`.
    //
    // Last-write-wins keyed by sampledAt — the watch publishes at
    // ~1Hz throughout the station plus one final publish at stop()
    // (i.e. when the station ends). The final one is usually the
    // last value we see; if it's late and arrives after advance, it
    // can also patch the just-finished split's repsCompleted if
    // the field hasn't been touched manually — see
    // `ingestRepCount` for the patching logic.
    private var latestWatchRepUpdate: WatchRepCountUpdate?

    // Most recent sampledAt we accepted — same out-of-order
    // rejection pattern as HR sample ingest.
    private var lastWatchRepSampleAt: Date = .distantPast

    // Maximum age of a Watch rep-count sample we'll accept. Same
    // 90s threshold as HR — covers transferUserInfo queued bursts
    // after a pocket-cycle while still discarding genuinely stale
    // samples from a previous race.
    private static let watchRepStaleThreshold: TimeInterval = 90

    // Receive a rep-count sample published from the Watch's
    // WatchRepCountingService via WCSession. Wired by RaceView
    // through `WatchCompanionService.onRepCount` for the active-
    // race lifetime.
    //
    // Two side effects:
    //   1. Update `latestWatchRepUpdate` so advance() can stamp
    //      the just-completed Split.repsCompleted.
    //   2. If the just-completed split (one before the current
    //      segment) has matching stationRaw AND no manually-set
    //      repsCompleted yet, patch it in-place — handles the
    //      "Watch's final-publish landed after iPhone advanced"
    //      race condition.
    func ingestRepCount(_ update: WatchRepCountUpdate) {
        let age = Date().timeIntervalSince(update.sampledAt)
        guard age < Self.watchRepStaleThreshold else { return }
        guard update.sampledAt >= lastWatchRepSampleAt else { return }
        lastWatchRepSampleAt = update.sampledAt

        latestWatchRepUpdate = update

        // Catch-up patching: if a rep update arrives AFTER the
        // athlete already advanced past the station it belongs to,
        // the just-completed Split is at index `splits.count - 1`
        // (engine.advance appended it). Find that split, check
        // station rawValue + that repsCompleted is still nil
        // (don't clobber a manual override), and patch.
        //
        // Walks backwards from the most-recent split. Two reasons:
        //   • Repeats — same station can appear multiple times in
        //     custom workouts; the most recent match is correct.
        //   • Bound — we only need to look at recently-closed
        //     splits, not the whole race.
        let splits = engine.splits
        for index in splits.indices.reversed() {
            let split = splits[index]
            guard split.station.rawValue == update.stationRaw else { continue }
            // Found the most recent split with matching station.
            // Patch only if reps are still nil (don't overwrite
            // manual input from the athlete in StationStatsSheet).
            if split.repsCompleted == nil {
                engine.setStationStats(
                    repsCompleted: .some(update.count),
                    atSplitIndex: index
                )
                persistActiveRace()
            }
            break
        }
    }

    // Called from `advance()` after engine.advance has appended
    // the just-finished split. Stamps repsCompleted on that split
    // when the latest Watch rep update matches its station and the
    // field is still nil (manual edits via StationStatsSheet win).
    //
    // Separate from `ingestRepCount`'s catch-up patching so the
    // happy-path advance (latest count is already in hand, no
    // race condition) is fast + obvious.
    private func stampLatestRepCountOnJustClosedSplit() {
        guard let update = latestWatchRepUpdate else { return }
        let index = engine.splits.count - 1
        guard engine.splits.indices.contains(index) else { return }
        let split = engine.splits[index]
        guard split.station.rawValue == update.stationRaw else { return }
        guard split.repsCompleted == nil else { return }
        engine.setStationStats(
            repsCompleted: .some(update.count),
            atSplitIndex: index
        )
        // Clear so a stale-but-still-recent update doesn't bleed
        // into a future advance on the same station (unlikely in
        // HYROX's fixed sequence but possible for custom workouts
        // that repeat a station).
        latestWatchRepUpdate = nil
    }

    // Receive a heart-rate sample published from the Watch's
    // HKLiveWorkoutBuilder via WCSession. Wired up by `RaceView` for
    // the active-race lifetime through `WatchCompanionService.onHeartRate`.
    //
    // Writes to `currentHeartRateBPM` — the same property the
    // existing phone-side HR poll writes to — so all downstream
    // consumers (race screen chip, Live Activity, snapshot publishing
    // for duo) keep working unchanged. The Watch's higher cadence
    // (~1Hz vs the phone's 5s poll) means Watch samples will dominate
    // the displayed value when both are active.
    //
    // Rejects samples older than 30 seconds (likely stale due to
    // WCSession queuing) and samples older than the last one we
    // accepted (out-of-order delivery).
    func ingestHeartRate(_ update: WatchHeartRateUpdate) {
        // Reject stale samples (queued + delivered late).
        let age = Date().timeIntervalSince(update.sampledAt)
        guard age < Self.watchHRStaleThreshold else { return }

        // Reject out-of-order samples.
        guard update.sampledAt >= lastWatchHRSampleAt else { return }
        lastWatchHRSampleAt = update.sampledAt

        // Sanity bounds — defense in depth. The Watch side already
        // filters bogus values, but the WCSession boundary deserves
        // its own guard.
        guard update.bpm >= 30, update.bpm <= 230 else { return }

        currentHeartRateBPM = update.bpm
        // §19 — every accepted Watch sample updates the source
        // attribution registry so the live HR chip's source glyph
        // shows `applewatch` even when polling momentarily falls
        // back to HK between Watch pushes.
        SensorSourceRegistry.shared.recordHRSource(.watch)
    }

    // MARK: - Live HR polling

    // Start a background loop that asks HealthKit for the latest HR
    // sample every `heartRatePollInterval` seconds, publishing each
    // reading to `currentHeartRateBPM` on MainActor. Idempotent — if
    // a loop is already running (e.g. resume called after startRace),
    // the old one is cancelled first.
    //
    // Guarded by `canImport(HealthKit)` so macOS builds compile
    // without the polling path at all.
    private func startHeartRatePolling() {
        // §19.4 Phase 10H — pair the cadence stream with the
        // HR polling lifecycle. HeadphoneMotionService.start()
        // is a safe no-op when AirPods aren't motion-capable,
        // so this never breaks Watch-only or iPhone-only
        // racers.
        HeadphoneMotionService.shared.start()

        #if canImport(HealthKit)
        stopHeartRatePolling()

        heartRatePollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Loop until cancelled. Task.isCancelled trips on
            // stopHeartRatePolling() or when the task is GC'd.
            while !Task.isCancelled {
                // §19 — `currentHeartRateWithSource()` returns the
                // BPM AND the writing source's name in one query.
                // We classify the source via the registry so the
                // attribution chip shows the correct glyph
                // (AirPods Pro 3 / Apple Watch / iPhone fallback)
                // for HK-polled samples too.
                if let result = await HealthKitService.shared.currentHeartRateWithSource() {
                    let bpm = result.bpm
                    let watchSampleAge = Date().timeIntervalSince(self.lastWatchHRSampleAt)
                    // 10s grace window: if a Watch sample arrived
                    // within the last 10s, the Watch is considered
                    // "live" and we skip the polled write. After
                    // 10s of silence we assume Watch streaming is
                    // dropped (app killed, HK denied, out of
                    // range) and let polling fill the gap.
                    if watchSampleAge >= 10 {
                        self.currentHeartRateBPM = bpm
                        // Attribute the polled sample by its source
                        // name. For an AirPods-only racer this
                        // surfaces as `.airPods("AirPods Pro 3")`;
                        // for a Watch user with Watch streaming
                        // dropped, the polled HK sample is still
                        // Watch-sourced, so `.watch` shows.
                        let source = SensorSourceRegistry.HRSource.classify(
                            sourceName: result.sourceName
                        )
                        SensorSourceRegistry.shared.recordHRSource(source)
                    }
                }
                // `try? await Task.sleep` — on cancellation, sleep
                // throws CancellationError which we swallow and the
                // outer while loop exits cleanly on the next check.
                try? await Task.sleep(for: .seconds(Self.heartRatePollInterval))
            }
        }
        #endif
    }

    // Stop the polling loop and clear any stale HR readout. Called on
    // race finish, abandon, and view-disappear so the task doesn't
    // outlive the race it was tracking.
    private func stopHeartRatePolling() {
        heartRatePollTask?.cancel()
        heartRatePollTask = nil
        currentHeartRateBPM = nil
        // §19.4 Phase 10H — tear down the cadence stream
        // alongside HR polling. Both are race-scoped; leaving
        // CMHeadphoneMotionManager subscribed after the race
        // would drain AirPods battery without any UI surface
        // consuming the values.
        HeadphoneMotionService.shared.stop()
    }

    // MARK: - HealthKit

    // Fire-and-forget push of the just-finished race to Apple Health. The
    // first call per install triggers the iOS authorization sheet; later
    // calls are silent. Failures (permission denied, HealthKit unavailable
    // on this device, etc.) are swallowed — the race is already saved
    // locally and shown in History, so HealthKit is additive not essential.
    //
    // Prerequisites (all in place as of the entitlements + Info.plist
    // wiring commit):
    //   - HealthKit capability on the main app target
    //     (Hyroxapp/Hyroxapp.entitlements)
    //   - NSHealthShareUsageDescription + NSHealthUpdateUsageDescription
    //     strings declared as INFOPLIST_KEY_* build settings
    // Without these, calling `requestAuthorization` crashes the app
    // unrecoverably — not an error we can catch. Keep them in sync if you
    // ever revisit the signing / Info.plist setup.
    private func saveFinishedRaceToHealthKit() {
        #if canImport(HealthKit)
        guard let race = activeRace else { return }
        Task {
            try? await HealthKitService.shared.saveRace(race)
        }
        #endif
    }
}

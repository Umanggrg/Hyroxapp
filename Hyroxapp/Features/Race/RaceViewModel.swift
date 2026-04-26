import Foundation
import SwiftData

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

    // Handle to the background polling Task so we can cancel it when
    // the race finishes, the user abandons, or the Race view
    // disappears. Nil outside of an active race.
    private var heartRatePollTask: Task<Void, Never>?

    // Pre-race countdown state — used to render a 3-2-1-GO overlay
    // on RaceView between the user tapping "Start Race" and the
    // engine timer actually beginning. `countdownValue` is the
    // current number on screen (3 → 2 → 1 → 0/"GO"); a Task ticks
    // it down once per second. Both nil when no countdown is
    // active. UI reads `isCountingDown` to decide whether to show
    // the overlay.
    private(set) var countdownValue: Int?
    private var countdownTask: Task<Void, Never>?

    var isCountingDown: Bool { countdownValue != nil }

    // How often we refresh current HR during a race. 5s is a good
    // balance — Watch publishes HR to HealthKit every 5–15s in ambient
    // mode and more frequently in workout mode, so a 5s poll usually
    // catches the latest sample shortly after it lands without
    // hammering HealthKit with redundant queries.
    private static let heartRatePollInterval: TimeInterval = 5

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
                currentStationName: stationName
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
                currentStationName: stationName
            )
        case .inRoxzone(let raceStart, _, let roxStart):
            return RaceActivityAttributes.ContentState(
                phase: .inRoxzone,
                timerStart: raceStart,
                segmentStart: roxStart,  // segment timer hidden in roxzone view
                roxzoneStart: roxStart,
                currentStationIndex: stationIndex,
                totalStations: engine.sequence.count,
                currentStationName: stationName
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
                currentStationName: stationName
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
    func makeRaceStateSnapshot(division: Division, maxHR: Int = 190) -> RaceStateSnapshot? {
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
            maxHeartRate: maxHR
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
        countdownEnabled: Bool
    ) {
        guard !isCountingDown, !isRacing else { return }

        guard countdownEnabled else {
            startRace(sequence: sequence, targetDuration: targetDuration)
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
            self.startRace(sequence: sequence, targetDuration: targetDuration)
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
        targetDuration: TimeInterval? = nil
    ) {
        guard isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = nil
        startRace(sequence: sequence, targetDuration: targetDuration)
    }

    func startRace(
        sequence: [Station] = Station.raceSequence,
        targetDuration: TimeInterval? = nil
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
        modelContext?.insert(race)
        activeRace = race
        saveContextSilently()
        // Kick off the live-HR polling loop. Runs independently of
        // the per-split HR stats — this feeds the on-screen "current
        // bpm" readout, not the historical per-station aggregates.
        startHeartRatePolling()

        // Kick off the Live Activity (lock screen + Dynamic
        // Island race timer). Initial state from the engine
        // we just started. Failures are silent — the in-app
        // race UI is the source of truth, the activity is
        // additive.
        #if canImport(ActivityKit)
        if let state = currentLiveActivityState() {
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
        engine.endSegment(at: Date())
        let newSplitIndex = engine.splits.count - 1
        persistActiveRace()

        // If endSegment was called on the FINAL segment, engine
        // flipped to .finished — mirror to HealthKit once.
        if wasInProgress, engine.isFinished {
            saveFinishedRaceToHealthKit()
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
    }

    // Resume a paused race. Engine shifts startedAt forward by the
    // pause duration so existing elapsed-time math keeps working;
    // persistence + HR polling come back online.
    func resumeRace() {
        engine.resume(at: Date())
        persistActiveRace()
        startHeartRatePolling()
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
        engine.advance(at: Date())
        // Capture the index of the split that `engine.advance` just appended
        // so the async HR patch can find and update it below. Must be read
        // before `persistActiveRace` because that's a sync write; the HR
        // task is what races the user forward.
        let newSplitIndex = engine.splits.count - 1
        persistActiveRace()

        if !wasFinished, engine.isFinished {
            saveFinishedRaceToHealthKit()
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

            // Run both HealthKit queries in parallel — HR stats and
            // calories sum are independent, so awaiting them
            // sequentially would just double the wall-clock latency.
            async let heartRate = HealthKitService.shared.heartRateStats(
                from: segmentStart,
                to: segmentEnd
            )
            async let calories = HealthKitService.shared.activeCalories(
                from: segmentStart,
                to: segmentEnd
            )
            let hr = await heartRate
            let kcal = await calories

            // Skip the persist round-trip if HealthKit had nothing
            // for this segment — common for indoor sessions without
            // a Watch streaming any of these metrics.
            guard hr.avg != nil || hr.max != nil || kcal != nil else {
                return
            }

            self.engine.setSegmentStats(
                heartRateAvg: hr.avg,
                heartRateMax: hr.max,
                activeCalories: kcal,
                atSplitIndex: index
            )
            self.persistActiveRace()
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
        #if canImport(HealthKit)
        stopHeartRatePolling()

        heartRatePollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Loop until cancelled. Task.isCancelled trips on
            // stopHeartRatePolling() or when the task is GC'd.
            while !Task.isCancelled {
                if let bpm = await HealthKitService.shared.currentHeartRate() {
                    self.currentHeartRateBPM = bpm
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

import Foundation

// Pure state machine for a HYROX race.
//
// Deliberately has zero dependencies on SwiftUI, SwiftData, or `@Observable`.
// This purity pays dividends in three places:
//   1. Unit tests can drive it with injected `Date`s — no runloop, no waiting.
//   2. The Apple Watch app (v2) reuses it unchanged.
//   3. Duo Mode (v2) feeds partner-originated `advance` events in from Supabase
//      Realtime — the engine doesn't care where the event came from.
//
// Timing is always derived by subtracting stored `Date`s. We never accumulate
// elapsed time tick-by-tick — that drifts, and drift compounds over a 90-minute
// race.
struct RaceEngine: Sendable {

    // MARK: - State

    enum State: Equatable, Sendable {
        case notStarted

        // An in-progress race.
        // `splits` holds completed segments; the current (not-yet-finished)
        // segment is `sequence[splits.count]`, which began at
        // `currentSegmentStartedAt`.
        case inProgress(
            startedAt: Date,
            currentSegmentStartedAt: Date,
            splits: [Split]
        )

        // Paused — race is mid-segment but the timer is frozen.
        // `pausedAt` snapshots the instant of pause so elapsed and
        // currentSegmentElapsed both freeze at "what they were when
        // I tapped Pause."
        //
        // Resume math: shift `startedAt` and `currentSegmentStartedAt`
        // forward by `(resumeNow - pausedAt)`. This "moves the race's
        // start origin into the future" so the existing elapsed-time
        // formula (`now - startedAt`) keeps working without scattered
        // "subtract pause duration" guards. Splits already captured
        // don't need adjustment — their endedAt is fixed history.
        case paused(
            startedAt: Date,
            currentSegmentStartedAt: Date,
            splits: [Split],
            pausedAt: Date
        )

        // Roxzone — between segments. The previous segment is
        // closed (its split is in `splits`), the next segment
        // hasn't started yet, and the athlete is in transition
        // (walking from run finish to sled, picking up gear,
        // setting up). The HYROX-specific metric.
        //
        // Race time keeps ticking against `startedAt` — the
        // overall timer is unchanged. `roxzoneStartedAt` records
        // when this transition began (= when the previous
        // segment ended) so the next-segment-start can compute
        // the roxzone duration and attach it to the upcoming
        // split.
        //
        // Only entered from .inProgress when the user explicitly
        // taps "End [segment]" with roxzone tracking enabled.
        // The single-tap advance path stays in .inProgress and
        // never enters this state.
        case inRoxzone(
            startedAt: Date,
            splits: [Split],
            roxzoneStartedAt: Date
        )

        case finished(
            startedAt: Date,
            endedAt: Date,
            splits: [Split]
        )
    }

    // MARK: - Stored properties

    // The ordered segments this race consists of. In v0.1 this is always
    // `Station.raceSequence`; keeping it injectable leaves room for truncated
    // practice variants and tests without reshaping the engine.
    let sequence: [Station]

    private(set) var state: State

    // Stash for the roxzone duration of the segment currently in
    // progress. Set by `startNextSegment` after a roxzone closes
    // and consumed when the next segment's split is created via
    // `advance` or `endSegment`. Cleared back to nil after the
    // attachment so a one-tap segment that follows wouldn't get
    // the prior roxzone re-applied. Persistence layer mirrors
    // this on Race so a force-killed mid-segment race resumes
    // with the correct roxzone attribution.
    var pendingRoxzoneSeconds: TimeInterval?

    // MARK: - Init

    init(sequence: [Station] = Station.raceSequence) {
        self.sequence = sequence
        self.state = .notStarted
    }

    // Reconstitute an engine from a persisted state — used when resuming a
    // race after the app was backgrounded or force-killed mid-race.
    init(sequence: [Station] = Station.raceSequence, state: State) {
        self.sequence = sequence
        self.state = state
    }

    // MARK: - Derived state (read-only)

    // The station the athlete is currently working on, or `nil` if the race
    // isn't in progress (or paused — the same station the athlete will
    // resume to). When in roxzone, this is the station the athlete is
    // about to start (the next segment, transitioning into).
    var currentStation: Station? {
        switch state {
        case .inProgress(_, _, let splits), .paused(_, _, let splits, _):
            return sequence[safe: splits.count]
        case .inRoxzone(_, let splits, _):
            // After a segment ends and we enter roxzone, splits.count
            // points to the next segment. That's the one being
            // transitioned into.
            return sequence[safe: splits.count]
        default:
            return nil
        }
    }

    // The station queued up after the current one — for "Up next: ..." UI.
    // `nil` on the final segment or when not in progress / paused.
    var upcomingStation: Station? {
        switch state {
        case .inProgress(_, _, let splits), .paused(_, _, let splits, _):
            return sequence[safe: splits.count + 1]
        case .inRoxzone(_, let splits, _):
            return sequence[safe: splits.count + 1]
        default:
            return nil
        }
    }

    // Completed splits so far (in race order).
    var splits: [Split] {
        switch state {
        case .notStarted:                       return []
        case .inProgress(_, _, let splits):     return splits
        case .paused(_, _, let splits, _):      return splits
        case .inRoxzone(_, let splits, _):      return splits
        case .finished(_, _, let splits):       return splits
        }
    }

    var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    // True while paused. UI uses this to swap the Pause button for a
    // Resume button, dim the screen, freeze the live HR poll, etc.
    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    // True while in roxzone (between segments). UI shows a
    // distinct overlay + "Tap to start [next station]" CTA.
    var isInRoxzone: Bool {
        if case .inRoxzone = state { return true }
        return false
    }

    // Total elapsed race time evaluated at `now`. Returns 0 before start.
    // Once finished, returns the frozen final time (independent of `now`).
    // While paused, returns the elapsed at the moment of pause —
    // freezing the timer display visually. While in roxzone, the
    // overall timer keeps ticking — race time hasn't stopped just
    // because the athlete is between segments.
    func elapsed(at now: Date) -> TimeInterval {
        switch state {
        case .notStarted:
            return 0
        case .inProgress(let startedAt, _, _):
            return now.timeIntervalSince(startedAt)
        case .paused(let startedAt, _, _, let pausedAt):
            return pausedAt.timeIntervalSince(startedAt)
        case .inRoxzone(let startedAt, _, _):
            return now.timeIntervalSince(startedAt)
        case .finished(let startedAt, let endedAt, _):
            return endedAt.timeIntervalSince(startedAt)
        }
    }

    // Elapsed time for the *current* (unfinished) segment, evaluated at `now`.
    // Returns 0 if not in progress or in roxzone (no active segment).
    // Paused freezes at the pause instant.
    func currentSegmentElapsed(at now: Date) -> TimeInterval {
        switch state {
        case .inProgress(_, let segmentStart, _):
            return now.timeIntervalSince(segmentStart)
        case .paused(_, let segmentStart, _, let pausedAt):
            return pausedAt.timeIntervalSince(segmentStart)
        default:
            return 0
        }
    }

    // Elapsed time INSIDE the current roxzone, evaluated at `now`.
    // Returns 0 when not in roxzone. Drives the live "you've been
    // in transition for 12s" countup on the in-roxzone overlay.
    func currentRoxzoneElapsed(at now: Date) -> TimeInterval {
        if case .inRoxzone(_, _, let roxzoneStart) = state {
            return now.timeIntervalSince(roxzoneStart)
        }
        return 0
    }

    // MARK: - Events (mutating)

    // Begin the race. No-op if already started or finished.
    mutating func start(at now: Date) {
        guard case .notStarted = state else { return }
        state = .inProgress(
            startedAt: now,
            currentSegmentStartedAt: now,
            splits: []
        )
    }

    // Close out the current segment and move to the next. If this was the
    // final segment, transitions to `.finished`. No-op unless a race is in
    // progress.
    //
    // Roxzone attachment: if `pendingRoxzoneSeconds` is set (the
    // last transition closed via startNextSegment), it gets
    // attached to the just-completed split's `roxzoneSeconds`.
    // Then cleared. Single-tap-mode races never set this so this
    // is a no-op for them.
    mutating func advance(at now: Date) {
        guard case .inProgress(let startedAt, let segmentStart, var splits) = state else { return }

        let index = splits.count
        guard index < sequence.count else { return }

        var completed = Split(
            station: sequence[index],
            startedAt: segmentStart,
            endedAt: now
        )
        if let roxzone = pendingRoxzoneSeconds {
            completed = completed.withRoxzone(seconds: roxzone)
            pendingRoxzoneSeconds = nil
        }
        splits.append(completed)

        if splits.count >= sequence.count {
            state = .finished(startedAt: startedAt, endedAt: now, splits: splits)
        } else {
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: now,
                splits: splits
            )
        }
    }

    // Abandon an in-progress or finished race and reset to the initial state.
    // Intended for the "Cancel race" affordance; does not persist anything.
    mutating func reset() {
        state = .notStarted
    }

    // End an in-progress race EARLY (wireframe §03.4 "End race here,
    // save partial"). Closes whatever segment was active as a Split
    // using its real elapsed time, then transitions to `.finished`
    // with however many splits the athlete actually completed.
    //
    // Handles all three "in-flight" states:
    //   • .inProgress  → close the currently-active segment, finish
    //   • .paused      → resume math wouldn't fire here (we're not
    //                    resuming, we're stopping), so the paused
    //                    segment's elapsed-as-of-pause is what we
    //                    capture. We use `pausedAt` as the natural
    //                    end-instant for the closing Split.
    //   • .inRoxzone   → no in-flight segment to close; just stamp
    //                    finished with the splits we have.
    //
    // Result is a `.finished` state with `splits.count <` sequence.count.
    // The Race row's `endedAt` is set to the same `now` so total
    // duration math is consistent. Downstream views can detect a
    // "partial" race by comparing `splits.count` vs `totalSegments`.
    //
    // No-op from `.notStarted` or already-`.finished` — both lack an
    // in-flight race to end.
    mutating func forceFinish(at now: Date) {
        switch state {
        case .inProgress(let startedAt, let segmentStart, var splits):
            let index = splits.count
            if index < sequence.count {
                var completed = Split(
                    station: sequence[index],
                    startedAt: segmentStart,
                    endedAt: now
                )
                if let roxzone = pendingRoxzoneSeconds {
                    completed = completed.withRoxzone(seconds: roxzone)
                    pendingRoxzoneSeconds = nil
                }
                splits.append(completed)
            }
            state = .finished(startedAt: startedAt, endedAt: now, splits: splits)

        case .paused(let startedAt, let segmentStart, var splits, let pausedAt):
            let index = splits.count
            if index < sequence.count {
                var completed = Split(
                    station: sequence[index],
                    startedAt: segmentStart,
                    endedAt: pausedAt
                )
                if let roxzone = pendingRoxzoneSeconds {
                    completed = completed.withRoxzone(seconds: roxzone)
                    pendingRoxzoneSeconds = nil
                }
                splits.append(completed)
            }
            // Use pausedAt as the race's ended-at — if the athlete
            // paused at 18:32 and then ended the race, their finish
            // time is 18:32, not "now plus paused duration."
            state = .finished(startedAt: startedAt, endedAt: pausedAt, splits: splits)

        case .inRoxzone(let startedAt, let splits, _):
            // No active segment to close — splits are already
            // captured up to the start of this transition.
            state = .finished(startedAt: startedAt, endedAt: now, splits: splits)

        case .notStarted, .finished:
            // Nothing to end.
            return
        }
    }

    // End the current segment and enter Roxzone. Two-tap-advance
    // path: closes the just-finished segment with a Split entry,
    // transitions to .inRoxzone where the transition timer counts
    // up until startNextSegment is called.
    //
    // From any non-inProgress state this is a no-op. Doesn't
    // finish the race even on the final segment — the user must
    // explicitly start (and then end) the final station after the
    // last roxzone, OR call `advance` directly on the final
    // segment to skip the wrap-up roxzone.
    //
    // Race time keeps running through the roxzone — this isn't
    // a pause, it's a transition that's part of the total race.
    mutating func endSegment(at now: Date) {
        guard case .inProgress(let startedAt, let segmentStart, var splits) = state else { return }

        let index = splits.count
        guard index < sequence.count else { return }

        var completed = Split(
            station: sequence[index],
            startedAt: segmentStart,
            endedAt: now
        )
        if let roxzone = pendingRoxzoneSeconds {
            completed = completed.withRoxzone(seconds: roxzone)
            pendingRoxzoneSeconds = nil
        }
        splits.append(completed)

        // If that was the FINAL segment, we go straight to
        // .finished — there's no segment after to transition
        // into, so no roxzone makes sense.
        if splits.count >= sequence.count {
            state = .finished(startedAt: startedAt, endedAt: now, splits: splits)
        } else {
            state = .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: now
            )
        }
    }

    // Begin the next segment after a roxzone. Computes the
    // roxzone duration (now - roxzoneStartedAt), stashes it on
    // the engine via `pendingRoxzoneSeconds`, and transitions
    // back to .inProgress with the next segment as the active
    // one. The pendingRoxzoneSeconds value is consumed when
    // that segment closes (via endSegment or advance), at which
    // point it's attached to the segment's Split.
    //
    // From any non-inRoxzone state this is a no-op.
    mutating func startNextSegment(at now: Date) {
        guard case .inRoxzone(let startedAt, let splits, let roxzoneStart) = state else { return }
        let duration = now.timeIntervalSince(roxzoneStart)
        pendingRoxzoneSeconds = duration
        state = .inProgress(
            startedAt: startedAt,
            currentSegmentStartedAt: now,
            splits: splits
        )
    }

    // Rebase the current segment's start timestamp without touching
    // the race-level startedAt. Used by the manual-run-start
    // feature: when the user advances into a run station with
    // manual start enabled, the engine has already moved to the
    // run, but the athlete may take a few seconds to pre-position
    // before they're ready. Tapping "Start Run" calls this with
    // `now` so the segment's recorded duration reflects only the
    // actual run time, not the pre-positioning delay. Total race
    // time keeps ticking through the delay (it's part of the
    // race), only the segment's clock starts fresh.
    //
    // No-op outside of `.inProgress` — paused / inRoxzone / finished
    // races don't have an active segment to rebase.
    mutating func rebaseCurrentSegmentStart(to now: Date) {
        guard case .inProgress(let raceStart, _, let splits) = state else {
            return
        }
        state = .inProgress(
            startedAt: raceStart,
            currentSegmentStartedAt: now,
            splits: splits
        )
    }

    // Pause an in-progress race. Captures `now` as `pausedAt`. From
    // any other state this is a no-op — pausing a not-yet-started or
    // already-finished race has no semantic meaning.
    mutating func pause(at now: Date) {
        guard case .inProgress(let startedAt, let segmentStart, let splits) = state else { return }
        state = .paused(
            startedAt: startedAt,
            currentSegmentStartedAt: segmentStart,
            splits: splits,
            pausedAt: now
        )
    }

    // Resume from paused. Computes pause duration and shifts both
    // start timestamps forward by that amount so the existing
    // `now - startedAt` formula keeps producing the correct elapsed
    // time without further adjustments. From any non-paused state
    // this is a no-op.
    //
    // Long pauses are fine — if the user paused, force-killed the
    // app, and resumed three days later, the math still works:
    // resumeDelta is just much larger.
    mutating func resume(at now: Date) {
        guard case .paused(let startedAt, let segmentStart, let splits, let pausedAt) = state else { return }
        let pauseDuration = now.timeIntervalSince(pausedAt)
        state = .inProgress(
            startedAt: startedAt.addingTimeInterval(pauseDuration),
            currentSegmentStartedAt: segmentStart.addingTimeInterval(pauseDuration),
            splits: splits
        )
    }

    // Attach segment-window statistics (HR avg/max + active calories)
    // to the split at the given index. Used from RaceViewModel after
    // a parallel batch of HealthKit queries returns — the advance
    // itself stays synchronous (the split is appended with all stats
    // nil, then patched here when HealthKit responds). No-op if the
    // index is out of range or the engine isn't in a state with splits.
    //
    // Safe to call from either `.inProgress` or `.finished` — stats can
    // be attached to the final split of a freshly-finished race exactly
    // as to an intermediate split.
    //
    // All metrics are optional: any combination of "have HR but no
    // calories", "have calories but no HR", or just one of the four
    // values is supported. The Split's `withSegmentStats` builder
    // forwards each value through unchanged.
    // Patch the manual-entry station stats (weight / reps / RPE)
    // on the split at `index`. Mirrors `setSegmentStats` for the
    // user-driven fields. Each parameter uses the double-optional
    // pattern from `Split.withStationStats`: passing `.some(nil)`
    // explicitly clears the field, omitting the parameter
    // (defaulted to nil-as-Optional<Optional<...>>) leaves it
    // unchanged.
    //
    // Safe to call from any state that has splits; no-op otherwise
    // or when the index is out of range.
    mutating func setStationStats(
        weightKg: Double?? = nil,
        repsCompleted: Int?? = nil,
        rpe: Int?? = nil,
        atSplitIndex index: Int
    ) {
        switch state {
        case .notStarted:
            return
        case .inProgress(let startedAt, let segmentStart, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = splits[index].withStationStats(
                weightKg: weightKg,
                repsCompleted: repsCompleted,
                rpe: rpe
            )
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits
            )
        case .paused(let startedAt, let segmentStart, var splits, let pausedAt):
            guard splits.indices.contains(index) else { return }
            splits[index] = splits[index].withStationStats(
                weightKg: weightKg,
                repsCompleted: repsCompleted,
                rpe: rpe
            )
            state = .paused(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits,
                pausedAt: pausedAt
            )
        case .inRoxzone(let startedAt, var splits, let roxzoneStart):
            // Edits while in roxzone target a previous (already-
            // closed) split — the just-finished one. Patch
            // through, preserve the roxzone state.
            guard splits.indices.contains(index) else { return }
            splits[index] = splits[index].withStationStats(
                weightKg: weightKg,
                repsCompleted: repsCompleted,
                rpe: rpe
            )
            state = .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxzoneStart
            )
        case .finished(let startedAt, let endedAt, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = splits[index].withStationStats(
                weightKg: weightKg,
                repsCompleted: repsCompleted,
                rpe: rpe
            )
            state = .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
    }

    mutating func setSegmentStats(
        heartRateAvg: Double?,
        heartRateMax: Double?,
        heartRateEntry: Double? = nil,
        heartRateEnd: Double? = nil,
        heartRateStdDev: Double? = nil,
        lowestSpO2: Double? = nil,
        activeCalories: Double?,
        atSplitIndex index: Int
    ) {
        // Helper to apply the patch in any state. Capturing entry/end
        // alongside avg/max lets the four boundary samples and the
        // segment-window aggregate land in the same Split mutation.
        func patch(_ split: Split) -> Split {
            split.withSegmentStats(
                heartRateAvg: heartRateAvg,
                heartRateMax: heartRateMax,
                heartRateEntry: heartRateEntry,
                heartRateEnd: heartRateEnd,
                heartRateStdDev: heartRateStdDev,
                lowestSpO2: lowestSpO2,
                activeCalories: activeCalories
            )
        }

        switch state {
        case .notStarted:
            return
        case .inProgress(let startedAt, let segmentStart, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits
            )
        case .paused(let startedAt, let segmentStart, var splits, let pausedAt):
            // HealthKit query results can land while the race is
            // paused (the parallel batch from the prior advance was
            // still in flight). Patch through unchanged — pausing
            // doesn't invalidate already-completed splits' stats.
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .paused(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits,
                pausedAt: pausedAt
            )
        case .inRoxzone(let startedAt, var splits, let roxzoneStart):
            // Same rationale as paused — the parallel HealthKit
            // batch from the just-completed segment may resolve
            // while the user is in roxzone. Patch through.
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxzoneStart
            )
        case .finished(let startedAt, let endedAt, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
    }

    // Patch the split at the given index with post-segment recovery
    // HR samples (30s and 60s after segment end). Called by the
    // delayed Task in RaceViewModel.attachSegmentStats — fires ~70s
    // after a segment completes, by which point HealthKit has had
    // time to receive the Watch's recovery-window samples.
    //
    // State-symmetric with setSegmentStats — recovery patches can
    // land in any race state including .finished (most common: the
    // final station's recovery window completes after the user has
    // already crossed the finish line).
    mutating func setRecoveryStats(
        heartRateRecovery30s: Double?,
        heartRateRecovery60s: Double?,
        atSplitIndex index: Int
    ) {
        func patch(_ split: Split) -> Split {
            split.withRecoveryStats(
                heartRateRecovery30s: heartRateRecovery30s,
                heartRateRecovery60s: heartRateRecovery60s
            )
        }

        switch state {
        case .notStarted:
            return
        case .inProgress(let startedAt, let segmentStart, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits
            )
        case .paused(let startedAt, let segmentStart, var splits, let pausedAt):
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .paused(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits,
                pausedAt: pausedAt
            )
        case .inRoxzone(let startedAt, var splits, let roxzoneStart):
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxzoneStart
            )
        case .finished(let startedAt, let endedAt, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = patch(splits[index])
            state = .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
    }

    // §19 Phase 10I — stamp the vertical-oscillation rolling
    // avg onto the just-ended split. Called synchronously
    // from RaceViewModel.attachSegmentStats at segment-end
    // on run-kind splits, before the async HR Task starts.
    // State-symmetric with setSegmentStats so the patch can
    // land in any race state. Split is a value type so we
    // mutate via the local var splits copy then reassign
    // state — same pattern setSegmentStats uses.
    mutating func setVerticalOscillation(
        _ verticalOscCm: Double,
        atSplitIndex index: Int
    ) {
        switch state {
        case .notStarted:
            return
        case .inProgress(let startedAt, let segmentStart, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index].verticalOscCmAvg = verticalOscCm
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits
            )
        case .paused(let startedAt, let segmentStart, var splits, let pausedAt):
            guard splits.indices.contains(index) else { return }
            splits[index].verticalOscCmAvg = verticalOscCm
            state = .paused(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits,
                pausedAt: pausedAt
            )
        case .inRoxzone(let startedAt, var splits, let roxzoneStart):
            guard splits.indices.contains(index) else { return }
            splits[index].verticalOscCmAvg = verticalOscCm
            state = .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxzoneStart
            )
        case .finished(let startedAt, let endedAt, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index].verticalOscCmAvg = verticalOscCm
            state = .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
    }

    // §19.4 Phase 10K — stamp the ground-contact-time rolling
    // avg onto the just-ended split. Same shape as
    // setVerticalOscillation above; both are run-kind metrics
    // captured at segment-end by RaceViewModel.attach
    // SegmentStats. State-symmetric across all engine states
    // (in-progress, paused, in-roxzone, finished) for the
    // same reasons.
    mutating func setGroundContactTime(
        _ groundContactMs: Double,
        atSplitIndex index: Int
    ) {
        switch state {
        case .notStarted:
            return
        case .inProgress(let startedAt, let segmentStart, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index].groundContactTimeMsAvg = groundContactMs
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits
            )
        case .paused(let startedAt, let segmentStart, var splits, let pausedAt):
            guard splits.indices.contains(index) else { return }
            splits[index].groundContactTimeMsAvg = groundContactMs
            state = .paused(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits,
                pausedAt: pausedAt
            )
        case .inRoxzone(let startedAt, var splits, let roxzoneStart):
            guard splits.indices.contains(index) else { return }
            splits[index].groundContactTimeMsAvg = groundContactMs
            state = .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxzoneStart
            )
        case .finished(let startedAt, let endedAt, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index].groundContactTimeMsAvg = groundContactMs
            state = .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
    }
}

// MARK: - Helpers

// Out-of-bounds-safe subscript. `currentStation` / `upcomingStation` rely on
// it so we don't have to sprinkle `indices.contains(...)` guards throughout.
//
// Promoted from `private` to module-internal because RaceViewModel also
// reaches into `engine.sequence[safe:]` when building the Live Activity
// snapshot (it falls back to the last station after a race finishes so the
// lock-screen UI still has a station name to render). A `private` extension
// inside RaceEngine.swift is only visible inside that file; making this
// `internal` (the default) lets the same helper be reused across the Race
// feature without forcing every caller to re-implement the bounds check.
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

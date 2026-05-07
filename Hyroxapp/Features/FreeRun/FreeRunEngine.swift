import Foundation

// Pure state machine for a Free Run session — companion to
// `RaceEngine` for HYROX races.
//
// What it owns:
//   • The phase the run is in (notStarted, inProgress, paused, finished).
//   • The list of completed splits.
//   • The cumulative distance, in metres.
//   • The split-unit (mile vs km) so it knows when to fire the
//     next auto-split.
//
// What it deliberately does NOT own:
//   • Any SwiftUI / SwiftData / WatchKit concerns. The engine is
//     plain Swift and is unit-testable in isolation, same contract
//     as `RaceEngine`.
//   • The HealthKit query path. Distance is fed in via
//     `recordDistance(...)` from whatever source has it (the Watch's
//     HKLiveWorkoutBuilder, the iPhone's CMPedometer, etc.). The
//     engine doesn't care which.
//   • HR / calorie aggregates. Those are post-finish enrichment
//     handled by the view model, same pattern as
//     `attachSegmentStats` for races.
//
// State machine:
//
//   notStarted ──start()──> inProgress ──end()──> finished
//                              │  ▲
//                              │  │
//                          pause() resume()
//                              │  │
//                              ▼  │
//                            paused
//
// Distance arrives via `recordDistance(at:metres:)`. The engine
// captures a split when the cumulative distance crosses the next
// integer multiple of `splitUnit.metresPerUnit`. Multiple splits
// can fire in a single recordDistance call if a pedometer batch
// pushes through more than one boundary at once (rare but
// defensible — long Watch-to-phone catch-up burst after a
// disconnect, etc.).
//
// Time math contract: same as RaceEngine — never accumulate ticks.
// The engine reads `Date()` (or a passed `at:` parameter) to
// timestamp state transitions; durations are computed from
// timestamp deltas at render time so backgrounding, sleep, and UI
// refresh rate can't drift the totals.
@MainActor
final class FreeRunEngine {

    // MARK: - Phase

    enum Phase: Equatable {
        case notStarted
        case inProgress(startedAt: Date)
        case paused(startedAt: Date, pausedAt: Date)
        case finished(startedAt: Date, endedAt: Date)
    }

    // MARK: - State

    private(set) var phase: Phase = .notStarted

    // Cumulative distance in metres. Monotonic — never decreases.
    // Updated by the consumer via `recordDistance(at:metres:)`.
    private(set) var distanceMetres: Double = 0

    // Completed splits, in order. The active (in-progress) split
    // is computed on-the-fly from `splits.last?.endedAt → now`
    // and `splits.last?.cumulativeDistanceMetres → distanceMetres`
    // — there's no "partial split" entry until a boundary fires.
    private(set) var splits: [FreeRunSplit] = []

    // Frozen at start time so the engine knows when to capture
    // the next auto-split. Immutable for the run's lifetime —
    // changing units mid-run would corrupt the existing split
    // boundaries.
    let splitUnit: FreeRunSplitUnit

    // Convenience aggregations that callers (view models, tests)
    // commonly want.

    var isRunning: Bool {
        if case .inProgress = phase { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    // MARK: - Init

    init(splitUnit: FreeRunSplitUnit) {
        self.splitUnit = splitUnit
    }

    // MARK: - Lifecycle

    // Begin the run. Idempotent against double-taps — calling
    // start() twice in a row from .inProgress is a no-op rather
    // than a state-transition crash.
    func start(at date: Date = Date()) {
        guard case .notStarted = phase else { return }
        phase = .inProgress(startedAt: date)
    }

    // Pause the timer. Distance accumulation should also pause
    // at the call site (the Watch's HKWorkoutSession.pause /
    // CMPedometer.stopUpdates) — the engine itself just records
    // the pause moment so resume math works.
    //
    // Stores the pause timestamp so `resume(at:)` can shift the
    // start anchor forward by the pause duration, keeping
    // elapsed-time math consistent without tracking pauses in
    // an array.
    func pause(at date: Date = Date()) {
        guard case .inProgress(let startedAt) = phase else { return }
        phase = .paused(startedAt: startedAt, pausedAt: date)
    }

    // Resume from pause. Shifts the startedAt forward by the
    // pause duration so `now − startedAt` continues to give the
    // correct ACTIVE elapsed time (excluding the pause window).
    // Same trick RaceEngine uses for race pauses.
    func resume(at date: Date = Date()) {
        guard case .paused(let startedAt, let pausedAt) = phase else { return }
        let pauseDuration = date.timeIntervalSince(pausedAt)
        let shiftedStart = startedAt.addingTimeInterval(pauseDuration)
        phase = .inProgress(startedAt: shiftedStart)
    }

    // End the run. Transitions to .finished and freezes everything.
    // Subsequent recordDistance / pause / resume calls are no-ops.
    //
    // Does NOT auto-capture a final split — many runs end mid-way
    // through a split (e.g. "I'm done, let's call this 3.4 mi").
    // The summary view handles displaying the partial trailing
    // split as "X.X mi · pace · HR" using the cumulative distance
    // minus the last full split's cumulative.
    func end(at date: Date = Date()) {
        switch phase {
        case .notStarted, .finished:
            return
        case .inProgress(let startedAt):
            phase = .finished(startedAt: startedAt, endedAt: date)
        case .paused(let startedAt, _):
            // Ending while paused — use the original start anchor;
            // the active elapsed time stops at `pausedAt` which
            // we'll have already captured into the engine's state
            // for the duration of the pause, so endedAt should
            // be the pause moment for clean math. Use `date` so
            // the caller (typically a UI tap) controls precision.
            phase = .finished(startedAt: startedAt, endedAt: date)
        }
    }

    // MARK: - Distance ingest

    // Update the cumulative distance from an external source. The
    // caller passes the source's view of total distance so far,
    // in metres — pedometer / HK live builder / GPS, doesn't
    // matter which. Monotonic-only: distance values that go
    // backwards (sensor jitter, source switch mid-run) are
    // ignored.
    //
    // Captures any auto-splits that the new distance crosses.
    // Multiple splits per call is possible if the source
    // delivered a batch (e.g. Watch reconnects after a disconnect
    // and floods 0.6 mi of accumulated distance into a single
    // update).
    //
    // No-op when not in progress — pause/finished states freeze
    // the distance value rather than letting late samples leak
    // into the totals.
    func recordDistance(at date: Date, metres: Double) {
        guard isRunning else { return }
        guard metres > distanceMetres else { return }

        let unitSize = splitUnit.metresPerUnit

        // Compute how many complete units fit before the new
        // value vs the old one. The difference is how many
        // splits should fire on this call.
        let priorWholeUnits = floor(distanceMetres / unitSize)
        let newWholeUnits = floor(metres / unitSize)
        let splitsToFire = Int(newWholeUnits - priorWholeUnits)

        // Update distance FIRST so the split-capture loop reads
        // the latest value. (If we updated after, the splits
        // would carry the prior cumulative as their "end".)
        let oldDistance = distanceMetres
        distanceMetres = metres

        guard splitsToFire > 0 else { return }

        // Linear-interpolate the timestamps for each split
        // boundary that fell inside this batch. The source
        // doesn't tell us when EXACTLY each boundary was crossed
        // — it just gives us a snapshot of cumulative distance
        // at one moment. We approximate by assuming constant
        // pace across the batch, which is fine for the common
        // case (consecutive 1Hz updates) and acceptable for the
        // rare case (a 0.6 mi catch-up burst — the splits land
        // with timestamps a few seconds apart instead of being
        // exact, but the durations integrate correctly because
        // every successive split's startedAt is the prior
        // split's endedAt).
        guard case .inProgress(let runStartedAt) = phase else { return }
        let lastSplitEnd = splits.last?.endedAt ?? runStartedAt
        let lastSplitDistance = splits.last?.cumulativeDistanceMetres ?? 0

        let totalElapsedThisBatch = date.timeIntervalSince(lastSplitEnd)
        let totalDistanceThisBatch = metres - oldDistance

        // Defensive — totalDistanceThisBatch can be 0 if the
        // monotonic guard above was bypassed somehow; we already
        // returned in that case but Swift can't know.
        guard totalDistanceThisBatch > 0 else { return }

        for i in 1...splitsToFire {
            let splitBoundary = (priorWholeUnits + Double(i)) * unitSize
            let distanceFromBatchStart = splitBoundary - lastSplitDistance
            let interpolatedFraction = (splitBoundary - oldDistance) / totalDistanceThisBatch
            let splitEndAt = lastSplitEnd
                .addingTimeInterval(totalElapsedThisBatch * interpolatedFraction)
            let splitStartAt = splits.last?.endedAt ?? runStartedAt
            let segmentDistance = distanceFromBatchStart - (splits.last.map {
                $0.cumulativeDistanceMetres - lastSplitDistance
            } ?? 0)

            let split = FreeRunSplit(
                index: splits.count,
                startedAt: splitStartAt,
                endedAt: splitEndAt,
                cumulativeDistanceMetres: splitBoundary,
                segmentDistanceMetres: splitBoundary - (splits.last?.cumulativeDistanceMetres ?? 0),
                heartRateAvgBPM: nil,
                heartRateMaxBPM: nil
            )
            _ = segmentDistance  // kept for clarity in the math; final value uses cumulative deltas
            splits.append(split)
        }
    }

    // MARK: - Post-finish enrichment

    // Patch the split at `index` with HR aggregates. Called by
    // FreeRunViewModel's post-finish rehydrate path after
    // HKLiveWorkoutBuilder.finishWorkout has flushed buffered
    // samples to HK and the per-split window queries return
    // real numbers.
    //
    // Same pattern as `RaceEngine.setSegmentStats(...)`. The
    // engine creates a fresh FreeRunSplit with the new HR fields
    // since the struct is immutable; SwiftData sees the new
    // splits array on the next persist round-trip.
    func setSplitHRStats(
        atIndex index: Int,
        avg: Double?,
        max: Double?
    ) {
        guard splits.indices.contains(index) else { return }
        let existing = splits[index]
        splits[index] = FreeRunSplit(
            index: existing.index,
            startedAt: existing.startedAt,
            endedAt: existing.endedAt,
            cumulativeDistanceMetres: existing.cumulativeDistanceMetres,
            segmentDistanceMetres: existing.segmentDistanceMetres,
            heartRateAvgBPM: avg,
            heartRateMaxBPM: max
        )
    }
}

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
    // isn't in progress.
    var currentStation: Station? {
        guard case .inProgress(_, _, let splits) = state else { return nil }
        return sequence[safe: splits.count]
    }

    // The station queued up after the current one — for "Up next: ..." UI.
    // `nil` on the final segment or when not in progress.
    var upcomingStation: Station? {
        guard case .inProgress(_, _, let splits) = state else { return nil }
        return sequence[safe: splits.count + 1]
    }

    // Completed splits so far (in race order).
    var splits: [Split] {
        switch state {
        case .notStarted:                    return []
        case .inProgress(_, _, let splits):  return splits
        case .finished(_, _, let splits):    return splits
        }
    }

    var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    // Total elapsed race time evaluated at `now`. Returns 0 before start.
    // Once finished, returns the frozen final time (independent of `now`).
    func elapsed(at now: Date) -> TimeInterval {
        switch state {
        case .notStarted:
            return 0
        case .inProgress(let startedAt, _, _):
            return now.timeIntervalSince(startedAt)
        case .finished(let startedAt, let endedAt, _):
            return endedAt.timeIntervalSince(startedAt)
        }
    }

    // Elapsed time for the *current* (unfinished) segment, evaluated at `now`.
    // Returns 0 if not in progress.
    func currentSegmentElapsed(at now: Date) -> TimeInterval {
        guard case .inProgress(_, let segmentStart, _) = state else { return 0 }
        return now.timeIntervalSince(segmentStart)
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
    mutating func advance(at now: Date) {
        guard case .inProgress(let startedAt, let segmentStart, var splits) = state else { return }

        let index = splits.count
        guard index < sequence.count else { return }

        let completed = Split(
            station: sequence[index],
            startedAt: segmentStart,
            endedAt: now
        )
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

    // Attach heart-rate statistics (avg + max over the segment window)
    // to the split at the given index. Used from RaceViewModel after an
    // async HealthKit HKStatisticsQuery returns — the advance itself
    // stays synchronous (the split is appended without HR, then patched
    // here when HealthKit responds). No-op if the index is out of range
    // or the engine isn't in a state with splits.
    //
    // Safe to call from either `.inProgress` or `.finished` — stats can
    // be attached to the final split of a freshly-finished race exactly
    // as to an intermediate split.
    mutating func setHeartRateStats(
        avg: Double?,
        max: Double?,
        atSplitIndex index: Int
    ) {
        switch state {
        case .notStarted:
            return
        case .inProgress(let startedAt, let segmentStart, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = splits[index].withHeartRateStats(avg: avg, max: max)
            state = .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segmentStart,
                splits: splits
            )
        case .finished(let startedAt, let endedAt, var splits):
            guard splits.indices.contains(index) else { return }
            splits[index] = splits[index].withHeartRateStats(avg: avg, max: max)
            state = .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
    }
}

// MARK: - Helpers

// Out-of-bounds-safe subscript. `currentStation` / `upcomingStation` rely on it
// so we don't have to sprinkle `indices.contains(...)` guards throughout.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

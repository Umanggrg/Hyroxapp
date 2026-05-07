import Foundation

// One auto-fired split inside a Free Run. Captured by `FreeRunEngine`
// every time the cumulative distance crosses a split boundary —
// every 1 mile or 1 km depending on the parent FreeRun's `splitUnit`.
//
// Companion to the HYROX `Split` (see Split.swift). They share the
// "captures HR + duration over a window" shape but differ in the
// boundary mechanism: HYROX splits are station-bounded (athlete
// taps "Next Station"), free-run splits are distance-bounded
// (athlete crosses a kilometre / mile marker).
//
// Stored as a `Codable` value type — SwiftData encodes the array on
// `FreeRun.splits` transparently, same pattern as `Race.splits`.
// Promoting to `@Model` would unlock per-split queries (e.g.
// "fastest mile ever" leaderboards) — defer until v2 when the
// social layer needs them.
//
// Backward-compat note: every field after the originals is optional
// with a Codable-friendly default so older persisted runs decode
// cleanly when the schema gains new fields. Same conservative
// migration discipline as `Split`.
struct FreeRunSplit: Codable, Equatable, Hashable, Identifiable, Sendable {

    // 0-based ordinal within the run. The FIRST completed split is
    // index 0, the second is index 1, etc. The active in-progress
    // split (the segment after the last completed one) does NOT
    // appear in the persisted array — display layers compute it
    // live from `now − last split's endedAt`.
    let index: Int

    // Window the split covers. `endedAt − startedAt` gives the
    // split's duration; `endedAt` is the moment the cumulative
    // distance crossed the next split boundary.
    let startedAt: Date
    let endedAt: Date

    // Cumulative distance at the moment this split closed, in
    // metres. The next split's `cumulativeDistanceMetres` minus
    // this one's gives that next split's distance — should always
    // equal one full `splitUnit.metresPerUnit` (1609.344 for miles,
    // 1000 for km), within a small floor due to GPS sampling
    // jitter or pedometer batching.
    let cumulativeDistanceMetres: Double

    // The actual distance covered IN this split, also in metres.
    // For the first split this equals `cumulativeDistanceMetres`;
    // for later splits it's `cumulativeDistanceMetres − previous
    // split's cumulativeDistanceMetres`. Stored explicitly rather
    // than recomputed at the call site so a corrupted upstream
    // delta calculation can't propagate through display.
    let segmentDistanceMetres: Double

    // HR aggregates over the split's window. Same nil-when-no-data
    // semantic as `Split.heartRateAvgBPM` — UI hides the line
    // gracefully when both are nil. Captured post-finish via the
    // same HKStatisticsQuery rehydration path that fixed the
    // race-level "physiology missing on most stations" bug.
    let heartRateAvgBPM: Double?
    let heartRateMaxBPM: Double?

    // Custom Identifiable conformance — `index` is unique within a
    // run, which is the only context FreeRunSplit ever appears in.
    var id: Int { index }

    // MARK: - Derived

    // Split duration in seconds. Used everywhere — the live HUD
    // (segment timer for the in-progress split is computed
    // separately), the summary list rows, the export.
    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    // Pace per unit (seconds per mile / second per km — caller
    // decides). `segmentDistanceMetres == 0` is defended against
    // even though it shouldn't happen (split always crosses a
    // full unit before being captured); a div-by-zero crash from
    // a sensor glitch would be a really bad UX.
    func paceSecondsPerUnit(metresPerUnit: Double) -> TimeInterval? {
        guard segmentDistanceMetres > 0 else { return nil }
        return duration / (segmentDistanceMetres / metresPerUnit)
    }
}

import Foundation

// Formatting + per-race stat helpers, shared across Race, History, and
// Profile. Consolidated here so every surface uses the same numbers and the
// same MM:SS / H:MM:SS rendering — future retuning (millisecond display,
// pace per km, etc.) is a single-file change.
//
// A subset of this file is also shared with the watchOS target (via
// target membership), because the watch's placeholder race screen needs
// `RaceStats.format()` to render its timer. But the watch target does NOT
// include `Race.swift` — Race is a SwiftData `@Model` with persistence
// semantics the watch doesn't need. To keep one file for both platforms,
// everything that touches `Race` is guarded `#if !os(watchOS)`; only
// `format()` is unconditionally compiled and therefore visible on watch.
enum RaceStats {

    // MARK: - Per-race stats (phone only)

    #if !os(watchOS)

    static func totalTime(_ race: Race) -> String {
        format(race.totalDuration ?? 0)
    }

    // Fastest single 1km run in this race.
    static func bestRun(_ race: Race) -> String {
        let runs = race.splits.filter { $0.station.kind == .run }
        guard let best = runs.map(\.duration).min() else { return "—" }
        return format(best)
    }

    // Average of the 8 run splits.
    static func avgRun(_ race: Race) -> String {
        let runs = race.splits.filter { $0.station.kind == .run }
        guard !runs.isEmpty else { return "—" }
        let avg = runs.map(\.duration).reduce(0, +) / Double(runs.count)
        return format(avg)
    }

    // Time spent on the Wall Balls station — the final grind in a HYROX
    // race, often the most indicative single split for overall fitness.
    static func wallBalls(_ race: Race) -> String {
        guard let split = race.splits.first(where: { $0.station == .wallBalls }) else { return "—" }
        return format(split.duration)
    }

    // Total active calories burned across every segment of this race,
    // summed from HealthKit per-split values. Returns nil when no
    // split has any calorie data — typical for races run without a
    // Watch streaming or before the calorie-capture feature shipped.
    // Returns 0 only if every split was actually queried and reported
    // 0 (extremely unlikely outside of a stationary mistake-race).
    static func totalActiveCalories(_ race: Race) -> Double? {
        let values = race.splits.compactMap(\.activeCaloriesKcal)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    // MARK: - Cross-race aggregates (for Profile) — phone only

    // Fastest total race time across the provided races (nil if none).
    static func personalBest(_ races: [Race]) -> TimeInterval? {
        races.compactMap(\.totalDuration).min()
    }

    // Average total race time across the provided races.
    static func averageTotal(_ races: [Race]) -> TimeInterval? {
        let times = races.compactMap(\.totalDuration)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    // Sum of completed splits across all provided races.
    static func totalStationsCompleted(_ races: [Race]) -> Int {
        races.reduce(0) { $0 + $1.splits.count }
    }

    // Was this race a personal best (fastest total time) at the moment it
    // was completed? Matches the Strava "New PR" model — only races that
    // actually broke a record get the badge, not every current-best race.
    // The first completed race counts as a PB by default.
    static func wasPBWhenSet(_ race: Race, among all: [Race]) -> Bool {
        guard let thisTotal = race.totalDuration else { return false }
        let earlierBest = all
            .filter { $0.createdAt < race.createdAt && $0.isFinished }
            .compactMap(\.totalDuration)
            .min()
        guard let earlierBest else {
            return true
        }
        return thisTotal < earlierBest
    }

    // MARK: - Per-station PB helpers

    // Fastest previous duration for the given station across races that
    // came strictly before `race`. Returns nil when the athlete has
    // never completed that station in an earlier finished race — i.e.
    // "no prior data to compare against." Callers use this to decide
    // whether to show a delta (`Δ vs prior best`) or stay silent.
    //
    // Shape mirrors `wasPBWhenSet` so both PB paths (whole-race and
    // per-station) read the same at the call site.
    static func bestDuration(
        for station: Station,
        before race: Race,
        among all: [Race]
    ) -> TimeInterval? {
        all
            .filter { $0.createdAt < race.createdAt && $0.isFinished }
            .flatMap(\.splits)
            .filter { $0.station == station }
            .map(\.duration)
            .min()
    }

    // Was this specific split — the one at index `station` inside this
    // specific race — the fastest time the athlete had logged for that
    // station at the time the race was completed? Only races that
    // actually broke the prior record get `true`; first-time completions
    // also return `true` (no prior to beat = implicit PB).
    static func wasPBSplit(
        _ split: Split,
        in race: Race,
        among all: [Race]
    ) -> Bool {
        guard let prior = bestDuration(
            for: split.station,
            before: race,
            among: all
        ) else {
            return true
        }
        return split.duration < prior
    }

    // Delta vs the athlete's prior best for this station, expressed as
    // a signed TimeInterval:
    //   - negative → this split was faster than prior best (good)
    //   - positive → this split was slower than prior best (bad)
    //   - nil      → no prior best, no delta to show
    // Callers format with `format(_:)` plus a sign decoration; keeping
    // the sign as part of the TimeInterval (not the string) makes the
    // UI layer do the coloring decision.
    static func deltaFromPriorBest(
        for split: Split,
        in race: Race,
        among all: [Race]
    ) -> TimeInterval? {
        guard let prior = bestDuration(
            for: split.station,
            before: race,
            among: all
        ) else {
            return nil
        }
        return split.duration - prior
    }

    // All-time fastest split for a given canonical station type across
    // every finished race the athlete has logged. Used by the Personal
    // Bests panel on Profile — one row per station type, all-time best
    // duration. Returns nil if the athlete has never completed that
    // station in any finished race.
    //
    // Run handling: the eight run cases (run1...run8) all share the
    // same `Station.Kind.run` — for the canonical "1km Run" PB we
    // aggregate across all of them, since the athlete cares about
    // their fastest 1km regardless of which slot it was in. Other
    // stations match their exact case (sledPush, wallBalls, etc.).
    static func allTimeBest(
        for stationType: Station,
        among all: [Race]
    ) -> Split? {
        let candidates: [Split] = all
            .filter { $0.isFinished }
            .flatMap(\.splits)
            .filter { split in
                stationType.kind == .run
                    ? split.station.kind == .run
                    : split.station == stationType
            }

        return candidates.min(by: { $0.duration < $1.duration })
    }

    #endif  // !os(watchOS)

    // MARK: - Pacing (mid-race "ahead / behind / on pace")

    // Naive expected elapsed time at the START of the segment after
    // `segmentsCompleted`. Splits the target finish time evenly across
    // every segment in the race regardless of station type.
    //
    // Why naive: a properly-weighted version (runs get more time
    // budget than sled push, etc.) needs either historical splits
    // from the athlete's own past races or community-aggregated
    // benchmarks — both gated on backend / data CLAUDE.md §13.4.
    // For now the even-split gives a directional signal that's
    // useful enough during a workout: "your overall pace is X:XX
    // ahead/behind your target".
    //
    // Returns 0 for the very start of the race (0 segments completed
    // → 0 expected time elapsed), and `target` at the finish line
    // (all segments done → target time should have fully elapsed).
    static func naiveExpectedElapsed(
        segmentsCompleted: Int,
        totalSegments: Int,
        target: TimeInterval
    ) -> TimeInterval {
        guard totalSegments > 0 else { return 0 }
        let fraction = Double(segmentsCompleted) / Double(totalSegments)
        return target * fraction
    }

    // Signed pace delta. Negative → athlete is ahead of pace (faster
    // than expected), positive → behind pace (slower than expected).
    // The UI layer chooses success/warning coloring from the sign.
    static func paceDelta(
        actualElapsed: TimeInterval,
        expectedElapsed: TimeInterval
    ) -> TimeInterval {
        actualElapsed - expectedElapsed
    }

    // MARK: - Formatting (shared with watchOS)

    // Render a TimeInterval as MM:SS, or H:MM:SS when it crosses an hour.
    // Rounds down to whole seconds — sub-second precision is distracting on
    // the big timer and only matters in the split table where raw splits
    // are already shown alongside. Pure arithmetic — no platform-specific
    // dependencies — so it compiles unchanged on iOS and watchOS.
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

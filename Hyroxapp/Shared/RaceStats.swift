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

    // Total Roxzone time across every transition this race captured.
    // Sum of all `roxzoneSeconds` on the race's splits. Returns nil
    // when no split has roxzone data — single-tap-mode races, or
    // races finished before the feature shipped, have nil here.
    //
    // The HYROX-specific transition-discipline metric. "How much of
    // your race was spent in transition vs work?" — lower is better;
    // elite athletes target sub-10s avg per transition.
    static func totalRoxzoneTime(_ race: Race) -> TimeInterval? {
        let values = race.splits.compactMap(\.roxzoneSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    // Average Roxzone time per logged transition. Returns nil when
    // no roxzone data captured. Useful as the headline number on
    // race summary / detail because the AVG is what athletes
    // actually optimize for ("get my avg under 10s").
    static func avgRoxzoneTime(_ race: Race) -> TimeInterval? {
        let values = race.splits.compactMap(\.roxzoneSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // Cross-race avg roxzone — for the Profile-level "your
    // transition discipline trend" surface. Walks every finished
    // race and pools all roxzone-bearing splits, then divides.
    // Single global average rather than per-race-then-averaged so
    // races with more transitions get appropriately more weight.
    static func crossRaceAvgRoxzone(among races: [Race]) -> TimeInterval? {
        let values = races
            .filter(\.isFinished)
            .flatMap(\.splits)
            .compactMap(\.roxzoneSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // Projected race-day time for this attempt at division-canonical
    // weight. Linear extrapolation by weight ratio — if you did
    // 100kg in 4:00 and the race weight is 152kg, the projection is
    // 4:00 × (152/100) = 6:05.
    //
    // Returns nil when:
    //   - The split has no logged weight (we have nothing to scale)
    //   - The station has no division race weight (runs, ergs)
    //   - The current weight equals the race weight (already at race
    //     weight, no projection needed; show the actual time instead)
    //   - The current weight is HIGHER than race weight (the athlete
    //     is over-weighting on purpose for training overload — a
    //     projection downward is still computable but reads weird,
    //     so we hide it as opinionated UX)
    //
    // Linear scaling is a simplification; in reality sled-push time
    // typically scales sub-linearly with weight (a strong athlete's
    // pace doesn't double when the weight doubles). We use linear as
    // a conservative-pessimistic estimate — the "this is the worst
    // case" projection. Athletes can read the projected time as a
    // floor, then actual race-day will likely be better.
    static func projectedRaceTime(
        forSplit split: Split,
        division: Division
    ) -> TimeInterval? {
        guard let logged = split.weightKg, logged > 0 else { return nil }
        guard let raceWeight = division.raceWeight(for: split.station) else {
            return nil
        }
        // Within ±0.5kg → already at race weight.
        guard abs(logged - raceWeight) >= 0.5 else { return nil }
        // Athlete is over-weighting; don't project downward.
        guard logged < raceWeight else { return nil }

        let ratio = raceWeight / logged
        return split.duration * ratio
    }

    // MARK: - Effort score (HR-time integration)
    //
    // A single interpretable number for "how hard was this race."
    // Formula per split with avg HR data:
    //
    //     segmentScore = (avgHR / maxHR) × (duration / 60)
    //
    // Then sum across splits. Reads as "intensity-weighted minutes"
    // — a 90-minute race at 80% avg HR scores ~72; a 60-minute race
    // at 95% scores ~57. Higher is harder.
    //
    // Returns nil when:
    //   • the race has no splits with HR data, OR
    //   • maxHR <= 0 (defensive — caller should pass profile.maxHeartRate)
    //
    // Splits without HR are silently skipped — counting them with
    // zero would underweight a race where HR fell out mid-way (e.g.
    // Watch slipped). Better to score what we measured.
    static func effortScore(for race: Race, maxHR: Int) -> Double? {
        guard maxHR > 0 else { return nil }
        let maxHRDouble = Double(maxHR)

        let scored = race.splits.compactMap { split -> Double? in
            guard let avg = split.heartRateAvgBPM, avg > 0 else { return nil }
            let intensity = avg / maxHRDouble
            let minutes = split.duration / 60
            return intensity * minutes
        }

        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +)
    }

    // Cross-race average effort score — useful for Profile-level
    // "your typical effort level" callouts. Pass finished races
    // only; in-progress races get a partial score that would skew
    // the average.
    static func averageEffortScore(across races: [Race], maxHR: Int) -> Double? {
        let scores = races
            .filter(\.isFinished)
            .compactMap { effortScore(for: $0, maxHR: maxHR) }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
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

    // MARK: - HYROX Performance Score (per-pillar rollups)

    // "Theoretical best HYROX" total time for a given pillar — sum
    // of the athlete's all-time best split for every station in
    // that pillar. For .engine, multiplies the best 1km run time
    // by 8 to represent all eight run slots in an actual race.
    //
    // Returns nil when the athlete has no completion data for ANY
    // station in the pillar. Returns a partial sum (with the rest
    // of the stations using nil → skipped) when some are covered
    // and others aren't. Callers can pair with `pillarStationsCovered`
    // to know how complete the score is.
    static func pillarTheoreticalBest(
        _ pillar: HyroxPillar,
        among races: [Race]
    ) -> TimeInterval? {
        let bests = pillar.stations.compactMap { station -> TimeInterval? in
            guard let split = allTimeBest(for: station, among: races) else {
                return nil
            }
            // For the engine pillar, the canonical .run1 entry
            // represents one 1km run — multiply by 8 to capture
            // all the runs in a HYROX. Non-run stations score
            // their single split.
            return station.kind == .run
                ? split.duration * 8
                : split.duration
        }
        guard !bests.isEmpty else { return nil }
        return bests.reduce(0, +)
    }

    // How many of the pillar's stations have ever been completed
    // by the athlete in a finished race. Used by the Performance
    // Score view to render "X of Y stations" subtitle so partial
    // scores don't look like reliable totals.
    static func pillarStationsCovered(
        _ pillar: HyroxPillar,
        among races: [Race]
    ) -> (covered: Int, total: Int) {
        let total = pillar.stations.count
        let covered = pillar.stations.filter { station in
            allTimeBest(for: station, among: races) != nil
        }.count
        return (covered, total)
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

    // Per-station trend data for `StationDetailView`'s history chart.
    // Walks every finished race, picks each split that matches the
    // requested station type (collapsing all run cases together the
    // same way `allTimeBest` does), and returns one (date, duration)
    // tuple per attempt sorted oldest → newest.
    //
    // Race-level grouping note: a single full HYROX race has 8 runs.
    // For a run-station chart we'd return all 8 attempts per race.
    // For a workout station (Sled Push, Wall Balls, etc.) we get
    // exactly one per race. Both are useful — the chart just renders
    // every dot in chronological order.
    //
    // Date used for the x-axis is the race's `endedAt` so the dot
    // lands at "when this race finished," which is what the athlete
    // remembers ("the race I did last Tuesday"). Falls back to
    // `startedAt` defensively.
    // Result type for `stationTrendDirection`. Carries enough info
    // for the Performance Overload callout to render a sentence
    // ("Sled Pull is trending 12% faster"): the direction, the
    // absolute % delta, and the station type (so the caller can map
    // back to a display name without holding extra state).
    enum TrendDirection: Sendable, Equatable {
        case improving(percentChange: Double)  // negative duration delta = faster
        case declining(percentChange: Double)  // positive duration delta = slower
        case plateau                            // change within the noise threshold

        var isMeaningful: Bool {
            switch self {
            case .improving, .declining: return true
            case .plateau:               return false
            }
        }
    }

    // Detect a meaningful trend in an athlete's last N attempts at a
    // station type. Splits the window in half (early vs late), takes
    // the average duration of each half, and returns the percent
    // change. Anything inside ±3% counts as plateau — the noise of
    // any single race outweighs that, so calling it a "trend" would
    // be misleading.
    //
    // Why split-and-compare over linear regression: with windows of
    // 4–8 attempts (typical for an athlete with 2–4 races' worth of
    // data per workout-station type), simple averages are more
    // robust to a single outlier race. A single bad sled push
    // shouldn't flip the trend direction; halves-of-the-window
    // averages it out.
    //
    // Returns `.plateau` when there's not enough history (< 4
    // attempts) — too few data points to call a trend honestly.
    static func stationTrendDirection(
        for stationType: Station,
        among all: [Race],
        windowSize: Int = 6,
        plateauThresholdPercent: Double = 3.0
    ) -> TrendDirection {
        let trend = stationTrend(for: stationType, among: all)
        // Take the most recent `windowSize` attempts. If we don't
        // have at least 4, bail — the result wouldn't be meaningful.
        let recent = Array(trend.suffix(windowSize))
        guard recent.count >= 4 else { return .plateau }

        // Split the window in half; average each half. Faster = lower
        // duration, so a percentage decrease (late < early) means
        // improvement.
        let mid = recent.count / 2
        let earlyAvg = average(recent[0..<mid].map(\.duration))
        let lateAvg = average(recent[mid..<recent.count].map(\.duration))
        guard earlyAvg > 0 else { return .plateau }

        let percentChange = ((lateAvg - earlyAvg) / earlyAvg) * 100.0

        if abs(percentChange) < plateauThresholdPercent {
            return .plateau
        }
        return percentChange < 0
            ? .improving(percentChange: abs(percentChange))
            : .declining(percentChange: abs(percentChange))
    }

    // Tiny helper; pulled out so `stationTrendDirection` reads
    // cleanly. Returns 0 for an empty slice rather than crashing.
    private static func average(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    // Per-run breakdown for compromised-running analysis. Each
    // entry pairs a 1km run split with the workout station that
    // PRECEDED it (the station that just compromised the
    // athlete's engine), plus the run's slowdown vs the baseline
    // (Run 1).
    //
    // The HYROX-specific insight: Run 1 is fresh legs, every
    // subsequent run is degraded by the station before it. The
    // biggest slowdown identifies which station is hurting your
    // engine recovery most — a metric no other fitness app
    // surfaces. "Sled Pull cost you 22% run pace" is actionable
    // training intelligence.
    //
    // Run 1 has no preceding station (it's the first segment) so
    // its `precedingStation` is nil and `percentSlower` is 0
    // (baseline against itself). Custom workouts that don't
    // start with a run, or have non-alternating sequences, will
    // produce empty/short results — gracefully handled by the
    // chart's data-availability gate.
    struct CompromisedRunData: Sendable, Equatable {
        let runIndex: Int             // 1-based: Run 1, Run 2, ...
        let split: Split              // the run split itself
        let precedingStation: Station?  // workout that just preceded; nil for Run 1
        let percentSlower: Double     // vs Run 1 baseline; 0 for Run 1, positive for slower
    }

    // Build the compromised-running breakdown for a race. Walks
    // the race's splits in order; for each run-kind split, pairs
    // it with the workout-kind split immediately before. Returns
    // empty when no run splits exist (custom workout with no
    // runs).
    static func compromisedRunData(for race: Race) -> [CompromisedRunData] {
        let splits = race.splits

        // Walk splits in order, accumulating runs with their
        // preceding workout. The race always alternates run/
        // workout/run/workout in the canonical sequence; for
        // custom workouts the pattern may differ, but we just
        // pair "most recent workout before this run" which
        // generalizes correctly.
        var lastWorkout: Station?
        var runs: [(Int, Split, Station?)] = []
        for split in splits {
            switch split.station.kind {
            case .workout:
                lastWorkout = split.station
            case .run:
                runs.append((runs.count + 1, split, lastWorkout))
            }
        }

        guard let baseline = runs.first?.1.duration, baseline > 0 else {
            return []
        }

        return runs.map { runIndex, split, preceding in
            let percentSlower = ((split.duration - baseline) / baseline) * 100.0
            return CompromisedRunData(
                runIndex: runIndex,
                split: split,
                precedingStation: preceding,
                percentSlower: percentSlower
            )
        }
    }

    // Identifies the run with the largest slowdown vs baseline,
    // along with the station that preceded it. Returns nil when
    // no runs slowed (only Run 1 in the data) or when there are
    // fewer than 2 runs. Used by the chart callout and the
    // narrative insight.
    static func biggestCompromisedRun(for race: Race) -> CompromisedRunData? {
        let data = compromisedRunData(for: race)
        // Skip the baseline (Run 1, percentSlower = 0) and find
        // the slowest. If multiple tie, the LATER run wins
        // (more typical "fade" pattern; latest run is more
        // meaningful for narrative purposes).
        return data
            .dropFirst()
            .max { $0.percentSlower < $1.percentSlower }
    }

    // Cross-race aggregation result: for each workout station that
    // precedes a run, the average % slowdown that station causes
    // on the following run, averaged across all races where the
    // station appeared. The KILLER insight no other app surfaces:
    // "across your last 5 races, Sandbag Lunges costs an avg 18%
    // run pace — that's your weakest engine recovery."
    //
    // Keyed by station (the workout that precedes the affected
    // run). Sample count is exposed so the UI can dim/disclose
    // entries with low confidence (1-2 race sample is noisy).
    struct StationImpact: Sendable, Equatable, Hashable {
        let station: Station          // the workout station that compromises the next run
        let avgPercentSlower: Double  // unsigned mean of percent-slower across races
        let sampleCount: Int          // number of races contributing to this average
    }

    // Compute per-station engine-impact averages across the
    // athlete's finished races. For every workout station that
    // preceded a run in any finished race, average that run's
    // percent-slowdown vs that race's Run 1 baseline.
    //
    // Returns a list sorted descending by avgPercentSlower —
    // biggest impact first, which matches what the visualization
    // wants to show prominently.
    //
    // Stations that never appeared as a preceding workout in any
    // race (custom workouts without that station, fresh history)
    // are simply absent from the result. The view layer renders
    // the present subset rather than fixed-list-with-zeros so
    // the data shape adapts to varied training.
    //
    // Wall Balls is intentionally absent — it's the final station,
    // no run follows it in the canonical sequence.
    static func crossRaceCompromisedAnalysis(
        among races: [Race]
    ) -> [StationImpact] {
        let finished = races.filter { $0.isFinished }

        // Build (station -> [percentSlower]) by walking each race's
        // compromised-run data and bucketing each non-baseline run
        // by its preceding station.
        var bucketed: [Station: [Double]] = [:]
        for race in finished {
            let data = compromisedRunData(for: race)
            for entry in data.dropFirst() {  // skip Run 1 baseline (percentSlower = 0)
                guard let station = entry.precedingStation else { continue }
                bucketed[station, default: []].append(entry.percentSlower)
            }
        }

        return bucketed
            .map { station, values in
                let avg = values.reduce(0, +) / Double(values.count)
                return StationImpact(
                    station: station,
                    avgPercentSlower: avg,
                    sampleCount: values.count
                )
            }
            .sorted { $0.avgPercentSlower > $1.avgPercentSlower }
    }

    static func stationTrend(
        for stationType: Station,
        among all: [Race]
    ) -> [(date: Date, duration: TimeInterval, split: Split)] {
        all
            .filter { $0.isFinished }
            .flatMap { race -> [(Date, TimeInterval, Split)] in
                let raceDate = race.endedAt ?? race.startedAt
                return race.splits
                    .filter { split in
                        stationType.kind == .run
                            ? split.station.kind == .run
                            : split.station == stationType
                    }
                    .map { (raceDate, $0.duration, $0) }
            }
            .sorted { $0.0 < $1.0 }
            .map { (date: $0.0, duration: $0.1, split: $0.2) }
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

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

    // Race-level rollup of the race-day weight projection. Sums:
    //   • For each split with a sub-race-weight projection (returned
    //     by `projectedRaceTime`): the projected duration.
    //   • For every other split: the actual logged duration.
    //
    // The result is "what your race would have been at official
    // HYROX weight, holding everything else equal." Single coaching
    // number, more honest than the per-station projection because
    // it shows the cumulative cost of training under-weight.
    //
    // Returns nil when no splits had a meaningful projection — in
    // that case the actual `totalDuration` IS the race-day projection
    // (every station was already at race weight) and surfacing a
    // duplicate would be noise.
    //
    // Also returns nil when the race isn't finished — projections
    // require all splits to be complete.
    static func raceDayProjectedTotal(
        for race: Race,
        division: Division
    ) -> TimeInterval? {
        guard race.isFinished else { return nil }

        // Track whether at least one station had a meaningful
        // projection — otherwise return nil and let the actual
        // total stand on its own.
        var anyProjected = false
        var total: TimeInterval = 0

        for split in race.splits {
            if let projected = projectedRaceTime(forSplit: split, division: division) {
                total += projected
                anyProjected = true
            } else {
                total += split.duration
            }
        }

        return anyProjected ? total : nil
    }

    // Coupled helper: how many splits in the race had a
    // meaningful sub-race-weight projection. Used by the UI to
    // render a confidence subtitle ("based on 3 stations") so the
    // athlete knows the projection isn't conjured from thin air.
    static func raceDayProjectionStationCount(
        for race: Race,
        division: Division
    ) -> Int {
        race.splits
            .compactMap { projectedRaceTime(forSplit: $0, division: division) }
            .count
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

    // MARK: - Recovery demand

    // Coarse-bucket categorization of how long the athlete should
    // expect to need before another intense session. Different
    // question from effort: effort says "how hard was this race,"
    // recovery says "when can you train hard again."
    //
    // Ranges are calibrated to how Whoop, ACSM, and Banister TRIMP
    // models map training load to recovery. We don't promise a
    // precision-engineered estimate — just an honest coaching
    // bucket. The athlete uses it to plan: "Hard session yesterday,
    // easy run today, save the next simulation for 2 days out."
    //
    // Returns nil when the race has no HR data — without effort
    // information we can't say anything useful about recovery
    // demand. Better silence than a fabricated number.
    enum RecoveryDemand: String, Sendable, CaseIterable, Codable {
        case light       // < 20 effective load — recovery day or short workout
        case moderate    // 20–35 — easy session next is fine
        case hard        // 35–55 — full rest day, then easy
        case veryHard    // > 55 — 2 days easy minimum

        var displayName: String {
            switch self {
            case .light:    return "Light"
            case .moderate: return "Moderate"
            case .hard:     return "Hard"
            case .veryHard: return "Very Hard"
            }
        }

        // Typical recovery time range. Lower bound is "minimum, if
        // you sleep well," upper bound is "more honest range."
        // Phrased loosely so we're not pretending we can predict
        // recovery to the hour.
        var typicalRecovery: String {
            switch self {
            case .light:    return "12–18 hours"
            case .moderate: return "18–30 hours"
            case .hard:     return "30–48 hours"
            case .veryHard: return "48–72 hours"
            }
        }

        // Coaching guidance — one-liner the athlete can use as a
        // training-plan input. Tone is "informed friend" not
        // "diagnostic engine" — language softens with each tier.
        var guidance: String {
            switch self {
            case .light:
                return "Easy session tomorrow is fine."
            case .moderate:
                return "Tomorrow stays light. Save intensity for the day after."
            case .hard:
                return "Take tomorrow easy. Save your next hard session for 2 days out."
            case .veryHard:
                return "Real recovery day tomorrow. Don't stack another hard session for 2-3 days."
            }
        }

        // SF Symbol for the rendering layer. Same icon language as
        // EffortCategory: leaf for light, flame intensity for higher
        // tiers. View layer doesn't pick its own icon — the bucket
        // owns its visual identity.
        var symbol: String {
            switch self {
            case .light:    return "leaf.fill"
            case .moderate: return "figure.walk.motion"
            case .hard:     return "flame.fill"
            case .veryHard: return "bed.double.fill"
            }
        }
    }

    // Compute the recovery demand for a finished race. Combines:
    //   • effort score (intensity-weighted minutes) — the base load
    //   • bonus weight on Z5 minutes (anaerobic/VO2max work creates
    //     disproportionate muscle damage and CNS fatigue per minute,
    //     so a 5-minute Z5 push above lactate threshold contributes
    //     more recovery demand than 5 minutes at moderate)
    //
    // The combined "load" number is then bucketed. Same units as
    // effort score (minutes of weighted intensity) so the bucket
    // boundaries map intuitively — a 90-minute HYROX at 80% avg HR
    // with some Z5 lands solidly in "Hard," matching the gut feel.
    //
    // Returns nil when the race lacks HR data; nothing useful to
    // say without it.
    static func recoveryDemand(for race: Race, maxHR: Int) -> RecoveryDemand? {
        guard let baseEffort = effortScore(for: race, maxHR: maxHR) else {
            return nil
        }

        // Z5 minutes — anaerobic work weights heavier in recovery
        // because muscle damage scales non-linearly with intensity.
        // Whoop, Polar, and Garmin all apply a similar non-linear
        // weighting in their TRIMP-style models.
        let maxHRDouble = Double(maxHR)
        let z5MinutesByDuration = race.splits.compactMap { split -> Double? in
            guard let avg = split.heartRateAvgBPM, avg > 0 else { return nil }
            // Use 0.90 maxHR as the Z5 threshold — same boundary
            // HRZone uses (0.90 = lactate threshold / VO2 max
            // floor). Splits AT or above that threshold contribute
            // their full duration to the Z5 minute count.
            guard avg / maxHRDouble >= 0.90 else { return nil }
            return split.duration / 60
        }
        let z5Minutes = z5MinutesByDuration.reduce(0, +)

        // Combined load: base effort + 1.5× Z5 minutes. The 1.5
        // multiplier is a calibrated guess — feels right when
        // backtested against a typical 90-min HYROX with 10ish
        // minutes of wall-balls / final-station Z5 push (lands
        // in Hard, occasionally Very Hard). Adjustable upward if
        // dogfood reveals it underestimates.
        let combinedLoad = baseEffort + (z5Minutes * 1.5)

        switch combinedLoad {
        case ..<20:  return .light
        case ..<35:  return .moderate
        case ..<55:  return .hard
        default:     return .veryHard
        }
    }

    // MARK: - Readiness

    // Real-time training readiness signal — answers "should I push
    // hard today, or take it easy?" by combining the most recent
    // race's recovery demand with how many hours have elapsed.
    //
    // Three states:
    //   • fresh — fully recovered (or no recent race) — push hard
    //   • partial — mid-recovery, easy session OK
    //   • recovering — recent hard session, recovery day
    //
    // Returns nil when there's no race history or the most recent
    // race lacks HR data — without that we have nothing to base
    // a readiness signal on, and a fabricated "Fresh" would mislead.
    enum ReadinessState: String, Sendable, CaseIterable, Codable {
        case fresh
        case partial
        case recovering

        var displayName: String {
            switch self {
            case .fresh:      return "Fresh"
            case .partial:    return "Partially Recovered"
            case .recovering: return "Recovering"
            }
        }

        // Guidance copy — same informed-friend tone as
        // RecoveryDemand. Tells the athlete what kind of session
        // makes sense today without being prescriptive.
        var guidance: String {
            switch self {
            case .fresh:
                return "Body's ready. Good day for an intense session."
            case .partial:
                return "Mostly recovered. Easy or moderate session is the call."
            case .recovering:
                return "Still recovering. Recovery day or skip; don't stack another hard session."
            }
        }

        var symbol: String {
            switch self {
            case .fresh:      return "bolt.fill"
            case .partial:    return "figure.walk.motion"
            case .recovering: return "leaf.fill"
            }
        }
    }

    // Carries both the state and the most-recent-race context so
    // the rendering view can show "Recovering · 18h since last
    // session" rather than just a bare state. Hours-since lets
    // the athlete sanity-check the signal against their own felt
    // sense of recovery.
    struct ReadinessReadout: Sendable {
        let state: ReadinessState
        let hoursSinceLastRace: Double
        let lastRaceDemand: RecoveryDemand
    }

    // Compute current readiness from race history + maxHR. Walks
    // the most recent finished race with HR data, computes its
    // recovery demand, and compares hours-elapsed to that bucket's
    // typical range to bucket into Fresh / Partial / Recovering.
    //
    // Boundaries (rough but honest):
    //   • Hours elapsed >= upper bound of demand's range → fresh
    //   • Hours elapsed >= 50% of upper bound        → partial
    //   • Otherwise                                  → recovering
    //
    // referenceDate is injectable for testing.
    static func currentReadiness(
        in races: [Race],
        maxHR: Int,
        referenceDate: Date = Date()
    ) -> ReadinessReadout? {
        // Find the most recent finished race that we can compute
        // a recovery demand for. Skip races without HR data —
        // they don't carry enough information to base readiness on.
        let candidate = races
            .filter { $0.isFinished }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
            .first { recoveryDemand(for: $0, maxHR: maxHR) != nil }

        guard let race = candidate,
              let endedAt = race.endedAt,
              let demand = recoveryDemand(for: race, maxHR: maxHR)
        else { return nil }

        let hoursElapsed = referenceDate.timeIntervalSince(endedAt) / 3600
        guard hoursElapsed >= 0 else { return nil }

        // Use the demand's upper-bound recovery hour estimate as the
        // "fully recovered" threshold. Below 50% of that, the
        // athlete is meaningfully under-recovered.
        let upperBound = recoveryUpperBound(for: demand)

        let state: ReadinessState
        if hoursElapsed >= upperBound {
            state = .fresh
        } else if hoursElapsed >= upperBound * 0.5 {
            state = .partial
        } else {
            state = .recovering
        }

        return ReadinessReadout(
            state: state,
            hoursSinceLastRace: hoursElapsed,
            lastRaceDemand: demand
        )
    }

    // Hours threshold that maps to "fully recovered" for each demand
    // bucket. Pegged to the upper bound of each bucket's typical
    // range. Light = 18, Moderate = 30, Hard = 48, Very Hard = 72.
    // Centralized here so the boundaries stay in sync with
    // RecoveryDemand.typicalRecovery copy.
    private static func recoveryUpperBound(for demand: RecoveryDemand) -> Double {
        switch demand {
        case .light:    return 18
        case .moderate: return 30
        case .hard:     return 48
        case .veryHard: return 72
        }
    }

    // Race-wide average heart rate. Duration-weighted across splits
    // that have HR data — a 5-minute station with avg 170 contributes
    // more to the race average than a 30-second station with avg 140.
    // This matches what an athlete intuitively means by "my race
    // average HR was X" (time-weighted, not equal-weighted).
    //
    // Returns nil when no splits have HR data — the UI shows nothing
    // rather than a misleading 0 or an over-confident average from a
    // single segment.
    static func averageHeartRate(for race: Race) -> Double? {
        var weightedSum: Double = 0
        var totalDuration: TimeInterval = 0
        for split in race.splits {
            guard let avg = split.heartRateAvgBPM, split.duration > 0 else { continue }
            weightedSum += avg * split.duration
            totalDuration += split.duration
        }
        guard totalDuration > 0 else { return nil }
        return weightedSum / totalDuration
    }

    // Race-wide peak heart rate. Max of all splits' max HR readings —
    // since each split's `heartRateMaxBPM` is already the peak in
    // that segment's time window, the race peak is simply the max
    // across them.
    //
    // Returns nil when no splits have max HR data.
    static func peakHeartRate(for race: Race) -> Double? {
        let maxes = race.splits.compactMap { $0.heartRateMaxBPM }
        return maxes.max()
    }

    // MARK: - Efficiency score

    // Per-station + race-wide efficiency = how much output (relative
    // pace) you produced per unit of cardiovascular cost (HR
    // intensity). Coaching question: "did I get good results for
    // the energy I spent?"
    //
    // Formula:
    //
    //   pace_factor      = priorBest / thisSplit.duration
    //   intensity_factor = thisSplit.avgHR / maxHR
    //   efficiency       = pace_factor / intensity_factor
    //
    // Reading the math:
    //   • Match your PB at race-pace HR (~0.85) → ~1.18  (efficient)
    //   • Match your PB at max HR (1.0)         → 1.00   (par)
    //   • 10% slower than PB at race-pace HR    → ~1.06
    //   • 10% slower than PB at max HR          → 0.90   (inefficient)
    //   • Beat your PB at low HR                → ~1.5+  (highly efficient)
    //
    // The "low HR + slow time" case scores around 1.0 too — the
    // athlete traded time for cardiovascular cost, which is honest
    // (cruise day vs race day are different intents).
    //
    // Categories:
    //   • highlyEfficient: ≥1.2 — great result for the cost
    //   • efficient:       1.0–1.2 — typical
    //   • slightlyInefficient: 0.8–1.0 — paid more than result earned
    //   • inefficient:     <0.8 — high HR cost for low output
    struct EfficiencyScore: Equatable {
        let overall: Double
        let worstStation: WorstStation?
        let category: Category
        let stationsCounted: Int

        struct WorstStation: Equatable {
            let station: Station
            let score: Double
        }

        enum Category: String, Equatable {
            case highlyEfficient
            case efficient
            case slightlyInefficient
            case inefficient

            var displayName: String {
                switch self {
                case .highlyEfficient:     return "Highly Efficient"
                case .efficient:           return "Efficient"
                case .slightlyInefficient: return "Slightly Inefficient"
                case .inefficient:         return "Inefficient"
                }
            }
        }

        static func category(forOverall score: Double) -> Category {
            switch score {
            case 1.2...:    return .highlyEfficient
            case 1.0..<1.2: return .efficient
            case 0.8..<1.0: return .slightlyInefficient
            default:        return .inefficient
            }
        }
    }

    // Per-split efficiency. Returns nil when the data needed to
    // compute it isn't available:
    //   - avg HR missing (no Watch / no HK auth / no samples)
    //   - prior PB missing (athlete's first time at this station)
    //   - max HR not set or invalid
    //
    // Same silence-on-missing-data pattern as the rest of RaceStats.
    static func efficiencyForSplit(
        _ split: Split,
        race: Race,
        history: [Race],
        maxHR: Int
    ) -> Double? {
        guard maxHR > 0,
              let avgHR = split.heartRateAvgBPM,
              avgHR > 0,
              split.duration > 0
        else { return nil }

        guard let priorBest = bestDuration(
            for: split.station,
            before: race,
            among: history
        ) else { return nil }

        let paceFactor = priorBest / split.duration
        let intensityFactor = avgHR / Double(maxHR)
        guard intensityFactor > 0 else { return nil }

        return paceFactor / intensityFactor
    }

    // Race-wide efficiency. Duration-weighted average across all
    // stations with computable per-split efficiency (so a long
    // wall-ball station with poor efficiency hurts the overall
    // more than a short station with the same poor score).
    //
    // Returns nil when fewer than 4 stations have computable
    // efficiency — same statistical-significance threshold as
    // the recovery score. A single noisy station shouldn't tank
    // the whole race's number.
    //
    // Also surfaces the worst-efficiency station so the insight
    // layer can call out specifically *which* station was the
    // efficiency drag ("High effort, low output on Wall Balls").
    static func efficiencyScore(
        for race: Race,
        history: [Race],
        maxHR: Int
    ) -> EfficiencyScore? {
        let perStation: [(station: Station, score: Double, weight: Double)] =
            race.splits.compactMap { split in
                guard let eff = efficiencyForSplit(
                    split,
                    race: race,
                    history: history,
                    maxHR: maxHR
                ) else { return nil }
                return (split.station, eff, split.duration)
            }

        guard perStation.count >= 4 else { return nil }

        let totalWeight = perStation.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let weightedSum = perStation
            .map { $0.score * $0.weight }
            .reduce(0, +)
        let overall = weightedSum / totalWeight

        // Worst-station detection. Filter out runs by default —
        // run efficiency varies wildly with terrain, indoor vs
        // outdoor treadmill, etc., and the actionable callout is
        // almost always a workout station the athlete can train
        // specifically. Skip when no workout stations have data.
        let workoutOnly = perStation.filter { $0.station.kind == .workout }
        let worst: EfficiencyScore.WorstStation?
        if let worstSplit = workoutOnly.min(by: { $0.score < $1.score }),
           // Only surface as "worst" if it's meaningfully below the
           // overall race average — otherwise it's noise, not signal.
           worstSplit.score < overall * 0.85 {
            worst = EfficiencyScore.WorstStation(
                station: worstSplit.station,
                score: worstSplit.score
            )
        } else {
            worst = nil
        }

        return EfficiencyScore(
            overall: overall,
            worstStation: worst,
            category: EfficiencyScore.category(forOverall: overall),
            stationsCounted: perStation.count
        )
    }

    // MARK: - Recovery score

    // Race-wide recovery quality score. Aggregates per-station HR
    // drops in the 30s + 60s after each segment ends, then
    // categorizes the athlete's typical drop into a four-bucket
    // recovery quality scale.
    //
    // The 30s window is the more discriminating signal — fast
    // post-segment HR drop within 30s reflects parasympathetic
    // tone and aerobic conditioning. The 60s number is included
    // for the slower-decay tail. Both averages are computed
    // independently across whichever splits have non-nil
    // recovery samples.
    //
    // Categories anchored to HYROX-realistic thresholds:
    //   • excellent: ≥25 bpm drop in 30s — elite-level conditioning
    //   • good:      15–25 bpm — solid race-fit
    //   • average:   10–15 bpm — typical recreational athlete
    //   • slow:      <10 bpm — conditioning gap; transition under
    //                 fatigue probably hurt your finish
    //
    // Returns nil when fewer than 4 splits have recovery30 data —
    // a single noisy sample can swing the average wildly. Four
    // splits is the threshold where a mean starts feeling
    // representative without artificially excluding races where
    // the Watch dropped a couple of recovery captures.
    struct RecoveryScore: Equatable {
        let averageDrop30s: Double
        let averageDrop60s: Double?
        let category: Category
        let stationsCounted: Int

        enum Category: String, Equatable {
            case excellent
            case good
            case average
            case slow

            var displayName: String {
                switch self {
                case .excellent: return "Excellent"
                case .good:      return "Good"
                case .average:   return "Average"
                case .slow:      return "Slow"
                }
            }

            // Coaching cue per category — used by the insight card
            // when this category is excellent or slow. Average and
            // good fire no insight (silence on the unactionable
            // middle).
            var coachingCue: String {
                switch self {
                case .excellent:
                    return "Excellent conditioning — recovery between stations is elite-level."
                case .good:
                    return "Good recovery — race-fit conditioning."
                case .average:
                    return "Average recovery — room to build the engine."
                case .slow:
                    return "Slow recovery — conditioning gap. Add easy-pace volume."
                }
            }
        }

        // Threshold table: which 30s-drop range maps to which
        // category. Centralized here so the insight, hero readout,
        // and any future surface use the same boundaries.
        static func category(forDrop30s drop: Double) -> Category {
            switch drop {
            case 25...:    return .excellent
            case 15..<25:  return .good
            case 10..<15:  return .average
            default:       return .slow
            }
        }
    }

    static func recoveryScore(for race: Race) -> RecoveryScore? {
        // Compute per-split drops only when both endHR and
        // recovery30s are present — without endHR we can't compute
        // the drop. Falling back to peakHR would inflate the drop
        // (peak is usually higher than endHR in HYROX since intensity
        // crests mid-station), making recovery look better than it
        // actually was. Honesty over flattery.
        let drops30: [Double] = race.splits.compactMap { split in
            guard let endHR = split.heartRateEndBPM,
                  let r30 = split.heartRateRecovery30sBPM else { return nil }
            return endHR - r30
        }
        let drops60: [Double] = race.splits.compactMap { split in
            guard let endHR = split.heartRateEndBPM,
                  let r60 = split.heartRateRecovery60sBPM else { return nil }
            return endHR - r60
        }

        // Need at least 4 stations with recovery data — single-
        // segment-noise tolerance. Below this, an aberrant sample
        // (Watch off wrist for one station, etc.) skews the mean
        // enough to mislead.
        guard drops30.count >= 4 else { return nil }

        let avg30 = drops30.reduce(0, +) / Double(drops30.count)
        let avg60: Double? = drops60.isEmpty
            ? nil
            : drops60.reduce(0, +) / Double(drops60.count)

        return RecoveryScore(
            averageDrop30s: avg30,
            averageDrop60s: avg60,
            category: RecoveryScore.category(forDrop30s: avg30),
            stationsCounted: drops30.count
        )
    }

    // MARK: - Cardiac drift across the 8 runs

    // Cardiac drift = how much average HR climbs across the race at
    // similar prescribed work. HYROX is uniquely 8 × 1km runs
    // interleaved with 8 workouts; each run is the same prescribed
    // distance, so a rising HR across the run sequence at flat-or-
    // similar pace is a clean signal of aerobic fatigue / engine
    // capacity gap. (Fatigue inflection in #3 catches a single
    // pivot point; this catches the chronic, gradual climb across
    // the whole race.)
    //
    // Method:
    //   1. Pull the splits for run stations, in race order.
    //   2. Split into "first half" (first 4 runs) vs "second half"
    //      (last 4 runs) — using halves rather than R1-vs-R8 alone
    //      averages out single-run sample noise (one bad run from
    //      a sip of water doesn't blow up the score).
    //   3. driftBPM = avg(secondHalf) - avg(firstHalf).
    //   4. Bucket by magnitude: <5 minimal, 5–10 moderate, >10
    //      severe. Thresholds match coaching literature on
    //      cardiovascular drift in trained vs untrained athletes —
    //      well-conditioned runners show <5 bpm of drift across
    //      moderate-intensity efforts of this duration.
    //
    // Pace context: we also report the second-half-vs-first-half
    // pace ratio. If pace also slowed substantially (>10%), the
    // drift signal weakens — slowing protects HR. If pace held or
    // improved while HR climbed, that's the strongest underprepared
    // signal. The insight surface uses both numbers to phrase the
    // takeaway honestly.
    struct HRDrift: Equatable {
        let firstHalfAvgHR: Double
        let secondHalfAvgHR: Double
        let driftBPM: Double                  // second - first
        let firstHalfAvgPace: Double          // sec/km
        let secondHalfAvgPace: Double         // sec/km
        let paceChangeFraction: Double        // (second - first) / first; +ve = slowing
        let runsCounted: Int                  // total runs with HR data
        let category: Category

        enum Category: String, Equatable {
            case minimal
            case moderate
            case severe

            var displayName: String {
                switch self {
                case .minimal:  return "Minimal"
                case .moderate: return "Moderate"
                case .severe:   return "Severe"
                }
            }

            // Coaching cue strings used by the insight card. We
            // surface insights only on `.moderate` and `.severe` —
            // minimal drift is the goal, not news.
            var coachingCue: String {
                switch self {
                case .minimal:
                    return "Minimal HR drift — engine held steady across all 8 runs."
                case .moderate:
                    return "Moderate HR drift — engine fading in the back half. Add zone-2 volume."
                case .severe:
                    return "Severe HR drift — aerobic capacity gap. Long easy runs are the fix."
                }
            }
        }

        static func category(forDrift bpm: Double) -> Category {
            switch bpm {
            case ..<5:   return .minimal
            case 5..<10: return .moderate
            default:     return .severe
            }
        }
    }

    static func heartRateDrift(for race: Race) -> HRDrift? {
        // Order matters — pull runs in the order they happened in
        // the race so we can split by halves correctly. The
        // canonical race sequence interleaves runs and workouts;
        // sorting by startedAt is the safest way to recover the
        // run order independent of station enum rawValues (which
        // are positional but the array order isn't guaranteed
        // SwiftData-side).
        let runSplits = race.splits
            .filter { $0.station.kind == .run }
            .sorted { $0.startedAt < $1.startedAt }

        // Need HR + duration on each run to compute the score.
        // We're conservative — drop runs missing either field
        // rather than imputing.
        let runs: [(hr: Double, paceSecPerKm: Double)] = runSplits.compactMap { split in
            guard let avg = split.heartRateAvgBPM, avg > 0,
                  split.duration > 0 else { return nil }
            // 1 km is the prescribed run distance for every HYROX
            // run station, so duration in seconds == sec/km pace.
            // No distance lookup needed — by sport definition.
            return (hr: avg, paceSecPerKm: split.duration)
        }

        // Need at least 6 runs split into 3+3 halves to make the
        // signal meaningful. Below that, the second-half average
        // is essentially one or two splits and noise dominates.
        guard runs.count >= 6 else { return nil }

        let mid = runs.count / 2
        let firstHalf = Array(runs.prefix(mid))
        let secondHalf = Array(runs.suffix(runs.count - mid))

        let firstHRAvg = firstHalf.map(\.hr).reduce(0, +) / Double(firstHalf.count)
        let secondHRAvg = secondHalf.map(\.hr).reduce(0, +) / Double(secondHalf.count)
        let firstPaceAvg = firstHalf.map(\.paceSecPerKm).reduce(0, +) / Double(firstHalf.count)
        let secondPaceAvg = secondHalf.map(\.paceSecPerKm).reduce(0, +) / Double(secondHalf.count)

        let drift = secondHRAvg - firstHRAvg
        let paceChange = firstPaceAvg > 0
            ? (secondPaceAvg - firstPaceAvg) / firstPaceAvg
            : 0

        return HRDrift(
            firstHalfAvgHR: firstHRAvg,
            secondHalfAvgHR: secondHRAvg,
            driftBPM: drift,
            firstHalfAvgPace: firstPaceAvg,
            secondHalfAvgPace: secondPaceAvg,
            paceChangeFraction: paceChange,
            runsCounted: runs.count,
            category: HRDrift.category(forDrift: drift)
        )
    }

    // MARK: - Aerobic decoupling

    // Sport-science classic for aerobic conditioning. Where #8
    // cardiac drift just measures HR climb across runs, this
    // normalizes by pace — a more honest engine signal.
    //
    // Coaching question: "did my pace-per-HR ratio hold steady
    // through the race, or did it deteriorate?" If pace held while
    // HR climbed, the ratio degraded. If HR held while pace
    // dropped, the ratio also degraded. Either way, the pace-per-
    // HR ratio falling = engine fading.
    //
    // Method:
    //   1. For each run split, compute pacePerHR = (1/pace) / HR.
    //      Higher = more efficient (more output per HR cost).
    //      Equivalent to "speed per heartbeat-per-minute," scaled.
    //   2. Average pacePerHR across the first half of runs.
    //   3. Average pacePerHR across the second half of runs.
    //   4. decoupling = (firstHalf - secondHalf) / firstHalf.
    //      Positive = ratio deteriorated (engine faded).
    //      Negative = ratio improved (rare, but possible — e.g.
    //      negative-split races where late efficiency rises).
    //
    // Threshold convention straight from sport science literature
    // (Friel, Daniels): under 5% across same-effort steady work is
    // the marker of "aerobically conditioned." 5-10% is moderate
    // aerobic gap. Over 10% is a real engine deficiency that
    // shows up in race performance.
    //
    // Why a separate metric from drift: drift is a single
    // dimension (HR up/down). Decoupling is a 2D ratio that
    // catches the case where pace and HR both drop or rise. An
    // athlete who slows their second half by 15% will have low
    // drift but high decoupling. The combination tells the
    // truer story — drift says what happened to HR, decoupling
    // says whether the engine worked harder for the same pace.
    struct AerobicDecoupling: Equatable {
        let firstHalfPacePerHR: Double      // (1/sec-per-km) / bpm, first half avg
        let secondHalfPacePerHR: Double     // same, second half
        let decouplingFraction: Double      // (first - second) / first; +ve = degradation
        let runsCounted: Int                // total runs with HR + pace data
        let category: Category

        // Sport-science threshold convention (Friel, Daniels).
        // Coaching language is gentler than the literature's —
        // "aerobic gap" lands better than "aerobically deficient."
        enum Category: String, Equatable {
            case conditioned    // <5%, the goal
            case moderateGap    // 5-10%
            case largeGap       // >10%

            var displayName: String {
                switch self {
                case .conditioned: return "Conditioned"
                case .moderateGap: return "Moderate gap"
                case .largeGap:    return "Large gap"
                }
            }

            var coachingCue: String {
                switch self {
                case .conditioned:
                    return "Aerobic engine held steady — well-conditioned for race distance."
                case .moderateGap:
                    return "Pace-per-HR ratio faded — moderate aerobic gap. Easy-pace volume helps."
                case .largeGap:
                    return "Significant decoupling — engine couldn't hold output. Long Z2 weeks needed."
                }
            }
        }

        // Decoupling category boundaries — the literature's
        // standard buckets. Negative decoupling (rare, ratio
        // improved) maps to .conditioned because it's strictly
        // better than holding steady.
        static func category(forFraction fraction: Double) -> Category {
            switch fraction {
            case ..<0.05:  return .conditioned
            case 0.05..<0.10: return .moderateGap
            default:       return .largeGap
            }
        }
    }

    static func aerobicDecoupling(for race: Race) -> AerobicDecoupling? {
        // Pull runs in chronological order — same approach as
        // heartRateDrift uses. Sorting by startedAt is the safest
        // recovery of run order independent of station enum
        // raw values.
        let runSplits = race.splits
            .filter { $0.station.kind == .run }
            .sorted { $0.startedAt < $1.startedAt }

        // For each run, compute the pace-per-HR efficiency ratio.
        // 1km is the prescribed distance for every HYROX run, so
        // duration in seconds is sec/km pace; speed = 1/duration
        // (in 1/seconds, which is fine — we only care about the
        // ratio, not absolute units). Drop runs missing HR or
        // duration.
        let ratios: [Double] = runSplits.compactMap { split -> Double? in
            guard let avg = split.heartRateAvgBPM, avg > 0,
                  split.duration > 0 else { return nil }
            // pace-per-HR. Inverse-second per bpm; the absolute
            // unit doesn't matter — only the ratio change does.
            let speed = 1.0 / split.duration
            return speed / avg
        }

        // Same 6-run minimum as heartRateDrift — below that, the
        // halves are too small for the average to be stable.
        guard ratios.count >= 6 else { return nil }

        let mid = ratios.count / 2
        let firstHalfAvg = ratios.prefix(mid).reduce(0, +) / Double(mid)
        let secondHalfCount = ratios.count - mid
        let secondHalfAvg = ratios.suffix(secondHalfCount).reduce(0, +) / Double(secondHalfCount)

        guard firstHalfAvg > 0 else { return nil }
        let decoupling = (firstHalfAvg - secondHalfAvg) / firstHalfAvg

        return AerobicDecoupling(
            firstHalfPacePerHR: firstHalfAvg,
            secondHalfPacePerHR: secondHalfAvg,
            decouplingFraction: decoupling,
            runsCounted: ratios.count,
            category: AerobicDecoupling.category(forFraction: decoupling)
        )
    }

    // MARK: - Personal HR baseline

    // Athlete-specific race-pace HR band, derived from their own
    // historical run splits. Coaching question this answers: "given
    // how *I* race, what's the HR I should hold during the runs?"
    //
    // Why personal vs textbook: every athlete's race-sustainable HR
    // sits in a different spot inside the textbook Z3 band (70-80%
    // of max). One athlete might cruise at 158, another at 172 —
    // both at the same RPE, both at "race pace." Telling them both
    // "Z3 is 70-80% of max" is generic; telling each of them their
    // own observed band is coaching.
    //
    // Method:
    //   1. Pull avg HR from every run split across the athlete's
    //      finished races (limited to recent N for relevance).
    //   2. Compute median (the band center) + IQR (the band edges
    //      = 25th percentile and 75th percentile).
    //   3. Return nil when fewer than 8 run-split HR samples exist
    //      — below that, percentile estimates are too noisy. Eight
    //      runs is roughly one full HYROX race, so this kicks in
    //      after the first race with full HR capture.
    //
    // The IQR specifically (not min/max) is chosen because race
    // splits include some outliers — a run where the athlete eased
    // up for fluid, a final-run sprint, etc. IQR cuts those off the
    // tails and reports the band the athlete actually lives in.
    //
    // Cue-integration consumers compare current HR to (lowerQuartile,
    // upperQuartile): below = push, inside = hold, above = slow.
    // Cleaner than the textbook 70-80% rule, especially for
    // athletes whose physiology lives at the edges of the textbook
    // band.
    struct PersonalHRBaseline: Equatable {
        let median: Double             // band center (50th percentile)
        let lowerQuartile: Double      // band lower edge (25th percentile)
        let upperQuartile: Double      // band upper edge (75th percentile)
        let sampleCount: Int           // total run-splits contributing
        let racesCounted: Int          // races contributing
    }

    static func personalHRBaseline(
        across races: [Race],
        recentRaceLimit: Int = 10
    ) -> PersonalHRBaseline? {
        // Pull recent finished races first — older races may pre-
        // date HR sampling or have noisy data. Sorting by createdAt
        // descending and prefixing N gives the most-recent window.
        let recentRaces = races
            .filter { $0.isFinished }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recentRaceLimit)

        // Collect every run split's avg HR across this window.
        let runHRSamples: [Double] = recentRaces.flatMap { race in
            race.splits.compactMap { split -> Double? in
                guard split.station.kind == .run,
                      let avg = split.heartRateAvgBPM,
                      avg > 0 else { return nil }
                return avg
            }
        }

        // Need at least 8 samples for a stable percentile estimate.
        // Below this, single-noisy-split skews the median enough to
        // mislead the cue downstream.
        guard runHRSamples.count >= 8 else { return nil }

        let sorted = runHRSamples.sorted()
        let median = percentile(sorted, p: 0.50)
        let q1 = percentile(sorted, p: 0.25)
        let q3 = percentile(sorted, p: 0.75)

        return PersonalHRBaseline(
            median: median,
            lowerQuartile: q1,
            upperQuartile: q3,
            sampleCount: runHRSamples.count,
            racesCounted: recentRaces.count
        )
    }

    // MARK: - Per-station HR signature

    // Per-station HR fingerprint, derived from the athlete's
    // historical splits at THAT station type. Coaching question:
    // "for this specific movement, what's normal HR for me?"
    //
    // Why per-station vs the personal baseline (#10): the global
    // baseline aggregates run splits — meaningful for runs because
    // they're all the same prescribed work. But sled push lives at
    // one HR cost, wall balls another, rowing somewhere else,
    // because muscle recruitment + breathing constraints differ
    // per movement. Reading today's sled-push HR against the
    // run-average median is meaningless. Per-station signatures
    // give each movement its own band.
    //
    // Classification surface: when today's split's avg HR is
    // outside the IQR (25th-75th percentile) of the athlete's
    // history at that station, surface a callout — "today's sled
    // push HR was 12 bpm above your usual." That's the kind of
    // observation a coach makes mid-block ("you looked heavy
    // today, were you OK?") and that no current HYROX tracker
    // surfaces.
    //
    // Returns nil when fewer than 3 prior splits at this station
    // exist — too noisy below that for a percentile estimate.
    struct StationHRSignature: Equatable {
        let station: Station
        let median: Double
        let lowerQuartile: Double
        let upperQuartile: Double
        let sampleCount: Int
        let racesCounted: Int
    }

    // Anomaly classification — where today's HR sits against the
    // historical band for this station. The "well above" / "well
    // below" buckets fire only when today's reading is more than
    // 1.5× the IQR width past the band edges, the same outlier
    // threshold used in classical box-plot whisker detection.
    // That keeps the call-out from firing on routine sample noise.
    enum StationHRAnomaly: Equatable {
        case wellBelowUsual  // HR much lower than typical for this station
        case belowUsual      // below Q1 but within whiskers
        case typical         // inside the IQR
        case aboveUsual      // above Q3 but within whiskers
        case wellAboveUsual  // HR much higher than typical for this station

        var displayName: String {
            switch self {
            case .wellBelowUsual: return "Well below usual"
            case .belowUsual:     return "Below usual"
            case .typical:        return "Typical"
            case .aboveUsual:     return "Above usual"
            case .wellAboveUsual: return "Well above usual"
            }
        }

        // Coaching cue strings — `aboveUsual` and `wellAboveUsual`
        // are the actionable signals (something might be off).
        // Below-usual is rarely a problem (you're more efficient
        // today, or going easy). Typical is the silent default.
        var coachingCue: String? {
            switch self {
            case .wellAboveUsual:
                return "Well above your usual HR for this station — heavier load, fatigue, or off-day."
            case .aboveUsual:
                return "Above your usual HR for this station — worth noting."
            case .wellBelowUsual:
                return "Well below your usual HR — efficient day or easy effort."
            case .belowUsual, .typical:
                return nil
            }
        }
    }

    static func stationHRSignature(
        for station: Station,
        across races: [Race],
        excludingRace: Race? = nil
    ) -> StationHRSignature? {
        // Pull this athlete's historical avg HR samples for the
        // requested station only. Excluding the current race lets
        // the caller compute "today vs my historical signature"
        // without the current sample biasing its own baseline —
        // important when classifying anomalies on a freshly-
        // finished race.
        let samples: [Double] = races
            .filter { $0.isFinished }
            .filter { excludingRace == nil ? true : $0.id != excludingRace!.id }
            .flatMap { race in
                race.splits.compactMap { split -> Double? in
                    guard split.station == station,
                          let avg = split.heartRateAvgBPM,
                          avg > 0 else { return nil }
                    return avg
                }
            }

        // Need at least 3 prior splits — below that, percentile
        // estimates are essentially "min/median/max of 2 numbers"
        // and the IQR isn't meaningful. Three is the smallest
        // sample where the box-plot framing reads as a real
        // distribution, not just point estimates.
        guard samples.count >= 3 else { return nil }

        let sorted = samples.sorted()
        return StationHRSignature(
            station: station,
            median: percentile(sorted, p: 0.50),
            lowerQuartile: percentile(sorted, p: 0.25),
            upperQuartile: percentile(sorted, p: 0.75),
            sampleCount: samples.count,
            racesCounted: races.filter { $0.isFinished && $0.splits.contains { $0.station == station } }.count
        )
    }

    // Classify a single split's avg HR against the historical
    // signature for that station. Returns nil when the split has
    // no avg HR data; the UI silently hides the callout in that
    // case rather than showing "—".
    static func classifyStationHR(
        currentHR: Double,
        signature: StationHRSignature
    ) -> StationHRAnomaly {
        let iqr = signature.upperQuartile - signature.lowerQuartile
        // Box-plot whisker thresholds — 1.5× IQR past each band
        // edge. Below lowerWhisker = wellBelow; above upperWhisker
        // = wellAbove. The classic outlier definition from
        // exploratory data analysis; not arbitrary.
        let lowerWhisker = signature.lowerQuartile - 1.5 * iqr
        let upperWhisker = signature.upperQuartile + 1.5 * iqr

        if currentHR < lowerWhisker { return .wellBelowUsual }
        if currentHR < signature.lowerQuartile { return .belowUsual }
        if currentHR > upperWhisker { return .wellAboveUsual }
        if currentHR > signature.upperQuartile { return .aboveUsual }
        return .typical
    }

    // Linear-interpolated percentile on a pre-sorted array. p in
    // [0, 1]. Empty array returns 0; single-element array returns
    // that element. Used by personalHRBaseline; kept fileprivate-
    // adjacent (private to RaceStats) so other helpers needing
    // percentile arithmetic can share it later.
    private static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let lowerIndex = Int(rank.rounded(.down))
        let upperIndex = Int(rank.rounded(.up))
        if lowerIndex == upperIndex { return sorted[lowerIndex] }
        let weight = rank - Double(lowerIndex)
        return sorted[lowerIndex] * (1 - weight) + sorted[upperIndex] * weight
    }

    // Per-split effort score — same intensity-weighted-minutes
    // formula as the whole-race version, but applied to a single
    // segment. Used by StationDetailView's physiology row + the
    // per-split effort chip on summary / detail.
    //
    // Returns nil when the split has no avg HR data or maxHR <= 0,
    // matching the whole-race variant's silence-on-missing-data.
    static func effortScore(forSplit split: Split, maxHR: Int) -> Double? {
        guard maxHR > 0, let avg = split.heartRateAvgBPM, avg > 0 else {
            return nil
        }
        let intensity = avg / Double(maxHR)
        let minutes = split.duration / 60
        return intensity * minutes
    }

    // Translate a raw effort score into a coarse category label.
    // The whole-race score reads in "intensity-weighted minutes" —
    // the absolute number depends heavily on duration, so a single
    // numeric chip is hard to interpret without context.
    //
    // The category-by-intensity-fraction approach normalizes that:
    // we take the raw score and divide back by minutes to get the
    // average HR fraction (avgHR / maxHR) for the segment, then
    // bucket:
    //
    //   < 0.65  → Recovery (Z1–Z2)
    //   < 0.75  → Moderate (Z3 — aerobic threshold)
    //   < 0.85  → High     (Z4 — lactate threshold)
    //   >= 0.85 → Very High (Z5 — VO2 max + anaerobic)
    //
    // Aligns with the HRZone tiering already shipped, so the
    // language used on the per-station effort chip matches what
    // an athlete sees on the zones chart elsewhere in the app.
    //
    // Returns nil when the score or duration is too small to
    // meaningfully categorize (under 5 seconds — usually a mistap
    // mid-race rather than a real segment).
    static func effortCategory(
        forSplit split: Split,
        maxHR: Int
    ) -> EffortCategory? {
        guard let avg = split.heartRateAvgBPM, avg > 0, maxHR > 0 else {
            return nil
        }
        guard split.duration >= 5 else { return nil }

        let fraction = avg / Double(maxHR)
        switch fraction {
        case ..<0.65:
            return .recovery
        case ..<0.75:
            return .moderate
        case ..<0.85:
            return .high
        default:
            return .veryHigh
        }
    }

    // Coarse category for the per-station effort chip. Keeps the
    // numeric score for the post-race summary while giving a
    // human-readable label for the in-line chip on summary /
    // detail / StationDetailView.
    enum EffortCategory: String, Sendable, CaseIterable {
        case recovery
        case moderate
        case high
        case veryHigh

        var displayName: String {
            switch self {
            case .recovery: return "Recovery"
            case .moderate: return "Moderate"
            case .high:     return "High"
            case .veryHigh: return "Very High"
            }
        }

        // SF Symbol + color hint for the rendering layer. The
        // category logic stays in RaceStats so views render the
        // same icon/color across every surface that displays effort.
        var symbol: String {
            switch self {
            case .recovery: return "leaf.fill"
            case .moderate: return "figure.walk.motion"
            case .high:     return "flame.fill"
            case .veryHigh: return "bolt.fill"
            }
        }
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

    // MARK: - Engine Quality composite score
    //
    // Single-number rollup (0-100) of the athlete's HR-derived
    // engine quality, computed across their last N finished races.
    // The Whoop strain / Apple Activity ring equivalent for HYROX
    // — frames every HR metric we compute (drift, recovery,
    // efficiency, decoupling) into one coaching readout.
    //
    // Composition: each sub-metric is normalized to 0-100 against
    // research-grounded thresholds, then averaged. Sub-scores that
    // can't be computed (insufficient data, missing HR captures)
    // are dropped from the average rather than treated as zero —
    // a brand-new athlete with two races shouldn't see "37" just
    // because one of three signals is unavailable.
    //
    // Sub-score normalizations (each clamped 0-100):
    //
    //   • Drift:        0bpm → 100, 15bpm → 0     (linear, less is better)
    //   • Recovery:     0bpm → 0,   30bpm → 100   (linear, more is better)
    //   • Efficiency:   0.6  → 0,   1.2  → 100    (linear, more is better)
    //   • Decoupling:   0%   → 100, 15%  → 0      (linear, less is better)
    //
    // Tier mapping:
    //   <40 = Building (engine has real work to do)
    //   40-70 = Steady (race-fit conditioning)
    //   >70 = Elite (everything firing)
    //
    // Athlete-level rollup vs per-race: the score uses the AVG of
    // each sub-metric across the recent races, not the most-recent
    // race alone. A single bad race shouldn't tank the engine
    // score; a single great race shouldn't inflate it. Five-race
    // window strikes the balance — long enough to smooth noise,
    // short enough to reflect current fitness rather than
    // historical.
    struct EngineScore: Equatable {
        let overall: Double          // 0-100
        let driftSubScore: Double?
        let recoverySubScore: Double?
        let efficiencySubScore: Double?
        let decouplingSubScore: Double?
        let racesCounted: Int
        let tier: Tier

        enum Tier: String, Equatable {
            case building
            case steady
            case elite

            var displayName: String {
                switch self {
                case .building: return "Building"
                case .steady:   return "Steady"
                case .elite:    return "Elite"
                }
            }

            // Coaching-cue strings used by the Profile card under
            // the tier label. One sentence each — enough to give
            // the number meaning without crowding the UI.
            var coachingCue: String {
                switch self {
                case .building:
                    return "Engine has real work to do. Long Z2 weeks pay off."
                case .steady:
                    return "Race-fit conditioning. Hold the volume, sharpen race pace."
                case .elite:
                    return "Everything firing. Maintain volume and add quality."
                }
            }
        }

        static func tier(forScore score: Double) -> Tier {
            switch score {
            case ..<40:  return .building
            case 40..<70: return .steady
            default:      return .elite
            }
        }
    }

    // Per-race engine score — same composition as the athlete-
    // level rollup but scoped to one race. Each sub-metric is
    // already a single-race signal (drift = within-this-race HR
    // climb, recovery = within-this-race HR drops, etc.), so the
    // per-race version is simply: "run each sub-metric helper on
    // THIS race, normalize, average."
    //
    // Use case differs from the athlete-level rollup. The rollup
    // answers "where am I in my conditioning right now" (5-race
    // smoothing). The per-race version answers "how was the
    // engine in *this* race specifically" — which is the headline
    // post-race readout, and which becomes a single dot on the
    // engine-score trend chart later.
    //
    // `history` is needed because the efficiency sub-metric
    // requires the athlete's prior PB at each station to compute
    // the relative-pace numerator. Pass the full race list; the
    // helper handles the exclusion of the current race itself.
    // Per-race engine-score interpretation against the athlete's
    // recent rolling baseline. Drives the post-race insight
    // narrative — turns the raw number ("Engine 78") into a
    // coaching observation ("Breakthrough — Recovery powered it").
    //
    // Three signals layered:
    //   1. Position vs recent average (last 5 races, excluding
    //      this one). Breakthrough if 10+ above; regression if
    //      10+ below; otherwise normal-range.
    //   2. All-time-best detection — strictly highest score in
    //      the athlete's race history. Surfaces only when there
    //      are 2+ prior races to compare against; first-race
    //      can't be a "best."
    //   3. Dominant sub-metric driver — for races with a clear
    //      delta (breakthrough or regression), identify which
    //      of the four sub-scores deviated most from the
    //      athlete's rolling sub-score baselines. Lets the
    //      insight name the specific sub-metric ("Recovery
    //      powered this race" / "Drift dragged it down").
    //
    // Returns nil for the first race ever or when sub-metric
    // data isn't available — the insight stays silent rather
    // than firing on noisy data.
    struct EngineScoreContext: Equatable {
        let thisRaceScore: Double
        let recentAverage: Double      // last 5 races excluding this one
        let delta: Double              // thisRace - recentAverage
        let isAllTimeBest: Bool
        let dominantSubMetric: SubMetric?
        let position: Position
        let priorRaceCount: Int

        // Which sub-metric most influenced this race vs the
        // athlete's rolling sub-score average. The "most
        // influenced" calculation is the largest absolute delta
        // between this race's sub-score and the rolling average
        // sub-score, in the direction of the overall delta. So a
        // breakthrough race shows the sub-metric that climbed
        // most; a regression race shows the one that fell most.
        enum SubMetric: String, Equatable {
            case drift
            case recovery
            case efficiency
            case decoupling

            var displayName: String {
                switch self {
                case .drift:       return "Drift"
                case .recovery:    return "Recovery"
                case .efficiency:  return "Efficiency"
                case .decoupling:  return "Decoupling"
                }
            }
        }

        // Three-way classification of this race vs recent baseline.
        enum Position: Equatable {
            case breakthrough  // 10+ above recent avg (or all-time best)
            case regression    // 10+ below recent avg
            case normal        // within ±10 of recent avg
        }
    }

    static func engineScoreContext(
        forRace race: Race,
        history: [Race],
        maxHR: Int
    ) -> EngineScoreContext? {
        // Need this race's score and at least 1 prior race for
        // any meaningful interpretation. Below that, there's no
        // context to interpret against.
        guard let thisRace = engineScore(forRace: race, history: history, maxHR: maxHR) else {
            return nil
        }

        // Recent rolling baseline: last 5 finished races EXCLUDING
        // this one. Same window the rollup helper uses; keeps the
        // "recent" definition consistent across surfaces.
        let priorRaces = history
            .filter { $0.isFinished && $0.id != race.id }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)

        guard !priorRaces.isEmpty else { return nil }

        let priorScores: [EngineScore] = priorRaces.compactMap {
            engineScore(forRace: $0, history: history, maxHR: maxHR)
        }
        guard !priorScores.isEmpty else { return nil }

        let recentAvg = priorScores.map(\.overall).reduce(0, +) / Double(priorScores.count)
        let delta = thisRace.overall - recentAvg

        // All-time-best across the full history (not just recent).
        // True if THIS race's score is strictly higher than every
        // prior race's score we could compute one for.
        let allHistoricalScores: [Double] = history
            .filter { $0.isFinished && $0.id != race.id }
            .compactMap { engineScore(forRace: $0, history: history, maxHR: maxHR)?.overall }
        let isAllTimeBest = !allHistoricalScores.isEmpty
            && allHistoricalScores.allSatisfy { thisRace.overall > $0 }

        // Position bucket — straight thresholds. The 10-point
        // threshold is roughly 1 tier-band's worth of movement
        // (Building→Steady spans 30 points), so 10 is the
        // smallest delta that's meaningful at the rollup level.
        let position: EngineScoreContext.Position = {
            if delta >= 10 { return .breakthrough }
            if delta <= -10 { return .regression }
            return .normal
        }()

        // Dominant sub-metric driver — only meaningful for non-
        // normal positions (in the normal band, no sub-metric
        // really "drove" anything). For breakthrough or
        // regression, find the sub-score that deviated most from
        // the athlete's rolling sub-score average, in the
        // direction of the overall delta.
        let dominant: EngineScoreContext.SubMetric? = {
            guard position != .normal else { return nil }
            return dominantSubMetricDriver(
                thisRace: thisRace,
                priorRaces: priorScores,
                direction: delta > 0 ? .breakthrough : .regression
            )
        }()

        return EngineScoreContext(
            thisRaceScore: thisRace.overall,
            recentAverage: recentAvg,
            delta: delta,
            isAllTimeBest: isAllTimeBest,
            dominantSubMetric: dominant,
            position: position,
            priorRaceCount: priorScores.count
        )
    }

    // Finds the sub-metric whose this-race deviation from the
    // rolling sub-score average is most aligned with the overall
    // delta. Returns nil if no sub-metric has comparable rolling
    // baseline data.
    private static func dominantSubMetricDriver(
        thisRace: EngineScore,
        priorRaces: [EngineScore],
        direction: EngineScoreContext.Position
    ) -> EngineScoreContext.SubMetric? {
        // Compute prior averages per sub-metric — only over races
        // where that sub-metric was available, matching the
        // engine-score helper's metric-by-metric averaging.
        let priorDriftAvg = averageOrNil(priorRaces.compactMap(\.driftSubScore))
        let priorRecoveryAvg = averageOrNil(priorRaces.compactMap(\.recoverySubScore))
        let priorEfficiencyAvg = averageOrNil(priorRaces.compactMap(\.efficiencySubScore))
        let priorDecouplingAvg = averageOrNil(priorRaces.compactMap(\.decouplingSubScore))

        // Pair each sub-metric with its delta vs the rolling avg.
        // A sub-metric only contributes if both the prior avg and
        // this race's sub-score are non-nil — `subDelta` returns
        // nil when either side is missing, dropping the pair.
        //
        // The two-step shape (build optional pairs, then
        // compactMap to non-optional) is intentional: a single
        // type-annotated literal that mixes `.drift` enum-case
        // shorthand with optional Doubles trips Swift's type
        // inference, since the outer annotation can't propagate
        // through the array literal into the optional-stripping
        // compactMap. Splitting it lets each step type-check
        // cleanly on its own.
        func subDelta(this: Double?, prior: Double?) -> Double? {
            guard let this, let prior else { return nil }
            return this - prior
        }
        let candidates: [(EngineScoreContext.SubMetric, Double?)] = [
            (.drift,      subDelta(this: thisRace.driftSubScore,      prior: priorDriftAvg)),
            (.recovery,   subDelta(this: thisRace.recoverySubScore,   prior: priorRecoveryAvg)),
            (.efficiency, subDelta(this: thisRace.efficiencySubScore, prior: priorEfficiencyAvg)),
            (.decoupling, subDelta(this: thisRace.decouplingSubScore, prior: priorDecouplingAvg))
        ]
        let deltas: [(metric: EngineScoreContext.SubMetric, delta: Double)] = candidates.compactMap { pair in
            guard let value = pair.1 else { return nil }
            return (metric: pair.0, delta: value)
        }

        guard !deltas.isEmpty else { return nil }

        // For breakthrough — pick the sub-metric with the largest
        // POSITIVE delta. For regression — largest NEGATIVE delta.
        // The sub-metric most aligned with the overall delta's
        // direction is the one that drove the change.
        switch direction {
        case .breakthrough:
            return deltas.max(by: { $0.delta < $1.delta })?.metric
        case .regression:
            return deltas.min(by: { $0.delta < $1.delta })?.metric
        case .normal:
            return nil
        }
    }

    static func engineScore(
        forRace race: Race,
        history: [Race],
        maxHR: Int
    ) -> EngineScore? {
        let drift = heartRateDrift(for: race)?.driftBPM
        let recovery = recoveryScore(for: race)?.averageDrop30s
        let decoupling = aerobicDecoupling(for: race)?.decouplingFraction
        let efficiency = efficiencyScore(for: race, history: history, maxHR: maxHR)?.overall

        let driftSub = drift.map { normalizeDrift($0) }
        let recoverySub = recovery.map { normalizeRecovery($0) }
        let efficiencySub = efficiency.map { normalizeEfficiency($0) }
        let decouplingSub = decoupling.map { normalizeDecoupling($0) }

        let subScores = [driftSub, recoverySub, efficiencySub, decouplingSub]
            .compactMap { $0 }
        guard !subScores.isEmpty else { return nil }
        let overall = subScores.reduce(0, +) / Double(subScores.count)

        return EngineScore(
            overall: overall,
            driftSubScore: driftSub,
            recoverySubScore: recoverySub,
            efficiencySubScore: efficiencySub,
            decouplingSubScore: decouplingSub,
            racesCounted: 1,
            tier: EngineScore.tier(forScore: overall)
        )
    }

    static func engineScore(
        across races: [Race],
        maxHR: Int,
        recentRaceLimit: Int = 5
    ) -> EngineScore? {
        // Pull the most recent finished races first.
        let recent = races
            .filter(\.isFinished)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recentRaceLimit)

        guard !recent.isEmpty else { return nil }

        // Per-race sub-metric extraction. Each helper returns nil
        // for races without enough data; we average over the
        // races that DO have data per metric, separately, so a
        // race missing recovery data still contributes to drift
        // average (etc.).
        let drifts: [Double] = recent.compactMap {
            heartRateDrift(for: $0)?.driftBPM
        }
        let recoveries: [Double] = recent.compactMap {
            recoveryScore(for: $0)?.averageDrop30s
        }
        let decouplings: [Double] = recent.compactMap {
            aerobicDecoupling(for: $0)?.decouplingFraction
        }
        // Efficiency is per-race overall — pulls history excluding
        // the current race for PB-baseline lookup. We use ALL
        // finished races (the full provided list) as the history,
        // not just the recent slice, so PBs are correct.
        let efficiencies: [Double] = recent.compactMap {
            efficiencyScore(for: $0, history: races, maxHR: maxHR)?.overall
        }

        // Average across available samples per metric. Returns nil
        // when no samples exist for that metric — the overall avg
        // ignores nil sub-scores.
        let avgDrift = averageOrNil(drifts)
        let avgRecovery = averageOrNil(recoveries)
        let avgDecoupling = averageOrNil(decouplings)
        let avgEfficiency = averageOrNil(efficiencies)

        // Normalize each into 0-100 via the formulas above.
        // Returning nil when the source metric is nil propagates
        // "no data" cleanly through.
        let driftSub = avgDrift.map { normalizeDrift($0) }
        let recoverySub = avgRecovery.map { normalizeRecovery($0) }
        let efficiencySub = avgEfficiency.map { normalizeEfficiency($0) }
        let decouplingSub = avgDecoupling.map { normalizeDecoupling($0) }

        // Overall = average of available sub-scores. We need at
        // least one sub-score to render a number — otherwise the
        // helper returns nil and the Profile card hides.
        let subScores = [driftSub, recoverySub, efficiencySub, decouplingSub]
            .compactMap { $0 }
        guard !subScores.isEmpty else { return nil }
        let overall = subScores.reduce(0, +) / Double(subScores.count)

        return EngineScore(
            overall: overall,
            driftSubScore: driftSub,
            recoverySubScore: recoverySub,
            efficiencySubScore: efficiencySub,
            decouplingSubScore: decouplingSub,
            racesCounted: recent.count,
            tier: EngineScore.tier(forScore: overall)
        )
    }

    // Average helper that returns nil for empty arrays — keeps
    // the engine-score formulas above readable and centralizes
    // the empty-set behavior. Distinct from the existing
    // `average(_:) -> TimeInterval` helper below which returns
    // 0 for empty (different semantics: this one says "no data,"
    // that one says "zero time"). Both are kept rather than
    // merged because the empty-set behavior is what
    // distinguishes them at the call site.
    private static func averageOrNil(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // 0bpm = 100 (engine held perfectly), 15bpm = 0 (engine
    // visibly faded). Anything beyond clamps. The 15bpm ceiling
    // is well into "severe drift" by §HRDrift's category bands;
    // an athlete drifting more than that has a real engine
    // problem, not a calibration issue.
    private static func normalizeDrift(_ bpm: Double) -> Double {
        let clamped = max(0, min(15, bpm))
        return (1 - clamped / 15) * 100
    }

    // 0bpm = 0 (no recovery), 30bpm = 100 (elite). 30 is the
    // top of the "excellent" band per RecoveryScore.category.
    private static func normalizeRecovery(_ bpm: Double) -> Double {
        let clamped = max(0, min(30, bpm))
        return (clamped / 30) * 100
    }

    // 0.6 = 0 (poor pace-per-HR), 1.2 = 100 (above PB pace at
    // sub-PB intensity). The 1.2 ceiling is generous — most
    // athletes' overall efficiency lives between 0.7 and 1.1
    // even at peak fitness; allowing a 1.2 stretches the upper
    // end so the score doesn't get pinned at 100 for any
    // serious athlete.
    private static func normalizeEfficiency(_ value: Double) -> Double {
        let clamped = max(0.6, min(1.2, value))
        return ((clamped - 0.6) / 0.6) * 100
    }

    // 0% = 100 (engine held perfectly), 15% = 0 (severe gap).
    // 15% is well past the "large gap" threshold from
    // AerobicDecoupling.category — same logic as the drift
    // ceiling.
    private static func normalizeDecoupling(_ fraction: Double) -> Double {
        let clamped = max(0, min(0.15, fraction))
        return (1 - clamped / 0.15) * 100
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

    // MARK: - Live coaching cue (shared with watchOS)
    //
    // Real-time pacing cue based on current HR vs the HYROX race-
    // sustainable band. The intent: while running, an athlete
    // should hold roughly Z3 — that's the 90-minute pace HYROX is
    // built around. Above Z3 means they're dipping into anaerobic
    // territory and won't last; below Z3 means they're leaving time
    // on the table.
    //
    // Workout stations (sled, lunges, wall balls) are deliberately
    // excluded — those are short tactical efforts where redlining
    // is normal and useful. Telling someone to "slow down" mid-sled-
    // push is bad coaching.
    //
    // Used on the iPhone race screen as a coaching chip and on the
    // Watch (with haptic on cue transitions). Lives outside the
    // `#if !os(watchOS)` guard above because it depends only on
    // `Station` + `HRZone` + `Int`, all of which are in the watchOS
    // compile set — so one helper serves both surfaces.
    enum CoachingCue: String, Equatable, Sendable {
        // Athlete is at race-sustainable HR during a run. Reads as
        // affirmation: "you're doing it right, keep it here."
        case hold

        // Athlete's HR is above Z3 during a run. Tactical push
        // mid-run is fine for short bursts (final 200m, hill);
        // a sustained Z4-Z5 mid-run is pacing failure. The cue
        // doesn't know which it is — it just flags "you can't
        // hold this for 90 min."
        case slow

        // Athlete is below Z3 during a run. They've got more in
        // the tank. Common at the start of races when fresh
        // legs feel slow, or when athlete is sandbagging out
        // of fear.
        case push

        // Currently on a workout station — no pace cue. Workouts
        // are short tactical bursts; a "hold/slow/push" cue mid-
        // wall-balls is wrong.
        case workout

        // No HR data, or race not in an active running/workout
        // state. UI hides the chip entirely in this case.
        case none

        var displayText: String {
            switch self {
            case .hold:    return "HOLD PACE"
            case .slow:    return "SLOW DOWN"
            case .push:    return "PUSH HARDER"
            case .workout: return "WORK"
            case .none:    return ""
            }
        }

        // Coaching-cue colors map onto the HYROX zone palette so
        // the chip's color reinforces the same vocabulary the
        // per-station tag uses. Hold is green (good zone), slow
        // is red (above sustainable), push is blue (below race
        // pace), workout is neutral white.
        var colorHex: UInt {
            switch self {
            case .hold:    return 0x32D74B  // success green
            case .slow:    return 0xFF3B30  // accent red
            case .push:    return 0x5B9BD5  // calm blue (matches Z1)
            case .workout: return 0xF5F5F7  // textPrimary off-white
            case .none:    return 0x000000  // unused
            }
        }
    }

    // Compute the coaching cue from current HR + max HR + current
    // station. Returns `.none` when any required input is missing —
    // the UI silently hides the chip rather than showing a stale
    // or misleading cue.
    //
    // When `personalLowerHR` and `personalUpperHR` are BOTH provided
    // (typically from `RaceStats.personalHRBaseline(across:)`'s IQR
    // bounds), the cue classifies against the athlete's *observed*
    // race-pace band instead of the textbook Z3 zone. This is much
    // more accurate than generic 70-80% of max — every athlete's
    // race-sustainable HR sits in a different spot inside the
    // textbook band, and the personalized version tells each of
    // them exactly where their own line is.
    //
    // Without the personal band, falls back to textbook Z3 (zone
    // computed from maxHR). The fallback path matches v0.1
    // behavior so first-race / no-history users still get useful
    // cues; the personal band kicks in once 8+ run-split HR samples
    // exist.
    static func coachingCue(
        currentHR: Double?,
        maxHR: Int,
        currentStation: Station?,
        personalLowerHR: Double? = nil,
        personalUpperHR: Double? = nil
    ) -> CoachingCue {
        guard let hr = currentHR,
              hr > 0,
              let station = currentStation,
              maxHR > 0
        else { return .none }

        // Workout stations: no pace cue — see note above.
        if station.kind == .workout {
            return .workout
        }

        // Personalized path: when the athlete has enough history
        // to derive an observed race-pace band, classify against
        // it directly. Both bounds must be present and ordered
        // sensibly; we defensively fall back to textbook if not.
        if let lower = personalLowerHR,
           let upper = personalUpperHR,
           lower > 0,
           upper > lower {
            if hr < lower { return .push }
            if hr > upper { return .slow }
            return .hold
        }

        // Textbook fallback — classify against Z3 (race-sustainable
        // band: 70-80% of max). Used until the personal baseline
        // bootstraps, and as a safety net when bounds are missing.
        let zone = HRZone.zone(for: hr, maxBPM: maxHR)
        switch zone {
        case .z1, .z2: return .push
        case .z3:      return .hold
        case .z4, .z5: return .slow
        }
    }

    // MARK: - Effort score (snapshot-side, shared with watchOS)
    //
    // Same intensity-weighted-minutes formula as `effortScore(for:Race)`,
    // but operates on `[SerializedSplit]` so it works on the Watch and
    // for the duo guest — neither has access to a SwiftData `Race`. The
    // host's running snapshot already carries serialized splits + the
    // host's max HR; consumers reconstruct the score from the snapshot
    // alone.
    //
    // Returns nil under the same conditions as the Race-shaped variant:
    // no splits with HR data, or maxHR <= 0.
    static func effortScore(forSplits splits: [SerializedSplit], maxHR: Int) -> Double? {
        guard maxHR > 0 else { return nil }
        let maxHRDouble = Double(maxHR)

        let scored = splits.compactMap { split -> Double? in
            guard let avg = split.heartRateAvgBPM, avg > 0 else { return nil }
            let intensity = avg / maxHRDouble
            let duration = split.endedAt.timeIntervalSince(split.startedAt)
            guard duration > 0 else { return nil }
            return intensity * (duration / 60)
        }

        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +)
    }

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

    // MARK: - Predicted finish time

    // Project the current pace forward to estimate total finish
    // time. Naive linear extrapolation: total predicted = elapsed
    // × (total segments / segments completed). Same shape as
    // `naiveExpectedElapsed` — assumes remaining stations take the
    // same average time as completed ones.
    //
    // Real-world note: HYROX athletes typically slow down on the
    // back half (fatigue + late wall balls), so this projection
    // tends to UNDERESTIMATE the true finish on a tired athlete.
    // We surface it anyway because the directional information
    // ("you're projected to beat 1:30") is useful even with the
    // bias, and v2 can refine using either the athlete's
    // historical back-half slowdown ratio or a weighted-by-
    // station-kind projection.
    //
    // Returns nil when:
    //   • segmentsCompleted == 0 — no data yet to project from
    //   • totalSegments == 0 — defensive against zero-station
    //     custom workouts
    static func predictedFinishTime(
        segmentsCompleted: Int,
        totalSegments: Int,
        actualElapsed: TimeInterval
    ) -> TimeInterval? {
        guard segmentsCompleted > 0, totalSegments > 0 else { return nil }
        guard actualElapsed > 0 else { return nil }
        let scaleFactor = Double(totalSegments) / Double(segmentsCompleted)
        return actualElapsed * scaleFactor
    }

    // Signed delta vs the target time. Negative = projecting under
    // (will beat goal), positive = projecting over (will miss).
    // Returns nil when no target is set or no projection is
    // available. Same convention as paceDelta — the UI layer
    // chooses tinting from the sign.
    static func predictedFinishDelta(
        predicted: TimeInterval?,
        target: TimeInterval?
    ) -> TimeInterval? {
        guard let predicted, let target else { return nil }
        return predicted - target
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

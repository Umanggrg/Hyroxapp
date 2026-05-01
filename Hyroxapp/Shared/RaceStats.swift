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

    // MARK: - Live coaching cue

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
    // Used on the iPhone race screen as a coaching chip, and shipped
    // to the Watch via the existing snapshot transport for the same
    // chip on the wrist (with haptic on cue transitions). One helper
    // serves both surfaces because RaceStats is already shared with
    // the watchOS target.
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
    static func coachingCue(
        currentHR: Double?,
        maxHR: Int,
        currentStation: Station?
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

        // Run stations: classify against Z3 (race-sustainable).
        let zone = HRZone.zone(for: hr, maxBPM: maxHR)
        switch zone {
        case .z1, .z2: return .push
        case .z3:      return .hold
        case .z4, .z5: return .slow
        }
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

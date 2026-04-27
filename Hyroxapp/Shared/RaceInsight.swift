import SwiftUI

// Auto-generated narrative callout shown on the post-race summary
// and detail screens. The kind of plain-English observation a coach
// would point at while reviewing a race ("you slowed down in the
// back half") rather than a raw stat the athlete has to interpret.
//
// Each insight carries its own SF Symbol + color so the rendering
// view doesn't need to know what category it is — it just iterates
// and renders. New insight types are added to the static
// `generate(for:allRaces:)` factory, not by extending the struct
// itself.
struct RaceInsight: Identifiable, Equatable {
    let id: UUID
    let text: String
    let symbol: String
    let color: Color

    init(text: String, symbol: String, color: Color) {
        self.id = UUID()
        self.text = text
        self.symbol = symbol
        self.color = color
    }

    // Equatable conformance — UUID is per-instance random, so two
    // insights with identical text aren't `==`. That's intentional;
    // SwiftUI uses `id` for diffing, and we don't ever need to test
    // equality across separately-generated insights.
    static func == (lhs: RaceInsight, rhs: RaceInsight) -> Bool {
        lhs.id == rhs.id
    }
}

// Factory that inspects a finished race and returns up to N
// noteworthy callouts. Order is loose-priority: PB count first
// (most actionable / motivating), then HR peak, then fatigue.
// The view shows them in the returned order without further
// sorting.
//
// Called at view-render time — cheap, no network, just walks the
// splits a couple of times. Don't memoize; the result depends on
// `allRaces` which can change between renders.
enum InsightGenerator {

    // MARK: - Public

    static func generate(for race: Race, allRaces: [Race], maxHR: Int? = nil) -> [RaceInsight] {
        var out: [RaceInsight] = []

        if let pbInsight = pbCountInsight(for: race, allRaces: allRaces) {
            out.append(pbInsight)
        }
        // Mode-aware PB callout — fires when this race is the
        // athlete's fastest *within its mode* (solo or duo). Lives
        // separately from per-station PBs because total-time PBs
        // are a different rhythm of celebration: stations rack up
        // every race, total-time records are rarer.
        if let modePBInsight = modeAwarePBInsight(for: race, allRaces: allRaces) {
            out.append(modePBInsight)
        }
        if let hrInsight = hrPeakInsight(for: race) {
            out.append(hrInsight)
        }
        // Compromised-running insight runs BEFORE the simpler
        // fatigue insight because it's HYROX-specific and
        // actionable ("which station compromised you?"). The
        // simpler fatigue check still fires when no specific
        // station stands out — they coexist as overlapping
        // signals at different granularities.
        if let compromisedInsight = compromisedRunningInsight(for: race) {
            out.append(compromisedInsight)
        }
        if let roxzoneInsight = roxzoneInsight(for: race) {
            out.append(roxzoneInsight)
        }
        if let fatigueInsight = runFatigueInsight(for: race) {
            out.append(fatigueInsight)
        }
        // Effort insight needs maxHR to compute scores; when the
        // caller doesn't have it, the insight is skipped silently.
        // All current call sites have a UserProfile and pass
        // maxHeartRate, so this branch fires in production.
        if let maxHR,
           let effortInsight = effortScoreInsight(for: race, allRaces: allRaces, maxHR: maxHR) {
            out.append(effortInsight)
        }
        // Hardest-station callout — names the single station that
        // burned the most intensity-weighted minutes. Pairs nicely
        // with the whole-race effort insight: one says "today's
        // race was hard," the other says "and *this* is the
        // station that did it." Skipped when no per-split HR data
        // is available (same maxHR-required gate).
        if let maxHR,
           let hardest = hardestStationInsight(for: race, maxHR: maxHR) {
            out.append(hardest)
        }

        return out
    }

    // MARK: - PB count

    // Counts how many splits in this race set new station PBs at
    // the time the race was completed. Renders one of:
    //   • 0 PBs → no insight (don't celebrate the average day)
    //   • 1 PB → "New station PB!"
    //   • 2+ PBs → "Set N new station PBs."
    private static func pbCountInsight(
        for race: Race,
        allRaces: [Race]
    ) -> RaceInsight? {
        let pbCount = race.splits.filter { split in
            RaceStats.wasPBSplit(split, in: race, among: allRaces)
        }.count

        guard pbCount > 0 else { return nil }

        // Avoid the "first race ever, every station is a PB" all-PBs
        // case — too noisy. If they got more than half their splits
        // as PBs, this is almost certainly their first race or two.
        // Skip the insight in that case (the per-split PB badges
        // already tell that story).
        let priorRaces = allRaces.filter {
            $0.createdAt < race.createdAt && $0.isFinished
        }
        if priorRaces.isEmpty { return nil }

        let text = pbCount == 1
            ? "New station personal best!"
            : "Set \(pbCount) new station personal bests."

        return RaceInsight(
            text: text,
            symbol: "trophy.fill",
            color: .success
        )
    }

    // MARK: - Mode-aware total-time PB

    // Was this race the fastest total time the athlete has logged
    // *within its mode*? Solo and duo races aren't directly
    // comparable — HYROX Doubles splits work between two athletes,
    // so a duo total of 1:05 is equivalent to a solo of 1:25-ish,
    // not a record-shattering moment. Mode-segregated PBs preserve
    // the meaning of each.
    //
    // Returns nil unless this race beats every prior finished race
    // *of the same mode*. The first race in a given mode does NOT
    // fire the insight — by the time an athlete is racing solo or
    // duo for the first time, the activity itself is the headline;
    // a "first ever PB" callout reads as filler.
    //
    // Distinct from `RaceStats.wasPBWhenSet` (total-time PB across
    // all modes) — the existing all-modes PB shows up as the
    // trophy on the race card; this insight is the
    // "you cracked your duo PB" coaching note that lives inside
    // the summary card.
    private static func modeAwarePBInsight(
        for race: Race,
        allRaces: [Race]
    ) -> RaceInsight? {
        guard let thisTotal = race.totalDuration else { return nil }

        let priorSameMode = allRaces.filter {
            $0.createdAt < race.createdAt
                && $0.isFinished
                && $0.mode == race.mode
        }
        // Need at least one prior in the same mode; otherwise
        // there's no "PB" to cracker against.
        guard !priorSameMode.isEmpty else { return nil }

        guard let priorBest = priorSameMode.compactMap(\.totalDuration).min(),
              thisTotal < priorBest
        else { return nil }

        let delta = priorBest - thisTotal
        let label = race.mode == .duo ? "duo" : "solo"
        let text = "New \(label) personal best — \(RaceStats.format(delta)) faster than your prior best."

        return RaceInsight(
            text: text,
            symbol: race.mode == .duo ? "person.2.fill" : "trophy.fill",
            color: .success
        )
    }

    // MARK: - HR peak

    // Find the station with the highest max HR captured in this
    // race. Tells the athlete which station spiked them hardest —
    // useful for understanding which work is most taxing.
    // Returns nil when no split has HR data.
    private static func hrPeakInsight(for race: Race) -> RaceInsight? {
        let candidates = race.splits.compactMap { split -> (Station, Double)? in
            guard let max = split.heartRateMaxBPM else { return nil }
            return (split.station, max)
        }
        guard let peak = candidates.max(by: { $0.1 < $1.1 }) else {
            return nil
        }
        let text = "HR peaked at \(Int(peak.1.rounded())) bpm during \(peak.0.displayName)."
        return RaceInsight(
            text: text,
            symbol: "heart.fill",
            color: .accent
        )
    }

    // MARK: - Compromised running

    // HYROX-specific narrative: which station hurt your engine
    // recovery the most? Pulls from `RaceStats.biggestCompromisedRun`
    // which already does the math. Only fires when the worst
    // run is meaningfully slower than baseline (>= 12%) — small
    // slowdowns are noise, not actionable feedback.
    //
    // Phrased as a coaching diagnosis ("Sled Pull cost you...")
    // rather than a statistic ("Run 6 was 22% slower"). Both
    // facts are true; the diagnosis is what the athlete can act
    // on in next week's training.
    private static func compromisedRunningInsight(for race: Race) -> RaceInsight? {
        guard let biggest = RaceStats.biggestCompromisedRun(for: race),
              let preceding = biggest.precedingStation,
              biggest.percentSlower >= 12.0
        else { return nil }

        let percent = Int(biggest.percentSlower.rounded())
        let text = "\(preceding.displayName) compromised your engine — Run \(biggest.runIndex) was \(percent)% slower."

        return RaceInsight(
            text: text,
            symbol: "arrow.down.right.circle.fill",
            color: .warning
        )
    }

    // MARK: - Roxzone discipline

    // Surfaces an opinionated callout about transition discipline
    // when roxzone data was captured. Three buckets:
    //
    //   • avg ≤ 10s — "Tight transitions" — race-grade discipline.
    //     Coral / success.
    //   • 10s < avg ≤ 20s — "Decent transitions" — room to tighten
    //     but not a problem. Subtle / textPrimary.
    //   • avg > 20s — "Lots of transition time" — actionable
    //     callout: "you can win minutes here." Warning / amber.
    //
    // Returns nil when no roxzone data was captured (single-tap-
    // mode races). The HYROX community's mental model is "every
    // second in roxzone is a second not racing" — fast transitions
    // aren't optional, they're a discipline you train.
    private static func roxzoneInsight(for race: Race) -> RaceInsight? {
        guard let avg = RaceStats.avgRoxzoneTime(race) else { return nil }
        let avgRounded = Int(avg.rounded())

        let text: String
        let symbol: String
        let color: Color

        if avg <= 10 {
            text = "Tight transitions — \(avgRounded)s avg roxzone."
            symbol = "bolt.fill"
            color = .success
        } else if avg <= 20 {
            text = "\(avgRounded)s avg roxzone — solid, room to tighten."
            symbol = "arrow.right.circle.fill"
            color = .textPrimary
        } else {
            text = "\(avgRounded)s avg roxzone — minutes to gain in transitions."
            symbol = "arrow.right.circle.fill"
            color = .warning
        }

        return RaceInsight(text: text, symbol: symbol, color: color)
    }

    // MARK: - Run fatigue

    // Compare the average run time of the first half of run splits
    // vs the second half. If the second half is meaningfully slower
    // (>10%), surface a fatigue callout — gives the athlete an
    // immediate read on whether they paced sustainably.
    //
    // Returns nil when the race has fewer than 4 run splits (need
    // 2 in each half to be statistically interesting), or when the
    // delta is below the 10% threshold (not actionable).
    private static func runFatigueInsight(for race: Race) -> RaceInsight? {
        let runs = race.splits.filter { $0.station.kind == .run }
        guard runs.count >= 4 else { return nil }

        let mid = runs.count / 2
        let firstHalf = runs.prefix(mid)
        let secondHalf = runs.suffix(runs.count - mid)

        let firstAvg = firstHalf.map(\.duration).reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.map(\.duration).reduce(0, +) / Double(secondHalf.count)
        guard firstAvg > 0 else { return nil }

        let delta = (secondAvg - firstAvg) / firstAvg
        // Only surface if the slowdown is meaningful. A small slowdown
        // is normal pacing; large slowdowns are coaching signal.
        guard Swift.abs(delta) >= 0.10 else { return nil }

        let percent = Int((Swift.abs(delta) * 100).rounded())
        let text = delta > 0
            ? "Slowed down \(percent)% on the back-half runs."
            : "Negative split — back-half runs \(percent)% faster."

        return RaceInsight(
            text: text,
            symbol: delta > 0 ? "tortoise.fill" : "hare.fill",
            color: delta > 0 ? .warning : .success
        )
    }

    // MARK: - Effort score
    //
    // Compares this race's effort score against the athlete's
    // recent average. Three buckets, one fires per race:
    //
    //   • >= 1.15 × average → "Highest-effort race in your last N"
    //     (or just "Big effort day" when no comparison is meaningful)
    //   • <= 0.75 × average → "Light effort — recovery vibes"
    //   • Otherwise → no insight (the score line under the hero
    //     already shows the number)
    //
    // First-race-with-HR: just surface the number with neutral
    // tone — there's nothing to compare against yet.
    //
    // Returns nil when the race has no effort score (no HR data),
    // matching the silence-on-no-data pattern of the other
    // insights here.
    private static func effortScoreInsight(
        for race: Race,
        allRaces: [Race],
        maxHR: Int
    ) -> RaceInsight? {
        guard let score = RaceStats.effortScore(for: race, maxHR: maxHR) else {
            return nil
        }

        // Compare against the athlete's last 10 finished races
        // EXCLUDING the current race itself. Using a recent
        // window (vs. all-time) keeps the comparison relevant
        // — older races may pre-date HR sampling or have noisier
        // data, and "highest effort ever" is less actionable than
        // "highest effort lately."
        let priorScores = allRaces
            .filter { $0.id != race.id && $0.isFinished }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .compactMap { RaceStats.effortScore(for: $0, maxHR: maxHR) }

        // No prior comparable data — surface the score itself
        // with a neutral framing so the athlete sees we computed
        // it without forcing a high/low judgment.
        guard !priorScores.isEmpty else {
            return RaceInsight(
                text: "Effort score \(Int(score.rounded())) — your first HR-tracked race.",
                symbol: "bolt.fill",
                color: .accent
            )
        }

        let avg = priorScores.reduce(0, +) / Double(priorScores.count)
        guard avg > 0 else { return nil }

        let ratio = score / avg

        if ratio >= 1.15 {
            return RaceInsight(
                text: "Big effort — \(Int(score.rounded())) effort score, \(Int(((ratio - 1) * 100).rounded()))% above your recent average.",
                symbol: "bolt.fill",
                color: .accent
            )
        } else if ratio <= 0.75 {
            return RaceInsight(
                text: "Light effort — \(Int(score.rounded())) effort score. Solid recovery day.",
                symbol: "leaf.fill",
                color: .success
            )
        } else {
            // Within the typical band — no callout. The hero's
            // "Effort N · HR-time" line already shows the number
            // for athletes who want it.
            return nil
        }
    }

    // MARK: - Hardest station

    // Identify the single split that consumed the most
    // intensity-weighted minutes of the race — i.e. the station
    // that hurt the most physiologically. Different question than
    // "longest split" (which is just duration) and different from
    // "highest avg HR" (which is intensity alone). Effort score
    // multiplies the two, so a long station at moderate HR can
    // beat a short station at peak HR — and that ordering matches
    // how a coach actually thinks about training load.
    //
    // Skips the run-station family by default. Eight 1km runs
    // collectively dominate a HYROX race's effort budget; calling
    // out "your runs were the hardest part" every time would be
    // noise. The athlete cares which WORKOUT station beat them up
    // most, because that's where training adaptations happen.
    //
    // Threshold: only fires when the top station's effort exceeds
    // the median workout-station effort by 30%+. Keeps the callout
    // meaningful — if every station was roughly equal, naming a
    // "hardest" one would mislead.
    private static func hardestStationInsight(
        for race: Race,
        maxHR: Int
    ) -> RaceInsight? {
        // Compute per-workout-split effort scores. Splits without
        // HR data are silently skipped — same silence-on-no-data
        // pattern used everywhere else in this module.
        let scored: [(split: Split, score: Double)] = race.splits
            .filter { $0.station.kind == .workout }
            .compactMap { split in
                guard let score = RaceStats.effortScore(forSplit: split, maxHR: maxHR) else {
                    return nil
                }
                return (split, score)
            }

        // Need at least 3 scored workout splits for a meaningful
        // ranking — calling something the "hardest" of two doesn't
        // really land.
        guard scored.count >= 3,
              let hardest = scored.max(by: { $0.score < $1.score })
        else { return nil }

        // Compare against the median of the rest. If the top score
        // doesn't pull meaningfully above the pack, don't name a
        // single station — they were all roughly equally taxing.
        let others = scored.filter { $0.split.station != hardest.split.station }
        guard !others.isEmpty else { return nil }

        let sortedOtherScores = others.map(\.score).sorted()
        let median: Double = {
            let mid = sortedOtherScores.count / 2
            if sortedOtherScores.count.isMultiple(of: 2) {
                return (sortedOtherScores[mid - 1] + sortedOtherScores[mid]) / 2
            }
            return sortedOtherScores[mid]
        }()
        guard median > 0, hardest.score / median >= 1.3 else { return nil }

        let stationName = hardest.split.station.displayName
        let text = "\(stationName) was your hardest station — biggest physiological cost of the race."

        return RaceInsight(
            text: text,
            symbol: "flame.fill",
            color: .warning
        )
    }
}

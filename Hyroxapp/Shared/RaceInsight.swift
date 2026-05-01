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
        // Fatigue inflection — looks for the SPECIFIC station where
        // the wheels fell off, vs. run-fatigue's blunt first-half /
        // second-half comparison. The two coexist intentionally:
        // run-fatigue answers "did you fade?", inflection answers
        // "where did you fade?", and they layer different
        // granularities of the same diagnosis.
        if let inflection = fatigueInflectionInsight(for: race) {
            out.append(inflection)
        }
        // Recovery quality — fires for excellent or slow categories
        // only. Average and good are silenced because they're not
        // actionable ("you're typical, keep it up" reads as filler).
        // Excellent gets a positive callout; slow flags a real
        // training gap.
        if let recoveryInsight = recoveryInsight(for: race) {
            out.append(recoveryInsight)
        }
        // Cardiac drift — chronic version of fatigue inflection.
        // Fires for moderate or severe drift only; minimal drift
        // is the goal and not noteworthy. Pairs naturally with
        // fatigue inflection (which catches the single pivot
        // station) and run-fatigue (first-half-vs-second pace).
        if let driftInsight = heartRateDriftInsight(for: race) {
            out.append(driftInsight)
        }
        // Aerobic decoupling — the sport-science cousin of drift.
        // Drift watches HR; decoupling watches the HR-to-pace
        // ratio. Fires only on moderate-gap or large-gap; the
        // .conditioned bucket is the goal and silent. Together
        // with drift, the two surface a complete engine story
        // — drift says "what happened to your HR," decoupling
        // says "did your engine actually fade or did you just
        // slow down."
        if let decouplingInsight = aerobicDecouplingInsight(for: race) {
            out.append(decouplingInsight)
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
        // Efficiency-worst-station — names the workout station
        // where the athlete spent the most HR cost for the
        // smallest pace return. Coaching-meaningful: this is the
        // station to train specifically. Different question than
        // "hardest station" — hardest is about absolute body load,
        // worst-efficiency is about cost-vs-output ratio.
        if let maxHR,
           let efficiencyDrag = efficiencyDragInsight(for: race, allRaces: allRaces, maxHR: maxHR) {
            out.append(efficiencyDrag)
        }
        // Engine-score interpretation — the rollup-level insight.
        // Reads "did this race break through, regress, or hold
        // steady against my recent baseline?" + which sub-metric
        // drove the change. Sits last in the insight list because
        // it's the meta-callout that frames everything above it
        // (the drift / recovery / decoupling insights are the
        // sub-metric stories; this one is the rollup).
        if let maxHR,
           let engineInsight = engineScoreInsight(for: race, allRaces: allRaces, maxHR: maxHR) {
            out.append(engineInsight)
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

    // MARK: - Fatigue inflection

    // Find the specific station after which the rest of the race got
    // meaningfully slower — the "wheels-fell-off" moment. Different
    // question than run-fatigue (first-half vs second-half runs),
    // and different from compromised running (which run did one
    // workout hurt). This one walks every possible split-index
    // pivot, computes pre-pivot and post-pivot averages for both
    // duration and HR, and finds the pivot with the largest
    // pace-decline that still passes a meaningfulness threshold.
    //
    // Classification by HR direction:
    //
    //   • HR rising (>3% jump, post vs pre) — classic fatigue.
    //     Body's working harder for less output. Coaching cue:
    //     conditioning gap, or the prior station drained the
    //     engine.
    //
    //   • HR flat or falling (<-2% drop) — pacing issue. Output
    //     dropped without intensity rising — the gas tank emptied,
    //     went out too hard. Coaching cue: pace your front half.
    //
    //   • HR ambiguous (between -2% and +3%, or no data) — flag
    //     the slowdown without naming a cause. The athlete still
    //     gets the "started fading at station X" callout without
    //     a misleading diagnosis.
    //
    // Returns nil when:
    //   - The race has fewer than 6 splits (need 3 pre, 3 post for
    //     the comparison to mean anything statistically).
    //   - No pivot's pace decline reaches 8% (small slowdowns are
    //     normal pacing variation, not actionable).
    //   - The pre-pivot duration is zero (degenerate; shouldn't
    //     happen in practice but defensive).
    private static func fatigueInflectionInsight(for race: Race) -> RaceInsight? {
        let splits = race.splits
        guard splits.count >= 6 else { return nil }

        // Walk pivots from index 2 to count-3 — guarantees ≥2 splits
        // on each side. Anchored away from the very ends because
        // a single station near the start or end inflating an
        // average isn't a real fatigue signal, just noise.
        var bestPivot: (
            index: Int,
            paceDecline: Double,
            hrDelta: Double?
        )?

        for pivot in 2..<(splits.count - 2) {
            let pre = Array(splits[0..<pivot])
            let post = Array(splits[pivot...])

            let preAvgDuration = pre.map(\.duration).reduce(0, +) / Double(pre.count)
            let postAvgDuration = post.map(\.duration).reduce(0, +) / Double(post.count)
            guard preAvgDuration > 0 else { continue }

            let paceDecline = (postAvgDuration - preAvgDuration) / preAvgDuration
            // 8% threshold — small enough to catch real fades, big
            // enough to ignore typical inter-segment pacing noise.
            guard paceDecline >= 0.08 else { continue }

            // HR delta — only computed when both pre and post have
            // at least one HR sample. Nil otherwise; the consumer
            // falls back to the unclassified "pace dropped" message.
            let preHRs = pre.compactMap(\.heartRateAvgBPM)
            let postHRs = post.compactMap(\.heartRateAvgBPM)
            var hrDelta: Double?
            if !preHRs.isEmpty, !postHRs.isEmpty {
                let preAvgHR = preHRs.reduce(0, +) / Double(preHRs.count)
                let postAvgHR = postHRs.reduce(0, +) / Double(postHRs.count)
                if preAvgHR > 0 {
                    hrDelta = (postAvgHR - preAvgHR) / preAvgHR
                }
            }

            if bestPivot == nil || paceDecline > bestPivot!.paceDecline {
                bestPivot = (pivot, paceDecline, hrDelta)
            }
        }

        guard let pivot = bestPivot else { return nil }

        let stationName = splits[pivot.index].station.displayName
        // 1-indexed for display so it matches the "Station 7 of 16"
        // language used everywhere else in the app.
        let stationNumber = pivot.index + 1
        let pacePct = Int((pivot.paceDecline * 100).rounded())

        // Three-mode classification by HR direction.
        if let hrDelta = pivot.hrDelta {
            let hrPct = Int((Swift.abs(hrDelta) * 100).rounded())
            if hrDelta > 0.03 {
                return RaceInsight(
                    text: "Fatigue point at station \(stationNumber) (\(stationName)) — pace dropped \(pacePct)% with HR up \(hrPct)%.",
                    symbol: "flame.fill",
                    color: .warning
                )
            } else if hrDelta < -0.02 {
                return RaceInsight(
                    text: "Started fading at station \(stationNumber) (\(stationName)) — pace dropped \(pacePct)% and HR dropped too. Pacing issue: went out too hard.",
                    symbol: "tortoise.fill",
                    color: .warning
                )
            }
            // Ambiguous HR delta — fall through to the unclassified
            // message rather than forcing a diagnosis the data
            // doesn't support.
        }

        return RaceInsight(
            text: "Pace dropped \(pacePct)% from station \(stationNumber) onward (\(stationName)).",
            symbol: "arrow.down.right.circle.fill",
            color: .warning
        )
    }

    // MARK: - Efficiency drag

    // Surface the worst-efficiency workout station as a coaching
    // callout. Builds on RaceStats.efficiencyScore which already
    // applies the workout-only filter and the "must be meaningfully
    // below the race average" threshold — if a worstStation is
    // returned, it's already actionable signal.
    //
    // Phrased as a coaching diagnosis ("High effort, low output on
    // X") rather than a raw score so the athlete sees what to
    // train, not just a number.
    //
    // Returns nil when:
    //   - No prior PB exists for any of this race's stations
    //     (first race ever — efficiency math has no baseline).
    //   - efficiencyScore returned no worstStation (no station
    //     stood meaningfully below the race average).
    //   - maxHR not provided.
    private static func efficiencyDragInsight(
        for race: Race,
        allRaces: [Race],
        maxHR: Int
    ) -> RaceInsight? {
        guard let efficiency = RaceStats.efficiencyScore(
            for: race,
            history: allRaces,
            maxHR: maxHR
        ), let worst = efficiency.worstStation else { return nil }

        let stationName = worst.station.displayName
        let scoreLabel = String(format: "%.2f", worst.score)
        let text = "High effort, low output on \(stationName) — efficiency \(scoreLabel). Train this station specifically."

        return RaceInsight(
            text: text,
            symbol: "arrow.down.right.circle.fill",
            color: .warning
        )
    }

    // MARK: - Recovery quality

    // Surface a recovery-quality callout when the athlete's
    // post-station HR drop is at either tail of the distribution.
    // Excellent recovery is praise-worthy ("elite-level
    // conditioning"); slow recovery is a real coaching signal
    // ("conditioning gap, build the engine"). The middle two
    // categories (average / good) intentionally fire no insight
    // — calling out "you're roughly average" reads as filler.
    //
    // The hero already shows the raw drop number for athletes
    // who want it; this insight is the narrative layer that turns
    // the number into a story the athlete can act on.
    //
    // Returns nil when:
    //   - The race has fewer than 4 stations with recovery data
    //     (silenced upstream by RaceStats.recoveryScore).
    //   - The category is .average or .good (no actionable signal).
    private static func recoveryInsight(for race: Race) -> RaceInsight? {
        guard let recovery = RaceStats.recoveryScore(for: race) else {
            return nil
        }

        switch recovery.category {
        case .excellent:
            let drop = Int(recovery.averageDrop30s.rounded())
            return RaceInsight(
                text: "Elite recovery — HR dropped \(drop) bpm avg in 30s between stations.",
                symbol: "wind",
                color: .success
            )
        case .slow:
            let drop = Int(recovery.averageDrop30s.rounded())
            return RaceInsight(
                text: "Slow recovery — HR only dropped \(drop) bpm avg in 30s. Add easy-pace volume.",
                symbol: "tortoise.fill",
                color: .warning
            )
        case .average, .good:
            return nil
        }
    }

    // MARK: - Aerobic decoupling insight
    //
    // Surfaces moderate-gap or large-gap aerobic decoupling. The
    // .conditioned bucket is the goal and silent — no insight
    // earns less screen real estate than "good news that's not
    // news." Phrasing leans on the sport-science vocabulary
    // ("aerobic gap," "decoupling") so the athlete encounters the
    // language they'll see in any serious endurance training
    // resource.
    private static func aerobicDecouplingInsight(for race: Race) -> RaceInsight? {
        guard let decoupling = RaceStats.aerobicDecoupling(for: race) else {
            return nil
        }
        guard decoupling.category != .conditioned else { return nil }

        let pct = Int((decoupling.decouplingFraction * 100).rounded())

        switch decoupling.category {
        case .moderateGap:
            return RaceInsight(
                text: "\(pct)% aerobic decoupling — pace-per-HR ratio faded. Add Z2 volume.",
                symbol: "chart.line.downtrend.xyaxis",
                color: .warning
            )
        case .largeGap:
            return RaceInsight(
                text: "\(pct)% aerobic decoupling — significant engine gap. Long Z2 weeks needed.",
                symbol: "chart.line.downtrend.xyaxis",
                color: .accent
            )
        case .conditioned:
            return nil
        }
    }

    // MARK: - Engine Score insight
    //
    // Per-race rollup interpretation. The decoupling / drift /
    // recovery insights above are sub-metric stories ("your
    // recovery was elite", "decoupling was 8%"). This is the
    // rollup story: "how did this race land against your recent
    // baseline, and what drove that?" Sits at the bottom of the
    // insight list because it's the meta-callout — the others
    // give the breakdown, this gives the headline.
    //
    // Three flavors fire:
    //   • All-time best (strictly highest engine score ever)
    //   • Breakthrough (10+ above recent 5-race avg, or all-time
    //     best). Names the dominant sub-metric driver.
    //   • Regression (10+ below recent 5-race avg). Names the
    //     dominant sub-metric drag.
    // Normal-range races (within ±10) silently skip — no insight
    // earns less screen real estate than "you raced normally."
    //
    // Requires maxHR for engine-score computation; without it the
    // helper returns nil and the insight skips. First-race users
    // also see no insight (no baseline to compare against).
    private static func engineScoreInsight(
        for race: Race,
        allRaces: [Race],
        maxHR: Int
    ) -> RaceInsight? {
        guard let context = RaceStats.engineScoreContext(
            forRace: race,
            history: allRaces,
            maxHR: maxHR
        ) else { return nil }

        let score = Int(context.thisRaceScore.rounded())
        let absDelta = Int(abs(context.delta).rounded())
        let driverName = context.dominantSubMetric?.displayName

        // All-time-best is the strongest positive callout — it
        // takes precedence over breakthrough phrasing even though
        // breakthrough is implied. The ATB string reads as
        // celebration, breakthrough as observation.
        if context.isAllTimeBest {
            let driverSuffix = driverName.map { " — \($0) led the way." } ?? ""
            return RaceInsight(
                text: "Best engine race ever — \(score).\(driverSuffix)",
                symbol: "trophy.fill",
                color: .success
            )
        }

        switch context.position {
        case .breakthrough:
            let driverSuffix = driverName.map { " \($0) powered it." } ?? ""
            return RaceInsight(
                text: "Breakthrough engine — \(score), +\(absDelta) above your recent average.\(driverSuffix)",
                symbol: "chart.line.uptrend.xyaxis",
                color: .success
            )
        case .regression:
            let driverSuffix = driverName.map { " \($0) was the drag." } ?? ""
            return RaceInsight(
                text: "Off-day engine — \(score), \(absDelta) below your recent average.\(driverSuffix)",
                symbol: "chart.line.downtrend.xyaxis",
                color: .warning
            )
        case .normal:
            return nil
        }
    }

    // MARK: - Cardiac drift insight
    //
    // Surfaces moderate or severe cardiac drift across the run sequence.
    // Phrasing also accounts for whether pace held — drifting HR while
    // pace held is the strongest underprepared-engine signal, while
    // drifting HR with substantially slower pace is a more complex
    // story (you slowed AND your HR climbed, which suggests both
    // pacing failure and fitness gap).
    //
    // Returns nil when:
    //   • RaceStats.heartRateDrift returns nil (insufficient run HR data),
    //   • the category is `.minimal` (good news but not insight-worthy
    //     — keeps the insight pane focused on actionable callouts).
    private static func heartRateDriftInsight(for race: Race) -> RaceInsight? {
        guard let drift = RaceStats.heartRateDrift(for: race) else {
            return nil
        }
        guard drift.category != .minimal else { return nil }

        let bpm = Int(drift.driftBPM.rounded())
        // Pace-held threshold: ≤4% slowdown across halves counts
        // as "pace held" for our purposes — that's roughly the
        // intra-race pacing variance you'd expect from a steady
        // effort. Above 4%, we acknowledge the slowdown so the
        // takeaway doesn't read as accusatory ("you didn't even
        // slow down" when in fact they did).
        let paceHeld = drift.paceChangeFraction <= 0.04

        switch drift.category {
        case .moderate:
            let suffix = paceHeld
                ? "Add zone-2 volume to build the engine."
                : "Pace also faded — pacing + engine both have room."
            return RaceInsight(
                text: "HR climbed \(bpm) bpm across the runs. \(suffix)",
                symbol: "waveform.path.ecg",
                color: .warning
            )
        case .severe:
            let suffix = paceHeld
                ? "Aerobic capacity gap — long easy runs are the fix."
                : "Engine and pacing both broke down — long easy volume first."
            return RaceInsight(
                text: "HR drifted \(bpm) bpm across the runs. \(suffix)",
                symbol: "waveform.path.ecg",
                color: .accent
            )
        case .minimal:
            return nil
        }
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

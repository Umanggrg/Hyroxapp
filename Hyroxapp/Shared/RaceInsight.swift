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

    static func generate(for race: Race, allRaces: [Race]) -> [RaceInsight] {
        var out: [RaceInsight] = []

        if let pbInsight = pbCountInsight(for: race, allRaces: allRaces) {
            out.append(pbInsight)
        }
        if let hrInsight = hrPeakInsight(for: race) {
            out.append(hrInsight)
        }
        if let fatigueInsight = runFatigueInsight(for: race) {
            out.append(fatigueInsight)
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
}

import Foundation

// Aggregated stats for a single calendar month of training —
// the data backbone for the in-app recap screen and the
// Spotify-Wrapped-style shareable card. One MonthlyRecap value
// per month the athlete has any races in.
//
// Pure value type, derived from `[Race]`. No persistence — recap
// regenerates from the live data whenever the view renders. This
// keeps history corrections (a race renamed, a photo added,
// a notes edit) reflected immediately in past recaps without any
// migration work.
//
// "Calendar month" uses the user's current calendar / locale, so
// a race that ended at 11:55pm on April 30 lands in April even
// if the device is in a timezone where it'd be May 1 UTC.
//
// Guarded `#if !os(watchOS)` because Race + RaceStats helpers
// are iOS-only.
#if !os(watchOS)
// Hashable conformance is required because MonthlyRecap is used
// as a navigation value in `.navigationDestination(for:)`. All
// stored properties are Hashable already (Date, Int, optionals
// of TimeInterval/Double, and the Hashable BiggestMover) so the
// synthesized conformance is straightforward.
struct MonthlyRecap: Sendable, Equatable, Hashable {

    // The month this recap covers — represented by any Date inside
    // the month (typically the first of the month at midnight in
    // the user's calendar).
    let monthStart: Date

    // Header counts.
    let raceCount: Int
    let totalDuration: TimeInterval

    // Best total time of the month (race PB if applicable, fastest
    // race otherwise). Nil when no races.
    let fastestTotal: TimeInterval?

    // Number of finished races in this month that set a NEW total-
    // time PB at the moment they were saved. Athletes count "PBs
    // this month" as a brag; this is the number that drives that.
    let totalTimePBCount: Int

    // Total active calories burned across all races in the month.
    // Nil when no race had calorie data.
    let totalCalories: Double?

    // Best 1km run split achieved any time in the month, across
    // any race. Nil if no run was completed.
    let fastestRun: TimeInterval?

    // The single station type that improved the most this month
    // (vs the athlete's window of recent attempts). Nil when no
    // station has a meaningful trend in the recap window — the
    // recap view falls back to a quieter "consistent training"
    // copy in that case.
    let biggestMover: BiggestMover?

    // Longest streak any day in the month — peaks during the
    // month. Doesn't have to end on the last day.
    let streakPeak: Int

    struct BiggestMover: Sendable, Equatable, Hashable {
        let station: Station
        let percentChange: Double  // unsigned
    }

    // Localized display of the month name + year — "April 2026".
    var displayName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthStart)
    }

    // Just the month name — "April" — used in heroes where the
    // year sits beside it as a small sub-label.
    var monthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: monthStart)
    }

    var yearLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: monthStart)
    }
}

// Aggregator. Walks finished races, partitions by calendar month,
// computes per-month stats, returns them sorted newest-first.
//
// Cheap O(n × stations) — the inner loops iterate splits which
// max out at 16 per race. At any practical history size (hundreds
// of races) this is sub-millisecond and runs every Profile render.
enum MonthlyRecapBuilder {

    // Build all monthly recaps available from the given races.
    // Returns newest-first so the most recent month leads.
    static func buildAll(
        from races: [Race],
        calendar: Calendar = .current
    ) -> [MonthlyRecap] {
        let finished = races.filter { $0.endedAt != nil }

        // Group by (year, month) start date.
        var groups: [Date: [Race]] = [:]
        for race in finished {
            guard let end = race.endedAt else { continue }
            let comps = calendar.dateComponents([.year, .month], from: end)
            guard let monthStart = calendar.date(from: comps) else { continue }
            groups[monthStart, default: []].append(race)
        }

        return groups
            .map { (monthStart, racesInMonth) in
                build(monthStart: monthStart, races: racesInMonth, allRaces: finished)
            }
            .sorted { $0.monthStart > $1.monthStart }
    }

    // Build a recap for a single month. `allRaces` is the full
    // history — needed to evaluate per-month trends and PB-status
    // against earlier races. `racesInMonth` is the subset.
    private static func build(
        monthStart: Date,
        races racesInMonth: [Race],
        allRaces: [Race]
    ) -> MonthlyRecap {
        let raceCount = racesInMonth.count
        let totalDuration = racesInMonth.reduce(0.0) {
            $0 + ($1.totalDuration ?? 0)
        }
        let fastestTotal = racesInMonth
            .compactMap(\.totalDuration)
            .min()

        // PBs SET this month — i.e. races whose total time was the
        // best at the moment they were saved, evaluated against
        // the cumulative history (RaceStats.wasPBWhenSet).
        let totalTimePBCount = racesInMonth.filter { race in
            RaceStats.wasPBWhenSet(race, among: allRaces)
        }.count

        let calories: Double? = {
            let allKcal = racesInMonth.compactMap(RaceStats.totalActiveCalories)
            guard !allKcal.isEmpty else { return nil }
            return allKcal.reduce(0, +)
        }()

        // Fastest 1km run anywhere in the month.
        let fastestRun: TimeInterval? = racesInMonth
            .flatMap(\.splits)
            .filter { $0.station.kind == .run }
            .map(\.duration)
            .min()

        // Biggest improver: walk every canonical station type, take
        // the one whose stationTrendDirection has the largest
        // unsigned improving percentage. We only consider improving
        // (not declining) for the recap brag — declining stations
        // already surface on the Performance Overload section.
        var topStation: Station?
        var topImprovement: Double = 0
        for station in Station.canonicalPickerOptions {
            let direction = RaceStats.stationTrendDirection(
                for: station,
                among: allRaces
            )
            if case .improving(let pct) = direction, pct > topImprovement {
                topImprovement = pct
                topStation = station
            }
        }
        let biggestMover: MonthlyRecap.BiggestMover? = topStation.map {
            .init(station: $0, percentChange: topImprovement)
        }

        // Streak peak — the longest consecutive-day run anywhere
        // within this month. We restrict the streak helper to races
        // ending in this month to keep "streak peak in April" from
        // being polluted by a 30-day streak that started in March.
        let streakPeak = RaceStreaks.longestStreak(in: racesInMonth)

        return MonthlyRecap(
            monthStart: monthStart,
            raceCount: raceCount,
            totalDuration: totalDuration,
            fastestTotal: fastestTotal,
            totalTimePBCount: totalTimePBCount,
            totalCalories: calories,
            fastestRun: fastestRun,
            biggestMover: biggestMover,
            streakPeak: streakPeak
        )
    }
}

// Convenience for ProfileView's banner — fetch the recap for the
// month containing the most recent finished race. Returns nil when
// there are no finished races at all (so the banner stays hidden).
extension MonthlyRecap {
    static func mostRecent(
        from races: [Race],
        calendar: Calendar = .current
    ) -> MonthlyRecap? {
        MonthlyRecapBuilder.buildAll(from: races, calendar: calendar).first
    }
}
#endif

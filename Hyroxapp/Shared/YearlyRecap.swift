import Foundation

// Aggregated stats for a single calendar year of training. The
// per-year analog of MonthlyRecap — broader window, richer
// "growth over time" angle. One YearlyRecap value per year the
// athlete has at least one race in.
//
// Pure value type derived from `[Race]`. Like MonthlyRecap, this
// doesn't persist anything — it regenerates from the live store
// every Profile render so retroactive edits (rename a race, add
// a photo) flow through to past recaps automatically.
//
// Why a separate type rather than just MonthlyRecap × 12:
//   • Annual aggregates differ in shape — we care about
//     monthly-level sparkline data ("which months did I race
//     most in?") that's meaningless monthly.
//   • Best month, total months active, and longest single
//     streak ANY time in the year are year-level concepts.
//   • The shareable card is laid out differently — the year is
//     more reflective ("growth"), the month is more immediate
//     ("recap").
//
// Guarded `#if !os(watchOS)` because Race + RaceStats are iOS-only.
#if !os(watchOS)
struct YearlyRecap: Sendable, Equatable, Hashable {

    // The year this recap covers — represented as a Date at Jan 1
    // 00:00 of the user's calendar.
    let yearStart: Date

    // Headline counts.
    let raceCount: Int
    let totalDuration: TimeInterval

    // Best total time of the year. Nil when no races finished.
    let fastestTotal: TimeInterval?

    // Number of races in the year that set a NEW total-time PB at
    // the moment they were saved. Same predicate the per-card
    // trophy uses, so this number aligns with what the athlete
    // sees on their feed.
    let totalTimePBCount: Int

    // Total active calories across the year. Nil when no race had
    // calorie data (most likely on years before HealthKit shipped).
    let totalCalories: Double?

    // Fastest 1km run anywhere in the year, across any race.
    let fastestRun: TimeInterval?

    // The single station type that improved the most this year vs
    // the athlete's recent attempts. Same shape as MonthlyRecap's
    // BiggestMover.
    let biggestMover: BiggestMover?

    // Longest training-day streak anywhere in the year. The streak
    // doesn't need to end on Dec 31 — a peak of 14 days in
    // April-May counts.
    let streakPeak: Int

    // How many distinct calendar months the athlete raced in.
    // 12 = trained every month; 1 = clustered training. Useful as
    // a "consistency" cue for the share card.
    let monthsActive: Int

    // The single calendar month with the most finished races in
    // the year. Nil when no races. Used as a "best month" callout.
    let bestMonth: BestMonth?

    // Per-month race-count dictionary — keyed by month-of-year
    // index 1...12. Drives the sparkline visualization on the
    // recap view + share card. Entries with 0 races are omitted;
    // the rendering layer fills missing months with zeros.
    let racesByMonth: [Int: Int]

    struct BiggestMover: Sendable, Equatable, Hashable {
        let station: Station
        let percentChange: Double
    }

    struct BestMonth: Sendable, Equatable, Hashable {
        let monthIndex: Int  // 1...12
        let raceCount: Int

        var displayName: String {
            DateFormatter().monthSymbols[monthIndex - 1]
        }
    }

    var displayName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: yearStart)
    }
}

enum YearlyRecapBuilder {

    // Build all annual recaps available from the given races.
    // Returns newest-first so the most recent year leads.
    static func buildAll(
        from races: [Race],
        calendar: Calendar = .current
    ) -> [YearlyRecap] {
        let finished = races.filter { $0.endedAt != nil }

        // Group by calendar year.
        var groups: [Date: [Race]] = [:]
        for race in finished {
            guard let end = race.endedAt else { continue }
            let comps = calendar.dateComponents([.year], from: end)
            guard let yearStart = calendar.date(from: comps) else { continue }
            groups[yearStart, default: []].append(race)
        }

        return groups
            .map { (yearStart, racesInYear) in
                build(yearStart: yearStart, races: racesInYear, allRaces: finished, calendar: calendar)
            }
            .sorted { $0.yearStart > $1.yearStart }
    }

    // Convenience for ProfileView's banner — fetch the most recent
    // year's recap, or nil when no finished races exist.
    static func mostRecent(
        from races: [Race],
        calendar: Calendar = .current
    ) -> YearlyRecap? {
        buildAll(from: races, calendar: calendar).first
    }

    private static func build(
        yearStart: Date,
        races racesInYear: [Race],
        allRaces: [Race],
        calendar: Calendar
    ) -> YearlyRecap {
        let raceCount = racesInYear.count
        let totalDuration = racesInYear.reduce(0.0) {
            $0 + ($1.totalDuration ?? 0)
        }
        let fastestTotal = racesInYear.compactMap(\.totalDuration).min()

        let totalTimePBCount = racesInYear.filter { race in
            RaceStats.wasPBWhenSet(race, among: allRaces)
        }.count

        let calories: Double? = {
            let allKcal = racesInYear.compactMap(RaceStats.totalActiveCalories)
            guard !allKcal.isEmpty else { return nil }
            return allKcal.reduce(0, +)
        }()

        let fastestRun: TimeInterval? = racesInYear
            .flatMap(\.splits)
            .filter { $0.station.kind == .run }
            .map(\.duration)
            .min()

        // Biggest mover — same logic as MonthlyRecap. Improving
        // stations only; biggest absolute % change wins.
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
        let biggestMover: YearlyRecap.BiggestMover? = topStation.map {
            .init(station: $0, percentChange: topImprovement)
        }

        // Streak peak within the year — restrict to in-year races
        // so a December → January spillover doesn't double-count.
        let streakPeak = RaceStreaks.longestStreak(in: racesInYear)

        // Per-month race count + best-month calculation.
        var racesByMonth: [Int: Int] = [:]
        for race in racesInYear {
            guard let end = race.endedAt else { continue }
            let monthIndex = calendar.component(.month, from: end)
            racesByMonth[monthIndex, default: 0] += 1
        }
        let monthsActive = racesByMonth.keys.count
        let bestMonth: YearlyRecap.BestMonth? = racesByMonth
            .max { $0.value < $1.value }
            .map { (key, value) in
                .init(monthIndex: key, raceCount: value)
            }

        return YearlyRecap(
            yearStart: yearStart,
            raceCount: raceCount,
            totalDuration: totalDuration,
            fastestTotal: fastestTotal,
            totalTimePBCount: totalTimePBCount,
            totalCalories: calories,
            fastestRun: fastestRun,
            biggestMover: biggestMover,
            streakPeak: streakPeak,
            monthsActive: monthsActive,
            bestMonth: bestMonth,
            racesByMonth: racesByMonth
        )
    }
}
#endif

import Testing
import Foundation
@testable import Hyroxapp

// Tests for the monthly + yearly recap aggregators. These power
// the Profile banners and the shareable cards. Critical to get
// right because they're the user-facing "look back at your
// training" surfaces.

@Suite("MonthlyRecap")
struct MonthlyRecapTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // Race ending at the given (year, month, day) at 12:00 UTC.
    private func race(
        year: Int,
        month: Int,
        day: Int,
        durationSeconds: TimeInterval = 5400  // 1:30:00 default
    ) -> Race {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        let end = calendar.date(from: comps)!
        return Race(
            startedAt: end.addingTimeInterval(-durationSeconds),
            endedAt: end
        )
    }

    @Test("buildAll with no races returns empty")
    func empty() {
        let recaps = MonthlyRecapBuilder.buildAll(from: [], calendar: calendar)
        #expect(recaps.isEmpty)
    }

    @Test("groups races by calendar month")
    func groupsByMonth() {
        let races = [
            race(year: 2026, month: 4, day: 5),
            race(year: 2026, month: 4, day: 20),
            race(year: 2026, month: 3, day: 28)
        ]
        let recaps = MonthlyRecapBuilder.buildAll(from: races, calendar: calendar)
        #expect(recaps.count == 2)

        // Sorted newest first → April leads.
        #expect(recaps[0].raceCount == 2)
        #expect(recaps[1].raceCount == 1)
    }

    @Test("totalDuration sums across the month")
    func totalDuration() {
        let races = [
            race(year: 2026, month: 4, day: 5, durationSeconds: 5400),
            race(year: 2026, month: 4, day: 12, durationSeconds: 4800)
        ]
        let recaps = MonthlyRecapBuilder.buildAll(from: races, calendar: calendar)
        #expect(recaps.first?.totalDuration == 10200)
    }

    @Test("fastestTotal picks the shortest race")
    func fastestTotal() {
        let races = [
            race(year: 2026, month: 4, day: 1, durationSeconds: 5400),
            race(year: 2026, month: 4, day: 8, durationSeconds: 4500),
            race(year: 2026, month: 4, day: 15, durationSeconds: 5000)
        ]
        let recaps = MonthlyRecapBuilder.buildAll(from: races, calendar: calendar)
        #expect(recaps.first?.fastestTotal == 4500)
    }

    @Test("unfinished races excluded")
    func unfinishedExcluded() {
        let inProgress = Race(startedAt: Date())
        let recaps = MonthlyRecapBuilder.buildAll(
            from: [inProgress],
            calendar: calendar
        )
        #expect(recaps.isEmpty)
    }
}

@Suite("YearlyRecap")
struct YearlyRecapTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func race(
        year: Int,
        month: Int,
        day: Int = 15,
        durationSeconds: TimeInterval = 5400
    ) -> Race {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        let end = calendar.date(from: comps)!
        return Race(
            startedAt: end.addingTimeInterval(-durationSeconds),
            endedAt: end
        )
    }

    @Test("buildAll groups races by calendar year")
    func groupsByYear() {
        let races = [
            race(year: 2026, month: 1),
            race(year: 2026, month: 6),
            race(year: 2025, month: 12)
        ]
        let recaps = YearlyRecapBuilder.buildAll(from: races, calendar: calendar)
        #expect(recaps.count == 2)
        #expect(recaps[0].raceCount == 2)  // 2026
        #expect(recaps[1].raceCount == 1)  // 2025
    }

    @Test("monthsActive counts distinct months")
    func monthsActive() {
        let races = [
            race(year: 2026, month: 1),
            race(year: 2026, month: 1),  // same month — dedupe
            race(year: 2026, month: 4),
            race(year: 2026, month: 7)
        ]
        let recaps = YearlyRecapBuilder.buildAll(from: races, calendar: calendar)
        #expect(recaps.first?.monthsActive == 3)
    }

    @Test("racesByMonth dictionary keyed 1...12")
    func racesByMonthKeys() {
        let races = [
            race(year: 2026, month: 1),
            race(year: 2026, month: 1),
            race(year: 2026, month: 7)
        ]
        let recap = YearlyRecapBuilder.buildAll(
            from: races,
            calendar: calendar
        ).first!

        #expect(recap.racesByMonth[1] == 2)
        #expect(recap.racesByMonth[7] == 1)
        #expect(recap.racesByMonth[3] == nil)  // empty months absent
    }

    @Test("bestMonth picks month with most races")
    func bestMonth() {
        let races = [
            race(year: 2026, month: 1),
            race(year: 2026, month: 6),
            race(year: 2026, month: 6),
            race(year: 2026, month: 6),
            race(year: 2026, month: 9)
        ]
        let recap = YearlyRecapBuilder.buildAll(
            from: races,
            calendar: calendar
        ).first!
        #expect(recap.bestMonth?.monthIndex == 6)
        #expect(recap.bestMonth?.raceCount == 3)
    }

    @Test("mostRecent returns the most recent year only")
    func mostRecentOnly() {
        let races = [
            race(year: 2026, month: 1),
            race(year: 2025, month: 12)
        ]
        let recap = YearlyRecapBuilder.mostRecent(from: races, calendar: calendar)
        #expect(recap?.displayName == "2026")
    }
}

import Testing
import Foundation
@testable import Hyroxapp

// Tests for `RaceStreaks` — the day-streak helper that drives the
// flame banner on Profile + the streak-protection notification.
//
// Driven by injected calendars + reference dates so we don't have to
// fight system time. Every test builds a `Calendar` and a fixed
// `referenceDate`, hands them to the helper alongside hand-crafted
// `Race` rows, and asserts on the count.

@Suite("RaceStreaks")
struct RaceStreaksTests {

    // MARK: - Helpers

    // Build a finished race ending at `endDate`. Splits and other
    // fields are irrelevant for streak math, so we keep the row
    // minimal — only `endedAt` (which gates "is finished") and
    // the date itself matter.
    private func finishedRace(endingAt endDate: Date) -> Race {
        let race = Race(
            startedAt: endDate.addingTimeInterval(-3600),
            endedAt: endDate
        )
        return race
    }

    // Stable calendar for tests — UTC + Gregorian so the math is
    // independent of where the test runner happens to live.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // Fixed "today" — Wed 2026-04-15 12:00 UTC.
    private var today: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 15
        comps.hour = 12
        return calendar.date(from: comps)!
    }

    private func days(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    // MARK: - currentStreak

    @Test("currentStreak is 0 when no races")
    func zeroWithNoRaces() {
        let streak = RaceStreaks.currentStreak(
            in: [],
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 0)
    }

    @Test("currentStreak is 0 when most recent race is older than yesterday")
    func zeroWhenStale() {
        // Last race 3 days ago — streak already broken.
        let races = [finishedRace(endingAt: days(-3))]
        let streak = RaceStreaks.currentStreak(
            in: races,
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 0)
    }

    @Test("currentStreak is 1 when only today has a race")
    func oneDayStreakToday() {
        let races = [finishedRace(endingAt: today)]
        let streak = RaceStreaks.currentStreak(
            in: races,
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 1)
    }

    @Test("currentStreak counts back through consecutive days")
    func consecutiveDays() {
        // Trained today, yesterday, day before, day before that = 4.
        let races = [
            finishedRace(endingAt: days(0)),
            finishedRace(endingAt: days(-1)),
            finishedRace(endingAt: days(-2)),
            finishedRace(endingAt: days(-3))
        ]
        let streak = RaceStreaks.currentStreak(
            in: races,
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 4)
    }

    @Test("currentStreak stops at gap")
    func stopsAtGap() {
        // Today, yesterday, [gap on day -2], -3, -4. Streak = 2.
        let races = [
            finishedRace(endingAt: days(0)),
            finishedRace(endingAt: days(-1)),
            finishedRace(endingAt: days(-3)),
            finishedRace(endingAt: days(-4))
        ]
        let streak = RaceStreaks.currentStreak(
            in: races,
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 2)
    }

    @Test("currentStreak counts when most recent is yesterday")
    func yesterdayCounts() {
        // Trained yesterday + day before — streak still alive.
        let races = [
            finishedRace(endingAt: days(-1)),
            finishedRace(endingAt: days(-2))
        ]
        let streak = RaceStreaks.currentStreak(
            in: races,
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 2)
    }

    @Test("multiple races on same day count as one")
    func sameDayDeduped() {
        // Two races today — still just "today's training day."
        let races = [
            finishedRace(endingAt: today.addingTimeInterval(-7200)),
            finishedRace(endingAt: today),
            finishedRace(endingAt: days(-1))
        ]
        let streak = RaceStreaks.currentStreak(
            in: races,
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 2)
    }

    @Test("unfinished races are ignored")
    func unfinishedIgnored() {
        // One in-progress race today, no finished races. Streak = 0.
        let inProgress = Race(startedAt: today)
        let streak = RaceStreaks.currentStreak(
            in: [inProgress],
            referenceDate: today,
            calendar: calendar
        )
        #expect(streak == 0)
    }

    // MARK: - longestStreak

    @Test("longestStreak is 0 when no races")
    func longestZero() {
        #expect(RaceStreaks.longestStreak(in: [], calendar: calendar) == 0)
    }

    @Test("longestStreak is 1 with single race")
    func longestSingle() {
        let races = [finishedRace(endingAt: today)]
        #expect(RaceStreaks.longestStreak(in: races, calendar: calendar) == 1)
    }

    @Test("longestStreak finds peak run anywhere in history")
    func longestFindsPeak() {
        // Two clusters: a 3-day run, then gap, then a 5-day run, then
        // gap, then today. Peak should be 5.
        let races = [
            finishedRace(endingAt: days(-30)),
            finishedRace(endingAt: days(-29)),
            finishedRace(endingAt: days(-28)),

            finishedRace(endingAt: days(-20)),
            finishedRace(endingAt: days(-19)),
            finishedRace(endingAt: days(-18)),
            finishedRace(endingAt: days(-17)),
            finishedRace(endingAt: days(-16)),

            finishedRace(endingAt: days(0))
        ]
        #expect(RaceStreaks.longestStreak(in: races, calendar: calendar) == 5)
    }
}

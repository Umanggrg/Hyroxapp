import Foundation

// Pure helper that derives training streaks from race history.
// Strava-style "X day streak" — counts consecutive calendar days
// on which the athlete completed at least one race (any kind:
// full HYROX simulation, custom workout, doesn't matter).
//
// The unit is the local-calendar day in the user's current
// timezone. A race that ended at 11:55pm on Monday and one that
// ended at 12:05am on Tuesday count as two separate days even
// though they're 10 minutes apart — that's the social-app
// expectation everyone shares with Strava / Duolingo / etc.
//
// Two flavors:
//   • currentStreak — days leading up to (and including) today,
//     ending if there's a gap. Returns 0 if the most recent
//     training day is older than yesterday — i.e. the streak has
//     already broken.
//   • longestStreak — the longest run of consecutive training
//     days anywhere in the history. Used as a "best" subtitle.
//
// Guarded `#if !os(watchOS)` because the input type `Race` is
// iOS-only (matches BadgeAwarder's pattern).
#if !os(watchOS)
enum RaceStreaks {

    static func currentStreak(
        in races: [Race],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let trainingDays = trainingDaySet(from: races, calendar: calendar)
        guard !trainingDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return 0
        }

        // Streak only counts when the most recent training day is
        // today or yesterday. If the last race was 2+ days ago the
        // streak has already broken regardless of how long it ran.
        guard let mostRecent = trainingDays.max() else { return 0 }
        guard mostRecent == today || mostRecent == yesterday else { return 0 }

        // Walk backward from the most recent training day, counting
        // each consecutive calendar day that's also in the set.
        // Stops at the first gap.
        var streak = 0
        var cursor: Date? = mostRecent
        while let day = cursor, trainingDays.contains(day) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        return streak
    }

    static func longestStreak(
        in races: [Race],
        calendar: Calendar = .current
    ) -> Int {
        let trainingDays = trainingDaySet(from: races, calendar: calendar)
            .sorted()
        guard !trainingDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in 1..<trainingDays.count {
            let prev = trainingDays[index - 1]
            let curr = trainingDays[index]
            // "Consecutive" means prev's date + 1 day == curr's
            // date. Because the set already de-duplicated days,
            // this comparison can never match within the same day.
            if let next = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(next, inSameDayAs: curr) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    // De-duplicate races down to the unique calendar days they
    // ended on. Unfinished races (endedAt == nil) are excluded —
    // an in-progress / abandoned race shouldn't count toward a
    // streak.
    private static func trainingDaySet(
        from races: [Race],
        calendar: Calendar
    ) -> Set<Date> {
        Set(races.compactMap { race -> Date? in
            guard let end = race.endedAt else { return nil }
            return calendar.startOfDay(for: end)
        })
    }
}
#endif

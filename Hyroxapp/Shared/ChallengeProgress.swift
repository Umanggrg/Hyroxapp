import Foundation

// Pure helper that evaluates a Challenge against a race history.
// Lives in Shared/ alongside RaceStats / RaceStreaks / etc. so the
// evaluation logic stays unit-testable and view-independent.
//
// Returns a `Progress` value carrying the current count, the
// target, and a normalized fraction (0.0 → 1.0+). Letting the
// caller see the raw current value AND the fraction means the UI
// can render "3 / 5 races" + a 60% progress bar from the same
// helper call without two passes through the data.
//
// `isComplete` is just `fraction >= 1.0`. Caller is responsible
// for setting `Challenge.completedAt` when the evaluator first
// reports complete; the evaluator itself is read-only.
//
// Guarded `#if !os(watchOS)` because Race / Challenge are iOS-only
// SwiftData @Models. The watch doesn't see challenges.
#if !os(watchOS)
enum ChallengeProgress {

    // Bundled progress readout. Each field is independently useful
    // — the UI shows current/target as a numeric line and fraction
    // as the progress-bar fill width.
    struct Progress: Sendable, Equatable {
        // Current value the athlete has accumulated, in the
        // challenge's units (count for raceCount, seconds for
        // fastestRace, days for streakLength).
        let currentValue: Double

        // Target the athlete committed to. Same units as current.
        let targetValue: Double

        // Normalized fraction. Goes >1.0 when the athlete blew
        // past their target (e.g. set "5 races" target, raced 7).
        // The UI typically clamps to 1.0 for the bar fill but
        // shows the raw current/target for the headline number.
        let fraction: Double

        var isComplete: Bool {
            fraction >= 1.0
        }
    }

    // Evaluate a Challenge against the athlete's race history.
    // referenceDate is injectable for testing — defaults to now.
    static func evaluate(
        _ challenge: Challenge,
        races: [Race],
        referenceDate: Date = Date()
    ) -> Progress {
        // Restrict the race set to ones falling inside the
        // challenge window. SwiftData hands us all races; we
        // filter here so each evaluator branch can assume its
        // input is already scoped to the right time period.
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: challenge.startDate)
        // Use end-of-day for endDate so a race finishing at 11:55pm
        // on the deadline still counts.
        let windowEnd = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: challenge.endDate
        ) ?? challenge.endDate

        let inWindow = races.filter { race in
            guard let endedAt = race.endedAt else { return false }
            return endedAt >= windowStart && endedAt <= windowEnd
        }

        switch challenge.challengeType {
        case .raceCount:
            return raceCountProgress(
                target: challenge.targetValue,
                inWindow: inWindow
            )
        case .fastestRace:
            return fastestRaceProgress(
                target: challenge.targetValue,
                inWindow: inWindow
            )
        case .streakLength:
            return streakLengthProgress(
                target: challenge.targetValue,
                allRaces: races,
                challenge: challenge,
                referenceDate: referenceDate
            )
        }
    }

    // MARK: - Per-type evaluators

    // raceCount: how many finished races fall inside the window?
    private static func raceCountProgress(
        target: Double,
        inWindow: [Race]
    ) -> Progress {
        let count = Double(inWindow.count)
        return Progress(
            currentValue: count,
            targetValue: target,
            fraction: target > 0 ? count / target : 0
        )
    }

    // fastestRace: did the athlete log a finished race inside the
    // window with totalDuration <= target?
    //
    // currentValue is the BEST (fastest) total time inside the
    // window — that's what the athlete cares about: "your fastest
    // race so far this month was X." If no races inside the
    // window, currentValue is `Double.infinity` so the fraction
    // calculation drops to 0.
    //
    // fraction is computed inversely: target / current. When
    // current <= target, fraction >= 1.0 (complete). When current
    // is way slower than target, fraction is small. The UI bar
    // grows as the athlete gets closer to the target time.
    private static func fastestRaceProgress(
        target: Double,
        inWindow: [Race]
    ) -> Progress {
        let times = inWindow.compactMap(\.totalDuration)
        let fastest = times.min() ?? .infinity

        // Defensive — if target is 0 we'd divide by zero. Treat as
        // already-complete (a 0-second target is meaningless).
        guard target > 0 else {
            return Progress(currentValue: fastest, targetValue: target, fraction: 1.0)
        }

        // For a non-finite "fastest" (no races yet), fraction is 0.
        // Otherwise inverse: target/current. Cap fraction at 2.0 to
        // avoid weirdly huge numbers if the athlete crushes a goal
        // wildly (e.g. target 1:30 hit at 0:45 would give fraction 2).
        let fraction: Double = {
            guard fastest.isFinite, fastest > 0 else { return 0 }
            return min(2.0, target / fastest)
        }()

        return Progress(
            currentValue: fastest,
            targetValue: target,
            fraction: fraction
        )
    }

    // streakLength: longest consecutive-day streak the athlete has
    // achieved inside the window. Reuses the existing RaceStreaks
    // helper for consistency with the rest of the app's streak math.
    private static func streakLengthProgress(
        target: Double,
        allRaces: [Race],
        challenge: Challenge,
        referenceDate: Date
    ) -> Progress {
        // Only races inside the window contribute to a streak
        // counted toward THIS challenge. Without that scoping, an
        // ancient streak before the challenge started would
        // pre-complete a fresh challenge.
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: challenge.startDate)
        let windowEnd = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: challenge.endDate
        ) ?? challenge.endDate

        let inWindow = allRaces.filter { race in
            guard let endedAt = race.endedAt else { return false }
            return endedAt >= windowStart && endedAt <= windowEnd
        }

        let longest = Double(RaceStreaks.longestStreak(in: inWindow))
        return Progress(
            currentValue: longest,
            targetValue: target,
            fraction: target > 0 ? longest / target : 0
        )
    }
}
#endif

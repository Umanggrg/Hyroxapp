import Foundation

// Pure helper that decides which badges an athlete has earned
// based on their race history + saved workout templates.
//
// One static entry point: `evaluate(races:templates:)` returns a
// `Set<Badge>` of everything currently earned. Re-evaluated on
// every Profile render — cheap because the criteria are simple
// reductions over the races array.
//
// Each criterion is its own private function so adding new badge
// types later is a one-place change: add a case to Badge, add a
// case to the switch in `evaluate`, write the criterion func.
//
// Guarded `#if !os(watchOS)` because the Race-dependent helpers
// (totalDuration, isFinished, RaceStats.wasPBSplit) only compile
// on iOS — same pattern used elsewhere in RaceStats.
#if !os(watchOS)
enum BadgeAwarder {

    static func evaluate(
        races: [Race],
        templates: [WorkoutTemplate]
    ) -> Set<Badge> {
        var earned = Set<Badge>()
        for badge in Badge.allCases {
            if isEarned(badge, races: races, templates: templates) {
                earned.insert(badge)
            }
        }
        return earned
    }

    // Single-badge check. Pulled out as a switch over the enum so
    // the compiler enforces exhaustiveness — adding a new Badge
    // case here will fail the build until a criterion is provided.
    private static func isEarned(
        _ badge: Badge,
        races: [Race],
        templates: [WorkoutTemplate]
    ) -> Bool {
        switch badge {
        case .firstRace:
            return finishedRaceCount(races) >= 1
        case .subOneThirty:
            return hasFinishedUnder(seconds: 90 * 60, races: races)
        case .subOneFifteen:
            return hasFinishedUnder(seconds: 75 * 60, races: races)
        case .tenRaces:
            return finishedRaceCount(races) >= 10
        case .allStationsPB:
            return hasPerfectPBRace(races: races)
        case .customCrafter:
            return templates.count >= 3
        }
    }

    // MARK: - Criteria

    private static func finishedRaceCount(_ races: [Race]) -> Int {
        races.filter(\.isFinished).count
    }

    // True if any finished race's totalDuration is under the given
    // second threshold. Sub-1:30 / sub-1:15 use this same check
    // with different thresholds.
    private static func hasFinishedUnder(
        seconds: TimeInterval,
        races: [Race]
    ) -> Bool {
        races
            .compactMap(\.totalDuration)
            .contains(where: { $0 < seconds })
    }

    // True if at least one finished race is "perfect" — every
    // single split in that race set a new station PB at the
    // moment it was completed. The kind of race where everything
    // clicked: faster sled push than ever, faster wall balls
    // than ever, all in the same session.
    private static func hasPerfectPBRace(races: [Race]) -> Bool {
        let finished = races.filter(\.isFinished)
        return finished.contains { race in
            // Race must have splits, and every split must be a PB.
            !race.splits.isEmpty && race.splits.allSatisfy { split in
                RaceStats.wasPBSplit(split, in: race, among: races)
            }
        }
    }
}
#endif

import Testing
import Foundation
@testable import Hyroxapp

// Tests for `BadgeAwarder` — the criteria-evaluator that decides
// which milestone badges the athlete has earned. Same fixed-date
// approach as RaceStreaksTests; we hand-craft Race rows with the
// fields the criteria depend on.

@Suite("BadgeAwarder")
struct BadgeAwarderTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // Build a finished race with a specific total duration. Other
    // criteria (perfect-day, custom-crafter) need different shapes
    // — built ad-hoc per test.
    private func finishedRace(
        durationSeconds: TimeInterval,
        startOffset: TimeInterval = 0
    ) -> Race {
        let start = t0.addingTimeInterval(startOffset)
        return Race(
            startedAt: start,
            endedAt: start.addingTimeInterval(durationSeconds)
        )
    }

    // MARK: - firstRace

    @Test("firstRace earned after one finished race")
    func firstRaceEarned() {
        let race = finishedRace(durationSeconds: 6000)
        let earned = BadgeAwarder.evaluate(races: [race], templates: [])
        #expect(earned.contains(.firstRace))
    }

    @Test("firstRace not earned with only unfinished races")
    func firstRaceNotEarnedUnfinished() {
        let inProgress = Race(startedAt: t0)
        let earned = BadgeAwarder.evaluate(races: [inProgress], templates: [])
        #expect(!earned.contains(.firstRace))
    }

    // MARK: - subOneThirty / subOneFifteen

    @Test("subOneThirty earned when any race finishes under 90 min")
    func subOneThirtyEarned() {
        let race = finishedRace(durationSeconds: 89 * 60)  // 1:29:00
        let earned = BadgeAwarder.evaluate(races: [race], templates: [])
        #expect(earned.contains(.subOneThirty))
    }

    @Test("subOneThirty not earned at exactly 90 min (strict <)")
    func subOneThirtyNotAtBoundary() {
        let race = finishedRace(durationSeconds: 90 * 60)
        let earned = BadgeAwarder.evaluate(races: [race], templates: [])
        #expect(!earned.contains(.subOneThirty))
    }

    @Test("subOneFifteen earned when any race finishes under 75 min")
    func subOneFifteenEarned() {
        let race = finishedRace(durationSeconds: 74 * 60 + 30)  // 1:14:30
        let earned = BadgeAwarder.evaluate(races: [race], templates: [])
        #expect(earned.contains(.subOneFifteen))
        // Sub 1:15 implies sub 1:30 too.
        #expect(earned.contains(.subOneThirty))
    }

    // MARK: - tenRaces

    @Test("tenRaces earned at exactly 10 finished races")
    func tenRacesEarned() {
        let races = (0..<10).map {
            finishedRace(durationSeconds: 6000, startOffset: TimeInterval($0) * 86400)
        }
        let earned = BadgeAwarder.evaluate(races: races, templates: [])
        #expect(earned.contains(.tenRaces))
    }

    @Test("tenRaces not earned at 9")
    func tenRacesNotAtNine() {
        let races = (0..<9).map {
            finishedRace(durationSeconds: 6000, startOffset: TimeInterval($0) * 86400)
        }
        let earned = BadgeAwarder.evaluate(races: races, templates: [])
        #expect(!earned.contains(.tenRaces))
    }

    // MARK: - customCrafter

    @Test("customCrafter earned at exactly 3 templates")
    func customCrafterEarned() {
        let templates = [
            WorkoutTemplate(name: "A", sequence: [.run1, .sledPush]),
            WorkoutTemplate(name: "B", sequence: [.run1, .sledPull]),
            WorkoutTemplate(name: "C", sequence: [.run1, .wallBalls])
        ]
        let earned = BadgeAwarder.evaluate(races: [], templates: templates)
        #expect(earned.contains(.customCrafter))
    }

    @Test("customCrafter not earned at 2")
    func customCrafterNotAtTwo() {
        let templates = [
            WorkoutTemplate(name: "A", sequence: [.run1, .sledPush]),
            WorkoutTemplate(name: "B", sequence: [.run1, .sledPull])
        ]
        let earned = BadgeAwarder.evaluate(races: [], templates: templates)
        #expect(!earned.contains(.customCrafter))
    }

    // MARK: - Empty state

    @Test("no badges earned with empty history")
    func emptyEarnsNothing() {
        let earned = BadgeAwarder.evaluate(races: [], templates: [])
        #expect(earned.isEmpty)
    }
}

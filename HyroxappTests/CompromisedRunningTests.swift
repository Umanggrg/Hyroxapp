import Testing
import Foundation
@testable import Hyroxapp

// Tests for the HYROX-specific compromised-running analysis —
// the killer-feature differentiator we layered on top of basic
// run-fatigue tracking.

@Suite("Compromised running analysis")
struct CompromisedRunningTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // Build a race with a custom split sequence + per-run
    // durations. Workout durations are fixed (we don't care
    // about them for compromise-from-baseline math) — only
    // run durations matter.
    private func race(
        sequence: [Station],
        runDurations: [TimeInterval],
        workoutDuration: TimeInterval = 240
    ) -> Race {
        var splits: [Split] = []
        var cursor = t0
        var runIndex = 0

        for station in sequence {
            let duration: TimeInterval = (station.kind == .run)
                ? runDurations[runIndex]
                : workoutDuration

            splits.append(Split(
                station: station,
                startedAt: cursor,
                endedAt: cursor.addingTimeInterval(duration)
            ))
            cursor = cursor.addingTimeInterval(duration)

            if station.kind == .run {
                runIndex += 1
            }
        }

        return Race(
            startedAt: t0,
            endedAt: cursor,
            splits: splits,
            sequence: sequence
        )
    }

    // MARK: - compromisedRunData

    @Test("empty race produces empty data")
    func emptyRace() {
        let r = Race(startedAt: t0, endedAt: t0)
        #expect(RaceStats.compromisedRunData(for: r).isEmpty)
    }

    @Test("baseline run has 0% slowdown")
    func baselineZero() {
        let r = race(
            sequence: [.run1, .sledPush, .run2],
            runDurations: [300, 360]  // R1 5:00 baseline, R2 6:00 (+20%)
        )
        let data = RaceStats.compromisedRunData(for: r)
        #expect(data.count == 2)
        #expect(data[0].percentSlower == 0)  // baseline
        #expect(data[0].precedingStation == nil)
    }

    @Test("non-baseline runs compute percent slower against R1")
    func slowdownMath() {
        let r = race(
            sequence: [.run1, .sledPush, .run2, .sledPull, .run3],
            runDurations: [300, 360, 330]  // R1=5:00, R2=6:00, R3=5:30
        )
        let data = RaceStats.compromisedRunData(for: r)
        #expect(data.count == 3)
        // R2 = (360-300)/300 = 20%
        #expect(abs(data[1].percentSlower - 20.0) < 0.001)
        // R3 = (330-300)/300 = 10%
        #expect(abs(data[2].percentSlower - 10.0) < 0.001)
    }

    @Test("each non-baseline run carries its preceding workout station")
    func precedingAttribution() {
        let r = race(
            sequence: [.run1, .sledPush, .run2, .sledPull, .run3],
            runDurations: [300, 360, 330]
        )
        let data = RaceStats.compromisedRunData(for: r)
        #expect(data[1].precedingStation == .sledPush)
        #expect(data[2].precedingStation == .sledPull)
    }

    @Test("biggestCompromisedRun finds the slowest")
    func biggestFindsSlowest() {
        let r = race(
            sequence: [.run1, .sledPush, .run2, .sledPull, .run3],
            runDurations: [300, 330, 360]  // R3 (after Sled Pull) is slowest
        )
        let biggest = RaceStats.biggestCompromisedRun(for: r)
        #expect(biggest != nil)
        #expect(biggest?.runIndex == 3)
        #expect(biggest?.precedingStation == .sledPull)
    }

    @Test("biggestCompromisedRun nil when only baseline run")
    func biggestNilWithSingleRun() {
        let r = race(
            sequence: [.run1, .sledPush],
            runDurations: [300]
        )
        #expect(RaceStats.biggestCompromisedRun(for: r) == nil)
    }

    // MARK: - crossRaceCompromisedAnalysis

    @Test("cross-race aggregation averages per-station slowdowns")
    func crossRaceAvg() {
        // Two races. Both have Sled Push → Run 2.
        // Race 1: R1 5:00, R2 6:00 → 20% slowdown after Sled Push
        // Race 2: R1 5:00, R2 5:30 → 10% slowdown after Sled Push
        // Average: 15%
        let r1 = race(
            sequence: [.run1, .sledPush, .run2],
            runDurations: [300, 360]
        )
        let r2 = race(
            sequence: [.run1, .sledPush, .run2],
            runDurations: [300, 330]
        )
        let impacts = RaceStats.crossRaceCompromisedAnalysis(among: [r1, r2])

        let sledPushImpact = impacts.first { $0.station == .sledPush }
        #expect(sledPushImpact != nil)
        #expect(abs((sledPushImpact?.avgPercentSlower ?? 0) - 15.0) < 0.001)
        #expect(sledPushImpact?.sampleCount == 2)
    }

    @Test("cross-race results sorted by biggest impact first")
    func crossRaceSorted() {
        // Sled Pull does +30%; Sled Push does +10%. Pull should lead.
        let r1 = race(
            sequence: [.run1, .sledPush, .run2, .sledPull, .run3],
            runDurations: [300, 330, 390]  // +10%, +30%
        )
        let impacts = RaceStats.crossRaceCompromisedAnalysis(among: [r1])
        #expect(impacts.first?.station == .sledPull)
    }

    @Test("stations that never preceded a run are absent")
    func absentStations() {
        // Race ends on Wall Balls — no run follows it, so it
        // shouldn't appear in the impacts list.
        let r = race(
            sequence: [.run1, .wallBalls],
            runDurations: [300]
        )
        let impacts = RaceStats.crossRaceCompromisedAnalysis(among: [r])
        #expect(!impacts.contains { $0.station == .wallBalls })
    }
}

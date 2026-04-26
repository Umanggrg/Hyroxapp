import Testing
import Foundation
@testable import Hyroxapp

// Tests for the two-step Roxzone advance path on `RaceEngine`.
//
// Roxzone semantics in plain English:
//   1. While in `.inProgress`, calling `endSegment` closes the current
//      segment as a Split and transitions to `.inRoxzone` (the
//      transition timer is now running but no station is "active").
//   2. While in `.inRoxzone`, calling `startNextSegment` records the
//      transition duration as `pendingRoxzoneSeconds` and transitions
//      back to `.inProgress` on the next station.
//   3. When that next station closes (via `endSegment` again, or via
//      a single-tap `advance`), the pending roxzone is attached to
//      the closing Split — i.e. the roxzone TIME ATTACHES TO THE
//      SEGMENT IT PRECEDED, not to the one that just ended. This is
//      the HYROX convention ("Sled Push's roxzone is the time between
//      Run 1 and Sled Push").
//
// Like the rest of `RaceEngineTests`, these tests are fully
// deterministic — `Date` is injected at every call site, no clocks
// are mocked.

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

@Suite("RaceEngine — roxzone two-step advance")
struct RoxzoneEngineTests {

    @Test("endSegment from .inProgress moves to .inRoxzone and records the split")
    func endSegmentEntersRoxzone() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.endSegment(at: t(300)) // close run1 at 5:00

        #expect(engine.splits.count == 1)
        #expect(engine.splits.first?.station == .run1)
        #expect(engine.splits.first?.duration == 300)
        // Roxzone hasn't been timed yet — the just-closed segment
        // gets its roxzone (if any) from the preceding transition,
        // and run1 is the first station so it has none.
        #expect(engine.splits.first?.roxzoneSeconds == nil)

        // Engine is now in .inRoxzone — the next station hasn't
        // started yet but the transition timer is running.
        if case .inRoxzone = engine.state {
            // good
        } else {
            Issue.record("Expected .inRoxzone state, got \(engine.state)")
        }
    }

    @Test("startNextSegment from .inRoxzone returns to .inProgress with the next station")
    func startNextSegmentResumesProgress() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.endSegment(at: t(300))           // close run1 → .inRoxzone
        engine.startNextSegment(at: t(312))     // 12s roxzone, begin skiErg

        #expect(engine.currentStation == .skiErg)
        // Race time keeps accumulating through roxzone.
        #expect(engine.elapsed(at: t(312)) == 312)
    }

    @Test("roxzone duration is attached to the next segment, not the one just closed")
    func roxzoneAttributesToNextSegment() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.endSegment(at: t(300))           // run1 closes at 5:00
        engine.startNextSegment(at: t(312))     // 12s roxzone elapsed
        engine.endSegment(at: t(540))           // skiErg closes at 9:00 (3:48 segment)

        // Expect two splits.
        #expect(engine.splits.count == 2)

        // Run1 has no preceding roxzone (it's the first station).
        let run = engine.splits[0]
        #expect(run.station == .run1)
        #expect(run.roxzoneSeconds == nil)

        // skiErg's roxzoneSeconds is the 12s transition between run1 close
        // and skiErg start. The HYROX convention: roxzone attaches
        // to the station it preceded.
        let skiErg = engine.splits[1]
        #expect(skiErg.station == .skiErg)
        #expect(skiErg.roxzoneSeconds == 12)
        #expect(skiErg.duration == 228) // 540 - 312
    }

    @Test("advance after a roxzone still attaches the pending roxzone to the closing split")
    func advanceConsumesPendingRoxzone() {
        // Mixing the two-tap (endSegment + startNextSegment) and
        // single-tap (advance) APIs is allowed — the pendingRoxzoneSeconds
        // field is the connector. This protects users who toggle the
        // Roxzone setting mid-race or whose UI dispatches both kinds
        // of action on the same race.
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.endSegment(at: t(300))           // run1 closes
        engine.startNextSegment(at: t(315))     // 15s roxzone, begin skiErg
        engine.advance(at: t(540))              // single-tap close skiErg

        #expect(engine.splits.count == 2)
        #expect(engine.splits[1].station == .skiErg)
        #expect(engine.splits[1].roxzoneSeconds == 15)
        // After consuming, pendingRoxzoneSeconds should be cleared.
        #expect(engine.pendingRoxzoneSeconds == nil)
    }

    @Test("startNextSegment is a no-op when not in .inRoxzone")
    func startNextSegmentRequiresRoxzoneState() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.startNextSegment(at: t(50)) // garbage — engine is .inProgress

        // No state change.
        #expect(engine.currentStation == .run1)
        #expect(engine.pendingRoxzoneSeconds == nil)
    }

    @Test("endSegment is a no-op when not in .inProgress")
    func endSegmentRequiresInProgressState() {
        var engine = RaceEngine()
        // Calling endSegment on a fresh engine (.notStarted) is a no-op.
        engine.endSegment(at: t(50))
        #expect(engine.splits.isEmpty)
        #expect(engine.state == .notStarted)
    }

    @Test("endSegment on the FINAL station finishes the race directly (no trailing roxzone)")
    func finalSegmentEndSegmentFinishesRace() {
        var engine = RaceEngine(sequence: [.run1, .wallBalls])
        engine.start(at: t0)
        engine.endSegment(at: t(300))           // close run1 → .inRoxzone
        engine.startNextSegment(at: t(312))     // 12s roxzone, begin wallBalls
        engine.endSegment(at: t(900))           // close wallBalls — should finish

        #expect(engine.isFinished)
        #expect(engine.splits.count == 2)
        // Final wallBalls split carries the 12s roxzone from the transition
        // before it.
        #expect(engine.splits.last?.roxzoneSeconds == 12)
    }

    @Test("roxzone clock keeps running while in .inRoxzone — elapsed accumulates")
    func roxzoneCountsTowardTotalElapsed() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.endSegment(at: t(300))           // run1 closes at 5:00
        // While in roxzone, total elapsed continues — race time isn't
        // paused. This is the difference between roxzone and pause.
        #expect(engine.elapsed(at: t(310)) == 310)
        #expect(engine.elapsed(at: t(330)) == 330)
    }
}

@Suite("RaceStats — roxzone aggregates")
struct RoxzoneStatsTests {

    // Build a finished race with known roxzone values for the
    // aggregate tests. Splits 0..3 carry roxzones of nil, 12, 18, 24.
    // First split has no preceding transition (HYROX convention).
    private func raceWithRoxzones() -> Race {
        let s0 = Split(
            station: .run1,
            startedAt: t0,
            endedAt: t(300),
            roxzoneSeconds: nil
        )
        let s1 = Split(
            station: .skiErg,
            startedAt: t(312),
            endedAt: t(540),
            roxzoneSeconds: 12
        )
        let s2 = Split(
            station: .run2,
            startedAt: t(558),
            endedAt: t(840),
            roxzoneSeconds: 18
        )
        let s3 = Split(
            station: .sledPush,
            startedAt: t(864),
            endedAt: t(1080),
            roxzoneSeconds: 24
        )
        let race = Race(
            startedAt: t0,
            createdAt: t0,
            sequence: [.run1, .skiErg, .run2, .sledPush]
        )
        race.splits = [s0, s1, s2, s3]
        race.endedAt = t(1080)
        return race
    }

    @Test("totalRoxzoneTime sums every non-nil roxzoneSeconds")
    func totalRoxzoneSums() {
        let race = raceWithRoxzones()
        #expect(RaceStats.totalRoxzoneTime(race) == 54) // 12 + 18 + 24
    }

    @Test("avgRoxzoneTime divides by the count of non-nil roxzones")
    func avgRoxzoneCorrectDivisor() {
        let race = raceWithRoxzones()
        // 54 / 3 = 18 — note we divide by 3 (the splits with a
        // roxzone), NOT by 4 (all splits). The first run has no
        // preceding transition by design.
        #expect(RaceStats.avgRoxzoneTime(race) == 18)
    }

    @Test("totalRoxzoneTime returns nil when no splits carry a roxzone")
    func totalNilForNoData() {
        // Single-tap-mode race — every split has roxzoneSeconds == nil.
        let s = Split(station: .run1, startedAt: t0, endedAt: t(300))
        let race = Race(startedAt: t0, createdAt: t0)
        race.splits = [s]
        race.endedAt = t(300)
        #expect(RaceStats.totalRoxzoneTime(race) == nil)
        #expect(RaceStats.avgRoxzoneTime(race) == nil)
    }

    @Test("crossRaceAvgRoxzone averages every roxzone across multiple finished races")
    func crossRaceAverageWorks() {
        let r1 = raceWithRoxzones()           // 12, 18, 24 → avg 18
        let r2 = raceWithRoxzones()           // same set repeated
        // 6 values total, sum 108, avg 18.
        #expect(RaceStats.crossRaceAvgRoxzone(among: [r1, r2]) == 18)
    }

    @Test("crossRaceAvgRoxzone ignores unfinished races")
    func crossRaceIgnoresUnfinished() {
        let finished = raceWithRoxzones()
        let unfinished = raceWithRoxzones()
        unfinished.endedAt = nil
        // Only the finished one contributes — same avg as a single race.
        #expect(RaceStats.crossRaceAvgRoxzone(among: [finished, unfinished]) == 18)
    }
}

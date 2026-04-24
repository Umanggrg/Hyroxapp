import Testing
import Foundation
@testable import Hyroxapp

// Tests for the resume-after-kill correctness path.
//
// The flow we're proving out:
//   1. A race is running; `RaceViewModel.persistActiveRace()` mirrors
//      engine state onto a `Race` SwiftData row on every event.
//   2. The app is killed.
//   3. On next launch, `RaceViewModel.checkForResumableRace` finds the
//      unfinished `Race` row.
//   4. `race.engineState` reconstructs the engine's enum state.
//   5. `RaceEngine(state: ...)` rebuilds a functioning engine.
//
// Any break in this chain means athletes lose their race mid-training.
// These tests pin every step so future refactors can't silently break
// the resume contract.
//
// Note: `Race` is a SwiftData `@Model`, but we can instantiate it without
// a `ModelContext` for pure-value tests — ModelContext is only required
// for persistence and queries, not for field access.

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func t(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

@Suite("Race → engineState round-trip")
struct RaceEngineStateRoundTripTests {

    @Test("freshly-started race reconstructs as in-progress at station 0")
    func freshlyStartedRace() {
        // Mirrors what `startRace()` writes: startedAt + currentSegmentStartedAt
        // both set to the moment of start; no splits yet.
        let race = Race(
            startedAt: t0,
            currentSegmentStartedAt: t0,
            sequence: Station.raceSequence
        )

        let state = race.engineState

        guard case .inProgress(let rStart, let segStart, let splits) = state else {
            Issue.record("Expected .inProgress, got \(state)")
            return
        }
        #expect(rStart == t0)
        #expect(segStart == t0)
        #expect(splits.isEmpty)

        // And the engine rebuilt from this state should be ready to
        // advance from station 0.
        let engine = RaceEngine(state: state)
        #expect(engine.currentStation == .run1)
        #expect(engine.elapsed(at: t(42)) == 42)
    }

    @Test("race with completed splits reconstructs at the correct station")
    func midRaceRace() {
        let splits = [
            Split(station: .run1, startedAt: t0, endedAt: t(300)),
            Split(station: .skiErg, startedAt: t(300), endedAt: t(540))
        ]
        let race = Race(
            startedAt: t0,
            splits: splits,
            currentSegmentStartedAt: t(540)  // about to start run2
        )

        let state = race.engineState
        let engine = RaceEngine(state: state)

        #expect(engine.currentStation == .run2)
        #expect(engine.upcomingStation == .sledPush)
        #expect(engine.splits.count == 2)
        #expect(engine.elapsed(at: t(600)) == 600)
        #expect(engine.currentSegmentElapsed(at: t(600)) == 60)
    }

    @Test("finished race reconstructs as .finished with all splits")
    func finishedRace() {
        // Simulate a complete race persisted just before the user tapped Done.
        var splits: [Split] = []
        let stations = Station.raceSequence
        for (i, station) in stations.enumerated() {
            let start = t(TimeInterval(i * 60))
            let end = t(TimeInterval((i + 1) * 60))
            splits.append(Split(station: station, startedAt: start, endedAt: end))
        }

        let race = Race(
            startedAt: t0,
            endedAt: t(TimeInterval(stations.count * 60)),
            splits: splits,
            currentSegmentStartedAt: nil
        )

        let state = race.engineState
        guard case .finished(let rStart, let rEnd, let persistedSplits) = state else {
            Issue.record("Expected .finished, got \(state)")
            return
        }
        #expect(rStart == t0)
        #expect(rEnd == t(960))
        #expect(persistedSplits.count == 16)

        // Resumed engine should refuse to advance further.
        var engine = RaceEngine(state: state)
        #expect(engine.isFinished)
        engine.advance(at: t(10_000))
        #expect(engine.splits.count == 16)  // unchanged
    }

    @Test("race with only startedAt (no segStart, no splits) reconstructs as .notStarted")
    func incompletelyPersistedRace() {
        // Defensive: a Race row missing currentSegmentStartedAt isn't a
        // valid in-progress state. `engineState` should fall through to
        // .notStarted so the resume prompt doesn't offer a bogus resume.
        let race = Race(
            startedAt: t0,
            endedAt: nil,
            splits: [],
            currentSegmentStartedAt: nil
        )

        #expect(race.engineState == .notStarted)
    }
}

@Suite("Resume → advance continues cleanly")
struct RaceResumeAndContinueTests {

    @Test("resumed engine's next advance appends a valid split")
    func advanceAfterResume() {
        // User completed run1 at 5:00, got through skiErg to 9:00,
        // app killed during run2 (segment started at 9:00).
        let priorSplits = [
            Split(station: .run1, startedAt: t0, endedAt: t(300)),
            Split(station: .skiErg, startedAt: t(300), endedAt: t(540))
        ]
        var engine = RaceEngine(state: .inProgress(
            startedAt: t0,
            currentSegmentStartedAt: t(540),
            splits: priorSplits
        ))

        // User relaunches and, minutes later, taps Next Station at t(700).
        // In our "not paused" model, total elapsed is 700s and run2's split
        // is (540 → 700) = 160 seconds — including any blackout time.
        engine.advance(at: t(700))

        #expect(engine.splits.count == 3)
        let run2Split = engine.splits[2]
        #expect(run2Split.station == .run2)
        #expect(run2Split.startedAt == t(540))
        #expect(run2Split.endedAt == t(700))
        #expect(run2Split.duration == 160)

        // Next station is set up correctly.
        #expect(engine.currentStation == .sledPush)
        #expect(engine.currentSegmentElapsed(at: t(700)) == 0)
    }

    @Test("resumed engine finishes on final advance")
    func finishAfterResume() {
        // Simulate: user was on the final station (wallBalls) when app died.
        var splits: [Split] = []
        let stations = Station.raceSequence
        for (i, station) in stations.dropLast().enumerated() {
            splits.append(Split(
                station: station,
                startedAt: t(TimeInterval(i * 60)),
                endedAt: t(TimeInterval((i + 1) * 60))
            ))
        }
        // Wall balls started at 15:00 (900s in); user killed app mid-wall-balls.
        var engine = RaceEngine(state: .inProgress(
            startedAt: t0,
            currentSegmentStartedAt: t(900),
            splits: splits
        ))

        // User reopens at 20:00, hold-to-finishes.
        engine.advance(at: t(1200))

        #expect(engine.isFinished)
        #expect(engine.splits.count == 16)
        #expect(engine.splits.last?.station == .wallBalls)
        #expect(engine.elapsed(at: t(99_999)) == 1200)  // frozen at finish time
    }
}

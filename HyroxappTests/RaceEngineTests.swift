import Testing
import Foundation
@testable import Hyroxapp

// Tests for the pure `RaceEngine` state machine.
//
// Because the engine takes `Date`s as inputs rather than reading `Date()`
// internally, every test is fully deterministic — no sleeping, no runloop,
// no clock mocking. If these tests pass, we can trust that drift, ordering,
// and boundary cases are correct regardless of how the engine is driven
// (solo, watchOS, or Duo Mode via Supabase Realtime).

// A fixed reference moment so every test reads the same way.
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

// Offset helper: `t(30)` is 30 seconds after `t0`.
private func t(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

@Suite("RaceEngine — initial state")
struct RaceEngineInitialStateTests {

    @Test("starts in .notStarted with no splits and zero elapsed")
    func initialState() {
        let engine = RaceEngine()
        #expect(engine.state == .notStarted)
        #expect(engine.splits.isEmpty)
        #expect(engine.currentStation == nil)
        #expect(engine.upcomingStation == nil)
        #expect(engine.isFinished == false)
        #expect(engine.elapsed(at: t0) == 0)
        #expect(engine.currentSegmentElapsed(at: t0) == 0)
    }

    @Test("default sequence is the full 16-station HYROX race")
    func defaultSequence() {
        let engine = RaceEngine()
        #expect(engine.sequence.count == 16)
        #expect(engine.sequence.first == .run1)
        #expect(engine.sequence.last == .wallBalls)
    }
}

@Suite("RaceEngine — starting")
struct RaceEngineStartTests {

    @Test("start transitions to .inProgress at first station")
    func startMovesToFirstStation() {
        var engine = RaceEngine()
        engine.start(at: t0)

        #expect(engine.isFinished == false)
        #expect(engine.currentStation == .run1)
        #expect(engine.upcomingStation == .skiErg)
        #expect(engine.splits.isEmpty)
        #expect(engine.elapsed(at: t(5)) == 5)
        #expect(engine.currentSegmentElapsed(at: t(5)) == 5)
    }

    @Test("calling start twice is a no-op (preserves original start time)")
    func startIsIdempotent() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.start(at: t(100)) // should be ignored

        #expect(engine.elapsed(at: t(100)) == 100) // measured from t0, not t(100)
        #expect(engine.currentStation == .run1)
    }
}

@Suite("RaceEngine — advancing")
struct RaceEngineAdvanceTests {

    @Test("advance records a split and moves to the next station")
    func advanceRecordsSplit() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.advance(at: t(300)) // finish run1 at 5:00

        #expect(engine.splits.count == 1)
        let split = engine.splits[0]
        #expect(split.station == .run1)
        #expect(split.startedAt == t0)
        #expect(split.endedAt == t(300))
        #expect(split.duration == 300)

        #expect(engine.currentStation == .skiErg)
        #expect(engine.upcomingStation == .run2)
    }

    @Test("currentSegmentElapsed resets on advance")
    func currentSegmentElapsedResets() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.advance(at: t(300)) // now on skiErg, segment started at t(300)

        #expect(engine.currentSegmentElapsed(at: t(300)) == 0)
        #expect(engine.currentSegmentElapsed(at: t(330)) == 30)
        // Total race elapsed still counts from the original start.
        #expect(engine.elapsed(at: t(330)) == 330)
    }

    @Test("advance on .notStarted is a no-op")
    func advanceBeforeStartIsNoop() {
        var engine = RaceEngine()
        engine.advance(at: t(10))

        #expect(engine.state == .notStarted)
        #expect(engine.splits.isEmpty)
    }

    @Test("advance after finish is a no-op")
    func advanceAfterFinishIsNoop() {
        var engine = RaceEngine()
        engine.start(at: t0)
        // Blast through all 16 segments.
        for i in 1...16 {
            engine.advance(at: t(TimeInterval(i * 60)))
        }
        #expect(engine.isFinished)
        let splitsBefore = engine.splits

        engine.advance(at: t(9999))
        #expect(engine.splits == splitsBefore) // no extra split appended
    }
}

@Suite("RaceEngine — finishing")
struct RaceEngineFinishTests {

    @Test("advancing through all segments transitions to .finished")
    func finishesAfterFinalStation() {
        var engine = RaceEngine()
        engine.start(at: t0)
        for i in 1...16 {
            engine.advance(at: t(TimeInterval(i * 60)))
        }

        #expect(engine.isFinished)
        #expect(engine.splits.count == 16)
        #expect(engine.currentStation == nil)
        #expect(engine.upcomingStation == nil)
    }

    @Test("elapsed is frozen once finished (ignores later `now`)")
    func elapsedFrozenWhenFinished() {
        var engine = RaceEngine()
        engine.start(at: t0)
        for i in 1...16 {
            engine.advance(at: t(TimeInterval(i * 60)))
        }
        // Total finish time was 16 × 60 = 960s
        #expect(engine.elapsed(at: t(10_000)) == 960)
    }

    @Test("every split's end equals the next split's start (no gaps, no overlaps)")
    func splitsAreContiguous() {
        var engine = RaceEngine()
        engine.start(at: t0)
        for i in 1...16 {
            engine.advance(at: t(TimeInterval(i * 45)))
        }
        let splits = engine.splits
        for i in 0..<(splits.count - 1) {
            #expect(splits[i].endedAt == splits[i + 1].startedAt)
        }
        #expect(splits.first?.startedAt == t0)
        #expect(splits.last?.endedAt == t(16 * 45))
    }

    @Test("split order matches the race sequence")
    func splitOrderMatchesSequence() {
        var engine = RaceEngine()
        engine.start(at: t0)
        for i in 1...16 {
            engine.advance(at: t(TimeInterval(i * 30)))
        }
        #expect(engine.splits.map(\.station) == Station.raceSequence)
    }
}

@Suite("RaceEngine — reset and resume")
struct RaceEngineResetResumeTests {

    @Test("reset returns the engine to .notStarted")
    func resetClearsState() {
        var engine = RaceEngine()
        engine.start(at: t0)
        engine.advance(at: t(60))
        engine.reset()

        #expect(engine.state == .notStarted)
        #expect(engine.splits.isEmpty)
        #expect(engine.currentStation == nil)
    }

    @Test("can be reconstituted from a persisted in-progress state")
    func resumeFromPersistedState() {
        // Simulate: user completed run1 then backgrounded the app.
        let priorSplit = Split(station: .run1, startedAt: t0, endedAt: t(300))
        let resumed = RaceEngine(
            state: .inProgress(
                startedAt: t0,
                currentSegmentStartedAt: t(300),
                splits: [priorSplit]
            )
        )

        #expect(resumed.currentStation == .skiErg)
        #expect(resumed.upcomingStation == .run2)
        #expect(resumed.splits == [priorSplit])
        #expect(resumed.elapsed(at: t(330)) == 330)
        #expect(resumed.currentSegmentElapsed(at: t(330)) == 30)
    }
}

@Suite("RaceEngine — custom sequences")
struct RaceEngineCustomSequenceTests {

    @Test("engine honors an injected short sequence (for practice / tests)")
    func injectedSequence() {
        var engine = RaceEngine(sequence: [.run1, .wallBalls])
        engine.start(at: t0)
        engine.advance(at: t(60))  // finish run1
        engine.advance(at: t(120)) // finish wallBalls → race ends

        #expect(engine.isFinished)
        #expect(engine.splits.map(\.station) == [.run1, .wallBalls])
        #expect(engine.elapsed(at: t(999)) == 120)
    }
}

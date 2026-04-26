import Testing
import Foundation
@testable import Hyroxapp

// Tests for `RaceStats.projectedRaceTime(forSplit:division:)`.
//
// Linear extrapolation logic: when the athlete trained at sub-race
// weight, scale this attempt's duration by `raceWeight / loggedWeight`
// to project what the same effort would cost at official HYROX weight.
//
// The function returns nil in these guard cases:
//   • split has no `weightKg` logged
//   • split's station is a run (no race weight defined)
//   • logged weight is at or above race weight (no projection needed)
//   • logged weight is within 0.5 kg of race weight (noise floor)

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

// Helper to build a Split with a given station, duration, and weight.
private func split(
    station: Station,
    duration: TimeInterval,
    weightKg: Double?
) -> Split {
    Split(
        station: station,
        startedAt: t0,
        endedAt: t0.addingTimeInterval(duration),
        weightKg: weightKg
    )
}

@Suite("RaceStats — race-day weight projection")
struct WeightProjectionTests {

    @Test("scales linearly when training under race weight (Men's Open Sled Push)")
    func mensOpenSledPushScaling() {
        // Men's Open Sled Push race weight is 152 kg (per Division.raceWeight).
        // Athlete trained at 76 kg (exactly half) and went 4:00.
        // Linear projection: 4:00 × (152 / 76) = 8:00.
        let s = split(station: .sledPush, duration: 240, weightKg: 76)
        let projected = RaceStats.projectedRaceTime(forSplit: s, division: .mensOpen)

        #expect(projected != nil)
        if let projected {
            #expect(abs(projected - 480) < 0.01)
        }
    }

    @Test("returns nil when no weight is logged")
    func nilForNoWeight() {
        let s = split(station: .sledPush, duration: 240, weightKg: nil)
        #expect(RaceStats.projectedRaceTime(forSplit: s, division: .mensOpen) == nil)
    }

    @Test("returns nil for a run station (no race weight defined)")
    func nilForRunStation() {
        // Even with a weight logged (which would be nonsensical on a run),
        // the run path returns nil because Division.raceWeight(for: .run1)
        // is nil — there's no weight to project against.
        let s = split(station: .run1, duration: 300, weightKg: 50)
        #expect(RaceStats.projectedRaceTime(forSplit: s, division: .mensOpen) == nil)
    }

    @Test("returns nil when training weight is at or above race weight")
    func nilWhenAtOrOverRaceWeight() {
        // Already at race weight — no projection needed.
        let atRaceWeight = split(station: .sledPush, duration: 240, weightKg: 152)
        #expect(RaceStats.projectedRaceTime(forSplit: atRaceWeight, division: .mensOpen) == nil)

        // Above race weight — the function only projects upward in
        // difficulty (you trained light → race day is harder). It
        // doesn't project downward (training heavy doesn't make race
        // day easier in any predictable way).
        let overWeight = split(station: .sledPush, duration: 240, weightKg: 200)
        #expect(RaceStats.projectedRaceTime(forSplit: overWeight, division: .mensOpen) == nil)
    }

    @Test("returns nil within the 0.5 kg noise-floor band")
    func nilWithinNoiseFloor() {
        // 151.6 kg is 0.4 kg under 152 — too close to call.
        let nearRaceWeight = split(station: .sledPush, duration: 240, weightKg: 151.6)
        #expect(RaceStats.projectedRaceTime(forSplit: nearRaceWeight, division: .mensOpen) == nil)

        // 151.4 kg is 0.6 kg under — outside the band, projection should fire.
        let belowBand = split(station: .sledPush, duration: 240, weightKg: 151.4)
        let projected = RaceStats.projectedRaceTime(forSplit: belowBand, division: .mensOpen)
        #expect(projected != nil)
        if let projected {
            // 240 × (152 / 151.4) ≈ 240.95
            #expect(abs(projected - 240.95) < 0.05)
        }
    }

    @Test("uses the division-specific race weight (Women's Open differs from Men's)")
    func divisionAwareScaling() {
        // Women's Open Sled Push is lighter than Men's — verify the
        // function actually consults Division.raceWeight rather than
        // hard-coding any single number.
        let mensRaceWeight = Division.mensOpen.raceWeight(for: .sledPush)!
        let womensRaceWeight = Division.womensOpen.raceWeight(for: .sledPush)!
        #expect(mensRaceWeight != womensRaceWeight)

        // Same logged weight + duration should project to different
        // expected race-day times for each division.
        let s = split(station: .sledPush, duration: 240, weightKg: 50)
        let mens = RaceStats.projectedRaceTime(forSplit: s, division: .mensOpen)!
        let womens = RaceStats.projectedRaceTime(forSplit: s, division: .womensOpen)!

        #expect(abs(mens - 240 * (mensRaceWeight / 50)) < 0.01)
        #expect(abs(womens - 240 * (womensRaceWeight / 50)) < 0.01)
    }

    @Test("guards against zero or negative weight (no division-by-zero)")
    func nilForZeroWeight() {
        // Logged weight of 0 (or nonsense negative) shouldn't crash —
        // should return nil and let the caller hide the projection.
        let zero = split(station: .sledPush, duration: 240, weightKg: 0)
        #expect(RaceStats.projectedRaceTime(forSplit: zero, division: .mensOpen) == nil)

        let negative = split(station: .sledPush, duration: 240, weightKg: -10)
        #expect(RaceStats.projectedRaceTime(forSplit: negative, division: .mensOpen) == nil)
    }
}

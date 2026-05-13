import Foundation

// Wire-friendly representation of a `Split`.
//
// The real `Split` is a SwiftData `@Model` class — it carries
// persistence identity, lives in a managed context, and isn't safe
// to encode-as-JSON-and-decode-into-a-fresh-instance. For shipping
// race state across the duo bridge we need a plain value type that
// round-trips through Codable cleanly.
//
// Same field set as `Split` minus the SwiftData identity.
// Round-trip helpers `init(from: Split)` and `toSplit()` make
// boundaries explicit: encode happens on the host before broadcast,
// decode happens on the guest when reconstructing a `Race` row from
// the host's `.finished` snapshot.
struct SerializedSplit: Codable, Sendable, Equatable {

    // Stored as the enum's `rawValue` (Int) so a future Station
    // enum addition can decode old payloads without crashing —
    // unknown raw → nil station via Station(rawValue:) when we
    // round-trip back to a Split.
    let stationRaw: Int

    let startedAt: Date
    let endedAt: Date

    // HealthKit-derived per-segment statistics.
    let heartRateAvgBPM: Double?
    let heartRateMaxBPM: Double?
    let activeCaloriesKcal: Double?

    // HR boundary samples — the values at specific moments
    // relative to the split's window. Powers the recovery
    // metric (drop in BPM in the 30s after the segment ended)
    // and per-station HR fingerprints. Both default nil so old
    // Codable payloads decode cleanly without these fields.
    //
    //   • heartRateEndBPM — HR at (or closest to) endedAt.
    //     The reference point recovery is measured against.
    //
    //   • heartRateRecovery30sBPM — HR 30s after endedAt.
    //     Compared against heartRateEndBPM to compute the
    //     recovery drop (higher drop = better conditioning).
    //
    // Both are needed together for the recovery calculation;
    // the consumer guards on both being non-nil.
    let heartRateEndBPM: Double?
    let heartRateRecovery30sBPM: Double?

    // Manual stats the athlete enters via StationStatsSheet.
    let weightKg: Double?
    let repsCompleted: Int?
    let rpe: Int?

    // Transition (roxzone) seconds attributed to this segment.
    let roxzoneSeconds: TimeInterval?

    // §19 Phase 10I — per-segment average vertical oscillation
    // (cm/step) from AirPods Pro 1+ head motion. Runs only;
    // workout splits leave this nil. Sent across the duo wire
    // so the guest's RaceDetail Running Economy section reads
    // the same per-segment number as the host's.
    let verticalOscCmAvg: Double?

    // §19.4 Phase 10K — per-segment average ground contact time
    // (ms) from AirPods head motion. Same shape + lifecycle as
    // verticalOscCmAvg above; sent across the duo wire so the
    // guest's RaceDetail Running Economy section shows the
    // same per-segment number the host sees.
    let groundContactTimeMsAvg: Double?

    init(from split: Split) {
        self.stationRaw = split.station.rawValue
        self.startedAt = split.startedAt
        self.endedAt = split.endedAt
        self.heartRateAvgBPM = split.heartRateAvgBPM
        self.heartRateMaxBPM = split.heartRateMaxBPM
        self.activeCaloriesKcal = split.activeCaloriesKcal
        self.heartRateEndBPM = split.heartRateEndBPM
        self.heartRateRecovery30sBPM = split.heartRateRecovery30sBPM
        self.weightKg = split.weightKg
        self.repsCompleted = split.repsCompleted
        self.rpe = split.rpe
        self.roxzoneSeconds = split.roxzoneSeconds
        self.verticalOscCmAvg = split.verticalOscCmAvg
        self.groundContactTimeMsAvg = split.groundContactTimeMsAvg
    }

    // Round-trip back to a `Split`. Returns nil for an unknown
    // `stationRaw` — defensive against version skew (host on a
    // newer build with new station cases that the guest doesn't
    // recognize). Caller filters nils out of the splits array
    // before saving the race so a partial decode doesn't leave
    // gaps.
    func toSplit() -> Split? {
        guard let station = Station(rawValue: stationRaw) else { return nil }
        // `var` (vs let) — Split is a value type; we need a
        // mutable local to assign the §19 10I verticalOscCmAvg
        // field after init.
        var split = Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            heartRateEndBPM: heartRateEndBPM,
            heartRateRecovery30sBPM: heartRateRecovery30sBPM,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: roxzoneSeconds
        )
        // §19 Phase 10I — verticalOscCmAvg is the only mutable
        // field on Split (declared `var` for direct stamping
        // from RaceViewModel); reinstating it post-init is the
        // same pattern.
        split.verticalOscCmAvg = verticalOscCmAvg
        split.groundContactTimeMsAvg = groundContactTimeMsAvg
        return split
    }
}

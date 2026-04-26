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

    // Manual stats the athlete enters via StationStatsSheet.
    let weightKg: Double?
    let repsCompleted: Int?
    let rpe: Int?

    // Transition (roxzone) seconds attributed to this segment.
    let roxzoneSeconds: TimeInterval?

    init(from split: Split) {
        self.stationRaw = split.station.rawValue
        self.startedAt = split.startedAt
        self.endedAt = split.endedAt
        self.heartRateAvgBPM = split.heartRateAvgBPM
        self.heartRateMaxBPM = split.heartRateMaxBPM
        self.activeCaloriesKcal = split.activeCaloriesKcal
        self.weightKg = split.weightKg
        self.repsCompleted = split.repsCompleted
        self.rpe = split.rpe
        self.roxzoneSeconds = split.roxzoneSeconds
    }

    // Round-trip back to a `Split`. Returns nil for an unknown
    // `stationRaw` — defensive against version skew (host on a
    // newer build with new station cases that the guest doesn't
    // recognize). Caller filters nils out of the splits array
    // before saving the race so a partial decode doesn't leave
    // gaps.
    func toSplit() -> Split? {
        guard let station = Station(rawValue: stationRaw) else { return nil }
        return Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: roxzoneSeconds
        )
    }
}

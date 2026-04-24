import Foundation

// A single completed segment of a race.
//
// Every split carries its own start and end timestamps. Duration is computed
// from those — never accumulated tick-by-tick from a timer — so it's accurate
// regardless of UI refresh rate, backgrounding, or device sleep.
//
// Heart-rate fields capture what HealthKit knew about the athlete during
// the segment's time window:
//   - `heartRateAvgBPM` — HKStatisticsQuery `.discreteAverage` over
//     [startedAt, endedAt]. Best single-number summary of intensity.
//   - `heartRateMaxBPM` — `.discreteMax` over the same window. Useful
//     for spotting peak strain (e.g. last 30s of wall balls).
// Both are optional because HR may be unavailable (no Watch on wrist,
// read auth denied, no samples in window). The UI omits the display
// gracefully when both are nil.
//
// Backward-compat note: earlier builds stored a single `heartRateBPM`
// field (a snapshot at advance time, not a segment average). The
// `CodingKeys` below map that legacy key into the new `heartRateAvgBPM`
// field so old persisted races decode without data loss. The semantic
// difference is small — at typical sampling rates the snapshot
// approximates the segment average — so reading it as "avg" is fine.
struct Split: Codable, Equatable, Hashable, Identifiable, Sendable {
    let station: Station
    let startedAt: Date
    let endedAt: Date
    let heartRateAvgBPM: Double?
    let heartRateMaxBPM: Double?

    // `Station.rawValue` is stable and unique within a race, so it doubles as
    // the Identifiable id — no extra UUID needed.
    var id: Int { station.rawValue }

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    // Codable keys. The `heartRateAvgBPM` key maps to the JSON key
    // "heartRateBPM" so old persisted splits (before max was added)
    // decode cleanly — their single HR value flows into the avg slot.
    // New encodes also write to "heartRateBPM" (not "heartRateAvgBPM")
    // so writers and readers stay symmetric across versions.
    enum CodingKeys: String, CodingKey {
        case station
        case startedAt
        case endedAt
        case heartRateAvgBPM = "heartRateBPM"
        case heartRateMaxBPM
    }

    // Convenience initializer preserving the pre-HR API so all existing
    // call sites (engine, tests) keep working unchanged.
    init(
        station: Station,
        startedAt: Date,
        endedAt: Date,
        heartRateAvgBPM: Double? = nil,
        heartRateMaxBPM: Double? = nil
    ) {
        self.station = station
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.heartRateAvgBPM = heartRateAvgBPM
        self.heartRateMaxBPM = heartRateMaxBPM
    }

    // Return a new Split with the given HR statistics attached. Used
    // after a successful HealthKit query to patch the just-completed
    // split with both its avg and max HR for the segment window.
    func withHeartRateStats(avg: Double?, max: Double?) -> Split {
        Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: avg,
            heartRateMaxBPM: max
        )
    }
}

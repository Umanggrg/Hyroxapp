import Foundation

// §47a — End-of-segment batch carrying the full per-rep timestamp
// array from the Watch's WatchRepCountingService.
//
// Distinct from `WatchRepCountUpdate` (which fires ~1Hz throughout
// the station carrying just the running count): this payload
// fires ONCE at segment-end inside the service's `stop()` path,
// shipping every rep timestamp the detector saw. Downstream the
// iPhone uses these to compute analytics that mid-race count
// alone can't power:
//
//   • Stroke-rate curve over the 1000m (rowing / SkiErg) —
//     spm by 100m segment, surfaces "did you hold cadence?"
//   • Distance per stroke (DPS) — the gold-standard rowing
//     efficiency metric. Constant for a known-distance erg
//     (1000m / strokes) but the trend across races + the
//     within-race front/back split signal pacing strategy.
//   • Stroke-rate consistency score (coefficient of variation)
//   • First-half vs second-half cadence delta — pacing tell.
//
// Why not just include timestamps in every WatchRepCountUpdate:
// the live-publish path runs at 1Hz throughout the station,
// and bloating each message with a growing array (50+ doubles
// at the end of a 1000m row) would burn WCSession bandwidth
// for no UX gain — the iPhone's live chip only renders the
// count, not the cadence curve. Single end-of-segment batch
// is the right shape.
//
// Wire format: timestamps as TimeInterval-since-1970 doubles.
// Receiver reconstructs Date locally; arrays of TimeIntervals
// encode compactly in WCSession's plist dictionary representation.
// Bounded by the count cap inside WatchRepCountingService's
// repTimestamps buffer (100 most recent), so worst-case payload
// is ~800 bytes — well under WCSession's per-message budget.
//
// Shared between iOS and watchOS targets via target membership.
struct WatchRepTimestampsBatch: Sendable, Equatable {

    /// The per-rep / per-stroke / per-pull timestamps, in
    /// chronological order. Length matches the detector's final
    /// count for the just-ended segment.
    let timestamps: [Date]

    /// Which station the detector was scoring when these
    /// timestamps were captured. iPhone matches against the
    /// just-closed split's station rawValue before stamping —
    /// guards against the rare case of a station change racing
    /// with the batch publish.
    let stationRaw: Int

    /// When the Watch published this batch. iPhone uses for
    /// stale-sample rejection (same 90s threshold the HR + rep-
    /// count paths use) and out-of-order discard if a delayed
    /// transferUserInfo arrives after a fresher batch.
    let sampledAt: Date

    init(timestamps: [Date], stationRaw: Int, sampledAt: Date) {
        self.timestamps = timestamps
        self.stationRaw = stationRaw
        self.sampledAt = sampledAt
    }

    // MARK: - Dictionary encoding

    private enum Key {
        static let kind = "kind"
        static let timestamps = "timestamps"
        static let stationRaw = "stationRaw"
        static let sampledAt = "sampledAt"
    }

    private static let kindValue = "repTimestampsBatch"

    func toDictionary() -> [String: Any] {
        [
            Key.kind: Self.kindValue,
            Key.timestamps: timestamps.map { $0.timeIntervalSince1970 },
            Key.stationRaw: stationRaw,
            Key.sampledAt: sampledAt.timeIntervalSince1970,
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Key.kind] as? String,
              kind == Self.kindValue else {
            return nil
        }
        guard let raw = dictionary[Key.stationRaw] as? Int,
              let sampledTs = dictionary[Key.sampledAt] as? TimeInterval,
              let tsArray = dictionary[Key.timestamps] as? [TimeInterval] else {
            return nil
        }
        self.stationRaw = raw
        self.sampledAt = Date(timeIntervalSince1970: sampledTs)
        self.timestamps = tsArray.map { Date(timeIntervalSince1970: $0) }
    }
}

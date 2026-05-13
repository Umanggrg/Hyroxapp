import Foundation

// A live rep-count sample sent from Watch → iPhone via WCSession
// during a rep-based station (wall balls in Phase 1; future
// expansions in §13.8 Tier 2). Symmetric counterpart to
// `WatchHeartRateUpdate` — the Watch is the source of truth
// because the IMU is on the wrist that's actually doing the work.
//
// Flow:
//   1. `WatchRepCountingService` detects a rep via Z-axis peak
//      analysis on CMDeviceMotion.userAcceleration.
//   2. Every ~1Hz (throttled to protect WCSession's budget) the
//      service calls `WatchRaceClient.publishRepCount(_:)` with
//      the latest tally for the current station.
//   3. On the phone side, `WatchCompanionService.didReceiveMessage`
//      (and the redundant `didReceiveUserInfo` queue path) decode
//      this struct and dispatch to a MainActor callback.
//   4. `RaceViewModel` ingests via the callback, holds the latest
//      auto-rep count for the current segment, and stamps
//      `Split.repsCompleted` at the engine's advance time.
//
// `sampledAt` lets the phone reject stale samples that arrive out
// of order (transferUserInfo can queue payloads across phone-
// pocketed periods and deliver them seconds late). The phone keeps
// only the most-recent-by-timestamp count per station.
//
// `stationRaw` is the `Station.rawValue` of the station the count
// belongs to. The phone validates that the snapshot's current
// station matches before applying the count — a stale update from
// a just-ended segment shouldn't bleed into the next station's
// reps (especially relevant during the moment between Watch
// detecting the station change via snapshot push and the next
// motion subscription's start).
//
// Shared between iOS and watchOS targets via target membership.
struct WatchRepCountUpdate: Sendable, Equatable {

    let count: Int
    let stationRaw: Int
    let sampledAt: Date

    init(count: Int, stationRaw: Int, sampledAt: Date) {
        self.count = count
        self.stationRaw = stationRaw
        self.sampledAt = sampledAt
    }

    // MARK: - Dictionary encoding

    private enum Key {
        // "kind" matches the discriminator pattern WatchAction +
        // WatchHeartRateUpdate use, so the iPhone-side dispatcher
        // can route by inspecting the dict's `kind` value.
        static let kind = "kind"
        static let count = "count"
        static let stationRaw = "stationRaw"
        static let sampledAt = "sampledAt"
    }

    private static let kindValue = "repCount"

    func toDictionary() -> [String: Any] {
        [
            Key.kind: Self.kindValue,
            Key.count: count,
            Key.stationRaw: stationRaw,
            Key.sampledAt: sampledAt.timeIntervalSince1970,
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Key.kind] as? String,
              kind == Self.kindValue else {
            return nil
        }
        guard let count = dictionary[Key.count] as? Int,
              let stationRaw = dictionary[Key.stationRaw] as? Int,
              let ts = dictionary[Key.sampledAt] as? TimeInterval else {
            return nil
        }
        self.count = count
        self.stationRaw = stationRaw
        self.sampledAt = Date(timeIntervalSince1970: ts)
    }
}

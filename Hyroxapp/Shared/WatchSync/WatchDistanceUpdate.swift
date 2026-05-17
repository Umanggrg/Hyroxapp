import Foundation

// A single cumulative-distance sample sent from Watch → iPhone via
// `WCSession.sendMessage(_:replyHandler:errorHandler:)` (or queued via
// `transferUserInfo` when the iPhone isn't reachable).
//
// §39 — fix for the treadmill bug. Before this payload existed, Free
// Run distance was sourced exclusively from the iPhone's CMPedometer.
// When the athlete put the phone on the treadmill console and ran a
// mile with their Watch on, the phone stayed stationary the whole
// run → zero steps registered → distance display stuck at 0.00 mi.
// Walking with the phone in hand was the only way to make it count.
//
// The Watch already runs its own HKWorkoutSession during a Free Run
// (started via the existing WatchControl.startFreeRunWorkout flow),
// and watchOS's HKLiveWorkoutBuilder auto-collects
// distanceWalkingRunning for `.running` activity sessions. The wrist
// is on the user's body, so it sees motion the phone doesn't. This
// payload streams the builder's cumulative distance back to the
// iPhone at ~1Hz so the live UI + the engine see Watch-grade values.
//
// On the iPhone side, FreeRunViewModel.ingestWatchDistance(...) feeds
// these samples directly into FreeRunEngine.recordDistance(at:metres:).
// The engine's existing monotonic filter (`guard metres > distanceMetres`)
// is exactly the arbitration we want: once the Watch's larger value
// lands, any later iPhone-pedometer samples are smaller and silently
// dropped. No explicit "Watch wins" logic needed — the monotonic
// invariant gives us that for free.
//
// `sampledAt` lets the phone reject stale samples that arrive out of
// order due to WCSession queuing (transferUserInfo can deliver
// seconds after the live sendMessage path for the same sample).
//
// Shared between iOS and watchOS targets via target membership.
struct WatchDistanceUpdate: Sendable, Equatable {

    let cumulativeMetres: Double
    let sampledAt: Date

    init(cumulativeMetres: Double, sampledAt: Date) {
        self.cumulativeMetres = cumulativeMetres
        self.sampledAt = sampledAt
    }

    // MARK: - Dictionary encoding

    private enum Key {
        // Discriminator matches WatchHeartRateUpdate's "kind" pattern
        // so the iPhone-side dispatcher can route by inspecting the
        // dict's `kind` value.
        static let kind = "kind"
        static let metres = "metres"
        static let sampledAt = "sampledAt"
    }

    private static let kindValue = "distanceUpdate"

    func toDictionary() -> [String: Any] {
        [
            Key.kind: Self.kindValue,
            Key.metres: cumulativeMetres,
            Key.sampledAt: sampledAt.timeIntervalSince1970,
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Key.kind] as? String,
              kind == Self.kindValue else {
            return nil
        }
        guard let metres = dictionary[Key.metres] as? Double,
              let ts = dictionary[Key.sampledAt] as? TimeInterval else {
            return nil
        }
        self.cumulativeMetres = metres
        self.sampledAt = Date(timeIntervalSince1970: ts)
    }
}

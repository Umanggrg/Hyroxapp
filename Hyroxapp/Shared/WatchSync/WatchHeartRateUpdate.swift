import Foundation

// A single heart-rate sample sent from Watch → iPhone via
// `WCSession.sendMessage(_:replyHandler:errorHandler:)`.
//
// The Watch's `WatchWorkoutManager` collects HR samples through
// `HKLiveWorkoutBuilderDelegate` at the device's native ~1-2Hz cadence
// while a race is active. Each sample is throttled to ~1Hz and
// forwarded to the phone, which writes it to
// `RaceViewModel.currentHeartRateBPM` — feeding the live BPM chip on
// the race screen and the Live Activity HR display without the phone
// needing to poll HealthKit itself.
//
// Why this matters vs the existing phone-side polling:
//   - Watch HR is the source of truth (the sensor is on your wrist).
//     Phone polling reads samples that the Watch already wrote to
//     HealthKit — adds 5+ seconds of latency.
//   - Watch HR works when the phone is locked, in a locker, or out
//     of Bluetooth range. Phone polling needs the phone awake.
//   - Watch HR cadence (1-2s) is much higher resolution than the
//     phone's 5-second poll interval.
//
// `sampledAt` lets the phone reject stale samples that arrive out of
// order due to WCSession queuing — when the watch is intermittently
// unreachable, sendMessage fails and we fall back to transferUserInfo
// for queued delivery; samples can arrive seconds late and we don't
// want them clobbering fresher values.
//
// Shared between iOS and watchOS targets via target membership.
struct WatchHeartRateUpdate: Sendable, Equatable {

    let bpm: Double
    let sampledAt: Date

    init(bpm: Double, sampledAt: Date) {
        self.bpm = bpm
        self.sampledAt = sampledAt
    }

    // MARK: - Dictionary encoding

    private enum Key {
        // "kind" matches the discriminator pattern WatchAction +
        // WatchControl use, so the iPhone-side dispatcher can route
        // by inspecting the dict's `kind` value.
        static let kind = "kind"
        static let bpm = "bpm"
        static let sampledAt = "sampledAt"
    }

    private static let kindValue = "hrUpdate"

    func toDictionary() -> [String: Any] {
        [
            Key.kind: Self.kindValue,
            Key.bpm: bpm,
            Key.sampledAt: sampledAt.timeIntervalSince1970,
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Key.kind] as? String,
              kind == Self.kindValue else {
            return nil
        }
        guard let bpm = dictionary[Key.bpm] as? Double,
              let ts = dictionary[Key.sampledAt] as? TimeInterval else {
            return nil
        }
        self.bpm = bpm
        self.sampledAt = Date(timeIntervalSince1970: ts)
    }
}

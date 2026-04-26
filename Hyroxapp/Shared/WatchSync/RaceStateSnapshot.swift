import Foundation

// A plain-data snapshot of the phone's race state, shaped for transport
// across the iPhone↔Apple Watch bridge.
//
// We don't ship the live `RaceEngine` across — it's a state machine with
// associated-value enum cases that don't round-trip well through
// `WCSession.updateApplicationContext(_:)`'s `[String: Any]` payload.
// Instead, every time the phone's race state changes materially (start,
// advance, abandon, finish), we take a snapshot struct and push it to
// the watch. The watch uses it to render; the watch does not itself own
// any race state — it's a stateless mirror.
//
// Design rule: all fields are plist-compatible scalar types (String,
// Double, Int, Bool, optional thereof). That lets `toDictionary()` hand
// the result directly to WCSession without a JSONEncoder in the middle.
// Debugging is also easier — you can print the raw dictionary from either
// side and see human-readable values.
//
// Shared between iOS and watchOS targets via target membership; the file
// is pure Swift with no platform imports so it compiles identically on
// both.
// `Codable` is added so the same snapshot type can ride two transports:
//   • WCSession (watch) — uses the hand-rolled plist-compatible dictionary
//     path below (`toDictionary()` / `init?(dictionary:)`)
//   • MultipeerConnectivity (Duo) — uses JSONEncoder/Decoder via Codable
// Both paths describe the same race-state shape; reusing the type means
// either transport can deliver a snapshot the receiver renders identically.
struct RaceStateSnapshot: Equatable, Sendable, Codable {

    enum Phase: String, Codable, Sendable {
        case notStarted
        case inProgress
        // Race timer is frozen — phone is in `.paused` engine state.
        // Watch shows last total elapsed at pause time (computed from
        // `startedAt..pausedAt`), dimmed UI, no advance button.
        case paused
        // Athlete just ended a segment and the next hasn't started yet.
        // `currentSegmentStartedAt` is set to the roxzone-start timestamp
        // so the watch's local timer ticks "transition time" from there.
        // Watch shows amber treatment + the next station's name.
        case inRoxzone
        case finished
    }

    let phase: Phase

    // `nil` when phase is `.notStarted`. When present, the watch uses
    // `Date().timeIntervalSince(startedAt)` to compute its own elapsed
    // time every frame — no per-tick pushes needed. This is why we ship
    // a timestamp instead of an `elapsed` value.
    let startedAt: Date?

    // Start of the current (in-progress) segment. Used for the "segment
    // timer" shown under the main total timer. Nil when the race isn't
    // in progress.
    //
    // For `.inRoxzone`, this carries the roxzone-start timestamp so the
    // watch can render "time in transition" the same way it renders a
    // segment timer — same arithmetic, different label.
    let currentSegmentStartedAt: Date?

    // When phase is `.paused`, the moment the athlete tapped pause on
    // the phone. Watch freezes its total-time display at
    // `pausedAt - startedAt` instead of computing live from `Date()`.
    // `nil` for every other phase.
    let pausedAt: Date?

    // Full per-segment timing data carried with the snapshot.
    // Used by the duo bridge — when the host's race finishes,
    // the guest reconstructs a local `Race` row from these splits
    // so the duo race appears in BOTH partners' Histories
    // independently (HYROX Doubles convention).
    //
    // Watch path doesn't use these — the watch only renders
    // station-counter / total-time / current-station-name from
    // the snapshot, no per-split detail. The dictionary
    // serialization below intentionally omits this field; it
    // ships only on the Codable path (Multipeer JSON). Default
    // `[]` keeps existing call sites compiling without explicit
    // splits — they're new with Duo Tier 1.
    let splits: [SerializedSplit]

    // Latest heart rate sample, in bpm. iOS host polls HealthKit
    // every ~5s during an active race; the polled value lives on
    // `RaceViewModel.currentHeartRateBPM` and gets included here
    // on each snapshot. Watch + duo guest both display this as a
    // small chip near the timer.
    //
    // `nil` outside an active race, before the first sample
    // arrives, or when HealthKit isn't authorized. Receivers
    // render a placeholder ("—") in those cases instead of
    // hiding the chip — the absence of HR is itself information.
    let currentHeartRateBPM: Double?

    // Athlete's configured max HR. Shipped with the snapshot so
    // the Watch (and duo guest) can compute effort scores via
    // `RaceStats.effortScore` without needing access to
    // `UserProfile`. Default 190 mirrors the same default
    // `UserProfile.maxHeartRate` ships with — receivers can
    // assume a non-zero value.
    let maxHeartRate: Int

    // 0-based index into `Station.raceSequence`. The watch resolves this
    // to a `Station` case and uses `station.displayName` /
    // `station.target(for: division)` for the header + subtitle.
    let currentStationIndex: Int

    // Number of splits already logged. Drives the "Station 3 of 16"
    // caption and will enable the splits-peek count on watch later.
    let completedStationsCount: Int

    // Constant 16 for a full HYROX race, but passed explicitly so the
    // watch doesn't hard-code race length and we can extend to
    // non-standard formats (half-rox, simulation mode) later.
    let totalStations: Int

    // User's HYROX division, needed for wall-ball rep count on the final
    // station. Stored as the enum's raw String so the snapshot stays
    // plist-compatible.
    let divisionRaw: String

    // When phase is `.finished`, the end timestamp. Used to freeze the
    // watch timer at the final time rather than continuing to tick.
    let endedAt: Date?

    // Explicit memberwise initializer. Swift auto-synthesizes one for
    // value types — but only if no other init is declared. Because we
    // also define the failable `init?(dictionary:)` below, the synthesis
    // is suppressed and we have to write this out by hand.
    init(
        phase: Phase,
        startedAt: Date?,
        currentSegmentStartedAt: Date?,
        currentStationIndex: Int,
        completedStationsCount: Int,
        totalStations: Int,
        divisionRaw: String,
        endedAt: Date?,
        pausedAt: Date? = nil,
        splits: [SerializedSplit] = [],
        currentHeartRateBPM: Double? = nil,
        maxHeartRate: Int = 190
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.currentSegmentStartedAt = currentSegmentStartedAt
        self.currentStationIndex = currentStationIndex
        self.completedStationsCount = completedStationsCount
        self.totalStations = totalStations
        self.divisionRaw = divisionRaw
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.splits = splits
        self.currentHeartRateBPM = currentHeartRateBPM
        self.maxHeartRate = maxHeartRate
    }

    // MARK: - Dictionary encoding (WCSession transport)

    // Keys for the application-context dictionary. Extracted as a nested
    // `enum` so encoding and decoding stay in sync — change a key here
    // and the compiler tells you where else it's referenced.
    private enum Key {
        static let phase = "phase"
        static let startedAt = "startedAt"
        static let currentSegmentStartedAt = "currentSegmentStartedAt"
        static let currentStationIndex = "currentStationIndex"
        static let completedStationsCount = "completedStationsCount"
        static let totalStations = "totalStations"
        static let divisionRaw = "divisionRaw"
        static let endedAt = "endedAt"
        static let pausedAt = "pausedAt"
        static let currentHeartRateBPM = "currentHeartRateBPM"
        static let maxHeartRate = "maxHeartRate"
    }

    // Build a plist-compatible dictionary suitable for
    // `WCSession.updateApplicationContext(_:)`. Dates are stored as
    // `TimeInterval` (Double seconds since 1970) because WCSession's
    // dictionary transport rejects raw `Date` on some paths.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            Key.phase: phase.rawValue,
            Key.currentStationIndex: currentStationIndex,
            Key.completedStationsCount: completedStationsCount,
            Key.totalStations: totalStations,
            Key.divisionRaw: divisionRaw,
            Key.maxHeartRate: maxHeartRate
        ]
        if let startedAt {
            dict[Key.startedAt] = startedAt.timeIntervalSince1970
        }
        if let currentSegmentStartedAt {
            dict[Key.currentSegmentStartedAt] = currentSegmentStartedAt.timeIntervalSince1970
        }
        if let endedAt {
            dict[Key.endedAt] = endedAt.timeIntervalSince1970
        }
        if let pausedAt {
            dict[Key.pausedAt] = pausedAt.timeIntervalSince1970
        }
        if let currentHeartRateBPM {
            dict[Key.currentHeartRateBPM] = currentHeartRateBPM
        }
        return dict
    }

    // Opposite side of `toDictionary()`. Returns `nil` for malformed or
    // version-mismatched payloads so the receiver can ignore them
    // cleanly rather than crashing or displaying a half-decoded state.
    init?(dictionary: [String: Any]) {
        guard
            let phaseRaw = dictionary[Key.phase] as? String,
            let phase = Phase(rawValue: phaseRaw),
            let currentStationIndex = dictionary[Key.currentStationIndex] as? Int,
            let completedStationsCount = dictionary[Key.completedStationsCount] as? Int,
            let totalStations = dictionary[Key.totalStations] as? Int,
            let divisionRaw = dictionary[Key.divisionRaw] as? String
        else {
            return nil
        }

        self.phase = phase
        self.currentStationIndex = currentStationIndex
        self.completedStationsCount = completedStationsCount
        self.totalStations = totalStations
        self.divisionRaw = divisionRaw

        // Optional timestamp fields — present only when the sender had
        // a meaningful value. We read them as Double to match how they
        // were encoded in `toDictionary()`.
        if let startedAtInterval = dictionary[Key.startedAt] as? TimeInterval {
            self.startedAt = Date(timeIntervalSince1970: startedAtInterval)
        } else {
            self.startedAt = nil
        }

        if let segStartInterval = dictionary[Key.currentSegmentStartedAt] as? TimeInterval {
            self.currentSegmentStartedAt = Date(timeIntervalSince1970: segStartInterval)
        } else {
            self.currentSegmentStartedAt = nil
        }

        if let endedAtInterval = dictionary[Key.endedAt] as? TimeInterval {
            self.endedAt = Date(timeIntervalSince1970: endedAtInterval)
        } else {
            self.endedAt = nil
        }

        if let pausedAtInterval = dictionary[Key.pausedAt] as? TimeInterval {
            self.pausedAt = Date(timeIntervalSince1970: pausedAtInterval)
        } else {
            self.pausedAt = nil
        }

        self.currentHeartRateBPM = dictionary[Key.currentHeartRateBPM] as? Double

        // maxHR has a sensible 190 default if missing from older
        // payloads — matches `UserProfile.maxHeartRate`'s default
        // so receivers compute meaningful effort scores even
        // before we re-encode with the new field.
        self.maxHeartRate = (dictionary[Key.maxHeartRate] as? Int) ?? 190

        // Splits aren't carried over the WCSession dictionary path.
        // The watch doesn't render per-split detail; the duo/Codable
        // path is the only consumer of `splits`. Initialize empty
        // here so receivers don't see junk data.
        self.splits = []
    }

    // MARK: - Convenience derived values

    // Resolve the snapshot's current station back to the shared
    // `Station` enum. `currentStationIndex` is the station's enum
    // rawValue (set on the publishing side from
    // `viewModel.currentStation?.rawValue`), so the correct lookup
    // is `Station(rawValue:)`, NOT indexing into
    // `Station.raceSequence`. The old indexing version happened to
    // work for the canonical 16-station race because
    // `Station.raceSequence` is in rawValue order — but it returned
    // wrong stations for any custom workout where the sequence
    // indices don't match rawValues. This is the bridge's view of
    // the snapshot for both the watch and the duo guest.
    var currentStation: Station? {
        Station(rawValue: currentStationIndex)
    }

    // Resolve the division raw string back to the enum. Falls back to
    // `.mensOpen` for unknown values so the watch UI never shows a
    // garbled target for wall balls on an old / forward-compat payload.
    var division: Division {
        Division(rawValue: divisionRaw) ?? .mensOpen
    }
}

import Foundation

// State snapshot for an in-progress Free Run, transported from
// iPhone → Watch via WCSession's `updateApplicationContext`.
// Companion to `RaceStateSnapshot` (HYROX races); the two are
// mutually exclusive — at any given moment the Watch is
// rendering EITHER a race state OR a free-run state, never
// both.
//
// Same dual-encoding pattern as RaceStateSnapshot:
//   • toDictionary() / init?(dictionary:) — plist-compatible
//     for the WCSession application-context transport.
//   • Codable synthesized — for any future Multipeer or
//     persisted-replay path (none today, but the pattern is
//     consistent across the project).
//
// Time math: the Watch reads `startedAt` and computes elapsed
// locally via `Date() − startedAt`, the same trick the race
// path uses to avoid per-tick pushes. Distance is shipped on
// every meaningful state change (split fired, every ~1s during
// the run).
//
// Empty / nil values are tolerated everywhere — the Watch UI
// degrades gracefully when a sample hasn't arrived yet (HR chip
// hidden, distance reads "0.00" until the first metres
// recordDistance lands).
//
// Shared between iOS and watchOS targets via target membership
// (see project.pbxproj's exception list).
struct FreeRunStateSnapshot: Equatable, Sendable, Codable {

    // The lifecycle phase. Watch UI dispatches on this — paused
    // gets a frozen timer + Resume button, finished pops the
    // wrist back to the idle / waiting state.
    enum Phase: String, Codable, Sendable {
        case notStarted
        case inProgress
        case paused
        case finished
    }

    let phase: Phase

    // When the run timer started ticking. Watch computes elapsed
    // time as `Date() − startedAt` so the wrist counter stays in
    // sync without per-tick pushes.
    let startedAt: Date?

    // Pause timestamp. Non-nil only when phase is `.paused` —
    // the wrist freezes its elapsed-time display at
    // `pausedAt − startedAt` instead of computing live.
    let pausedAt: Date?

    // End timestamp. Non-nil only when phase is `.finished` —
    // wrist shows the static final duration.
    let endedAt: Date?

    // Cumulative distance in metres. Watch converts to the
    // user's chosen unit (mile / km) at the display layer using
    // `splitUnitRaw`. Updated on every distance ingest from the
    // iPhone's HKWorkoutSession.
    let distanceMetres: Double

    // Split unit raw value (mile / km). Stored raw because
    // FreeRunSplitUnit isn't Codable directly through the
    // dictionary path — same pattern divisionRaw uses.
    let splitUnitRaw: String

    // Indoor / outdoor. The wrist UI shows a small chip so the
    // athlete can confirm the right mode is recording (e.g.
    // they didn't accidentally start an indoor run when they
    // meant outdoor).
    let locationTypeRaw: String

    // Latest HR sample. Same field-shape as RaceStateSnapshot's
    // currentHeartRateBPM — wrist renders a chip when present,
    // hides when nil.
    let currentHeartRateBPM: Double?

    // Number of splits captured so far. Drives the "Mile 3 / Mile 4"
    // hint on the wrist. We don't ship the full splits array
    // because the Watch surface doesn't render them (the iPhone
    // summary owns that view).
    let completedSplitCount: Int

    // MARK: - Init

    init(
        phase: Phase,
        startedAt: Date?,
        pausedAt: Date? = nil,
        endedAt: Date? = nil,
        distanceMetres: Double = 0,
        splitUnitRaw: String,
        locationTypeRaw: String,
        currentHeartRateBPM: Double? = nil,
        completedSplitCount: Int = 0
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.endedAt = endedAt
        self.distanceMetres = distanceMetres
        self.splitUnitRaw = splitUnitRaw
        self.locationTypeRaw = locationTypeRaw
        self.currentHeartRateBPM = currentHeartRateBPM
        self.completedSplitCount = completedSplitCount
    }

    // MARK: - Dictionary transport (WCSession)

    private enum Key {
        // `kind` discriminator — present only on the free-run
        // dictionary so the Watch can distinguish a free-run
        // payload from a race payload at decode time. RaceStateSnapshot
        // has its own keys with no `kind`; the receiver tries
        // FreeRunStateSnapshot first via the discriminator and
        // falls back to RaceStateSnapshot.
        static let kind = "kind"
        static let phase = "phase"
        static let startedAt = "startedAt"
        static let pausedAt = "pausedAt"
        static let endedAt = "endedAt"
        static let distanceMetres = "distanceMetres"
        static let splitUnitRaw = "splitUnitRaw"
        static let locationTypeRaw = "locationTypeRaw"
        static let currentHeartRateBPM = "currentHeartRateBPM"
        static let completedSplitCount = "completedSplitCount"
    }

    // Discriminator value identifying this dictionary as a
    // free-run snapshot.
    static let kindValue = "freeRunSnapshot"

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            Key.kind: Self.kindValue,
            Key.phase: phase.rawValue,
            Key.distanceMetres: distanceMetres,
            Key.splitUnitRaw: splitUnitRaw,
            Key.locationTypeRaw: locationTypeRaw,
            Key.completedSplitCount: completedSplitCount
        ]
        if let startedAt {
            dict[Key.startedAt] = startedAt.timeIntervalSince1970
        }
        if let pausedAt {
            dict[Key.pausedAt] = pausedAt.timeIntervalSince1970
        }
        if let endedAt {
            dict[Key.endedAt] = endedAt.timeIntervalSince1970
        }
        if let currentHeartRateBPM {
            dict[Key.currentHeartRateBPM] = currentHeartRateBPM
        }
        return dict
    }

    init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Key.kind] as? String,
              kind == Self.kindValue else {
            return nil
        }
        guard let phaseRaw = dictionary[Key.phase] as? String,
              let phase = Phase(rawValue: phaseRaw),
              let splitUnitRaw = dictionary[Key.splitUnitRaw] as? String,
              let locationTypeRaw = dictionary[Key.locationTypeRaw] as? String
        else {
            return nil
        }
        self.phase = phase
        self.splitUnitRaw = splitUnitRaw
        self.locationTypeRaw = locationTypeRaw
        self.distanceMetres = (dictionary[Key.distanceMetres] as? Double) ?? 0
        self.completedSplitCount = (dictionary[Key.completedSplitCount] as? Int) ?? 0
        self.currentHeartRateBPM = dictionary[Key.currentHeartRateBPM] as? Double

        if let interval = dictionary[Key.startedAt] as? TimeInterval {
            self.startedAt = Date(timeIntervalSince1970: interval)
        } else {
            self.startedAt = nil
        }
        if let interval = dictionary[Key.pausedAt] as? TimeInterval {
            self.pausedAt = Date(timeIntervalSince1970: interval)
        } else {
            self.pausedAt = nil
        }
        if let interval = dictionary[Key.endedAt] as? TimeInterval {
            self.endedAt = Date(timeIntervalSince1970: interval)
        } else {
            self.endedAt = nil
        }
    }
}

import Foundation

// A lifecycle command sent from iPhone → Apple Watch via
// `WCSession.sendMessage(_:replyHandler:errorHandler:)`.
//
// Symmetric counterpart to `WatchAction` (Watch → iPhone user intent):
// this carries workout-session lifecycle commands in the OTHER
// direction. The Watch's `WatchWorkoutManager` runs the actual
// `HKWorkoutSession` + `HKLiveWorkoutBuilder` and reacts to these
// commands, so the Watch's workout state stays in lock-step with the
// iPhone-side race engine without having to reverse-engineer
// transitions from RaceStateSnapshot diffs.
//
// Why `sendMessage` (not `updateApplicationContext`):
//   - These are discrete events that should fire promptly. A delayed
//     `startWorkout` would mean the workout session begins minutes
//     after the race actually started — wrong duration, wrong HR
//     samples attached.
//   - We don't want stale commands queued and replayed on next app
//     launch — pushing a stale `endWorkout` could blow away an
//     in-progress workout session.
//
// Encoding uses key `"control"` so iPhone-side and Watch-side
// dispatchers can disambiguate WatchAction (key `"action"`) from
// WatchControl by inspecting the message dictionary. They're
// directional today (iPhone never receives WatchControl, Watch
// never receives WatchAction), but the disambiguation keeps
// future bidirectional flows clean.
//
// Shared between iOS and watchOS targets via target membership.
enum WatchControl: Sendable, Equatable {

    // Race started. Watch creates an `HKWorkoutSession` of type
    // `.functionalStrengthTraining` (HYROX is mixed strength +
    // conditioning, but `.functionalStrengthTraining` is the
    // closest match in HealthKit's enum) and begins live sample
    // collection. The `Date` is the race's start timestamp — keeps
    // the Watch's workout-session start aligned with the engine's
    // view of the race.
    case startWorkout(at: Date)

    // Race finished (final station completed). Watch ends its
    // workout session and calls `finishWorkout()` on the live
    // builder, persisting the resulting `HKWorkout` to Apple
    // Health. This is what unlocks Activity ring credit for the
    // race and makes it appear in Apple Fitness alongside other
    // workouts.
    case endWorkout(at: Date)

    // Race paused. Watch pauses its workout session — sample
    // collection is held, no activity ring time accumulates while
    // paused. Mirrors the engine's `.paused` state.
    case pauseWorkout

    // Race resumed from a pause. Watch resumes the workout session.
    case resumeWorkout

    // Race abandoned (user tapped Cancel mid-race). Watch ends
    // the workout session WITHOUT calling `finishWorkout()` — no
    // HKWorkout is persisted, no Activity ring credit. Keeps the
    // user's Health data clean from races they didn't actually
    // complete. Mirrors `RaceViewModel.abandon()`.
    case discardWorkout

    // Free Run started. Watch creates an `HKWorkoutSession` of
    // type `.running` with the supplied indoor/outdoor location
    // type — different config from `.startWorkout` which uses
    // `.functionalStrengthTraining`. The Watch's HR + distance
    // collection writes samples to HK in real time during the
    // run, which is what makes the iPhone's HR poll find anything.
    //
    // The locationTypeRaw is the FreeRunLocationType raw value
    // ("indoor" / "outdoor"); decoded on the Watch side via the
    // same enum. Outdoor sessions also get a route builder
    // attached so the GPS polyline saves to Apple Health
    // alongside the HKWorkout.
    case startFreeRunWorkout(at: Date, locationTypeRaw: String)

    // Free Run finished — Watch ends its session and finalizes
    // the HKWorkout. Symmetric to `endWorkout` but kept distinct
    // so the Watch dispatcher knows it's the free-run session
    // it's tearing down (today the Watch tracks at most one
    // session at a time, so the disambiguation is defensive
    // rather than strictly necessary).
    case endFreeRunWorkout(at: Date)

    // MARK: - Dictionary encoding

    private enum Key {
        static let kind = "control"
        static let date = "date"
        static let locationTypeRaw = "locationTypeRaw"
    }

    // Stable raw values — changing these later without a versioning
    // story would break older Watch / iPhone builds talking to
    // newer counterparts.
    private var rawKind: String {
        switch self {
        case .startWorkout:        return "startWorkout"
        case .endWorkout:          return "endWorkout"
        case .pauseWorkout:        return "pauseWorkout"
        case .resumeWorkout:       return "resumeWorkout"
        case .discardWorkout:      return "discardWorkout"
        case .startFreeRunWorkout: return "startFreeRunWorkout"
        case .endFreeRunWorkout:   return "endFreeRunWorkout"
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [Key.kind: rawKind]
        switch self {
        case .startWorkout(let date), .endWorkout(let date), .endFreeRunWorkout(let date):
            // Encoded as TimeInterval (seconds since epoch) — the
            // standard plist-friendly date encoding for WCSession
            // payloads.
            dict[Key.date] = date.timeIntervalSince1970
        case .startFreeRunWorkout(let date, let locationTypeRaw):
            dict[Key.date] = date.timeIntervalSince1970
            dict[Key.locationTypeRaw] = locationTypeRaw
        case .pauseWorkout, .resumeWorkout, .discardWorkout:
            break
        }
        return dict
    }

    init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Key.kind] as? String else { return nil }
        switch kind {
        case "startWorkout":
            guard let ts = dictionary[Key.date] as? TimeInterval else { return nil }
            self = .startWorkout(at: Date(timeIntervalSince1970: ts))
        case "endWorkout":
            guard let ts = dictionary[Key.date] as? TimeInterval else { return nil }
            self = .endWorkout(at: Date(timeIntervalSince1970: ts))
        case "pauseWorkout":   self = .pauseWorkout
        case "resumeWorkout":  self = .resumeWorkout
        case "discardWorkout": self = .discardWorkout
        case "startFreeRunWorkout":
            guard let ts = dictionary[Key.date] as? TimeInterval,
                  let locRaw = dictionary[Key.locationTypeRaw] as? String else { return nil }
            self = .startFreeRunWorkout(
                at: Date(timeIntervalSince1970: ts),
                locationTypeRaw: locRaw
            )
        case "endFreeRunWorkout":
            guard let ts = dictionary[Key.date] as? TimeInterval else { return nil }
            self = .endFreeRunWorkout(at: Date(timeIntervalSince1970: ts))
        default: return nil
        }
    }
}

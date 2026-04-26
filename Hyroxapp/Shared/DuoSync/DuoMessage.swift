import Foundation

// Wire protocol for the iPhone↔iPhone Duo bridge.
//
// Two phones, one race. The leader (host) owns the `RaceEngine`; the
// guest's phone is a remote display + remote input. Messages flow in
// two directions:
//
//   Guest → Host: requests
//     The guest can't mutate the race directly. Their button taps
//     become `request*` messages sent to the host. The host's engine
//     processes them, mutates state, and broadcasts the new state
//     back. This avoids the "two engines drift apart" bug — the host
//     is the single source of truth.
//
//   Host → Guest: state updates
//     Every time the host's engine state changes (start, advance,
//     pause, etc.), the host serializes the new `RaceStateSnapshot`
//     and sends it. The guest replaces its local snapshot and
//     re-renders. The watch already does this exact pattern via
//     WCSession; Duo reuses the same snapshot type.
//
//   Bidirectional:
//     • `hello` — sent by both sides on connect with display name +
//       division so each phone can label the other ("Connected to
//       Sarah") and so the guest's wall-ball rep count uses the
//       host's division at race time.
//     • `disconnect` — explicit "I'm leaving" signal, lets the
//       receiver distinguish a deliberate leave from a network drop.
//
// Why a single enum instead of separate request/response types?
// Multipeer's `MCSession` delivers raw `Data`. We'd need a discriminator
// either way; an enum with associated values gives us type-safe
// dispatch + automatic `Codable` synthesis. JSON over Multipeer keeps
// debugging trivial (just print the bytes as a string).
enum DuoMessage: Codable, Sendable, Equatable {

    // Initial handshake — sent by BOTH sides immediately after the
    // MCSession transitions to `.connected`. Carries identity info
    // the receiver needs to render the partner's name and to share
    // a division at race-start.
    case hello(displayName: String, divisionRaw: String)

    // Guest → host requests. Each maps directly to a method on the
    // host's `RaceViewModel` / `RaceEngine`. The host applies and
    // re-broadcasts; if the host's state can't accept the request
    // (e.g. requestStartNextSegment while in .inProgress), the
    // request is silently dropped — the host's next stateUpdate
    // will resync the guest's view.
    case requestStart
    case requestAdvance
    case requestEndSegment
    case requestStartNextSegment
    case requestPause
    case requestResume
    case requestFinish
    case requestCancel

    // Host → guest broadcasts. Every host-side state mutation pushes
    // one of these. The snapshot is the same type the watch receives
    // — same encoding, same fields, same render path.
    case stateUpdate(snapshot: RaceStateSnapshot)

    // Either side can announce a deliberate disconnect (back button,
    // closing the app via the tab bar, etc.). Lets the receiver
    // distinguish "partner left on purpose" from "network dropped"
    // — both end up as solo-finish locally, but the messaging is
    // friendlier in the deliberate case.
    case disconnect

    // Sender's own latest heart rate sample, in bpm. The receiver
    // stores this as `partnerHeartRateBPM` and surfaces it as a
    // second HR chip on the in-race screen.
    //
    // Why a separate message instead of riding `stateUpdate`?
    // `stateUpdate` flows host→guest only. HR needs to flow both
    // ways (host already ships its HR via snapshot.currentHR; this
    // gives the guest a way to reciprocate). One symmetric message
    // is simpler than embedding it in two different message
    // shapes.
    //
    // Optional payload — `nil` means "I have no current sample
    // (HealthKit not authorized, no Watch streaming, polling
    // hasn't returned yet)." Receivers render a "—" placeholder.
    case localHeartRate(bpm: Double?)

    // MARK: - Encoding

    // JSON over Multipeer. Encoding errors are unrecoverable here
    // (a malformed snapshot would never be sent in the first place),
    // so we crash-on-debug rather than ship a silent failure path.
    func encode() -> Data {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            assertionFailure("DuoMessage.encode failed: \(error)")
            return Data()
        }
    }

    // Returns nil for malformed payloads — the receiver should
    // ignore them (and log) rather than crash. Forward-compat:
    // when we add new message cases later, an old client decoding
    // a new message will simply return nil and skip it.
    static func decode(_ data: Data) -> DuoMessage? {
        try? JSONDecoder().decode(DuoMessage.self, from: data)
    }
}

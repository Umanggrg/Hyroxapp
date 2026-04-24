import Foundation

// `WatchConnectivity` is available on iOS, watchOS, and visionOS but NOT on
// macOS-native. The iOS target supports macOS in its platforms list
// (for Mac-Catalyst-style builds), so we must guard the whole file —
// otherwise Swift's module resolver fails with
// "Unable to resolve module dependency: 'WatchConnectivity'" on macOS.
// Callers guard their use of `WatchCompanionService` with the same check.
#if canImport(WatchConnectivity)
import WatchConnectivity

// The iPhone side of the iPhone↔Apple Watch bridge.
//
// Wraps `WCSession` — Apple's framework for bidirectional messaging
// between a paired iPhone and its Apple Watch companion. The session is
// a singleton managed by the system; we just activate it, set ourselves
// as the delegate, and (in later chunks) send/receive messages through it.
//
// Today this file is intentionally bare — it only activates the session.
// No race-state pushing, no action receiving. That ships in Chunk 2b
// (phone → watch state sync) and Chunk 3 (watch → phone actions). The
// purpose of landing an empty scaffold now is to verify:
//   - both targets can import WatchConnectivity cleanly
//   - the delegate is wired without compile errors
//   - session activation logs a reasonable state at launch
//
// The matching Watch-side class is `WatchRaceClient` in the HyroxappWatch
// target. The two activate independently but pair automatically at the
// system level via `WKCompanionAppBundleIdentifier` (set in the Watch
// target's Info.plist).
//
// Threading notes: `WCSessionDelegate` methods are called on an arbitrary
// queue — never assume MainActor. We mark the delegate methods as
// `nonisolated` to be explicit, and when we later need to update UI state
// from inside a delegate method, we hop to MainActor via `Task { @MainActor in ... }`.
final class WatchCompanionService: NSObject {

    static let shared = WatchCompanionService()

    private override init() {
        super.init()
    }

    // Activates the default `WCSession`. Safe to call multiple times —
    // `activate()` is idempotent on an already-activated session. Callers
    // should invoke this early in app launch (HyroxappApp.init) so any
    // inbound messages from the watch are not dropped because the session
    // wasn't live yet.
    func activate() {
        guard WCSession.isSupported() else {
            // Some simulator or older device configurations don't support
            // WatchConnectivity. Nothing to do — the phone app just runs
            // without a watch companion.
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // Push the latest race state to the watch. Uses
    // `updateApplicationContext(_:)` rather than `sendMessage(_:...)`
    // because:
    //   - we only ever care about the LATEST state, not a history —
    //     context keeps just the most recent payload, replacing any
    //     older one.
    //   - it's delivered even if the watch is currently unreachable
    //     (queued until connectivity returns, then delivered on next
    //     app launch).
    //   - the watch computes its own timer locally from `startedAt`,
    //     so we don't need per-frame pushes — only discrete state
    //     transitions (start, advance, finish, abandon).
    //
    // Errors are swallowed: if the update fails, the next state change
    // will re-push, and in the meantime the watch either keeps showing
    // the last successful snapshot or stays on its idle state. Nothing
    // on the phone side should degrade because the watch isn't listening.
    func publish(_ snapshot: RaceStateSnapshot) {
        let session = WCSession.default
        // Activation can be in-flight on first launch; pushing before it
        // completes raises. Skip if not fully activated — the view will
        // re-push on the next state change once activation finishes.
        guard session.activationState == .activated else { return }

        do {
            try session.updateApplicationContext(snapshot.toDictionary())
        } catch {
            // Intentional: logged silently for now. Hook into a structured
            // logger (`os.Logger`) in a later polish pass.
            _ = error
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchCompanionService: WCSessionDelegate {

    // Called when activation completes (or fails). `state` will typically
    // be `.activated` on a paired-and-reachable watch, `.notActivated` if
    // no watch is paired, `.inactive` in some switching scenarios. We
    // don't surface this to the user today — later we'll flip a
    // reachability flag on `@Observable` state so the UI can show
    // "waiting for watch" or similar.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Intentionally no logging yet — we'll add a structured logger
        // (`Logger` from `os`) in Chunk 2b once we have real events to
        // trace. Silent-by-default during scaffolding.
        _ = (session, activationState, error)
    }

    // iOS only — these two delegate methods don't exist on watchOS (the
    // watch can only be paired with one iPhone at a time). On the iPhone
    // side they're REQUIRED conformance, because an iPhone can unpair
    // from one watch and pair with another without restarting, and iOS
    // needs somewhere to notify us so we can tear down and re-activate.

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // Called when the user starts switching to a different watch.
        // Nothing meaningful to do until Chunk 2b adds real state.
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Called once the switch completes. Apple's guidance: immediately
        // re-activate so the session binds to the new watch. Missing this
        // call is the #1 cause of "my watch stopped receiving messages
        // after I switched devices."
        WCSession.default.activate()
    }
}

#endif  // canImport(WatchConnectivity)

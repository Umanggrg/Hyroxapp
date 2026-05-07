import Foundation
import WatchConnectivity

// The Apple Watch side of the iPhone↔Watch bridge.
//
// Mirror of `WatchCompanionService` on the phone. Receives race state
// pushes (as `RaceStateSnapshot`s) from the phone via `WCSession` and
// publishes them as an observable `snapshot` property so SwiftUI views
// on the watch can render live from it.
//
// `@Observable` gives us free SwiftUI re-rendering whenever `snapshot`
// is reassigned — views that read `client.snapshot.currentStationIndex`
// automatically re-render when a new payload arrives from the phone.
//
// Threading: `WCSessionDelegate` callbacks fire on an arbitrary queue —
// never `@MainActor`. Delegate methods are `nonisolated` and hop to
// the main actor (via `Task { @MainActor in ... }`) before mutating the
// observable state, because `@Observable` state changes must happen on
// the main actor.
@Observable
final class WatchRaceClient: NSObject {

    static let shared = WatchRaceClient()

    // The latest race state pushed by the phone. `nil` means "no race
    // state received yet" — the watch shows an idle/waiting screen in
    // that case. Set on receipt of an application-context update.
    var snapshot: RaceStateSnapshot?

    // The latest Free Run state pushed by the phone. Mutually
    // exclusive with `snapshot` at the rendering layer — the
    // Watch's main view dispatches to either the race UI or the
    // free-run UI based on which one is active. nil means "no
    // free run in progress." Set on receipt of an application-
    // context update with the FreeRunStateSnapshot discriminator.
    var freeRunSnapshot: FreeRunStateSnapshot?

    private override init() {
        super.init()
    }

    // Activates the default `WCSession`. Safe to call multiple times.
    // Called from `HyroxappWatchApp.init` so the session is live before
    // the first view renders and ready to receive any pending messages
    // the phone queued while the watch app was launching.
    //
    // Crucially, the phone's most recent `updateApplicationContext` is
    // delivered even if the watch app wasn't running when it was sent —
    // iOS/watchOS queue it, and the delegate callback fires shortly after
    // activation completes. So the first snapshot may arrive seconds
    // after launch rather than synchronously.
    func activate() {
        guard WCSession.isSupported() else {
            print("[WatchClient] activate: WCSession.isSupported == false")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("[WatchClient] activate called — state=\(session.activationState.rawValue) reachable=\(session.isReachable)")
    }

    // Push a heart-rate sample to the paired iPhone. Called from
    // `WatchWorkoutManager`'s `HKLiveWorkoutBuilderDelegate` whenever
    // a new HR reading is collected during a race.
    //
    // Dual-path delivery for resilience:
    //
    //   1. `sendMessage` — low-latency live delivery. Only succeeds
    //      when the iPhone is reachable (foregrounded or in a state
    //      where WCSession allows live messaging). When it fails,
    //      we don't retry; the next sample arrives in ~1s anyway.
    //
    //   2. `transferUserInfo` — queued background delivery. Survives
    //      phone-backgrounded / locked states, where `sendMessage`
    //      silently drops. Higher latency but eventually consistent.
    //      We send EVERY sample down this channel too so the phone
    //      always has a recent reading even if `sendMessage` was
    //      dropped earlier.
    //
    // Previously this method gated on `session.isReachable`, which
    // is only true when the iPhone app is foregrounded. Pocketing
    // the phone made `isReachable == false` and HR pushes silently
    // disappeared — the bug behind "HR stuck at 70 during a jog."
    // Now we attempt both transports unconditionally; whichever
    // path delivers first wins on the phone (the receiver
    // de-duplicates by sample timestamp).
    func publishHeartRate(_ update: WatchHeartRateUpdate) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let dict = update.toDictionary()

        // Branch on reachability — pick exactly one transport so
        // we don't double-fill WCSession's queue at 1Hz. Either
        // path eventually lands the same sample on the phone; the
        // receiver de-duplicates by `sampledAt` timestamp anyway.
        if session.isReachable {
            // Live path — fires immediately when the iPhone app is
            // foregrounded or in a state where WCSession allows
            // live messaging.
            session.sendMessage(
                dict,
                replyHandler: nil,
                errorHandler: { error in
                    // Most failures are routine (phone briefly
                    // unreachable, locked). Logged-only — the next
                    // sample (~1s later) retries.
                    print("[WatchClient] publishHeartRate sendMessage FAILED — \(error.localizedDescription)")
                }
            )
        } else {
            // Queued path — survives phone backgrounded / locked.
            // transferUserInfo enqueues for delivery as soon as the
            // phone becomes reachable. Fixes the "HR stuck during
            // a jog" case where the previous code gated on
            // `session.isReachable == true` and silently dropped
            // every sample with the phone in a pocket. Higher
            // latency (~5-30s when phone is asleep) but reliable.
            session.transferUserInfo(dict)
        }
    }

    // Send a user-initiated action to the paired iPhone (e.g. "advance
    // to next station" when the Watch's Next button is tapped).
    //
    // Uses `sendMessage(_:replyHandler:errorHandler:)` rather than
    // `updateApplicationContext` because:
    //   - These are real-time intents. If the phone isn't reachable,
    //     we'd rather the tap fail loudly than be silently queued and
    //     delivered much later (advancing the race unexpectedly).
    //   - We don't need a reply today; the phone's state change will
    //     propagate back via the application-context push.
    //
    // Errors are logged but not surfaced to the UI — the user will
    // notice that the Watch didn't update if the tap didn't reach the
    // phone, which is the right feedback.
    func send(_ action: WatchAction) {
        let session = WCSession.default
        print("[WatchClient] send requested action=\(action) state=\(session.activationState.rawValue) reachable=\(session.isReachable)")

        guard session.activationState == .activated else {
            print("[WatchClient] send SKIPPED — not activated")
            return
        }
        guard session.isReachable else {
            print("[WatchClient] send SKIPPED — phone not reachable")
            return
        }

        session.sendMessage(
            action.toDictionary(),
            replyHandler: nil,
            errorHandler: { error in
                print("[WatchClient] send FAILED — \(error.localizedDescription)")
            }
        )
        print("[WatchClient] send dispatched")
    }

    // Merge an incoming raw dictionary into our observable `snapshot`.
    // Called from both the activation callback (picks up any pending
    // context) and the didReceive callback (live updates). Factored out
    // so both paths share the same decode + main-thread handoff logic.
    //
    // `nonisolated` so it can be safely called from the nonisolated
    // `WCSessionDelegate` callbacks (which fire on an arbitrary background
    // queue). The decode + log work runs on whatever queue the delegate
    // hands us; only the final write to the @Observable `snapshot`
    // property hops to the MainActor via the Task block, which is the
    // contract @Observable requires.
    nonisolated private func ingest(_ dictionary: [String: Any]) {
        print("[WatchClient] ingest called — keys: \(dictionary.keys.sorted())")

        // Try the Free Run discriminator first — the dictionary
        // carries `kind = "freeRunSnapshot"` when it's a free-run
        // payload. Race snapshots have no such discriminator, so
        // they fall through to RaceStateSnapshot decoding.
        if let freeRun = FreeRunStateSnapshot(dictionary: dictionary) {
            print("[WatchClient] ingest OK FREE-RUN phase=\(freeRun.phase.rawValue) distance=\(Int(freeRun.distanceMetres))m")
            Task { @MainActor in
                // Activating a free run clears any prior race
                // snapshot so the wrist UI dispatcher picks the
                // free-run surface unambiguously. Conversely, a
                // .notStarted free-run snapshot means "free run
                // ended" — clear so the wrist returns to its
                // race / idle UI.
                if freeRun.phase == .notStarted {
                    self.freeRunSnapshot = nil
                } else {
                    self.freeRunSnapshot = freeRun
                    self.snapshot = nil
                }
            }
            return
        }

        guard let snapshot = RaceStateSnapshot(dictionary: dictionary) else {
            print("[WatchClient] ingest FAILED to decode snapshot")
            return
        }

        print("[WatchClient] ingest OK phase=\(snapshot.phase.rawValue) stationIndex=\(snapshot.currentStationIndex)")
        Task { @MainActor in
            self.snapshot = snapshot
            // A race snapshot pushing in implies no free run is
            // active (mutually exclusive surfaces); clear stale
            // free-run state defensively.
            self.freeRunSnapshot = nil
            print("[WatchClient] snapshot assigned on MainActor")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchRaceClient: WCSessionDelegate {

    // Fires when activation finishes. If the phone pushed an application
    // context while the watch app was asleep/launching, it's delivered
    // now via `session.receivedApplicationContext`. We pick it up so the
    // watch opens with the latest known state instead of a blank screen.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("[WatchClient] activation completed — state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none") reachable=\(session.isReachable)")
        guard activationState == .activated else { return }

        let pending = session.receivedApplicationContext
        print("[WatchClient] receivedApplicationContext has \(pending.count) keys")
        if !pending.isEmpty {
            ingest(pending)
        }
    }

    // Live updates from the phone while the watch app is running.
    // Fires whenever `WCSession.default.updateApplicationContext(_:)` is
    // called on the phone side with a different dictionary than last time.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        print("[WatchClient] didReceiveApplicationContext FIRED — \(applicationContext.count) keys")
        ingest(applicationContext)
    }

    // Live messages from the phone via `sendMessage`. Today these
    // are exclusively `WatchControl` lifecycle commands that drive
    // the Watch's HKWorkoutSession (start, end, pause, resume,
    // discard). Decoded on the background queue, then dispatched to
    // the MainActor-isolated `WatchWorkoutManager`.
    //
    // Distinct from `didReceiveApplicationContext` which carries
    // race-state snapshots — that's a different transport
    // (updateApplicationContext) for different content (state vs.
    // commands).
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchClient] didReceiveMessage FIRED — keys: \(message.keys.sorted())")
        guard let control = WatchControl(dictionary: message) else {
            print("[WatchClient] didReceiveMessage — failed to decode control, ignoring")
            return
        }
        print("[WatchClient] didReceiveMessage decoded control=\(control)")

        Task { @MainActor in
            WatchWorkoutManager.shared.handle(control)
        }
    }

    // Queued user-info delivery. WatchCompanionService falls back
    // to `transferUserInfo` for `WatchControl` commands when the
    // Watch app wasn't reachable at send time (e.g. iPhone tapped
    // Start while the Watch app was asleep). The queued payload
    // lands here whenever the Watch app next runs — we decode the
    // same `WatchControl` shape and dispatch it to the workout
    // manager. Late delivery is fine because controls carry their
    // own timestamp; `startWorkout(at:)` backdates the HK session
    // accordingly.
    //
    // Distinct from `didReceiveMessage` (live transport, only
    // fires when both apps are foregrounded). Both routes
    // converge on `WatchWorkoutManager.handle` so the lifecycle
    // behavior is identical regardless of transport.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String : Any] = [:]
    ) {
        print("[WatchClient] didReceiveUserInfo FIRED — keys: \(userInfo.keys.sorted())")
        guard let control = WatchControl(dictionary: userInfo) else {
            print("[WatchClient] didReceiveUserInfo — not a control, ignoring")
            return
        }
        print("[WatchClient] didReceiveUserInfo decoded control=\(control)")

        Task { @MainActor in
            WatchWorkoutManager.shared.handle(control)
        }
    }
}

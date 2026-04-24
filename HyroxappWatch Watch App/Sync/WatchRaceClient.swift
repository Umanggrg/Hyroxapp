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
    private func ingest(_ dictionary: [String: Any]) {
        print("[WatchClient] ingest called — keys: \(dictionary.keys.sorted())")
        guard let snapshot = RaceStateSnapshot(dictionary: dictionary) else {
            print("[WatchClient] ingest FAILED to decode snapshot")
            return
        }

        print("[WatchClient] ingest OK phase=\(snapshot.phase.rawValue) stationIndex=\(snapshot.currentStationIndex)")
        Task { @MainActor in
            self.snapshot = snapshot
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
}

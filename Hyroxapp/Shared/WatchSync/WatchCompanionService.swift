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

    // Callback invoked on MainActor when the Watch sends an action
    // (e.g. tap Next Station from the wrist). Callers — typically
    // `RaceView` — set this on `.onAppear` and clear it on
    // `.onDisappear` so incoming actions are dispatched to whatever
    // view is currently orchestrating the race. If no handler is set
    // (race tab not on screen), the action is logged and dropped —
    // advancing a race the user isn't looking at would be confusing.
    //
    // `@MainActor @Sendable` closure signature so it can be invoked
    // from the nonisolated delegate method via `Task { @MainActor in
    // onAction?(action) }` without concurrency warnings.
    var onAction: (@MainActor @Sendable (WatchAction) -> Void)?

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
            print("[WatchCompanion] activate: WCSession.isSupported == false, skipping")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("[WatchCompanion] activate called — state=\(session.activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
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

        // Skip silently when the Watch app isn't installed on the
        // paired Watch. This is the common case for athletes who
        // haven't installed the companion (or are on a free dev
        // account where the Watch install path is unreliable, like
        // we kept hitting in development). Pushing in that state
        // would call updateApplicationContext repeatedly, fail with
        // WCErrorCodeWatchAppNotInstalled on every state change, and
        // spam the console with no-ops. Once the Watch app is
        // actually installed, paired iOS reports isWatchAppInstalled
        // == true and publishes start flowing again.
        guard session.isWatchAppInstalled else {
            return
        }

        print("[WatchCompanion] publish requested phase=\(snapshot.phase.rawValue) stationIndex=\(snapshot.currentStationIndex) state=\(session.activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")

        // Activation can be in-flight on first launch; pushing before it
        // completes raises. Skip if not fully activated — the view will
        // re-push on the next state change once activation finishes.
        guard session.activationState == .activated else {
            print("[WatchCompanion] publish SKIPPED — not activated")
            return
        }

        do {
            try session.updateApplicationContext(snapshot.toDictionary())
            print("[WatchCompanion] publish OK")
        } catch {
            print("[WatchCompanion] publish FAILED — \(error.localizedDescription)")
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
        print("[WatchCompanion] activation completed — state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none") paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
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

    // Watch → iPhone action receiver. Fired when the Watch calls
    // `sendMessage(_:...)` with a payload that decodes into a WatchAction.
    // Decodes on the background queue, then hops to MainActor to invoke
    // the callback (which will typically mutate the race view model).
    //
    // This version has no replyHandler parameter — the Watch sends
    // actions fire-and-forget. If we later need acknowledgements
    // (e.g. "did the phone actually advance?"), we'd add a paired
    // delegate method with a replyHandler.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchCompanion] didReceiveMessage FIRED — keys: \(message.keys.sorted())")
        guard let action = WatchAction(dictionary: message) else {
            print("[WatchCompanion] didReceiveMessage — failed to decode action, ignoring")
            return
        }

        Task { @MainActor in
            print("[WatchCompanion] dispatching action=\(action) — handler \(Self.shared.onAction == nil ? "NOT set" : "set")")
            Self.shared.onAction?(action)
        }
    }
}

#endif  // canImport(WatchConnectivity)

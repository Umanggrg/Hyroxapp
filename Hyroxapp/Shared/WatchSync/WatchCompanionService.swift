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

    // Callback invoked on MainActor when the Watch publishes a new
    // heart-rate sample during a race. Set by `RaceView` for the
    // active-race lifetime; the handler typically forwards the
    // sample into `RaceViewModel.ingestHeartRate(_:)` which writes
    // to `currentHeartRateBPM` (the same property the existing
    // phone-side HR poll writes to, so all downstream consumers —
    // race screen chip, Live Activity, snapshot publishing to the
    // duo partner — keep working unchanged).
    //
    // When the Watch isn't paired or isn't running the workout
    // session (no HKWorkoutSession active), this callback simply
    // never fires and the phone's existing HealthKit-poll path
    // continues to populate `currentHeartRateBPM` as a fallback.
    var onHeartRate: (@MainActor @Sendable (WatchHeartRateUpdate) -> Void)?

    // §39 — callback invoked on MainActor when the Watch publishes
    // a cumulative-distance sample during a Free Run. Set by
    // FreeRunViewModel for the active-run lifetime; the handler
    // forwards the value into the engine via
    // `recordDistance(at:metres:)`. Solves the treadmill bug —
    // when the iPhone is sitting stationary on the treadmill
    // console, its CMPedometer reports zero metres, but the
    // Watch on the user's wrist sees real motion. With this
    // callback wired, the wrist-grade distance feeds the engine
    // and the iPhone pedometer's zero updates are silently
    // dropped by the engine's monotonic filter.
    //
    // Inactive for HYROX races — those use .functionalStrengthTraining
    // activity, which doesn't collect distanceWalkingRunning.
    var onDistance: (@MainActor @Sendable (WatchDistanceUpdate) -> Void)?

    // §13.8 Tier 2 — callback invoked on MainActor when the Watch
    // publishes a rep-count update during a rep-counting station
    // (Phase 1 — wall balls). Set by RaceView for the active-race
    // lifetime; the handler forwards the update into RaceViewModel
    // which holds the latest count per station rawValue and stamps
    // it onto Split.repsCompleted at engine.advance time.
    //
    // When no rep-counting station is active (or the Watch lacks
    // compatible motion hardware), this callback simply never
    // fires and Split.repsCompleted stays at whatever manual value
    // the athlete entered (or nil).
    var onRepCount: (@MainActor @Sendable (WatchRepCountUpdate) -> Void)?

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

    // Symmetric publish for Free Run state. The Watch dispatches
    // on the snapshot's `kind` discriminator and renders the free-
    // run live UI when this lands instead of the race UI. Same
    // transport (updateApplicationContext) — only one
    // application-context dictionary is in flight at a time, so
    // the Watch never sees both a race AND a free-run snapshot
    // simultaneously.
    func publishFreeRun(_ snapshot: FreeRunStateSnapshot) {
        let session = WCSession.default
        guard session.isWatchAppInstalled else { return }
        guard session.activationState == .activated else {
            print("[WatchCompanion] publishFreeRun SKIPPED — not activated")
            return
        }
        do {
            try session.updateApplicationContext(snapshot.toDictionary())
            print("[WatchCompanion] publishFreeRun OK phase=\(snapshot.phase.rawValue) distance=\(Int(snapshot.distanceMetres))m")
        } catch {
            print("[WatchCompanion] publishFreeRun FAILED — \(error.localizedDescription)")
        }
    }

    // Push a workout-lifecycle control to the Watch. Uses
    // `sendMessage(_:replyHandler:errorHandler:)` (not
    // `updateApplicationContext`) because:
    //   - These are discrete events that should fire promptly. A
    //     delayed `startWorkout` would mean the workout session
    //     begins minutes after the race actually started.
    //   - We don't want stale commands queued and replayed on a
    //     later launch (could blow away an in-progress workout).
    //
    // Bails silently when the Watch app isn't installed or the
    // session isn't reachable — phone-side race continues unaffected,
    // and the existing iOS-side HealthKit fallback (poll + write
    // workout on finish) covers the no-Watch case.
    func sendControl(_ control: WatchControl) {
        let session = WCSession.default

        guard session.isWatchAppInstalled else {
            // No Watch installed — phone-side race continues without
            // a Watch workout session. Phone's HealthKit polling +
            // saveRace fallback handles HR + workout persistence in
            // this case.
            return
        }

        guard session.activationState == .activated else {
            print("[WatchCompanion] sendControl SKIPPED — not activated")
            return
        }

        guard session.isReachable else {
            // Watch isn't currently reachable (app asleep / wrist
            // down / out of range). `sendMessage` would silently
            // drop the command — that was the root cause of the
            // "HR not showing" bug: iPhone tap → start command
            // dropped → Watch never started its HKWorkoutSession
            // → no HR samples on either surface.
            //
            // Fall through to `transferUserInfo` so the command is
            // queued for delivery as soon as the Watch app runs
            // again. WatchRaceClient's `didReceiveUserInfo`
            // handler decodes it and dispatches it to the
            // workout manager. Late delivery is acceptable here
            // because:
            //   • WatchRaceView ALSO self-heals from the snapshot
            //     phase (see synchronizeWorkoutSession) — even if
            //     this queued message never lands, the snapshot
            //     alone is enough to start the session.
            //   • Both the start and end controls carry their own
            //     timestamp, so a delayed `startWorkout` still
            //     backdates the HK session to the actual race
            //     start, not to delivery time.
            print("[WatchCompanion] sendControl QUEUED via transferUserInfo — watch not reachable control=\(control)")
            session.transferUserInfo(control.toDictionary())
            return
        }

        session.sendMessage(
            control.toDictionary(),
            replyHandler: nil,
            errorHandler: { error in
                print("[WatchCompanion] sendControl FAILED — \(error.localizedDescription)")
                // Live delivery failed (watch became unreachable
                // mid-flight, transient WCSession error, etc.).
                // Re-queue via the durable transport so the
                // command isn't lost.
                session.transferUserInfo(control.toDictionary())
            }
        )
        print("[WatchCompanion] sendControl dispatched control=\(control)")
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

    // Watch → iPhone message receiver. Fired when the Watch calls
    // `sendMessage(_:...)`. Two payload types flow over this channel:
    //
    //   • WatchAction — user intent ("advance to next station") from
    //     the Watch's race screen buttons.
    //   • WatchHeartRateUpdate — live HR samples from the Watch's
    //     HKLiveWorkoutBuilder, throttled to ~1Hz.
    //
    // Disambiguated by the dictionary's `kind` / `action` discriminator
    // keys. Decoded on the background queue, then dispatched to the
    // appropriate MainActor callback.
    //
    // Fire-and-forget — no replyHandler. If we later need
    // acknowledgements (e.g. "did the phone actually advance?"),
    // we'd add a paired delegate method with a replyHandler.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchCompanion] didReceiveMessage FIRED — keys: \(message.keys.sorted())")

        // HR updates first because they're the high-frequency case —
        // the typecast attempt is cheap and most messages during a
        // race will be HR samples.
        if let hrUpdate = WatchHeartRateUpdate(dictionary: message) {
            Task { @MainActor in
                Self.shared.onHeartRate?(hrUpdate)
            }
            return
        }

        // §39 — Free Run distance samples from the Watch's
        // HKLiveWorkoutBuilder. Fires only during Free Runs
        // (.running activity collects distanceWalkingRunning);
        // HYROX races don't produce these.
        if let distanceUpdate = WatchDistanceUpdate(dictionary: message) {
            Task { @MainActor in
                Self.shared.onDistance?(distanceUpdate)
            }
            return
        }

        // §13.8 Tier 2 — rep count updates during wall balls
        // (Phase 1). Same throttled-publish cadence as HR (~1Hz),
        // routed through the same MainActor handler pattern.
        if let repUpdate = WatchRepCountUpdate(dictionary: message) {
            Task { @MainActor in
                Self.shared.onRepCount?(repUpdate)
            }
            return
        }

        if let action = WatchAction(dictionary: message) {
            Task { @MainActor in
                print("[WatchCompanion] dispatching action=\(action) — handler \(Self.shared.onAction == nil ? "NOT set" : "set")")
                Self.shared.onAction?(action)
            }
            return
        }

        print("[WatchCompanion] didReceiveMessage — unrecognized payload, ignoring")
    }

    // Receives queued payloads sent via `transferUserInfo`.
    // Survives phone-backgrounded / locked states where
    // `didReceiveMessage` doesn't fire — that's the gap this
    // delegate closes. Used as a redundant channel for HR samples
    // so the in-pocket-phone case still gets recent readings.
    //
    // The watch publishes every HR sample via BOTH `sendMessage`
    // (when reachable) and `transferUserInfo` (always). On the
    // receiving side both can deliver the same sample; the
    // RaceViewModel's ingest path de-duplicates by `sampledAt`
    // timestamp so the redundancy doesn't double-update the chip.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        print("[WatchCompanion] didReceiveUserInfo FIRED — keys: \(userInfo.keys.sorted())")

        // Same payload shape as didReceiveMessage. We support HR
        // updates here today; future queued payloads (analytics
        // batches, sample backfills) can branch off the same dict
        // shape recognition.
        if let hrUpdate = WatchHeartRateUpdate(dictionary: userInfo) {
            Task { @MainActor in
                Self.shared.onHeartRate?(hrUpdate)
            }
            return
        }

        // §39 — queued distance fallback. The Watch publishes
        // every distance sample via transferUserInfo when the
        // iPhone isn't reachable (locked / pocketed). Late
        // delivery is fine because the engine de-dups by
        // monotonic comparison — a queued sample arriving after
        // a fresher one is simply ignored.
        if let distanceUpdate = WatchDistanceUpdate(dictionary: userInfo) {
            Task { @MainActor in
                Self.shared.onDistance?(distanceUpdate)
            }
            return
        }

        // §13.8 Tier 2 — rep count via the queued path. Same
        // de-dup discipline as HR (ingest handler keys by
        // sampledAt). transferUserInfo is the fallback when the
        // iPhone is locked / pocketed; late delivery is fine
        // because the phone-side ingest applies the latest count
        // for a station as long as the station hasn't been
        // closed manually.
        if let repUpdate = WatchRepCountUpdate(dictionary: userInfo) {
            Task { @MainActor in
                Self.shared.onRepCount?(repUpdate)
            }
            return
        }

        print("[WatchCompanion] didReceiveUserInfo — unrecognized payload, ignoring")
    }
}

#endif  // canImport(WatchConnectivity)

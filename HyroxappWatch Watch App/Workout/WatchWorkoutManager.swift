import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

// On-Watch workout-session manager. Owns the live `HKWorkoutSession` +
// `HKLiveWorkoutBuilder` for the duration of a race so:
//
//   1. Heart rate samples stream at the Watch's native ~1Hz cadence
//      (Round 3 — sample collection wiring lands then; Round 2 just
//      sets up the session so HealthKit collects samples in the
//      background ready to be consumed).
//   2. Apple Health receives a real `HKWorkout` with attached samples
//      when the race finishes — earns Activity ring credit + proper
//      "Functional Strength Training" categorization.
//   3. The Watch app stays alive with screen-off because workout
//      sessions automatically extend runtime on watchOS — no
//      separate background mode declaration required.
//
// Round 2 scope (this file's current state): full lifecycle. The phone
// sends `WatchControl` commands via WCSession; this manager turns them
// into `HKWorkoutSession.startActivity` / `pause` / `resume` / `end`
// calls and finalizes the workout via `HKLiveWorkoutBuilder.finishWorkout()`
// when the race completes. Sample-collection delegate callbacks fire
// throughout but their data isn't yet streamed to the iPhone — that's
// Round 3.
//
// Threading model:
//   - The manager itself is `@MainActor` so view code can read its
//     state directly.
//   - `HKWorkoutSessionDelegate` and `HKLiveWorkoutBuilderDelegate`
//     callbacks fire on an arbitrary HealthKit queue (`nonisolated`).
//     Each delegate method hops to MainActor via `Task` before
//     mutating the manager's state.
//
// Singleton because there's only ever one active workout session per
// device, and the phone-side caller wants a stable handle to send
// controls to.
#if canImport(HealthKit)

@MainActor
@Observable
final class WatchWorkoutManager: NSObject {

    static let shared = WatchWorkoutManager()

    // The HealthKit store. Single instance owned by this manager.
    // `HKHealthStore` is the documented entry point and is safe to
    // hold long-term; Apple recommends one per app.
    private let healthStore = HKHealthStore()

    // Tracks whether we've successfully obtained read+write
    // authorization for the types this app needs. Mostly diagnostic
    // — the actual gate at race-start time will be `healthStore`'s
    // `authorizationStatus(for:)` since the user can revoke
    // permissions in iOS Settings between launches.
    private(set) var isAuthorized: Bool = false

    // True while a HealthKit auth request is in flight. Prevents
    // double-prompting if the app launches twice in quick succession
    // before the first request resolves.
    private var isAuthorizationInFlight: Bool = false

    // The active workout session, if any. Non-nil during a race.
    // `HKWorkoutSession` is not `Sendable` — we keep it pinned to
    // MainActor by holding it on this `@MainActor` class.
    private var workoutSession: HKWorkoutSession?

    // The live builder that collects samples (HR, energy, etc.) for
    // the active session. Pairs 1:1 with `workoutSession` — created
    // and destroyed together.
    private var workoutBuilder: HKLiveWorkoutBuilder?

    // Tracks whether the manager has an active workout session, for
    // defensive guards. `HKWorkoutSession.startActivity` raises if
    // called twice without an `end` in between.
    private(set) var isWorkoutActive: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    // The HealthKit data types the Watch app reads + writes.
    //
    // Reads:
    //   • heart rate — sampled into per-station HR avg/max + the live
    //     BPM chip on the race screen.
    //   • active energy burned — surfaces as per-station calories on
    //     the post-race summary.
    //
    // Writes:
    //   • workouts — completed races persisted as `HKWorkout` rows
    //     so they appear in Apple Fitness alongside Strava etc. and
    //     close Activity rings.
    private static var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    private static var typesToWrite: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    // Request HealthKit authorization. Idempotent — calling twice in
    // a row is a no-op the second time. Failures are logged and
    // swallowed; the race UI continues to work without HR data, just
    // without the live BPM chip and per-station HR averages.
    func requestAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard !isAuthorizationInFlight else { return }

        isAuthorizationInFlight = true

        Task {
            defer { isAuthorizationInFlight = false }

            do {
                try await healthStore.requestAuthorization(
                    toShare: Self.typesToWrite,
                    read: Self.typesToRead
                )
                isAuthorized = true
            } catch {
                isAuthorized = false
            }
        }
    }

    // MARK: - Control dispatch

    // Single entry point invoked from `WatchRaceClient` when the
    // iPhone sends a `WatchControl` over WCSession. Centralizes
    // dispatch so the bridge code stays tiny and the manager owns
    // the lifecycle invariants.
    func handle(_ control: WatchControl) {
        print("[WatchWorkout] handle control=\(control)")
        switch control {
        case .startWorkout(let date):
            start(at: date)
        case .endWorkout(let date):
            end(at: date, finalize: true)
        case .pauseWorkout:
            pause()
        case .resumeWorkout:
            resume()
        case .discardWorkout:
            end(at: Date(), finalize: false)
        }
    }

    // MARK: - Lifecycle

    // Begin a new HKWorkoutSession + HKLiveWorkoutBuilder pair. The
    // session keeps the Watch app awake with screen-off and surfaces
    // the workout to iOS's running-workouts list. The builder collects
    // samples (HR, active energy) automatically so they're ready to
    // be persisted on `finishWorkout`.
    private func start(at startDate: Date) {
        guard !isWorkoutActive else {
            // Defensive: HKWorkoutSession.startActivity raises if
            // called on an already-active session. Bail silently
            // rather than crash. The most likely cause is a
            // duplicate `startWorkout` due to retried WCSession
            // delivery.
            print("[WatchWorkout] start IGNORED — workout already active")
            return
        }

        // HYROX is mixed strength + conditioning; .functionalStrengthTraining
        // is the closest activity type. Indoor — HYROX is an indoor
        // race format (per CLAUDE.md §1 non-goals) and the location
        // type affects calorie estimation.
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            session.delegate = self
            builder.delegate = self

            // Start the session FIRST, then start collection. Order
            // matters per Apple's docs — collection on a non-running
            // session would error.
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { success, error in
                if let error {
                    print("[WatchWorkout] beginCollection FAILED — \(error.localizedDescription)")
                } else {
                    print("[WatchWorkout] beginCollection OK success=\(success)")
                }
            }

            self.workoutSession = session
            self.workoutBuilder = builder
            self.isWorkoutActive = true

            print("[WatchWorkout] start OK at=\(startDate)")
        } catch {
            print("[WatchWorkout] start FAILED — \(error.localizedDescription)")
        }
    }

    // End the active workout session.
    //
    // `finalize == true` (race completed normally): after the session
    // transitions to `.ended`, the HKWorkoutSessionDelegate callback
    // calls `endCollection` then `finishWorkout()` to persist the
    // resulting HKWorkout to Apple Health.
    //
    // `finalize == false` (race abandoned via Cancel): we end the
    // session but discard the builder without persisting. No
    // HKWorkout row is created; Activity ring credit is not awarded
    // for the partial work. Keeps user's Health data clean.
    private func end(at endDate: Date, finalize: Bool) {
        guard isWorkoutActive, let session = workoutSession else {
            print("[WatchWorkout] end IGNORED — no active workout")
            return
        }

        // Stash whether to finalize on the manager so the delegate
        // callback (which fires after session.end()) knows what to
        // do. Cleared after dispatch.
        self.pendingFinalize = finalize

        // session.end() asynchronously transitions the session to
        // `.ended` and fires the delegate callback. The callback
        // then calls `endCollection` + `finishWorkout` (or discards).
        session.end()
        print("[WatchWorkout] end requested at=\(endDate) finalize=\(finalize)")
    }

    // Pause the active session. HealthKit halts sample collection
    // until resume is called.
    private func pause() {
        guard let session = workoutSession else { return }
        session.pause()
        print("[WatchWorkout] pause requested")
    }

    private func resume() {
        guard let session = workoutSession else { return }
        session.resume()
        print("[WatchWorkout] resume requested")
    }

    // Whether the next `session.ended` transition should call
    // finishWorkout (true) or discard (false). Set by `end(at:finalize:)`,
    // read by the HKWorkoutSessionDelegate.
    private var pendingFinalize: Bool = true

    // Throttle gate for HR publishing to the iPhone. Even though
    // HKLiveWorkoutBuilder samples at ~1-2Hz natively, the delegate
    // method can fire in bursts during state changes — coalescing to
    // ~1Hz keeps WCSession's per-app message budget healthy without
    // sacrificing the live-feeling UI updates on the iPhone side.
    private var lastHRPublishedAt: Date = .distantPast
    private static let minHRPublishInterval: TimeInterval = 0.8

    // Tear down the manager's references after the session has fully
    // ended. Called from the delegate's didChangeTo:.ended branch.
    private func clearWorkoutHandles() {
        self.workoutSession = nil
        self.workoutBuilder = nil
        self.isWorkoutActive = false
        self.pendingFinalize = true
        self.lastHRPublishedAt = .distantPast
    }

    // MARK: - HR publishing

    // Extract the most recent HR sample from the live builder's
    // statistics and forward it to the iPhone via WCSession.
    // Called from the `HKLiveWorkoutBuilderDelegate` whenever new
    // HR samples land. Throttled to ~1Hz so we don't flood the
    // WC channel during sample bursts.
    fileprivate func publishLatestHeartRateIfNeeded(
        from builder: HKLiveWorkoutBuilder
    ) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let stats = builder.statistics(for: hrType),
              let mostRecent = stats.mostRecentQuantity() else {
            return
        }

        // Throttle: skip if we published within the last interval.
        let now = Date()
        guard now.timeIntervalSince(lastHRPublishedAt) >= Self.minHRPublishInterval else {
            return
        }
        lastHRPublishedAt = now

        // Extract bpm. HealthKit's HR unit is count per minute.
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let bpm = mostRecent.doubleValue(for: bpmUnit)

        // Sanity guard against bogus values (HealthKit occasionally
        // emits 0 or absurdly high readings during sensor warmup
        // or contact loss).
        guard bpm >= 30, bpm <= 230 else { return }

        // Use the sample's actual end time when available so the
        // phone can deduplicate / reject stale samples that arrive
        // out of order via WCSession queuing.
        let sampledAt = stats.mostRecentQuantityDateInterval()?.end ?? now

        let update = WatchHeartRateUpdate(bpm: bpm, sampledAt: sampledAt)
        WatchRaceClient.shared.publishHeartRate(update)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {

    // Fires when the session transitions between states (.notStarted
    // → .running → .paused/.running → .ended). Apple's pattern is to
    // wait for `.ended` here and call `endCollection` + `finishWorkout`
    // on the builder — running those before the session has fully
    // ended races against in-flight sample writes.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("[WatchWorkout] session state \(fromState.rawValue) → \(toState.rawValue)")

        guard toState == .ended else { return }

        // Hop to MainActor before reading our own state — the manager
        // is MainActor-isolated and `pendingFinalize` lives here.
        Task { @MainActor in
            guard let builder = self.workoutBuilder else {
                print("[WatchWorkout] state .ended but no builder — clearing handles")
                self.clearWorkoutHandles()
                return
            }

            let shouldFinalize = self.pendingFinalize

            if shouldFinalize {
                // Race finished normally. End collection at the
                // session's actual end timestamp, then finalize.
                builder.endCollection(withEnd: date) { _, endError in
                    if let endError {
                        print("[WatchWorkout] endCollection FAILED — \(endError.localizedDescription)")
                    }

                    // finishWorkout persists the HKWorkout. Fires on
                    // an arbitrary queue; hop to MainActor to clear
                    // our own state.
                    builder.finishWorkout { workout, finishError in
                        if let finishError {
                            print("[WatchWorkout] finishWorkout FAILED — \(finishError.localizedDescription)")
                        } else if let workout {
                            print("[WatchWorkout] finishWorkout OK duration=\(workout.duration)")
                        }
                        Task { @MainActor in
                            self.clearWorkoutHandles()
                        }
                    }
                }
            } else {
                // Race abandoned. Discard the builder so no
                // HKWorkout is persisted.
                builder.discardWorkout()
                print("[WatchWorkout] discardWorkout — race abandoned")
                self.clearWorkoutHandles()
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        // Most failures are recoverable from the user's perspective —
        // the workout session can fail mid-race (e.g. low battery
        // forcing watchOS to drop the session) but the iPhone-side
        // race continues unaffected, just without Activity ring
        // credit for this race. Log + clear state.
        print("[WatchWorkout] session FAILED — \(error.localizedDescription)")
        Task { @MainActor in
            self.clearWorkoutHandles()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {

    // Fires when the builder collects a new sample (heart rate,
    // active energy, etc). Filter for HR samples specifically and
    // forward the latest reading to the iPhone via WCSession so the
    // race screen's live BPM chip + the Live Activity HR display
    // update from the Watch's first-party source instead of the
    // phone's HealthKit-polling fallback.
    //
    // Active energy samples ride along into the eventual HKWorkout
    // automatically when finishWorkout is called — no separate
    // forwarding needed.
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        guard collectedTypes.contains(hrType) else { return }

        // Hop to MainActor to read manager state (lastHRPublishedAt)
        // and to call into WatchRaceClient.shared on its expected
        // actor. The builder reference is captured locally — it's
        // safe to use across the hop because HKLiveWorkoutBuilder
        // serializes its own sample queries.
        Task { @MainActor in
            self.publishLatestHeartRateIfNeeded(from: workoutBuilder)
        }
    }

    // Fires for in-workout events (lap markers, pauses). Stub for now.
    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {
        // No-op in Round 2.
    }
}

#else

// Non-HealthKit platforms (e.g. macOS Designed-for-iPad builds, the
// simulator on platforms where HealthKit isn't linked) get a no-op
// stub so call sites compile cleanly.
@MainActor
final class WatchWorkoutManager {
    static let shared = WatchWorkoutManager()
    private init() {}
    func requestAuthorizationIfNeeded() {}
    func handle(_ control: WatchControl) {}
}

#endif

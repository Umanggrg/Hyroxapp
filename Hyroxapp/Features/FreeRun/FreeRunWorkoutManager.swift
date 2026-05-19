import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// iPhone-side distance + HR source for Free Run.
//
// Three layers compose this manager:
//
//   • CMPedometer — drives indoor distance (treadmill, gym track) and
//     contributes outdoor distance when GPS is sparse / blocked. iOS
//     reports cumulative distance derived from step count + the device's
//     built-in stride model.
//   • CLLocationManager — outdoor GPS. When fixes are accurate enough
//     (≤50m horizontal accuracy and ≤10s stale), distance integrates
//     from the CL-derived deltas, overriding the pedometer's estimate
//     for the more accurate GPS reading.
//   • HKWorkoutSession + HKLiveWorkoutBuilder (iOS 26.0+) — phone-side
//     workout context. CRITICAL for AirPods Pro 3 HR — Apple's docs are
//     explicit that in-ear PPG samples only flow into HealthKit while a
//     supported HKWorkoutSession is active (Watch's OR iPhone's, doesn't
//     matter which). Without this, an athlete with AirPods Pro 3 and no
//     paired Apple Watch sees zero HR data even though the sensor on
//     their ear is sensing it perfectly.
//
//     Availability: iPhone-side HKLiveWorkoutBuilder requires iOS 26.0+
//     (an earlier Phase 41 comment claimed iOS 17.0+; that was wrong —
//     the Xcode SDK rejects HKLiveWorkoutBuilder usage on iOS targets
//     below 26.0). Practical impact: zero. AirPods Pro 3 hardware
//     itself requires iOS 26.0 to pair, so anyone in the "AirPods Pro
//     3 + no Watch" case is already on iOS 26+. iOS 17-25 users fall
//     back to the pre-§41 behavior: no iPhone-side session, no AirPods
//     Pro 3 HR — but they couldn't have AirPods Pro 3 anyway. The
//     stored session / builder slots use Any? typing to dodge the
//     type-level availability error; cast inside `if #available(iOS 26,
//     *)` blocks at every use site.
//
//   • The session ALSO buys us a real HKWorkout written to Apple Health
//     on finish — Activity ring credit + an entry in the Fitness app —
//     which the previous polling-only implementation lost.
//
// Coordination with the Watch path: when a paired Watch IS available,
// it runs its own HKWorkoutSession via `WatchControl.startFreeRunWorkout`
// and we DON'T duplicate that on the iPhone — letting the Watch own the
// session keeps the data shape consistent with HYROX races and avoids
// HealthKit's duplicate-source dedupe complications. The iPhone session
// is gated on `!SensorSourceRegistry.shared.hasWatch` so it only kicks
// in when there's no Watch to do the job.
//
// Threading: `@MainActor` to match the rest of the manager surface;
// CL delegate hops back via Task. CMPedometer's handler runs on a
// background queue, the closure jumps to MainActor before mutating
// state.
@MainActor
@Observable
final class FreeRunWorkoutManager: NSObject {

    static let shared = FreeRunWorkoutManager()

    // MARK: - Active state

    // True between `start(...)` and `end(...)`. Defensive guard
    // against double-start / late samples landing after a stop.
    private(set) var isActive: Bool = false

    // Cumulative distance metres. Watch this property to drive
    // the engine; the manager guarantees it's monotonic during
    // an active session and stays at the last value after end.
    private(set) var distanceMetres: Double = 0

    // Latest live HR sample (bpm). Nil until the first poll
    // returns or HK auth is denied.
    private(set) var currentHeartRateBPM: Double?

    // Whichever location type the active session is configured
    // for. Drives whether we spin up CLLocationManager. Set on
    // start, cleared on end.
    private var activeLocationType: FreeRunLocationType?

    // Latest CMPedometer cumulative distance + the offset we
    // captured when starting (CMPedometer reports relative to a
    // user-supplied start date but accumulates from step events
    // that may have landed before the session began on edge
    // cases). Tracked separately from `distanceMetres` so we can
    // arbitrate between pedometer and GPS when both feed.
    private var pedometerStartDistance: Double = 0
    private var pedometerCumulative: Double = 0

    // Latest GPS-integrated distance. We compute it from
    // location-to-location deltas inside `didUpdateLocations`;
    // running total exposed here so the arbiter below picks the
    // larger / fresher of the two streams.
    private var gpsCumulative: Double = 0

    // Last GPS fix used in the GPS-distance integration. Each new
    // fix that passes the accuracy filter contributes
    // `lastFix.distance(from: newFix)` metres to gpsCumulative.
    private var lastGoodFix: CLLocation?

    // MARK: - Source handles

    #if canImport(CoreMotion)
    private let pedometer = CMPedometer()
    #endif
    #if canImport(CoreLocation)
    private var locationManager: CLLocationManager?
    #endif

    // HR polling task — same 5-second cadence RaceViewModel uses.
    private var hrPollTask: Task<Void, Never>?

    // §41 — iPhone-side HKWorkoutSession + HKLiveWorkoutBuilder.
    // The session is what gives AirPods Pro 3 a workout context so
    // its in-ear PPG samples flow into HealthKit. Lazy — only spun
    // up when no paired Watch exists (the Watch owns the session in
    // that case).
    //
    // §48 — Stored as Any? to dodge the type-level availability
    // error on HKLiveWorkoutBuilder (iOS 26.0+ on iPhone). Cast
    // inside `if #available(iOS 26.0, *)` blocks at every use site.
    // HKWorkoutSession is iOS 17.0+ but we keep both in Any? for
    // consistency — the iPhone session is meaningless without the
    // builder for sample collection anyway, so both gate together.
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    private var iPhoneWorkoutSession: Any?  // HKWorkoutSession when iOS 26+
    private var iPhoneWorkoutBuilder: Any?  // HKLiveWorkoutBuilder when iOS 26+
    // Throttle + de-dup for HR samples extracted from the builder's
    // stats. Same pattern WatchWorkoutManager uses on the wrist.
    private var lastBuilderHRPublishedAt: Date = .distantPast
    private var lastBuilderHRSampleEnd: Date = .distantPast
    private static let minBuilderHRPublishInterval: TimeInterval = 0.5
    #endif

    // MARK: - Callbacks (FreeRunViewModel registers these)

    var onDistanceUpdate: ((Date, Double) -> Void)?
    var onHeartRateUpdate: ((Date, Double) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    // Best-effort auth. CMPedometer + CL prompt on first use; HK
    // auth funnels through the existing HealthKitService.
    func requestAuthorizationIfNeeded() async {
        await HealthKitService.shared.requestAuthorization()
    }

    // MARK: - Lifecycle

    func start(locationType: FreeRunLocationType, at startDate: Date = Date()) {
        guard !isActive else { return }

        isActive = true
        activeLocationType = locationType
        distanceMetres = 0
        currentHeartRateBPM = nil
        pedometerStartDistance = 0
        pedometerCumulative = 0
        gpsCumulative = 0
        lastGoodFix = nil

        startPedometer(from: startDate)

        if locationType == .outdoor {
            startLocation()
        }

        startHeartRatePolling()

        // §41 — iPhone-side HKWorkoutSession when no Watch is paired.
        // Without this, AirPods Pro 3 PPG samples have nowhere to
        // land in HealthKit, so the live HR chip stays empty even
        // though the sensor on the ear is sensing fine.
        startIPhoneWorkoutSessionIfNeeded(
            locationType: locationType,
            startDate: startDate
        )
    }

    func pause() {
        // Pause behaves the same regardless of source — we stop
        // accepting new samples until resume, but keep the
        // accumulated distance so the engine doesn't reset.
        stopPedometer()
        stopLocation()
        stopHeartRatePolling()
        pauseIPhoneWorkoutSession()
    }

    func resume() {
        guard isActive else { return }
        // Restart sources from now() — accumulated distance
        // continues from the previous high-water mark.
        startPedometer(from: Date())
        if activeLocationType == .outdoor {
            startLocation()
        }
        startHeartRatePolling()
        resumeIPhoneWorkoutSession()
    }

    func end(finalize: Bool = true, at endDate: Date = Date()) {
        guard isActive else { return }
        stopPedometer()
        stopLocation()
        stopHeartRatePolling()
        endIPhoneWorkoutSession(finalize: finalize, at: endDate)
        isActive = false
        activeLocationType = nil
        // distanceMetres + currentHeartRateBPM left at their last
        // values so the summary view can render them; cleared on
        // the next start.
    }

    // MARK: - Pedometer

    private func startPedometer(from startDate: Date) {
        #if canImport(CoreMotion)
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: startDate) { [weak self] data, _ in
            guard let self, let data, let metres = data.distance else { return }
            Task { @MainActor in
                let cumulative = metres.doubleValue
                self.pedometerCumulative = cumulative
                self.publishDistanceArbitrated(at: Date())
            }
        }
        #endif
    }

    private func stopPedometer() {
        #if canImport(CoreMotion)
        pedometer.stopUpdates()
        #endif
    }

    // MARK: - Location (outdoor only)

    private func startLocation() {
        #if canImport(CoreLocation)
        let manager = locationManager ?? {
            let m = CLLocationManager()
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyBest
            m.activityType = .fitness
            m.pausesLocationUpdatesAutomatically = false
            m.allowsBackgroundLocationUpdates = false
            self.locationManager = m
            return m
        }()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        #endif
    }

    private func stopLocation() {
        #if canImport(CoreLocation)
        locationManager?.stopUpdatingLocation()
        #endif
    }

    // MARK: - Heart rate polling

    // Same cadence + same source as RaceViewModel uses for its
    // HR fallback. Watch-streamed samples land in HK in real time
    // during a workout session; our poll picks them up at 5s
    // intervals which is plenty for a "live HR chip" UI tier.
    private func startHeartRatePolling() {
        stopHeartRatePolling()
        hrPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let bpm = await HealthKitService.shared.currentHeartRate() {
                    self?.currentHeartRateBPM = bpm
                    self?.onHeartRateUpdate?(Date(), bpm)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopHeartRatePolling() {
        hrPollTask?.cancel()
        hrPollTask = nil
    }

    // MARK: - iPhone HKWorkoutSession (§41)

    // Start a phone-side HKWorkoutSession for `.running` (indoor or
    // outdoor). This is the workout context AirPods Pro 3 needs to
    // write its in-ear PPG samples to HealthKit. The live builder's
    // delegate publishes HR samples into our existing
    // `onHeartRateUpdate` callback at ~1Hz — same downstream path
    // the Watch's WCSession stream uses.
    //
    // Gated on TWO conditions:
    //   1. No paired Watch — the Watch already runs its own
    //      session in that case, and starting a duplicate iPhone
    //      session would either get rejected by HealthKit or
    //      produce duplicate HR samples.
    //   2. HealthKit available on this device.
    //
    // The session is fire-and-forget — `startActivity` + `beginCollection`
    // run async. If either fails (auth denied, etc.), we log and
    // bail; the legacy HK 5s polling continues to do whatever it
    // can in the meantime.
    private func startIPhoneWorkoutSessionIfNeeded(
        locationType: FreeRunLocationType,
        startDate: Date
    ) {
        #if canImport(HealthKit)
        // §48 — iPhone-side HKLiveWorkoutBuilder requires iOS 26.0+.
        // On older iOS, the AirPods Pro 3 hardware itself isn't
        // supported either, so the practical user impact is zero.
        guard #available(iOS 26.0, *) else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Skip when the Watch app is installed — the Watch owns the
        // workout session in that case (started via
        // WatchControl.startFreeRunWorkout). Check installed-ness, NOT
        // mere pairing: a paired Watch without the app can't run a
        // session, so the iPhone needs to step in. Also covers the
        // user-uninstalled-Trakrr-from-Watch case.
        //
        // `isWatchAppInstalled` matches the exact gate
        // WatchCompanionService.sendControl uses to decide whether to
        // dispatch the control in the first place — so this branch
        // strictly mirrors the Watch-side decision and we never end
        // up with two sessions running at once.
        #if canImport(WatchConnectivity)
        let watchSession = WCSession.default
        let watchOwnsIt = watchSession.activationState == .activated
            && watchSession.isWatchAppInstalled
        guard !watchOwnsIt else {
            print("[FreeRunPhoneHK] skip — Watch app installed, Watch owns the session")
            return
        }
        #endif
        guard iPhoneWorkoutSession == nil else {
            print("[FreeRunPhoneHK] skip — session already active")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = (locationType == .outdoor) ? .outdoor : .indoor

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

            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { success, error in
                if let error {
                    print("[FreeRunPhoneHK] beginCollection FAILED — \(error.localizedDescription)")
                } else {
                    print("[FreeRunPhoneHK] beginCollection OK success=\(success)")
                }
            }

            self.iPhoneWorkoutSession = session
            self.iPhoneWorkoutBuilder = builder
            print("[FreeRunPhoneHK] start OK at=\(startDate) location=\(configuration.locationType.rawValue)")
        } catch {
            print("[FreeRunPhoneHK] start FAILED — \(error.localizedDescription)")
        }
        #endif
    }

    private func pauseIPhoneWorkoutSession() {
        #if canImport(HealthKit)
        guard #available(iOS 26.0, *) else { return }
        (iPhoneWorkoutSession as? HKWorkoutSession)?.pause()
        #endif
    }

    private func resumeIPhoneWorkoutSession() {
        #if canImport(HealthKit)
        guard #available(iOS 26.0, *) else { return }
        (iPhoneWorkoutSession as? HKWorkoutSession)?.resume()
        #endif
    }

    // End the iPhone session if one is active. `finalize: true` saves
    // the HKWorkout to Apple Health (Activity ring credit); `false`
    // discards (abandon path).
    private func endIPhoneWorkoutSession(finalize: Bool, at endDate: Date) {
        #if canImport(HealthKit)
        guard #available(iOS 26.0, *) else { return }
        guard let session = iPhoneWorkoutSession as? HKWorkoutSession else { return }
        pendingIPhoneFinalize = finalize
        session.end()
        print("[FreeRunPhoneHK] end requested at=\(endDate) finalize=\(finalize)")
        #endif
    }

    #if canImport(HealthKit)
    // Set by `endIPhoneWorkoutSession`; read by the delegate when the
    // session transitions to `.ended`.
    private var pendingIPhoneFinalize: Bool = true

    private func clearIPhoneWorkoutHandles() {
        iPhoneWorkoutSession = nil
        iPhoneWorkoutBuilder = nil
        pendingIPhoneFinalize = true
        lastBuilderHRPublishedAt = .distantPast
        lastBuilderHRSampleEnd = .distantPast
    }

    // Pull the latest HR sample out of the live builder's statistics
    // and forward it through the existing `onHeartRateUpdate` channel
    // so FreeRunViewModel + the HR ring chip see the same value
    // they'd see from a Watch HR push. Throttled to ~2Hz to keep
    // closure firing reasonable. De-duped by sample-end timestamp so
    // a re-publish for the same underlying sample (didCollectDataOf
    // fires for every data type, not just HR) doesn't double-update.
    @available(iOS 26.0, *)
    fileprivate func publishLatestBuilderHRIfNeeded(
        from builder: HKLiveWorkoutBuilder
    ) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let stats = builder.statistics(for: hrType),
              let mostRecent = stats.mostRecentQuantity(),
              let sampleInterval = stats.mostRecentQuantityDateInterval() else {
            return
        }

        let sampledAt = sampleInterval.end
        guard sampledAt > lastBuilderHRSampleEnd else { return }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let bpm = mostRecent.doubleValue(for: bpmUnit)
        guard bpm >= 30, bpm <= 230 else { return }

        let now = Date()
        guard now.timeIntervalSince(lastBuilderHRPublishedAt)
            >= Self.minBuilderHRPublishInterval else {
            return
        }

        lastBuilderHRPublishedAt = now
        lastBuilderHRSampleEnd = sampledAt
        currentHeartRateBPM = bpm
        onHeartRateUpdate?(sampledAt, bpm)
    }
    #endif

    // MARK: - Distance arbitration

    // Pick whichever source has the fresher / more accurate
    // distance for the current location type:
    //   • indoor → pedometer always wins
    //   • outdoor → GPS wins WHEN we have a usable fix, otherwise
    //     pedometer fills the gap (e.g. tunnel, building, GPS
    //     warmup window)
    //
    // The published `distanceMetres` is monotonic — even if a
    // source delivers a stale / regressed value, we never push
    // backward. The engine ingest already filters non-monotonic
    // updates, but doing it here too keeps the manager-level
    // contract clean.
    private func publishDistanceArbitrated(at date: Date) {
        let candidate: Double = {
            switch activeLocationType {
            case .outdoor:
                // Prefer GPS when we've got a recent fix.
                // Otherwise fall through to pedometer.
                if let last = lastGoodFix,
                   abs(last.timestamp.timeIntervalSinceNow) < 15 {
                    return max(gpsCumulative, pedometerCumulative)
                }
                return pedometerCumulative
            case .indoor, .none:
                return pedometerCumulative
            }
        }()

        guard candidate > distanceMetres else { return }
        distanceMetres = candidate
        onDistanceUpdate?(date, candidate)
    }
}

// MARK: - HKWorkoutSessionDelegate + HKLiveWorkoutBuilderDelegate (§41 / §48)
//
// Whole-extension availability annotation: HKLiveWorkoutBuilder
// is iOS 26.0+ on iPhone, and both delegate protocols + their
// callback parameter types reference it. Gating the extensions
// keeps the rest of FreeRunWorkoutManager available on iOS 17+
// (CMPedometer / GPS / HK polling path) while the delegate
// surface only exists on iOS 26+.

#if canImport(HealthKit)
@available(iOS 26.0, *)
extension FreeRunWorkoutManager: HKWorkoutSessionDelegate {

    // Fires on every session state transition. We only act on `.ended`
    // — that's when we end collection + finalize (or discard) the
    // builder. Pattern matches WatchWorkoutManager's race-session
    // handling.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("[FreeRunPhoneHK] session state \(fromState.rawValue) → \(toState.rawValue)")
        guard toState == .ended else { return }

        Task { @MainActor in
            guard let builder = self.iPhoneWorkoutBuilder as? HKLiveWorkoutBuilder else {
                print("[FreeRunPhoneHK] state .ended but no builder — clearing handles")
                self.clearIPhoneWorkoutHandles()
                return
            }

            let shouldFinalize = self.pendingIPhoneFinalize

            if shouldFinalize {
                builder.endCollection(withEnd: date) { _, endError in
                    if let endError {
                        print("[FreeRunPhoneHK] endCollection FAILED — \(endError.localizedDescription)")
                    }
                    builder.finishWorkout { workout, finishError in
                        if let finishError {
                            print("[FreeRunPhoneHK] finishWorkout FAILED — \(finishError.localizedDescription)")
                        } else if let workout {
                            print("[FreeRunPhoneHK] finishWorkout OK duration=\(workout.duration)")
                        }
                        Task { @MainActor in
                            self.clearIPhoneWorkoutHandles()
                        }
                    }
                }
            } else {
                builder.discardWorkout()
                print("[FreeRunPhoneHK] discardWorkout — run abandoned")
                self.clearIPhoneWorkoutHandles()
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[FreeRunPhoneHK] session FAILED — \(error.localizedDescription)")
        Task { @MainActor in
            self.clearIPhoneWorkoutHandles()
        }
    }
}

@available(iOS 26.0, *)
extension FreeRunWorkoutManager: HKLiveWorkoutBuilderDelegate {

    // Fires when the builder collects new samples. We filter for HR
    // and publish the latest through onHeartRateUpdate. Distance
    // samples ride along into the eventual HKWorkout automatically;
    // for live distance we already have CMPedometer + GPS, so no
    // need to extract from the builder here.
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        guard collectedTypes.contains(hrType) else { return }

        Task { @MainActor in
            self.publishLatestBuilderHRIfNeeded(from: workoutBuilder)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {
        // No-op — Free Run doesn't emit lap markers / pauses we'd
        // want to record on the builder.
    }
}
#endif

// MARK: - CLLocationManagerDelegate

#if canImport(CoreLocation)
extension FreeRunWorkoutManager: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Same accuracy filter the HK route builder used —
        // ≤50m horizontal accuracy and recent.
        let valid = locations.filter {
            $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= 50
                && abs($0.timestamp.timeIntervalSinceNow) < 10
        }
        guard !valid.isEmpty else { return }

        Task { @MainActor in
            for location in valid {
                if let prior = self.lastGoodFix {
                    let delta = location.distance(from: prior)
                    // CLLocation can produce zero / tiny deltas on
                    // a stationary athlete; ignore sub-1m
                    // contributions to keep noise out of the
                    // accumulated total.
                    if delta >= 1 {
                        self.gpsCumulative += delta
                    }
                }
                self.lastGoodFix = location
            }
            self.publishDistanceArbitrated(at: Date())
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Non-fatal — the run continues with pedometer-only
        // distance. CL errors are typically transient
        // (kCLErrorLocationUnknown during warmup).
    }
}
#endif

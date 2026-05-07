import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

// iPhone-side distance + HR source for Free Run.
//
// Originally a HealthKit-backed HKWorkoutSession + HKLiveWorkoutBuilder,
// but those APIs gating to iOS 26+ on iPhone made them unusable for our
// iOS 17 deployment floor. Switched to a simpler stack that's iOS 17
// compatible end-to-end:
//
//   • CMPedometer — drives indoor distance (treadmill, gym track) and
//     contributes outdoor distance when GPS is sparse / blocked. iOS
//     reports cumulative distance derived from step count + the device's
//     built-in stride model.
//   • CLLocationManager — outdoor GPS. When fixes are accurate enough
//     (≤50m horizontal accuracy and ≤10s stale), distance integrates
//     from the CL-derived deltas, overriding the pedometer's estimate
//     for the more accurate GPS reading.
//   • HealthKitService.currentHeartRate() — polled every 5s for the
//     latest HR sample. Samples come from the user's paired Apple Watch
//     when on the wrist (the Watch writes to HK regardless of which
//     app started it). iPhone-only users see no HR.
//
// What we LOSE vs the HKLiveWorkoutBuilder path:
//   • No HKWorkout written to Apple Health on finish (no Activity ring
//     credit, no entry alongside Apple Workouts). When a paired Watch
//     is running its own session, the Watch handles that — same as
//     Race Mode. iPhone-only users on iOS 17-25 don't get HK
//     persistence for free runs; that's an acceptable v1 limit and
//     can come back as a Phase-3.5 enhancement on iPhones running
//     iOS 26+.
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
    }

    func pause() {
        // Pause behaves the same regardless of source — we stop
        // accepting new samples until resume, but keep the
        // accumulated distance so the engine doesn't reset.
        stopPedometer()
        stopLocation()
        stopHeartRatePolling()
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
    }

    func end(finalize: Bool = true, at endDate: Date = Date()) {
        guard isActive else { return }
        stopPedometer()
        stopLocation()
        stopHeartRatePolling()
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

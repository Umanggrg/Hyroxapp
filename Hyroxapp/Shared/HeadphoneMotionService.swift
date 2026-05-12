import Foundation
import Observation

#if canImport(CoreMotion)
import CoreMotion
#endif

// §19.4 Phase 10H — derive running cadence (steps per minute)
// from AirPods Pro 1+ / AirPods 4 / Max head motion. The
// wrist-mounted Watch already does this via its native
// pedometer, but the head is a different vantage and gives
// Trakrr a cadence reading even on AirPods-only racers (no
// Watch present).
//
// Detection algorithm:
//   1. Subscribe to `CMHeadphoneMotionManager.deviceMotionUpdates`
//      at ~50Hz. The framework hands back `CMDeviceMotion`
//      objects with `userAcceleration` (gravity-removed).
//   2. Read the Z-axis component — that's the up/down impact
//      direction relative to head orientation. Each step
//      produces a sharp negative spike (head dips on impact)
//      followed by a positive recovery as the body unloads.
//   3. Peak-detect: when the Z-axis crosses a positive
//      threshold AFTER having been below a negative threshold,
//      register a step. Per-step interval gates spurious
//      double-counts (running cadence caps ~240 spm = 250ms
//      minimum step interval).
//   4. Rolling average over the last 8 steps → smoothed cadence
//      in spm. 8 steps ≈ 2.5s at 180 spm, so the readout reacts
//      to real changes within a few seconds without
//      jittering on transient signal noise.
//
// Service is iOS-only — `CMHeadphoneMotionManager` doesn't
// exist on watchOS / macOS. Guarded by `canImport(CoreMotion)`
// AND a runtime `isDeviceMotionAvailable` check (false on
// AirPods 2/3 non-Pro). Calling `start()` is a no-op when the
// hardware can't deliver — the service silently never
// publishes a cadence value and the UI renders its
// not-available placeholder.
//
// Lifecycle: paired with the race. RaceViewModel.startRace
// calls `start()`; race-finish / abandon / pause-with-discard
// call `stop()`. Idempotent — multiple starts cancel the
// existing subscription first.
@MainActor
@Observable
final class HeadphoneMotionService {

    static let shared = HeadphoneMotionService()

    // MARK: - Published state

    /// Current cadence in steps per minute, rolling-averaged
    /// over the last 8 detected steps. Nil when no steps have
    /// been detected in the last 3 seconds (race paused,
    /// athlete stationary, AirPods motion unavailable).
    private(set) var currentCadenceSPM: Int?

    /// True while the underlying CMHeadphoneMotionManager is
    /// actively delivering updates. Drives UI placeholders +
    /// the cadence chip's enabled state. False on iPhones
    /// without AirPods in the route, or with AirPods that
    /// don't have motion sensors (AirPods 2/3 non-Pro).
    private(set) var isStreaming: Bool = false

    // MARK: - Internal state

    #if canImport(CoreMotion)
    private let manager = CMHeadphoneMotionManager()
    #endif

    /// Recent step timestamps used for rolling cadence math.
    /// We keep up to 16 to amortize the rolling-average buffer
    /// without unbounded growth; cadence reads from the
    /// trailing 8.
    private var stepTimestamps: [Date] = []
    private var lastZ: Double = 0
    private var crossedNegative: Bool = false

    /// Per-step minimum interval — caps the cadence at 240
    /// spm, which is 60 / (250ms). Anything faster is signal
    /// noise (double-detect on a single step's positive
    /// recovery curve). Per-step cap > per-window cap because
    /// a single step is the atomic unit; the rolling average
    /// already smooths over.
    private static let minStepInterval: TimeInterval = 0.25

    /// Z-axis peak detection thresholds. Tuned conservatively
    /// for HYROX-pace running (160–180 spm). Below the
    /// negative threshold = foot impact ground; above the
    /// positive threshold = peak vertical recovery. Pair
    /// trips a step event.
    private static let zNegativeThreshold: Double = -0.25
    private static let zPositiveThreshold: Double = 0.25

    /// Drop cadence to nil if no new steps in this window.
    /// Athlete walked → station → cadence should clear, not
    /// linger at the last running value.
    private static let staleStepThreshold: TimeInterval = 3.0

    private var staleCheckTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    /// Begin subscribing to head-motion updates. Returns
    /// immediately and idempotent — calling start() while
    /// already streaming first cancels the previous
    /// subscription. Returns true on success, false when the
    /// hardware can't deliver (no AirPods, or non-motion
    /// AirPods).
    @discardableResult
    func start() -> Bool {
        #if canImport(CoreMotion)
        // Avoid stacking subscriptions.
        if isStreaming {
            stop()
        }

        guard manager.isDeviceMotionAvailable else {
            // AirPods 2/3 non-Pro, or no AirPods in route.
            // The cadence chip will render its placeholder
            // and Trakrr falls back to whatever cadence the
            // Watch can publish (or nothing).
            isStreaming = false
            return false
        }

        stepTimestamps.removeAll()
        lastZ = 0
        crossedNegative = false
        currentCadenceSPM = nil

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard let motion = motion, error == nil else { return }
            self.processMotion(motion)
        }
        isStreaming = true

        // Stale-step watchdog — fires every second and clears
        // currentCadenceSPM when no fresh steps have come in.
        // Without this, the cadence value would linger from
        // the athlete's last run after they stopped at a
        // station.
        staleCheckTask?.cancel()
        staleCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.checkForStaleSteps()
            }
        }

        return true
        #else
        isStreaming = false
        return false
        #endif
    }

    /// Tear down the head-motion subscription and clear any
    /// derived state. Safe to call when not streaming.
    func stop() {
        #if canImport(CoreMotion)
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        #endif
        isStreaming = false
        stepTimestamps.removeAll()
        currentCadenceSPM = nil
        crossedNegative = false
        lastZ = 0
        staleCheckTask?.cancel()
        staleCheckTask = nil
    }

    // MARK: - Signal processing

    #if canImport(CoreMotion)
    private func processMotion(_ motion: CMDeviceMotion) {
        // userAcceleration is gravity-removed acceleration in
        // g-units along the head's local axes. Z is "up/down"
        // relative to head orientation — perfect for detecting
        // the vertical bob of running gait.
        let z = motion.userAcceleration.z
        let now = Date()

        // Latch the "below negative threshold" state so we
        // only register a step on the up-stroke. Without the
        // latch, a slow walk could trigger spurious steps from
        // signal noise floating around zero.
        if z < Self.zNegativeThreshold {
            crossedNegative = true
        } else if crossedNegative && z > Self.zPositiveThreshold {
            crossedNegative = false
            registerStep(at: now)
        }
        lastZ = z
    }
    #endif

    private func registerStep(at timestamp: Date) {
        // Enforce minimum step interval to suppress double-
        // detects on the same impact's recovery curve.
        if let last = stepTimestamps.last,
           timestamp.timeIntervalSince(last) < Self.minStepInterval {
            return
        }

        stepTimestamps.append(timestamp)
        // Cap buffer size — keep the trailing 16 timestamps
        // (2× the rolling-average window for robustness).
        if stepTimestamps.count > 16 {
            stepTimestamps.removeFirst(stepTimestamps.count - 16)
        }

        updateCadenceFromBuffer()
    }

    private func updateCadenceFromBuffer() {
        // Need at least 4 steps before we publish a cadence
        // reading — anything less is just noise.
        guard stepTimestamps.count >= 4 else {
            currentCadenceSPM = nil
            return
        }

        // Use the trailing 8 steps (or whatever's available)
        // for the rolling average. spm = (steps - 1) /
        // (last - first) * 60.
        let window = stepTimestamps.suffix(8)
        guard let first = window.first, let last = window.last else { return }
        let duration = last.timeIntervalSince(first)
        guard duration > 0 else { return }
        let stepsInWindow = window.count - 1
        let spm = Double(stepsInWindow) / duration * 60.0

        // Clamp to a plausible cadence band. Anything outside
        // 60–240 spm is signal noise (60 spm = slow walk
        // floor; 240 spm = elite sprint ceiling). Trakrr's
        // target HYROX-runner band is 160–180.
        let clamped = max(60.0, min(240.0, spm))
        currentCadenceSPM = Int(clamped.rounded())
    }

    private func checkForStaleSteps() {
        guard let last = stepTimestamps.last else {
            // No steps ever recorded this session — nothing
            // to clear.
            return
        }
        let age = Date().timeIntervalSince(last)
        if age > Self.staleStepThreshold {
            currentCadenceSPM = nil
        }
    }
}

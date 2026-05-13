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

    /// §19 Phase 10I — live vertical oscillation in
    /// centimeters per step, rolling-averaged over the last 8
    /// steps. Computed from peak-to-trough Z-axis
    /// acceleration amplitude during each step cycle. Stryd /
    /// Garmin Forerunner expose this as a "running economy"
    /// metric — lower is more efficient (elite runners ~6-8
    /// cm; recreational 10-14 cm). Nil while the rolling
    /// buffer fills (first ~4 steps) or when no steps in the
    /// last 3s.
    ///
    /// v1 approximation: scales peak-to-trough Z accel
    /// (in g-units) by an 8x heuristic constant clamped 3-20cm.
    /// True bounce-height integration would require flight-
    /// time detection (ground contact time); shipping the
    /// proxy first and tightening the math when GCT lands
    /// (10K).
    private(set) var currentVerticalOscillationCm: Double?

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

    /// §19 Phase 10I — per-step peak-to-trough Z amplitudes in
    /// g-units, captured during each step cycle. Trailing
    /// 8 used for currentVerticalOscillationCm rolling avg.
    private var stepAmplitudes: [Double] = []

    /// §19.4 Phase 10K — average ground contact time in
    /// milliseconds, rolling-averaged over the last 8 steps.
    /// Computed from the time the foot is on the ground during
    /// each step cycle (Z dip → Z return to neutral). Nil
    /// while the rolling buffer fills (< 4 steps) OR when no
    /// steps in the last 3s.
    ///
    /// Elite distance runners run 180-220ms; recreational
    /// 250-300ms+. Lower = more efficient (less energy lost to
    /// braking on each step, better elastic-recoil return).
    private(set) var currentGroundContactTimeMs: Double?

    /// §19.4 Phase 10K — per-step GCT values in milliseconds,
    /// captured during each step cycle. Trailing 8 used for
    /// currentGroundContactTimeMs rolling avg. Parallel
    /// structure to stepAmplitudes for symmetry.
    private var stepGroundContactsMs: [Double] = []

    /// §19.4 Phase 10K — timestamp of the start of the current
    /// step's impact phase (the moment Z first crossed below
    /// the negative threshold). Cleared at step-registration
    /// time so each cycle measures its GCT independently.
    private var impactStartedAt: Date?

    /// §19.4 Phase 10K — GCT for the in-flight cycle, captured
    /// when Z returns to >= 0 (flight phase begins). Held until
    /// the step actually registers on the positive peak (so
    /// the period gate's discard path can short-circuit
    /// cleanly without partial state).
    private var pendingGroundContactMs: Double?

    /// Running min/max Z during the current step cycle (between
    /// negative-cross and positive-cross). Reset on each step
    /// registration so the next cycle's amplitude is measured
    /// independently.
    private var currentCycleZMin: Double = 0
    private var currentCycleZMax: Double = 0

    /// §19 Phase 10J — periodic snapshots of head pitch (in
    /// radians) recorded during a race. Used after-the-fact
    /// to compute first-half vs second-half mean pitch delta
    /// → posture drift fatigue insight. One sample per second
    /// is plenty (head pitch changes over minutes, not Hz).
    private var pitchSamples: [(timestamp: Date, pitch: Double)] = []
    private var lastPitchSampleAt: Date = .distantPast
    private static let pitchSampleInterval: TimeInterval = 1.0

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
        stepAmplitudes.removeAll()
        stepGroundContactsMs.removeAll()
        pitchSamples.removeAll()
        currentCycleZMin = 0
        currentCycleZMax = 0
        lastPitchSampleAt = .distantPast
        lastZ = 0
        crossedNegative = false
        impactStartedAt = nil
        pendingGroundContactMs = nil
        currentCadenceSPM = nil
        currentVerticalOscillationCm = nil
        currentGroundContactTimeMs = nil

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
    ///
    /// NB: `pitchSamples` is intentionally NOT cleared here —
    /// consumers (RaceViewModel on race finish) need to query
    /// it AFTER stop() runs. Call `flushPitchSamples()`
    /// explicitly when the consumer is done reading.
    func stop() {
        #if canImport(CoreMotion)
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        #endif
        isStreaming = false
        stepTimestamps.removeAll()
        stepAmplitudes.removeAll()
        stepGroundContactsMs.removeAll()
        currentCycleZMin = 0
        currentCycleZMax = 0
        currentCadenceSPM = nil
        currentVerticalOscillationCm = nil
        currentGroundContactTimeMs = nil
        crossedNegative = false
        impactStartedAt = nil
        pendingGroundContactMs = nil
        lastZ = 0
        staleCheckTask?.cancel()
        staleCheckTask = nil
    }

    /// §19 Phase 10J — consume + clear the pitch sample
    /// buffer. Called by RaceViewModel after computing the
    /// race's posture drift; subsequent races start with a
    /// fresh buffer. Returns the samples in their captured
    /// order; consumers handle the first-half / second-half
    /// split themselves.
    func flushPitchSamples() -> [(timestamp: Date, pitch: Double)] {
        let captured = pitchSamples
        pitchSamples.removeAll()
        lastPitchSampleAt = .distantPast
        return captured
    }

    /// §19 Phase 10J — read the pitch samples without
    /// clearing the buffer. Useful for mid-race diagnostics
    /// or alternate consumers that don't own the buffer's
    /// lifecycle. RaceViewModel uses `flushPitchSamples()`
    /// instead so a finished race's data doesn't bleed into
    /// the next one.
    func peekPitchSamples() -> [(timestamp: Date, pitch: Double)] {
        pitchSamples
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

        // §19 Phase 10I — track running min/max Z continuously
        // so the amplitude on each step represents the FULL
        // peak-to-trough range over that step's cycle. min/max
        // are reset at step-registration time (inside
        // registerStep), so each new cycle measures
        // independently.
        currentCycleZMin = min(currentCycleZMin, z)
        currentCycleZMax = max(currentCycleZMax, z)

        // Latch the "below negative threshold" state so we
        // only register a step on the up-stroke. Without the
        // latch, a slow walk could trigger spurious steps from
        // signal noise floating around zero.
        if z < Self.zNegativeThreshold {
            if !crossedNegative {
                // §19.4 Phase 10K — first crossing into the
                // impact phase of this step cycle. Foot has
                // just landed; head's accelerating downward.
                // Mark the moment so we can measure GCT when
                // Z returns to neutral.
                impactStartedAt = now
            }
            crossedNegative = true
        } else if crossedNegative {
            // §19.4 Phase 10K — capture flight-start time on
            // the first zero-crossing after impact. The foot
            // has left the ground; vertical accel has returned
            // to neutral (briefly) before reversing upward to
            // the positive peak. This is the cleanest signal
            // for GCT end from head motion.
            //
            // Only set pendingGroundContactMs once per cycle
            // (the nil-check); subsequent Z samples in the
            // rising phase shouldn't overwrite the captured
            // value with a later one.
            if pendingGroundContactMs == nil,
               z >= 0,
               let start = impactStartedAt {
                pendingGroundContactMs = now.timeIntervalSince(start) * 1000.0
            }

            if z > Self.zPositiveThreshold {
                crossedNegative = false
                // Cycle complete — pass the captured amplitude
                // (max − min) to registerStep, which uses it to
                // update the vertical-oscillation rolling avg
                // AND resets the cycle's min/max for the next step.
                let amplitude = currentCycleZMax - currentCycleZMin
                let gct = pendingGroundContactMs
                impactStartedAt = nil
                pendingGroundContactMs = nil
                registerStep(at: now, amplitudeG: amplitude, gctMs: gct)
            }
        }
        lastZ = z

        // §19 Phase 10J — sample head pitch at ~1Hz so we have
        // a timeline to slice for first-half / second-half
        // posture drift analysis at race finish. Storing the
        // raw radians value; consumers convert to degrees in
        // the analysis path. Pitch axis convention: positive =
        // head tilted forward (chin to chest), which is the
        // direction fatigued runners' heads drift.
        if now.timeIntervalSince(lastPitchSampleAt) >= Self.pitchSampleInterval {
            lastPitchSampleAt = now
            pitchSamples.append((now, motion.attitude.pitch))
            // Cap the buffer at 10,000 samples (≈ 2.7 hours at
            // 1 sample/sec). HYROX races top out around 1.5h,
            // so this is well above the worst-case race length.
            if pitchSamples.count > 10_000 {
                pitchSamples.removeFirst(pitchSamples.count - 10_000)
            }
        }
    }
    #endif

    private func registerStep(at timestamp: Date, amplitudeG: Double = 0, gctMs: Double? = nil) {
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

        // §19 Phase 10I — record the step's peak-to-trough
        // Z amplitude. Same trailing 16 buffer cap;
        // currentVerticalOscillationCm reads from the latest 8.
        if amplitudeG > 0 {
            stepAmplitudes.append(amplitudeG)
            if stepAmplitudes.count > 16 {
                stepAmplitudes.removeFirst(stepAmplitudes.count - 16)
            }
        }

        // §19.4 Phase 10K — record the step's GCT in
        // milliseconds. Plausibility-gated 50-500ms to filter
        // edge cases where the impact-end detection misfires
        // (e.g. AirPods readjustment, walking slow enough that
        // there's no flight phase). Steps outside the band
        // still count for cadence but contribute no GCT data.
        if let gctMs, gctMs >= 50, gctMs <= 500 {
            stepGroundContactsMs.append(gctMs)
            if stepGroundContactsMs.count > 16 {
                stepGroundContactsMs.removeFirst(stepGroundContactsMs.count - 16)
            }
        }

        // Reset the cycle's min/max so the next step measures
        // its full peak-to-trough range without bleeding in
        // values from the previous cycle. lastZ is the most
        // recent sample, so seed both to it — the next
        // processMotion call will widen the range from there.
        currentCycleZMin = lastZ
        currentCycleZMax = lastZ

        updateCadenceFromBuffer()
        updateVerticalOscillationFromBuffer()
        updateGroundContactTimeFromBuffer()
    }

    // §19.4 Phase 10K — rolling-average update for the
    // published `currentGroundContactTimeMs` value. Same shape
    // as updateVerticalOscillationFromBuffer above: needs at
    // least 4 samples before publishing (anything below is
    // signal noise), uses the trailing 8 for the rolling
    // average.
    private func updateGroundContactTimeFromBuffer() {
        guard stepGroundContactsMs.count >= 4 else {
            currentGroundContactTimeMs = nil
            return
        }
        let window = stepGroundContactsMs.suffix(8)
        let avg = window.reduce(0, +) / Double(window.count)
        currentGroundContactTimeMs = avg
    }

    // §19 Phase 10I — convert step amplitude (g-units) to
    // approximate vertical oscillation (cm). Heuristic v1:
    // multiply by 8 (so a 1g amplitude reads as ~8cm), clamp
    // to the plausible runner band (3-20cm). Future v2:
    // proper integration once ground-contact-time (10K) lands
    // so flight phase can be isolated.
    private static let amplitudeToCm: Double = 8.0
    private static let minOscillationCm: Double = 3.0
    private static let maxOscillationCm: Double = 20.0

    private func updateVerticalOscillationFromBuffer() {
        // Need at least 4 amplitude samples before publishing
        // — matches the cadence buffer's warmup gate.
        guard stepAmplitudes.count >= 4 else {
            currentVerticalOscillationCm = nil
            return
        }
        let window = stepAmplitudes.suffix(8)
        let avg = window.reduce(0, +) / Double(window.count)
        let cm = avg * Self.amplitudeToCm
        let clamped = max(Self.minOscillationCm, min(Self.maxOscillationCm, cm))
        currentVerticalOscillationCm = clamped
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
            // §19 Phase 10I — also clear oscillation; same
            // semantics ("no fresh steps" → no published
            // metric).
            currentVerticalOscillationCm = nil
            // §19.4 Phase 10K — same staleness semantics for GCT.
            currentGroundContactTimeMs = nil
        }
    }
}

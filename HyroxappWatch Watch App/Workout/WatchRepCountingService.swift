import Foundation
import Observation
#if canImport(CoreMotion)
import CoreMotion
#endif

// §13.8 Tier 2 — Wrist IMU rep counting on Apple Watch.
//
// Marquee AirPods+Watch differentiator. While the athlete is on a
// rhythmic-cycle station, this service subscribes to high-rate
// accelerometer data and counts reps (or strokes / pulls) in real
// time. The resulting count gets published to the iPhone via
// WCSession and auto-fills `Split.repsCompleted` so the athlete
// doesn't have to remember + type "47" into a sheet post-race.
//
// Supported stations (per detector profile):
//   • Wall Balls — Z-axis peak-with-negative-trough latch.
//     Sharp arm-overhead drive after a catch+squat cycle.
//   • Rowing strokes / SkiErg pulls (§46) — magnitude-based
//     peak detection. ~2s rhythmic cycle, less sharp than wall
//     balls but very consistent. One detector serves both
//     stations because the cycle shape is similar enough that
//     the same thresholds work; SkiErg's arm-only motion has
//     slightly lower peak magnitude than rowing's full-body
//     drive but stays above the threshold.
//
// Out of scope (deliberately, per §45):
//   • Sled Push + Sled Pull — continuous-effort stations, not
//     rep-based. They get a separate continuous-effort
//     instrumentation track (cadence + activity threshold +
//     wall hits), not rep counting.
//   • Burpee Broad Jumps + Sandbag Lunges — rhythmic but
//     bigger cycle variance than ergs; needs its own profile
//     in a follow-up phase.
//   • Farmers Carry — CMPedometer cadence (already shipped),
//     not IMU rep counting.
//
// Detection algorithm (per profile below):
//   1. Subscribe to `CMBatchedSensorManager.deviceMotionUpdates` on
//      Series 8+ / Ultra (watchOS 9.4+) at the framework's
//      batched-update rate (~200Hz device motion when paired with
//      an active HKWorkoutSession). On older hardware, fall back
//      to `CMMotionManager.startDeviceMotionUpdates` at 50Hz —
//      still well above what wall ball cadence (~30 reps/min)
//      requires.
//   2. Read `userAcceleration.z` — gravity-removed vertical
//      acceleration along the wrist's local Z axis. Wall ball
//      arm drive produces a sharp positive Z peak as the ball
//      is launched overhead.
//   3. Latch state — only register a rep when we've seen a
//      negative Z dip (squat / catch phase) BEFORE the positive
//      peak. Stops the same arm motion firing twice via
//      oscillation in the recovery curve.
//   4. Period gate — minimum 0.8s between reps. Wall ball pace
//      caps at ~50 reps/min (1.2s/rep); 0.8s gives margin against
//      double-detect on signal noise without missing actual reps.
//   5. Increment `currentRepCount` and broadcast to WCSession at
//      throttled 1Hz cadence (matches HR pipeline; per-rep
//      broadcast would burn WC budget for no UX gain since the
//      counter chip only re-renders 1Hz anyway).
//
// Lifecycle: started by `WatchRaceView`'s snapshot observer when
// `currentStation == .wallBalls`, stopped when station changes
// (advance, finish, abandon). Resetting between attempts means
// each segment starts at 0. The final count for a segment is
// captured in the iPhone-side ingest path (RaceViewModel holds
// the latest auto-rep count and stamps Split.repsCompleted at
// advance time).
//
// Hardware capability tiers:
//   • Series 8+ / Ultra — CMBatchedSensorManager.deviceMotionUpdates
//     (200Hz, energy-optimized for active HKWorkoutSession).
//   • Series 1–7 / SE — CMMotionManager.startDeviceMotionUpdates
//     (50Hz fallback — coarser but accurate enough for wall balls).
//   • Neither available — service refuses to start, `isCounting`
//     stays false, the iPhone's manual-entry path (StationStatsSheet)
//     remains the only way to capture reps.
//
// Singleton because the Watch only ever runs one rep-counting
// session at a time (paired with one active HKWorkoutSession), and
// WatchRaceView wants a stable observable handle for its UI.
@MainActor
@Observable
final class WatchRepCountingService {

    static let shared = WatchRepCountingService()

    // MARK: - Published state

    /// Reps counted in the current segment. Resets to 0 on each
    /// `start(for:)` call. Reads as `0` while not counting.
    private(set) var currentRepCount: Int = 0

    /// True while the underlying motion subscription is active and
    /// delivering samples. Drives UI placeholder vs live chip
    /// rendering on `WatchRaceMainPage`.
    private(set) var isCounting: Bool = false

    /// The station this service is currently counting reps for.
    /// `nil` when stopped. Used by the iPhone-side ingest path
    /// (via the WatchRepCountUpdate payload's stationRaw) to make
    /// sure stale counts from a previous segment don't bleed into
    /// the current one.
    private(set) var currentStationRaw: Int?

    // MARK: - Detector profile

    /// Which detection algorithm the service is currently
    /// running. Set by `start(for:)` based on the station type;
    /// `processMotion` dispatches on this so the two profiles
    /// share lifecycle plumbing (WCSession publish, motion
    /// subscription, state reset) but use independent signal
    /// processing.
    private enum DetectorProfile {
        case wallBalls
        /// Rowing strokes + SkiErg pulls share this profile.
        /// Both have ~2s rhythmic cycles with smooth magnitude
        /// peaks; same thresholds work across them.
        case rowingStroke
        /// Burpee broad jumps (§49). Multi-phase rep cycle —
        /// sharp negative Z trough on the drop-to-floor, sustained
        /// near-zero plateau during the push-up, then sharp
        /// positive Z spike on the jump up + forward. Much bigger
        /// amplitudes than wall balls (jumping is more violent
        /// than overhead pressing), longer cycle (~2-4s).
        case burpeeJump
        /// Sandbag lunges (§49). Alternating L/R lunge cycles
        /// at ~2-3s/rep. Vertical Z dip on the knee-drop, return
        /// to neutral on the drive back up. Smaller amplitude
        /// than burpees but the alternation cadence is what
        /// makes the signal countable. Phase 50 will layer
        /// gyro-based L/R asymmetry detection on this profile;
        /// for now we just count cycles.
        case lunge
    }

    private var activeProfile: DetectorProfile?

    // MARK: - Wall-ball detection state

    private var lastRepRegisteredAt: Date = .distantPast
    private var crossedNegative: Bool = false
    private var lastZ: Double = 0

    // MARK: - Rowing-stroke detection state (§46)

    /// Two-state cycle gate for the rowing/ski stroke detector.
    /// `seekingValley` — magnitude must drop below
    /// `rowingValleyThreshold` before we look for the next peak.
    /// `seekingPeak` — magnitude rising; first sample above
    /// `rowingPeakThreshold` registers the stroke and flips
    /// the gate back to seekingValley.
    ///
    /// This is the magnitude-based analogue of the wall ball's
    /// negative-trough latch — same idea, different signal.
    private enum StrokeGate {
        case seekingValley
        case seekingPeak
    }

    private var strokeGate: StrokeGate = .seekingValley

    /// Timestamp of the most recent transition INTO `.seekingPeak`.
    /// Powers the stale-gate timeout: if the gate sits in
    /// `.seekingPeak` for too long without a real stroke arriving,
    /// we re-arm to `.seekingValley`. Defends against the
    /// pause-then-twitch false positive — athlete stops rowing
    /// mid-segment (drink, adjust handle), magnitude drops below
    /// valley once, then an ambient wrist motion >0.35g later
    /// would otherwise register as a stroke. With the timeout,
    /// the gate disengages instead.
    private var gateArmedAt: Date = .distantPast

    // Last few magnitude samples for smoothing — accelerometer
    // noise at 200Hz is significant and a single-sample
    // threshold check produces jitter. 3-sample moving average
    // smooths the curve enough that peak detection is stable
    // without lagging meaningfully (15ms at 200Hz).
    private var magnitudeRing: [Double] = []
    private static let magnitudeRingSize: Int = 3

    /// How long the gate is allowed to sit in `.seekingPeak`
    /// without registering a stroke before we re-arm. 4s is
    /// long enough to clear the slowest reasonable rowing
    /// cadence (~16 spm = 3.75s/stroke) but short enough that
    /// a paused athlete's first ambient wrist motion doesn't
    /// land a phantom stroke seconds later.
    private static let rowingGateTimeout: TimeInterval = 4.0

    // MARK: - Tuning constants (wall balls)

    /// Positive Z threshold for the arm-drive peak. Wall ball
    /// drives produce ~1.0–2.0g upward acceleration at peak; 0.7g
    /// gives margin against weaker reps while filtering out
    /// background motion (walking between rounds, adjusting form).
    private static let zPositivePeak: Double = 0.7

    /// Negative Z threshold for the catch / squat phase. Latched
    /// requirement so each rep cycle starts from a low position.
    private static let zNegativeTrough: Double = -0.4

    /// Minimum interval between counted reps. Wall ball pace caps
    /// at ~50/min in competition (1.2s/rep); the 0.8s floor allows
    /// for slightly faster reps in training without double-counting
    /// signal-noise oscillations in the arm-drive recovery curve.
    private static let minRepInterval: TimeInterval = 0.8

    // MARK: - Tuning constants (rowing / ski strokes, §46)

    /// Smoothed magnitude must exceed this to register a stroke.
    /// Rowing drives produce ~0.4–0.7g magnitude peaks (less
    /// sharp than wall balls but more sustained); 0.35g floor
    /// catches even the smoothest strokes while filtering out
    /// background wrist motion between strokes (adjusting grip,
    /// breathing, etc.). SkiErg pulls land in the same range —
    /// arm-only motion is slightly weaker but stays above this
    /// floor.
    private static let rowingPeakThreshold: Double = 0.35

    /// Smoothed magnitude must drop below this between strokes
    /// before the next peak counts. Defends against double-
    /// counting a single stroke's recovery oscillation. Set
    /// well below the peak floor so genuine recoveries clear
    /// the valley unambiguously even on choppy form.
    private static let rowingValleyThreshold: Double = 0.18

    /// Minimum interval between counted strokes. Elite rowers
    /// cap at ~36 spm in HYROX (1.67s/stroke); the 1.0s floor
    /// allows for sprint cadence (60 spm = 1.0s) without
    /// double-counting signal noise. SkiErg pulls cap slightly
    /// faster but the same floor holds.
    private static let rowingMinInterval: TimeInterval = 1.0

    // MARK: - Tuning constants (burpee broad jumps, §49)

    /// Positive Z peak threshold for the jump-up phase. Burpee
    /// broad jumps produce big positive Z spikes when the
    /// athlete drives up from the floor + launches forward —
    /// ~1.5-2.5g typical at the apex. 1.0g floor catches the
    /// weaker cumulative-fatigue reps while filtering background
    /// motion between cycles.
    private static let burpeePositivePeak: Double = 1.0

    /// Negative Z trough threshold for the drop-to-floor phase.
    /// Hitting the ground in a burpee produces a sharp negative
    /// impulse (~-1.5 to -2.5g depending on form aggression).
    /// -1.0g floor stays above background squat / setup motion.
    /// Sharper than wall balls (-0.4g) because the drop is more
    /// violent than a wall-ball squat.
    private static let burpeeNegativeTrough: Double = -1.0

    /// Minimum interval between counted burpees. Race pace is
    /// roughly 16 burpee-broad-jumps in 80m at ~5s/rep average,
    /// but training reps can be faster. 1.5s floor catches sprint
    /// cadence (~40 burpees/min) without double-counting the
    /// jump-then-land oscillation as two reps.
    private static let burpeeMinInterval: TimeInterval = 1.5

    // MARK: - Tuning constants (sandbag lunges, §49)

    /// Positive Z peak for the drive-up phase after a lunge knee
    /// drop. Lunges have smaller vertical amplitude than burpees
    /// or wall balls (the body doesn't fully rise) but a real
    /// lunge — sandbag-loaded, deep knee bend, full drive — pushes
    /// well above +0.5g at the recovery apex. The previous
    /// 0.35g floor was tight enough to false-positive on the
    /// walking-arm swing between reps (athletes step forward
    /// during the 100m carry); raised to 0.5g in §49 follow-up
    /// after a review caught the walking-confusion risk.
    private static let lungePositivePeak: Double = 0.5

    /// Negative Z trough for the knee-drop phase. Sandbag-loaded
    /// knee drops produce a real ~-0.4 to -0.6g vertical dip.
    /// The previous -0.2g floor was within the range of an
    /// ambient walking heel-strike (athletes walk forward between
    /// lunges with a sandbag) — tightened to -0.35g in §49
    /// follow-up so background gait can't satisfy the trough
    /// gate. Combined with the +0.5g peak threshold this
    /// requires a real loaded knee drop AND a real drive-up
    /// before a rep registers.
    private static let lungeNegativeTrough: Double = -0.35

    /// Minimum interval between counted lunges. Typical HYROX
    /// pace is ~50 lunges in 100m at ~2.5s/lunge; sprint training
    /// can hit ~2s/lunge. 1.2s floor catches sprint cadence
    /// without double-counting the in-step shuffle some athletes
    /// do between reps.
    private static let lungeMinInterval: TimeInterval = 1.2

    // MARK: - Motion managers

    #if canImport(CoreMotion)
    /// Preferred high-rate source — `CMBatchedSensorManager` on
    /// Series 8+/Ultra running watchOS 9.4+. Pulled into 200Hz
    /// energy-efficient batched delivery while an HKWorkoutSession
    /// is active. Nil on older hardware → fall back to motionManager.
    private let batchedManager: CMBatchedSensorManager? = {
        if #available(watchOS 9.4, *), CMBatchedSensorManager.isDeviceMotionSupported {
            return CMBatchedSensorManager()
        }
        return nil
    }()

    /// Fallback motion source. 50Hz update interval — plenty for
    /// wall ball cadence (rep period ≥ 1.2s = 60+ samples per rep)
    /// without the battery cost of higher rates on non-batched-
    /// capable hardware.
    private let motionManager = CMMotionManager()
    #endif

    /// Buffer for last-seen rep timestamps, used purely for
    /// diagnostics (smoke-checking detection during real-world
    /// use). Capped at 100 to avoid unbounded growth.
    private var repTimestamps: [Date] = []

    /// Throttle clock for WCSession publish. Bound the rate at
    /// 1Hz max so the iPhone's race screen renders smoothly
    /// without hammering WCSession's per-app budget. Per-rep
    /// publish would fire up to ~30Hz at sprint pace.
    private var lastPublishedAt: Date = .distantPast
    private static let publishInterval: TimeInterval = 1.0

    private init() {}

    // MARK: - Lifecycle

    /// Begin rep counting for `station`. Phase 1 only supports
    /// `.wallBalls`; other rep stations refuse silently so the
    /// caller can use the same start/stop wiring across all
    /// stations and let this service decide which signatures
    /// it actually handles. Calling start() while already
    /// counting first stops the existing session.
    ///
    /// Returns true when a motion subscription was activated,
    /// false when no compatible hardware is available or the
    /// station isn't supported.
    @discardableResult
    func start(for station: Station) -> Bool {
        #if canImport(CoreMotion)
        // Pick the detector profile for the station, or refuse
        // if it's not a rhythmic-cycle station we know how to
        // count. Sled push / sled pull / farmers carry get
        // continuous-effort instrumentation in a separate track,
        // not rep counting — they fall through to false here.
        let profile: DetectorProfile
        switch station {
        case .wallBalls:
            profile = .wallBalls
        case .rowing, .skiErg:
            profile = .rowingStroke
        case .burpeeBroadJumps:
            profile = .burpeeJump
        case .sandbagLunges:
            profile = .lunge
        default:
            return false
        }

        // Idempotent — re-starting first cancels any in-flight
        // subscription so we don't stack delivery handlers.
        if isCounting {
            stopInternal()
        }

        // Reset per-attempt state — last segment's counts must
        // not bleed into this one. currentRepCount starts at 0,
        // both profiles' detection state goes cold.
        currentRepCount = 0
        currentStationRaw = station.rawValue
        activeProfile = profile
        repTimestamps.removeAll()
        lastRepRegisteredAt = .distantPast
        lastPublishedAt = .distantPast
        // Wall-ball state
        crossedNegative = false
        lastZ = 0
        // Rowing-stroke state — start gate in "seeking valley"
        // so the very first sample doesn't false-positive if
        // it happens to be above the peak threshold. gateArmedAt
        // gets a real value on the first valley→peak transition.
        strokeGate = .seekingValley
        gateArmedAt = .distantPast
        magnitudeRing.removeAll()

        // Try the high-rate batched API first. It requires an
        // active HKWorkoutSession to function — WatchWorkoutManager
        // owns the session for the duration of the race, so by
        // the time we hit this code the session is live.
        //
        // `CMBatchedSensorManager.startDeviceMotionUpdates` handler
        // signature is `([CMDeviceMotion]?, (any Error)?) -> Void`
        // — both array AND error are optional. Errors can arrive
        // mid-stream (sensor drop, session interruption); we bail
        // silently on each. Each motion in the batch gets the
        // same processMotion treatment a single-tick
        // CMMotionManager update would.
        if let batched = batchedManager, #available(watchOS 9.4, *) {
            do {
                try batched.startDeviceMotionUpdates { [weak self] motions, error in
                    guard error == nil, let motions else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        for motion in motions {
                            self.processMotion(motion)
                        }
                    }
                }
                isCounting = true
                return true
            } catch {
                // Fall through to motionManager fallback. The
                // documented failure cases are "no active workout
                // session" (shouldn't happen here) and "hardware
                // not supported" (already gated via isDeviceMotionSupported).
            }
        }

        // 50Hz fallback for older hardware. Still publishes
        // CMDeviceMotion so the downstream math is identical.
        guard motionManager.isDeviceMotionAvailable else {
            isCounting = false
            currentStationRaw = nil
            return false
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard error == nil, let motion else { return }
            self.processMotion(motion)
        }
        isCounting = true
        return true
        #else
        return false
        #endif
    }

    /// Stop rep counting and return the final count for the
    /// just-ended segment. The caller (WatchRaceView's snapshot
    /// observer) typically captures the returned count and
    /// publishes a final WCSession update so the iPhone has
    /// the authoritative end-of-station count even if its
    /// throttle window swallowed the last live publish.
    @discardableResult
    func stop() -> Int {
        let final = currentRepCount
        // §47a — publish the per-rep timestamp batch BEFORE
        // tearing down so the iPhone has the cadence-curve data
        // for the just-ended segment. Buffer is already
        // maintained in `repTimestamps`; just convert + ship.
        // Captures stationRaw locally because stopInternal()
        // clears currentStationRaw and publishCurrentRepTimestamps
        // would no-op after.
        publishCurrentRepTimestamps()
        stopInternal()
        return final
    }

    private func stopInternal() {
        #if canImport(CoreMotion)
        if #available(watchOS 9.4, *), let batched = batchedManager {
            batched.stopDeviceMotionUpdates()
        }
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        #endif
        isCounting = false
        currentStationRaw = nil
        activeProfile = nil
        crossedNegative = false
        lastZ = 0
        strokeGate = .seekingValley
        gateArmedAt = .distantPast
        magnitudeRing.removeAll()
    }

    // MARK: - Signal processing

    #if canImport(CoreMotion)
    private func processMotion(_ motion: CMDeviceMotion) {
        // Dispatch by profile. Wall-ball, burpee, and lunge use
        // Z-axis + negative-trough latch with different thresholds;
        // rowing/ski uses magnitude + valley/peak gate. The three
        // latch-based detectors share the same `crossedNegative`
        // / `lastZ` / `lastRepRegisteredAt` state because they're
        // mutually exclusive at runtime (only one profile is
        // active at a time).
        switch activeProfile {
        case .wallBalls:
            processMotionWallBalls(motion)
        case .rowingStroke:
            processMotionRowingStroke(motion)
        case .burpeeJump:
            processMotionBurpeeJump(motion)
        case .lunge:
            processMotionLunge(motion)
        case nil:
            // Motion can land in the brief window between start()
            // returning false and the caller noticing. Silent.
            break
        }
    }

    /// Wall-ball detector — Z-axis peak with negative-trough latch.
    /// Unchanged from Phase 13 ship; just hoisted into its own
    /// method so the rowing profile can sit alongside.
    private func processMotionWallBalls(_ motion: CMDeviceMotion) {
        // Z-axis of userAcceleration. Wrist convention: positive
        // Z is "out of the back of the hand" when palm faces down,
        // which translates roughly to "up" during a wall ball
        // drive (arms extended overhead, palms facing forward to
        // catch the ball).
        let z = motion.userAcceleration.z
        let now = Date()

        // Latch the negative-trough requirement. Wall ball cycle:
        // catch + squat (Z dips) → drive (Z spikes). Without the
        // latch, the natural recovery oscillation after each peak
        // could re-cross the positive threshold and double-count.
        if z < Self.zNegativeTrough {
            crossedNegative = true
        } else if crossedNegative && z > Self.zPositivePeak {
            // Peak detected after a valid trough — candidate rep.
            // Period gate suppresses double-detects on the same
            // rep's recovery curve.
            if now.timeIntervalSince(lastRepRegisteredAt) >= Self.minRepInterval {
                registerRep(at: now)
            }
            crossedNegative = false
        }
        lastZ = z
    }

    /// Rowing/SkiErg stroke detector — magnitude-based peak
    /// detection with two-state cycle gate.
    ///
    /// Why magnitude instead of a signed axis: rowing involves
    /// the wrist sweeping through a horizontal arc (handle pulled
    /// from extended-forward to retracted-near-chest) and the
    /// axis-aligned acceleration components depend heavily on
    /// wrist orientation, which varies between athletes. The
    /// MAGNITUDE of userAcceleration rises consistently during
    /// every drive phase regardless of wrist orientation, so
    /// it generalizes across users without per-user calibration.
    ///
    /// Algorithm:
    ///   1. Compute |userAcceleration| at this sample.
    ///   2. Push into a 3-sample smoothing ring; use the average
    ///      (raw accelerometer noise at 200Hz produces false
    ///      threshold crossings on every sample).
    ///   3. Gate is in `.seekingValley` after the last stroke.
    ///      Wait for smoothed magnitude to drop below the valley
    ///      threshold (recovery phase) before looking for the
    ///      next peak. Flip to `.seekingPeak`.
    ///   4. In `.seekingPeak`, the first sample above the peak
    ///      threshold (after the refractory period elapses)
    ///      registers a stroke and flips the gate back.
    private func processMotionRowingStroke(_ motion: CMDeviceMotion) {
        // 3-sample smoothing reduces noise without lagging
        // meaningfully (~15ms at 200Hz batched, ~60ms at 50Hz
        // fallback — both well under a stroke cycle).
        let accel = motion.userAcceleration
        let raw = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
        magnitudeRing.append(raw)
        if magnitudeRing.count > Self.magnitudeRingSize {
            magnitudeRing.removeFirst()
        }
        let smoothed = magnitudeRing.reduce(0, +) / Double(magnitudeRing.count)

        let now = Date()

        switch strokeGate {
        case .seekingValley:
            // Wait for the recovery dip before arming the next
            // peak detection. Defends against the post-drive
            // oscillation re-triggering immediately.
            if smoothed < Self.rowingValleyThreshold {
                strokeGate = .seekingPeak
                gateArmedAt = now
            }
        case .seekingPeak:
            // Stale-gate timeout — if we've been waiting for a
            // peak too long, athlete probably stopped rowing
            // (drink, handle adjust, etc.). Re-arm to
            // seekingValley so the next genuine cycle has to
            // re-establish valley → peak from scratch. Without
            // this, the first wrist twitch above 0.35g during
            // a pause would register as a phantom stroke.
            if now.timeIntervalSince(gateArmedAt) > Self.rowingGateTimeout {
                strokeGate = .seekingValley
                return
            }
            // Refractory window AND magnitude floor must both be
            // satisfied — the period gate alone isn't enough
            // because rowing peaks are slightly less sharp than
            // wall balls (broader plateau means multiple samples
            // above threshold per stroke; we want the first).
            guard now.timeIntervalSince(lastRepRegisteredAt) >= Self.rowingMinInterval else {
                return
            }
            if smoothed > Self.rowingPeakThreshold {
                registerRep(at: now)
                strokeGate = .seekingValley
            }
        }
    }

    /// §49 — Burpee broad jump detector. Same Z-axis negative-
    /// trough latch pattern as wall balls but with bigger
    /// amplitudes (jumping is more violent than overhead pressing)
    /// and a longer refractory window (slower cycle).
    ///
    /// Cycle anatomy:
    ///   1. Athlete drops to floor (chest-down). Sharp negative
    ///      Z impulse from the impact — typically -1.5 to -2.5g.
    ///   2. Push-up phase. Z hovers near zero for 500-1500ms.
    ///   3. Jump up + forward. Sharp positive Z spike at the
    ///      drive apex — typically +1.5 to +2.5g.
    ///   4. Land. Brief negative spike that re-latches
    ///      `crossedNegative=true` immediately. This is fine —
    ///      it just means the next rep's drop-to-floor is
    ///      reinforcing a gate that's already armed. The
    ///      refractory window (1.5s) is what actually prevents
    ///      double-counting; it filters reps, not the latch.
    ///
    /// The latch (`crossedNegative`) requires the drop-to-floor
    /// phase to register before the jump-up peak can fire,
    /// preventing a stray upward wrist motion (mid-walking, mid-
    /// setup) from being miscounted as a rep.
    ///
    /// Sprint-cadence note: training reps under 1.5s apart are
    /// silently dropped by the refractory. Race pace is ~5s/rep
    /// so this is a non-issue in practice; if sprint-cadence
    /// training matters later, lower `burpeeMinInterval` or
    /// switch the latch-clear to fire only on successful
    /// registration.
    private func processMotionBurpeeJump(_ motion: CMDeviceMotion) {
        let z = motion.userAcceleration.z
        let now = Date()
        if z < Self.burpeeNegativeTrough {
            crossedNegative = true
        } else if crossedNegative && z > Self.burpeePositivePeak {
            if now.timeIntervalSince(lastRepRegisteredAt) >= Self.burpeeMinInterval {
                registerRep(at: now)
            }
            crossedNegative = false
        }
        lastZ = z
    }

    /// §49 — Sandbag lunge detector. Same negative-trough latch
    /// pattern but with softer thresholds because lunges involve
    /// less vertical excursion than burpees or wall balls.
    ///
    /// Cycle anatomy:
    ///   1. Knee drop (descent of the lunging leg). Soft negative
    ///      Z dip — typically -0.3 to -0.5g.
    ///   2. Drive back up. Watch arm sweeps slightly forward as
    ///      the leg straightens, producing a 0.4-0.7g positive Z.
    ///   3. Step / pause before next rep.
    ///
    /// Phase 50 will layer gyro roll tracking on this profile to
    /// classify each rep as left-lead or right-lead (asymmetry
    /// detection — the killer coaching insight for this station).
    /// Phase 49 just counts cycles.
    private func processMotionLunge(_ motion: CMDeviceMotion) {
        let z = motion.userAcceleration.z
        let now = Date()
        if z < Self.lungeNegativeTrough {
            crossedNegative = true
        } else if crossedNegative && z > Self.lungePositivePeak {
            if now.timeIntervalSince(lastRepRegisteredAt) >= Self.lungeMinInterval {
                registerRep(at: now)
            }
            crossedNegative = false
        }
        lastZ = z
    }
    #endif

    private func registerRep(at timestamp: Date) {
        currentRepCount += 1
        lastRepRegisteredAt = timestamp
        repTimestamps.append(timestamp)
        if repTimestamps.count > 100 {
            repTimestamps.removeFirst(repTimestamps.count - 100)
        }

        // Throttled WCSession publish. The race screen's rep chip
        // re-renders 1Hz max anyway (driven by SwiftUI body
        // invalidation from @Observable property writes), so per-
        // rep broadcast would just burn WC budget for no UX gain.
        let now = Date()
        if now.timeIntervalSince(lastPublishedAt) >= Self.publishInterval {
            lastPublishedAt = now
            publishCurrentCount()
        }
    }

    // MARK: - WCSession publish

    /// Broadcast the current rep count to the iPhone. Called from
    /// `registerRep` on the 1Hz throttle, and from `stop()`'s
    /// caller on segment-end to deliver the authoritative final
    /// count. Routed through `WatchRaceClient` which owns the
    /// WCSession handle.
    func publishCurrentCount() {
        guard let stationRaw = currentStationRaw else { return }
        let update = WatchRepCountUpdate(
            count: currentRepCount,
            stationRaw: stationRaw,
            sampledAt: Date()
        )
        WatchRaceClient.shared.publishRepCount(update)
    }

    /// §47a — Publish the full per-rep timestamp array to the
    /// iPhone. Fires once at segment-end inside `stop()`. The
    /// iPhone uses this to compute stroke-rate curves, DPS,
    /// pacing consistency — analytics the count-only live
    /// updates can't power.
    ///
    /// No-op when no stroke / rep was actually counted —
    /// shipping an empty batch would just bloat the channel
    /// for no value (the receiver's stale-sample / station
    /// match guards would discard it anyway).
    func publishCurrentRepTimestamps() {
        guard let stationRaw = currentStationRaw else { return }
        guard !repTimestamps.isEmpty else { return }
        let batch = WatchRepTimestampsBatch(
            timestamps: repTimestamps,
            stationRaw: stationRaw,
            sampledAt: Date()
        )
        WatchRaceClient.shared.publishRepTimestamps(batch)
    }
}

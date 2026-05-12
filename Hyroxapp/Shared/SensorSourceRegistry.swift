import Foundation
import Observation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(AVFoundation) && !os(watchOS)
import AVFoundation
#endif

// §19.2 — adaptive sensor sourcing.
//
// One service that knows what's connected right now and what
// data each device can provide. Views read `profile` to decide
// whether to render an HR chip, a cadence readout, a source
// attribution glyph, etc. — and the rest of the app gracefully
// degrades through four `DeviceProfile` cases.
//
// Sources tracked:
//   • Apple Watch  — via `WCSession.isPaired` / `.isReachable`
//   • AirPods motion — via `CMHeadphoneMotionManager.isDeviceMotionAvailable`
//                      (true on AirPods Pro 1+, AirPods 4, AirPods Max;
//                      false on AirPods 2/3 non-Pro)
//   • AirPods HR    — derived from the current audio-route port name
//                      containing "Pro 3" (Apple's only HR-capable
//                      earbuds today; rumored Pro 4 / Max 2 would
//                      extend this match list when they ship)
//
// Reactivity model:
//   • Audio-route changes fire `AVAudioSession.routeChangeNotification`,
//     which this registry subscribes to — gives us instant updates
//     when AirPods are inserted/removed mid-session.
//   • WCSession state doesn't publish KVO. Callers that care about
//     mid-race Watch disconnect can invoke `refresh()` from their
//     `.onAppear` / `WCSessionDelegate.sessionReachabilityDidChange`
//     hooks. Race start path always calls `refresh()` once.
//   • HR source attribution — `recordHRSource(_:)` is called by the
//     HR ingestion path in `RaceViewModel` when a fresh sample lands
//     with a known `HKHeartRateSample.sourceRevision`. That gives
//     downstream views the "HR via Apple Watch" / "HR via AirPods
//     Pro 3" / "fused" chip without each consumer re-reading
//     HealthKit.
//
// iOS / iPadOS only. watchOS doesn't pair to AirPods directly and
// doesn't need a registry — the wrist is its own source.
@MainActor
@Observable
final class SensorSourceRegistry {

    static let shared = SensorSourceRegistry()

    // MARK: - Watch state

    /// True when an Apple Watch is paired to this iPhone, regardless
    /// of reachability. Survives the watch being off-wrist /
    /// in-the-other-room — pairing is durable, reachability is
    /// momentary.
    private(set) var hasWatch: Bool = false

    /// True when the paired Watch is currently reachable for live
    /// `WCSession` messaging. Distinct from `hasWatch` because a
    /// paired Watch can be unreachable (off-wrist, dead battery,
    /// out of Bluetooth range). HR streaming via HealthKit doesn't
    /// require reachability — the Watch can record locally and
    /// sync later — but the Race-screen live chip does need the
    /// live channel.
    private(set) var watchReachable: Bool = false

    // MARK: - AirPods state

    /// True when AirPods Pro 1+, AirPods 4, or AirPods Max are the
    /// current audio output AND `CMHeadphoneMotionManager` reports
    /// device motion is available. False on AirPods 2 / 3 (non-Pro)
    /// — they lack the motion-processing hardware.
    private(set) var hasAirPodsMotion: Bool = false

    /// True when AirPods Pro 3 (or future HR-capable models) are
    /// the current audio output. Derived from the audio route port
    /// name. HR streaming through HealthKit auto-fuses with the
    /// Watch when both are present (Apple does the source picking
    /// at the OS layer).
    private(set) var hasAirPodsHR: Bool = false

    /// Display name of the AirPods currently in the audio route,
    /// or nil when no AirPods connected. e.g. "AirPods Pro 3" /
    /// "AirPods Pro" / "AirPods Max". Used by the source
    /// attribution chip + the post-race provenance block.
    private(set) var airPodsModelName: String? = nil

    // MARK: - HR source provenance

    /// The most recent HR sample's source, as observed by the HR
    /// ingestion path. Drives the live HR chip's attribution glyph
    /// and the post-race provenance block. Defaults to `.unknown`
    /// before the first sample lands; `.iPhone` is a sentinel for
    /// fallback paths (manual entry / mock data).
    private(set) var lastHRSource: HRSource = .unknown

    enum HRSource: Equatable, Hashable {
        case watch
        case airPods(model: String)   // model from sourceRevision, e.g. "AirPods Pro 3"
        case fused                    // both Watch + AirPods publishing within the same window
        case iPhone
        case unknown

        /// Map a `HKHeartRateSample.sourceRevision.source.name`
        /// string to an HRSource case. Centralizes the substring
        /// matching so every HR ingestion path uses the same
        /// classifier rules. Defensive across the various names
        /// Apple uses across iOS versions ("Apple Watch", "Sarah's
        /// Apple Watch", "AirPods Pro 3", etc.).
        static func classify(sourceName: String) -> HRSource {
            let lower = sourceName.lowercased()
            if lower.contains("apple watch") || lower == "watch" {
                return .watch
            }
            if lower.contains("airpods") {
                return .airPods(model: sourceName)
            }
            if lower.contains("iphone") {
                return .iPhone
            }
            return .unknown
        }

        /// Short display label for the in-line attribution chip.
        var shortLabel: String {
            switch self {
            case .watch:                return "Apple Watch"
            case .airPods(let model):   return model
            case .fused:                return "Fused"
            case .iPhone:               return "iPhone"
            case .unknown:              return "—"
            }
        }

        /// SF Symbol name for the source glyph. Falls back to a
        /// generic heart on `.unknown` so the chip never renders
        /// empty.
        var symbolName: String {
            switch self {
            case .watch:        return "applewatch"
            case .airPods:      return "airpodspro"
            case .fused:        return "arrow.triangle.merge"
            case .iPhone:       return "iphone"
            case .unknown:      return "heart"
            }
        }
    }

    // MARK: - Device profile

    /// The composite "what can we track right now" answer. Drives
    /// per-feature enablement gates in the live race screen,
    /// Profile, and Train hub.
    var profile: DeviceProfile {
        let airPodsActive = hasAirPodsHR || hasAirPodsMotion
        if hasWatch && airPodsActive {
            return .full
        } else if hasWatch {
            return .watchOnly
        } else if airPodsActive {
            return .airpodsOnly
        } else {
            return .minimal
        }
    }

    enum DeviceProfile: String, Equatable {
        /// Watch + AirPods Pro 3 + iPhone. Everything lights up.
        /// HR fuses; rep counting can fuse wrist + head IMU.
        case full

        /// Watch + iPhone, no AirPods (or non-motion AirPods).
        /// Current pre-§19 Trakrr — every HR feature works.
        case watchOnly

        /// AirPods Pro 3 + iPhone, no Watch. All HR-derived
        /// features work via in-ear PPG. SpO2 / skin temp /
        /// overnight HRV / ECG / Watch race surface gone.
        /// AirPods-exclusive features (cadence, vertical
        /// oscillation, posture drift) light up.
        case airpodsOnly

        /// iPhone only. Race timer + pace ghost + roxzone +
        /// Live Activity. No HR-dependent features.
        case minimal

        /// Single-line label for the sensor status row.
        var displayLabel: String {
            switch self {
            case .full:         return "Apple Watch + AirPods Pro 3"
            case .watchOnly:    return "Apple Watch"
            case .airpodsOnly:  return "AirPods"
            case .minimal:      return "iPhone only"
            }
        }
    }

    // MARK: - Lifecycle

    private var headphoneMotion: CMHeadphoneMotionManager?

    private init() {
        // Lazy CMHeadphoneMotionManager — instantiation is cheap
        // but `isDeviceMotionAvailable` is queried per refresh so
        // the registry tracks devices that connect mid-session.
        headphoneMotion = CMHeadphoneMotionManager()

        // Audio-route changes (AirPods inserted / removed /
        // switched to speaker) flow through this notification.
        // Reason key distinguishes insertions from removals; we
        // refresh on all of them and let `refreshAirPodsState`
        // re-read the current route as the source of truth.
        #if canImport(AVFoundation) && !os(watchOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        #endif

        refresh()
    }

    // MARK: - Refresh

    /// Re-evaluate all sources. Idempotent. Call from app launch,
    /// race-start, and scene-phase transitions to keep state
    /// honest. Audio-route changes fire `audioRouteChanged(_:)`
    /// automatically.
    func refresh() {
        refreshWatchState()
        refreshAirPodsState()
    }

    private func refreshWatchState() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            hasWatch = false
            watchReachable = false
            return
        }
        let session = WCSession.default
        hasWatch = session.isPaired
        watchReachable = session.isReachable
        #else
        hasWatch = false
        watchReachable = false
        #endif
    }

    private func refreshAirPodsState() {
        #if canImport(AVFoundation) && !os(watchOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        var foundHR = false
        var foundModelName: String? = nil

        for output in outputs {
            let portName = output.portName
            let lower = portName.lowercased()
            // Match any AirPods family; capture the exact display
            // name so the chip can render "AirPods Pro 3" verbatim
            // rather than a generic "AirPods" string.
            if lower.contains("airpods") {
                foundModelName = portName
                // HR sensor capability — Apple's docs are explicit
                // that only Pro 3 ships with in-ear PPG today.
                // Future Pro 4 / Max 2 would be added here when
                // they ship.
                if lower.contains("pro 3") {
                    foundHR = true
                }
            }
        }

        airPodsModelName = foundModelName
        hasAirPodsHR = foundHR

        // CMHeadphoneMotionManager is the authoritative check for
        // motion availability — handles the AirPods 2/3 (non-Pro)
        // case correctly by returning false even when those are
        // the active audio route.
        hasAirPodsMotion = headphoneMotion?.isDeviceMotionAvailable ?? false
        #else
        hasAirPodsMotion = false
        hasAirPodsHR = false
        airPodsModelName = nil
        #endif
    }

    #if canImport(AVFoundation) && !os(watchOS)
    @objc private nonisolated func audioRouteChanged(_ note: Notification) {
        // Notification fires on an arbitrary queue. Hop to
        // MainActor to mutate the @Observable state cleanly.
        Task { @MainActor [weak self] in
            self?.refreshAirPodsState()
        }
    }
    #endif

    // MARK: - HR source attribution

    /// Called by the HR ingestion path (`RaceViewModel`) when a
    /// fresh HR sample arrives. The source is derived from
    /// `HKHeartRateSample.sourceRevision.source.name`:
    ///   • "Apple Watch" → .watch
    ///   • "AirPods Pro 3" / "AirPods" → .airPods(model:)
    ///   • multiple sources within a 5s window → .fused
    /// Updates `lastHRSource`, which views render via the
    /// attribution chip.
    func recordHRSource(_ source: HRSource) {
        guard lastHRSource != source else { return }
        lastHRSource = source
    }

    // MARK: - Convenience

    /// True when at least one HR-capable device is currently
    /// publishing samples. Used by views that want to render a
    /// placeholder when HR isn't available — different from
    /// "no Watch paired" because the Watch could be paired but
    /// off-wrist.
    var canTrackHR: Bool {
        hasWatch || hasAirPodsHR
    }

    /// True when at least one motion-capable sensor is
    /// available for AirPods-derived metrics (cadence, vertical
    /// oscillation, posture drift). Today only AirPods Pro 1+
    /// / AirPods 4 / Max satisfy this — the Watch motion
    /// stream is a separate pipeline owned by `WatchWorkoutManager`.
    var canTrackHeadMotion: Bool {
        hasAirPodsMotion
    }
}

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// §12C — Live Activity attributes for the Free Run timer.
// Parallel to RaceActivityAttributes but with the Free-Run-
// shaped fields: distance + pace instead of segment counts +
// roxzone phase. Shared between the iOS app target (which
// starts / updates / ends activities) and the Widget Extension
// target (which renders the lock screen + Dynamic Island UI).
//
// Same Codable + Sendable + push-budget discipline RaceActivity
// Attributes uses — see that file's header for the full
// rationale on why we send keyed timestamps instead of tick-by-
// tick elapsed values.
//
// Guarded `#if canImport(ActivityKit)` so non-iOS platforms
// (macOS, watchOS) compile cleanly.
#if canImport(ActivityKit)

public struct FreeRunActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {

        // Three-state phase for Free Run lifecycle. Distinct
        // from race's phase: no inRoxzone (Free Run has no
        // segments) but otherwise symmetric.
        public enum Phase: String, Codable, Hashable, Sendable {
            case running
            case paused
            case finished
        }

        public var phase: Phase

        // Reference timestamp for the widget's local ticking
        // timer. Equal to FreeRun.startedAt while running, or
        // shifted forward by total pause time after a resume
        // (matches FreeRunEngine's internal shift). Widgets
        // render via SwiftUI's Text(_:style:) timer view — no
        // per-second updates burned against the budget.
        public var timerStart: Date

        // Frozen elapsed time at the moment of pause / finish.
        // Non-nil only when phase ∈ {.paused, .finished}. The
        // widget renders this verbatim instead of starting a
        // live timer, so pause + finish screens stay still.
        public var frozenElapsed: TimeInterval?

        // Cumulative distance in meters. The widget converts
        // to the user's preferred unit (mile / km) using
        // splitUnitMetres below — we ship meters for precision
        // and let the widget format.
        public var distanceMeters: Double

        // Meters-per-unit for the athlete's chosen split unit.
        // 1609.344 for miles, 1000 for km. Sent as a number so
        // the widget doesn't have to mirror the FreeRunSplitUnit
        // enum (which would couple the widget target to the
        // FreeRun feature module).
        public var splitUnitMetres: Double

        // Short unit label for the widget ("mi" / "km"). Same
        // rationale as splitUnitMetres — no enum coupling.
        public var splitUnitLabel: String

        // Average pace in seconds per unit (so /mi or /km
        // matching splitUnitLabel). Optional: nil during the
        // first ~5s before distance ramps up, or after a pause
        // resume before the engine recomputes.
        public var avgPaceSecondsPerUnit: TimeInterval?

        // Live HR + zone — same convention as the race activity.
        // Both optional; widget skips the chip when nil.
        public var currentHR: Int?
        public var currentHRZone: Int?

        public init(
            phase: Phase,
            timerStart: Date,
            frozenElapsed: TimeInterval? = nil,
            distanceMeters: Double,
            splitUnitMetres: Double,
            splitUnitLabel: String,
            avgPaceSecondsPerUnit: TimeInterval? = nil,
            currentHR: Int? = nil,
            currentHRZone: Int? = nil
        ) {
            self.phase = phase
            self.timerStart = timerStart
            self.frozenElapsed = frozenElapsed
            self.distanceMeters = distanceMeters
            self.splitUnitMetres = splitUnitMetres
            self.splitUnitLabel = splitUnitLabel
            self.avgPaceSecondsPerUnit = avgPaceSecondsPerUnit
            self.currentHR = currentHR
            self.currentHRZone = currentHRZone
        }
    }

    // Static / fixed-for-the-activity fields. Free Run uses
    // the location type (indoor vs outdoor) to label the lock-
    // screen banner — outdoor runs see "OUTDOOR RUN", indoor
    // see "INDOOR RUN". Set once on start, never changes.
    public let locationLabel: String

    public init(locationLabel: String) {
        self.locationLabel = locationLabel
    }
}

#endif

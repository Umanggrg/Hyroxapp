import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// Live Activity attributes for the race timer. Shared between
// the iOS app target (which starts/updates/ends activities) and
// the Widget Extension target (which renders the lock screen +
// Dynamic Island UI). Both targets must include this file via
// target membership.
//
// ActivityAttributes splits its data into two halves:
//
//   • Static fields (the type itself) — set once on `start` and
//     never change for the lifetime of the activity. We put the
//     race name and start timestamp here because they're
//     immutable for a given race.
//
//   • ContentState (nested struct) — mutable, updated via
//     `Activity.update(...)`. Carries everything that changes
//     during the race: which station you're on, current phase
//     (running / paused / inRoxzone), elapsed time at the moment
//     of the last update, and pause/roxzone reference timestamps
//     so the widget can render a live-counting timer without
//     receiving a tick-by-tick stream of updates.
//
// Why we don't push elapsed-second updates: ActivityKit budgets
// updates per app per hour. Pushing every 100ms during a 90-min
// race would burn the budget instantly. Instead we send keyed
// timestamps and let the widget compute elapsed locally via
// SwiftUI's `Text(_:style:)` timer view — that ticks for free
// in the system process.
//
// Guarded `#if canImport(ActivityKit)` so platforms without it
// (macOS, watchOS) compile cleanly. The widget extension and
// the iOS app both have ActivityKit available; this is just
// belt-and-braces.
#if canImport(ActivityKit)

public struct RaceActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        // The phase the race is currently in. Drives which UI
        // the widget renders (active timer / paused freeze /
        // roxzone transition timer).
        public enum Phase: String, Codable, Hashable, Sendable {
            case running
            case paused
            case inRoxzone
            case finished
        }

        public var phase: Phase

        // Timestamp keys for the widget's local timer:
        //
        //   • timerStart — for the OVERALL race elapsed timer.
        //     Equal to `Race.startedAt` while running, or the
        //     start shifted forward by total pause time after a
        //     resume (same shift the engine applies internally).
        //
        //   • segmentStart — for the SEGMENT timer (current
        //     station's elapsed time). Updates on every advance.
        //
        //   • frozenElapsed / frozenSegmentElapsed — non-nil
        //     only when phase == .paused. They snapshot the
        //     timer values at the moment of pause so the widget
        //     renders a frozen number rather than a ticking one.
        //
        //   • roxzoneStart — non-nil only when phase ==
        //     .inRoxzone. Drives the transition countup.
        public var timerStart: Date
        public var segmentStart: Date
        public var frozenElapsed: TimeInterval?
        public var frozenSegmentElapsed: TimeInterval?
        public var roxzoneStart: Date?

        // Race progress — 1-indexed for "Station 4 of 16"
        // display semantics that match the in-app UI.
        public var currentStationIndex: Int
        public var totalStations: Int
        public var currentStationName: String

        public init(
            phase: Phase,
            timerStart: Date,
            segmentStart: Date,
            frozenElapsed: TimeInterval? = nil,
            frozenSegmentElapsed: TimeInterval? = nil,
            roxzoneStart: Date? = nil,
            currentStationIndex: Int,
            totalStations: Int,
            currentStationName: String
        ) {
            self.phase = phase
            self.timerStart = timerStart
            self.segmentStart = segmentStart
            self.frozenElapsed = frozenElapsed
            self.frozenSegmentElapsed = frozenSegmentElapsed
            self.roxzoneStart = roxzoneStart
            self.currentStationIndex = currentStationIndex
            self.totalStations = totalStations
            self.currentStationName = currentStationName
        }
    }

    // Static / fixed-for-the-activity fields.
    public let raceName: String

    public init(raceName: String) {
        self.raceName = raceName
    }
}

#endif

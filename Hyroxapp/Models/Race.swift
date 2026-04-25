import Foundation
import SwiftData

// A HYROX race — either in-progress (`endedAt == nil`) or finished.
//
// Persisted via SwiftData so:
//   1. Completed races populate History.
//   2. An in-progress race survives app backgrounding and force-kill; on next
//      launch we find the unfinished `Race` and offer to resume from it.
//
// `splits` is stored as an array of the existing `Split` value struct.
// SwiftData transparently encodes `Codable` composite types as attributes,
// which keeps v0.1 simple (single table, no relationships). If v1 needs to
// query individual splits for leaderboards (e.g. "fastest wall ball ever"),
// we can promote `Split` to its own `@Model` class then.
@Model
final class Race {

    // Stable identity — useful for resume-by-id and future cloud-sync pairing.
    var id: UUID

    // When the timer began ticking. All elapsed calculations derive from this.
    var startedAt: Date

    // When the final segment was completed. `nil` while the race is in progress.
    var endedAt: Date?

    // Completed splits, in race order. Appended as the athlete advances.
    var splits: [Split]

    // When the current (not-yet-completed) segment began. `nil` once finished.
    var currentSegmentStartedAt: Date?

    // The station sequence this race is following, as raw values. We store it
    // (rather than recomputing from `Station.raceSequence`) so future variants
    // — truncated practice runs, Doubles, etc. — coexist in History without
    // conflating them with full official races.
    var sequenceRaw: [Int]

    // "solo" or "duo" — stored as raw string to avoid SwiftData enum-attribute
    // quirks. Expose the typed value through the `mode` computed property.
    var modeRawValue: String

    // Sort key for History. Set once at insertion, so a paused-and-resumed
    // race keeps its original chronological slot in the list.
    var createdAt: Date

    // Free-form athlete notes — "how did this feel?", what to remember,
    // what to try next time. Editable from `RaceSummaryView` immediately
    // after finishing and from `RaceDetailView` retroactively. Empty
    // string default keeps SwiftData's lightweight migration happy for
    // pre-existing rows: adding a String with a default value is a
    // safe additive schema change (unlike the division-enum case which
    // had to go optional).
    var notes: String = ""

    // Athlete's finish-time goal for this race, set at start time
    // ("I want to beat 1:30:00 today"). Optional because setting a
    // target is opt-in — some training days are just "show up and
    // move," not goal-chasing. Displayed as a subtitle under the
    // in-race timer and on the summary / detail views as a delta
    // ("+5:23 over target" / "1:15 ahead of target").
    //
    // Stored on Race (not UserProfile) because the goal is per-race:
    // the athlete might aim for 1:30 on one day and a relaxed 1:45
    // on another. Profile-level default is a future enhancement.
    var targetDuration: TimeInterval?

    // Optional human-given title for the race ("Tuesday morning race",
    // "First sub-1:30 attempt", "Brick session with Praanshu"). Empty
    // string falls back to the auto-generated date heading at every
    // display site, so untitled races still render fine. Foreshadows
    // the social feed where titles are how Strava activities get
    // character. Same SwiftData additive-schema-safe pattern as
    // `notes` — empty default lets pre-existing rows migrate cleanly.
    var name: String = ""

    // Set to the moment of pause when the race is paused, nil
    // otherwise. Persisting the pause time means a paused race
    // survives backgrounding / force-kill: on relaunch we read
    // `engineState` and bring the engine back as `.paused`, ready
    // to be resumed by the athlete with the original elapsed-time
    // math intact. Same SwiftData additive-default pattern as
    // `notes` / `name`; pre-existing rows decode cleanly with nil.
    var pausedAt: Date?

    // Optional photo attached to this race — gym selfie, workout
    // shot, post-race PR snap. Stored as compressed JPEG bytes
    // (~0.7 quality on save) the same way UserProfile stores
    // avatars, so the whole race travels with its photo as one
    // unit through SwiftData (and later cloud sync). When present,
    // the photo becomes the hero banner on RaceCardView and the
    // shareable race card — the most direct foreshadow of the
    // social feed where photos drive engagement.
    //
    // Migration-safe nil default — pre-existing race rows decode
    // cleanly without a photo, same as `notes` / `name`.
    @Attribute(.externalStorage) var photoData: Data?

    // Roxzone-mode persistence. When non-nil, the race is
    // currently in Roxzone state — the previous segment closed
    // at this timestamp and the athlete is in transition to the
    // next segment. Cleared when the next segment starts (its
    // duration is captured into `pendingRoxzoneSeconds` for the
    // engine to attach to the upcoming split).
    //
    // Survives force-kill: on relaunch, `engineState` reads this
    // and reconstitutes the engine in `.inRoxzone` so the
    // athlete picks up exactly where they left off.
    var roxzoneStartedAt: Date?

    // Roxzone duration to attach to the next-completed split.
    // Set after the user starts a segment from .inRoxzone via
    // `startNextSegment(at:)` — the engine stashes the duration
    // here, then consumes it on the next advance/endSegment.
    // Survives force-kill so a kill mid-segment-after-roxzone
    // doesn't lose the transition time.
    var pendingRoxzoneSeconds: TimeInterval?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        splits: [Split] = [],
        currentSegmentStartedAt: Date? = nil,
        sequence: [Station] = Station.raceSequence,
        mode: RaceMode = .solo,
        createdAt: Date = Date(),
        notes: String = "",
        targetDuration: TimeInterval? = nil,
        name: String = "",
        pausedAt: Date? = nil,
        photoData: Data? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.splits = splits
        self.currentSegmentStartedAt = currentSegmentStartedAt
        self.sequenceRaw = sequence.map(\.rawValue)
        self.modeRawValue = mode.rawValue
        self.createdAt = createdAt
        self.notes = notes
        self.targetDuration = targetDuration
        self.name = name
        self.pausedAt = pausedAt
        self.photoData = photoData
    }

    // MARK: - Derived

    var isFinished: Bool { endedAt != nil }

    var sequence: [Station] {
        sequenceRaw.compactMap(Station.init(rawValue:))
    }

    var mode: RaceMode {
        RaceMode(rawValue: modeRawValue) ?? .solo
    }

    // Total duration — `nil` while the race is in progress.
    var totalDuration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    // Reconstitute a `RaceEngine.State` from persisted fields so a resumed
    // race picks up exactly where it left off (splits, current segment start,
    // total elapsed — all accurate to the millisecond).
    var engineState: RaceEngine.State {
        if let endedAt {
            return .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
        // Roxzone has its OWN no-current-segment shape: the
        // previous segment is closed (in `splits`), the next
        // hasn't started, and `roxzoneStartedAt` records the
        // transition's start. Resolved before the in-progress
        // path because it has no `currentSegmentStartedAt`.
        if let roxStart = roxzoneStartedAt, currentSegmentStartedAt == nil {
            return .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxStart
            )
        }
        if let segStart = currentSegmentStartedAt {
            // Paused state takes precedence over inProgress when both
            // currentSegmentStartedAt and pausedAt are set. The engine
            // state machine resolves cleanly back to .inProgress once
            // the athlete taps Resume.
            if let pausedAt {
                return .paused(
                    startedAt: startedAt,
                    currentSegmentStartedAt: segStart,
                    splits: splits,
                    pausedAt: pausedAt
                )
            }
            return .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segStart,
                splits: splits
            )
        }
        return .notStarted
    }
}

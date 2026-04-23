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

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        splits: [Split] = [],
        currentSegmentStartedAt: Date? = nil,
        sequence: [Station] = Station.raceSequence,
        mode: RaceMode = .solo,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.splits = splits
        self.currentSegmentStartedAt = currentSegmentStartedAt
        self.sequenceRaw = sequence.map(\.rawValue)
        self.modeRawValue = mode.rawValue
        self.createdAt = createdAt
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
        if let segStart = currentSegmentStartedAt {
            return .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segStart,
                splits: splits
            )
        }
        return .notStarted
    }
}

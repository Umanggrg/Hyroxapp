import Foundation
import SwiftData

// A saved custom workout — a reusable named sequence of stations.
//
// Created from the Custom Workout Builder when an athlete taps Save on
// a sequence they've built, so they don't have to re-construct the
// same pattern every Tuesday. "Quick Conditioning", "Sled Circuit",
// "Half Rox" are typical names.
//
// Shape mirrors `Race`: `sequenceRaw` is an array of `Station.rawValue`
// ints so SwiftData stores the ordered list without needing a separate
// relational table or a Codable round-trip. The typed `sequence: [Station]`
// accessor below is the read path everyone should use.
//
// `name` is the user's free-form label — non-empty, no uniqueness
// constraint, no format rules. If two templates happen to be named
// "Tuesday," that's the athlete's problem (same as Notes or any other
// folder-named app).
//
// Sorted by `createdAt` descending in the picker list; `updatedAt`
// tracks edits for a future "last modified" display.
@Model
final class WorkoutTemplate {

    // Stable identity — useful for delete-by-id and future cloud pairing.
    var id: UUID

    var name: String

    // Station rawValues in the order the template runs. Engine
    // reconstructs the [Station] via `sequence` below.
    var sequenceRaw: [Int]

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sequence: [Station],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sequenceRaw = sequence.map(\.rawValue)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    // Typed accessor over `sequenceRaw`. `compactMap` drops any
    // unrecognizable rawValues (shouldn't happen in practice but keeps
    // the read path defensive against a future rawValue being removed).
    var sequence: [Station] {
        sequenceRaw.compactMap(Station.init(rawValue:))
    }

    // Count displayed in the picker row — no need to call `.sequence.count`
    // which would re-build the typed array just to count.
    var stationCount: Int { sequenceRaw.count }
}

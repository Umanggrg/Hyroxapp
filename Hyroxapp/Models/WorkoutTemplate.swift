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

    // MARK: - Default templates (first-launch seeding)

    // Three starter workouts inserted on first app launch, when the
    // athlete has no saved templates yet. Gives them something useful
    // to load from the Custom Workout Builder right away — better
    // than landing on an empty picker that requires building from
    // scratch before the app does anything for them.
    //
    // Each one is a real-world HYROX training pattern:
    //   • Half HYROX — official 8-segment "halfrox" format, 4 runs
    //     alternating with 4 workouts. Most common scaled-down session.
    //   • Strength Day — heavy-station focus (sleds, lunges, wall balls)
    //     with two runs as transitions. ~30 min, lift-day rhythm.
    //   • Conditioning — cardio-station focus (ski erg, rowing, burpees)
    //     interleaved with runs. Pure engine work, no heavy weights.
    //
    // Sequences chosen to be educational — show the athlete what kinds
    // of bespoke workouts the builder supports. Users will likely build
    // their own variants from these starting points.
    @MainActor
    static func seedDefaultsIfNeeded(in modelContext: ModelContext) {
        var descriptor = FetchDescriptor<WorkoutTemplate>()
        descriptor.fetchLimit = 1

        // Bail if any template already exists. Both "athlete saved one"
        // and "we seeded once on a previous launch" count — we want
        // this method to be a one-shot, never replacing user data.
        guard let existing = try? modelContext.fetch(descriptor), existing.isEmpty else {
            return
        }

        let now = Date()
        let defaults: [WorkoutTemplate] = [
            // Half HYROX: 4 runs + 4 workouts, official halfrox format.
            // Run.run1...run4 used because they're the first four run
            // slots — the engine treats them identically (same .kind),
            // and Split positional indexing means duplicates are fine.
            WorkoutTemplate(
                name: "Half HYROX",
                sequence: [
                    .run1, .skiErg,
                    .run2, .sledPush,
                    .run3, .sandbagLunges,
                    .run4, .wallBalls
                ],
                createdAt: now,
                updatedAt: now
            ),
            // Strength Day: heavy stations with bookend runs. Ordered
            // sled-push → sled-pull (paired heavy) → run reset →
            // sandbag → wall balls (paired posterior chain).
            WorkoutTemplate(
                name: "Strength Day",
                sequence: [
                    .run1,
                    .sledPush, .sledPull,
                    .run2,
                    .sandbagLunges, .wallBalls
                ],
                createdAt: now,
                updatedAt: now
            ),
            // Conditioning: 1km between every cardio station — keeps
            // HR elevated and mimics race-day flow. Skips the sled
            // stations and wall balls entirely (pure engine, no grip).
            WorkoutTemplate(
                name: "Conditioning",
                sequence: [
                    .run1, .skiErg,
                    .run2, .rowing,
                    .run3, .burpeeBroadJumps,
                    .run4, .farmersCarry
                ],
                createdAt: now,
                updatedAt: now
            )
        ]

        for template in defaults {
            modelContext.insert(template)
        }
        try? modelContext.save()
    }
}

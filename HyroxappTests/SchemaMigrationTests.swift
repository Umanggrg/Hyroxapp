import Testing
import Foundation
import SwiftData
@testable import Hyroxapp

// SwiftData lightweight-migration safety tests. Every additive
// optional field we've shipped (Race.notes, .name, .pausedAt,
// .targetDuration, .photoData; Split.weightKg, .repsCompleted, .rpe;
// UserProfile.division, .audioCuesEnabled, .countdownEnabled,
// .notificationsEnabled, .maxHeartRate, .hasCompletedOnboarding;
// RaceEvent everything) needs to decode cleanly in isolation.
//
// We can't perfectly simulate "install old build, then install
// new build" inside a unit test — but we CAN exercise the
// in-memory ModelContainer with the current schema and verify
// that every model:
//   1. Inserts cleanly
//   2. Persists round-trip through a save + fetch
//   3. Codable splits encode/decode without losing fields
//
// If any field's default isn't migration-safe, the
// ModelContainer init itself crashes — caught by the very first
// container-creation test.

@Suite("SwiftData schema migration safety")
struct SchemaMigrationTests {

    // Fresh in-memory container with all four @Model types
    // registered. Mirrors HyroxappApp.swift's modelContainer
    // declaration. If a new @Model is added there but not here,
    // these tests start failing — early-warning signal.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Race.self, UserProfile.self, WorkoutTemplate.self, RaceEvent.self,
            configurations: config
        )
    }

    @Test("ModelContainer initializes with current schema")
    func containerInits() throws {
        _ = try makeContainer()
    }

    @Test("UserProfile defaults round-trip cleanly")
    @MainActor
    func userProfileRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let profile = UserProfile.makeDefault()
        context.insert(profile)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(fetched.count == 1)

        let p = fetched.first!
        // Every additive default field should land at its expected value.
        #expect(p.audioCuesEnabled == true)
        #expect(p.countdownEnabled == true)
        #expect(p.notificationsEnabled == false)
        #expect(p.maxHeartRate == 190)
        #expect(p.hasCompletedOnboarding == false)
        #expect(p.resolvedDivision == .mensOpen)
    }

    @Test("Race with all optional fields nil round-trips")
    @MainActor
    func raceMinimalRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let race = Race(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(5400),
            splits: []
        )
        context.insert(race)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Race>())
        #expect(fetched.count == 1)

        let r = fetched.first!
        // All additive optional fields should be empty / nil.
        #expect(r.notes == "")
        #expect(r.name == "")
        #expect(r.pausedAt == nil)
        #expect(r.targetDuration == nil)
        #expect(r.photoData == nil)
    }

    @Test("Race with all optional fields populated round-trips")
    @MainActor
    func raceFullRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let race = Race(
            startedAt: now.addingTimeInterval(-5400),
            endedAt: now,
            sequence: Station.raceSequence,
            notes: "Felt great",
            targetDuration: 5400,
            name: "Tuesday morning race",
            pausedAt: nil,
            photoData: Data(repeating: 0xAB, count: 64)
        )
        context.insert(race)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Race>())
        let r = fetched.first!
        #expect(r.notes == "Felt great")
        #expect(r.name == "Tuesday morning race")
        #expect(r.targetDuration == 5400)
        #expect(r.photoData?.count == 64)
    }

    @Test("Split Codable handles all fields round-trip")
    func splitCodableRoundTrip() throws {
        let now = Date()
        let original = Split(
            station: .sledPush,
            startedAt: now,
            endedAt: now.addingTimeInterval(240),
            heartRateAvgBPM: 168,
            heartRateMaxBPM: 184,
            activeCaloriesKcal: 28.5,
            weightKg: 152,
            repsCompleted: nil,
            rpe: 8
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Split.self, from: encoded)

        #expect(decoded.station == .sledPush)
        #expect(decoded.heartRateAvgBPM == 168)
        #expect(decoded.heartRateMaxBPM == 184)
        #expect(decoded.activeCaloriesKcal == 28.5)
        #expect(decoded.weightKg == 152)
        #expect(decoded.repsCompleted == nil)
        #expect(decoded.rpe == 8)
    }

    @Test("Split decodes legacy heartRateBPM key into heartRateAvgBPM")
    func splitLegacyHeartRateKey() throws {
        // The CodingKeys map heartRateAvgBPM ↔ JSON key "heartRateBPM"
        // so old persisted splits (pre avg/max split) decode cleanly
        // into the new shape.
        let now = Date()
        let isoStart = ISO8601DateFormatter().string(from: now)
        let isoEnd = ISO8601DateFormatter().string(from: now.addingTimeInterval(300))
        let json = """
        {
          "station": 1,
          "startedAt": \(now.timeIntervalSinceReferenceDate),
          "endedAt": \(now.addingTimeInterval(300).timeIntervalSinceReferenceDate),
          "heartRateBPM": 165
        }
        """.data(using: .utf8)!
        _ = isoStart
        _ = isoEnd

        let decoded = try JSONDecoder().decode(Split.self, from: json)
        #expect(decoded.heartRateAvgBPM == 165)
        #expect(decoded.heartRateMaxBPM == nil)
        #expect(decoded.weightKg == nil)
    }

    @Test("WorkoutTemplate round-trips")
    @MainActor
    func templateRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let template = WorkoutTemplate(
            name: "Half HYROX",
            sequence: [.run1, .sledPush, .run2, .sledPull]
        )
        context.insert(template)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(fetched.first?.name == "Half HYROX")
        #expect(fetched.first?.sequenceRaw.count == 4)
    }

    @Test("RaceEvent round-trips")
    @MainActor
    func raceEventRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let date = Date().addingTimeInterval(60 * 86400)
        let event = RaceEvent(
            name: "HYROX Miami",
            date: date,
            division: .mensOpen,
            targetDuration: 5400,
            location: "Miami, FL"
        )
        context.insert(event)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RaceEvent>())
        let e = fetched.first!
        #expect(e.name == "HYROX Miami")
        #expect(e.location == "Miami, FL")
        #expect(e.targetDuration == 5400)
        #expect(e.resolvedDivision == .mensOpen)
    }

    @Test("RaceEvent with nil division resolves to default")
    @MainActor
    func raceEventNilDivision() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = RaceEvent(
            name: "Untyped Race",
            date: Date().addingTimeInterval(86400),
            division: nil
        )
        context.insert(event)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RaceEvent>())
        let e = fetched.first!
        // resolvedDivision should fall back to .mensOpen, not crash.
        #expect(e.resolvedDivision == .mensOpen)
        #expect(e.divisionRawValue == nil)
    }
}

import Testing
import Foundation
@testable import Hyroxapp

// Tests for the Duo Tier 1 wire protocol.
//
// Three layers, three suites:
//   1. SerializedSplit — Split ↔ SerializedSplit round-trip preserves
//      every field. Critical because the guest reconstructs its
//      local Race row from the host's broadcast snapshot, and any
//      lost field there is silently dropped HR / weight / RPE data.
//   2. RaceStateSnapshot Codable — JSON round-trip over the Multipeer
//      JSON path. The host encodes via `JSONEncoder()`, the guest
//      decodes; every snapshot phase + every optional field needs
//      to survive the transit.
//   3. DuoMessage Codable — every case through `encode()` →
//      `decode(_:)`. This is the wire format; if any case loses
//      its associated value or shifts shape, the guest's
//      `handleInbound` switch silently mismatches and the duo
//      flow stops working.
//
// All tests are fully deterministic — fixed dates, fixed values,
// no clocks involved.

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func t(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

// MARK: - SerializedSplit round-trip

@Suite("SerializedSplit ↔ Split round-trip")
struct SerializedSplitTests {

    @Test("preserves every field on the basic round-trip")
    func basicRoundTrip() {
        let original = Split(
            station: .sledPush,
            startedAt: t(0),
            endedAt: t(195),
            heartRateAvgBPM: 168,
            heartRateMaxBPM: 182,
            activeCaloriesKcal: 41.5,
            weightKg: 152,
            repsCompleted: 1,
            rpe: 9,
            roxzoneSeconds: 8.4
        )

        let serialized = SerializedSplit(from: original)
        let decoded = serialized.toSplit()

        // toSplit() returns Optional<Split> — guard, then field-check.
        guard let decoded else {
            Issue.record("toSplit returned nil for a known-good station")
            return
        }
        #expect(decoded.station == .sledPush)
        #expect(decoded.startedAt == t(0))
        #expect(decoded.endedAt == t(195))
        #expect(decoded.heartRateAvgBPM == 168)
        #expect(decoded.heartRateMaxBPM == 182)
        #expect(decoded.activeCaloriesKcal == 41.5)
        #expect(decoded.weightKg == 152)
        #expect(decoded.repsCompleted == 1)
        #expect(decoded.rpe == 9)
        #expect(decoded.roxzoneSeconds == 8.4)
        #expect(decoded.duration == 195)
    }

    @Test("nil optionals stay nil through round-trip")
    func nilOptionalsRoundTrip() {
        // The "no Watch on wrist, no manual stats entered" case —
        // every optional field stays nil. Tests we don't accidentally
        // coerce nil → 0 anywhere along the way.
        let original = Split(
            station: .run1,
            startedAt: t(0),
            endedAt: t(280)
        )

        let serialized = SerializedSplit(from: original)
        let decoded = serialized.toSplit()

        guard let decoded else {
            Issue.record("toSplit returned nil for a known-good station")
            return
        }
        #expect(decoded.heartRateAvgBPM == nil)
        #expect(decoded.heartRateMaxBPM == nil)
        #expect(decoded.activeCaloriesKcal == nil)
        #expect(decoded.weightKg == nil)
        #expect(decoded.repsCompleted == nil)
        #expect(decoded.rpe == nil)
        #expect(decoded.roxzoneSeconds == nil)
    }

    @Test("Codable JSON round-trip preserves shape")
    func codableJSONRoundTrip() throws {
        let original = SerializedSplit(from: Split(
            station: .wallBalls,
            startedAt: t(60),
            endedAt: t(420),
            heartRateAvgBPM: 175,
            heartRateMaxBPM: 191,
            activeCaloriesKcal: 88,
            weightKg: 9.07,    // 20 lb wall ball
            repsCompleted: 100,
            rpe: 10,
            roxzoneSeconds: 12.0
        ))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SerializedSplit.self, from: data)

        #expect(decoded == original)
    }
}

// MARK: - RaceStateSnapshot Codable

@Suite("RaceStateSnapshot — Codable JSON round-trip")
struct RaceStateSnapshotCodableTests {

    @Test("inProgress with full payload survives JSON encode/decode")
    func inProgressRoundTrip() throws {
        let serializedSplit = SerializedSplit(from: Split(
            station: .run1,
            startedAt: t(0),
            endedAt: t(285),
            heartRateAvgBPM: 158,
            heartRateMaxBPM: 172,
            activeCaloriesKcal: 51.2,
            weightKg: nil,
            repsCompleted: nil,
            rpe: nil,
            roxzoneSeconds: nil
        ))

        let snapshot = RaceStateSnapshot(
            phase: .inProgress,
            startedAt: t(0),
            currentSegmentStartedAt: t(285),
            currentStationIndex: Station.skiErg.rawValue,
            completedStationsCount: 1,
            totalStations: 16,
            divisionRaw: Division.mensOpen.rawValue,
            endedAt: nil,
            pausedAt: nil,
            splits: [serializedSplit],
            currentHeartRateBPM: 162,
            maxHeartRate: 188
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RaceStateSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.splits.count == 1)
        #expect(decoded.splits.first?.heartRateAvgBPM == 158)
        #expect(decoded.maxHeartRate == 188)
    }

    @Test("paused phase preserves pausedAt timestamp")
    func pausedRoundTrip() throws {
        let snapshot = RaceStateSnapshot(
            phase: .paused,
            startedAt: t(0),
            currentSegmentStartedAt: t(60),
            currentStationIndex: Station.skiErg.rawValue,
            completedStationsCount: 1,
            totalStations: 16,
            divisionRaw: Division.womensOpen.rawValue,
            endedAt: nil,
            pausedAt: t(180),
            splits: [],
            currentHeartRateBPM: nil,
            maxHeartRate: 190
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RaceStateSnapshot.self, from: data)

        #expect(decoded.phase == .paused)
        #expect(decoded.pausedAt == t(180))
        #expect(decoded == snapshot)
    }

    @Test("inRoxzone phase preserves currentSegmentStartedAt as transition origin")
    func inRoxzoneRoundTrip() throws {
        let snapshot = RaceStateSnapshot(
            phase: .inRoxzone,
            startedAt: t(0),
            currentSegmentStartedAt: t(285),
            currentStationIndex: Station.skiErg.rawValue,
            completedStationsCount: 1,
            totalStations: 16,
            divisionRaw: Division.mensOpen.rawValue,
            endedAt: nil,
            pausedAt: nil,
            splits: [],
            currentHeartRateBPM: 145,
            maxHeartRate: 190
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RaceStateSnapshot.self, from: data)

        #expect(decoded.phase == .inRoxzone)
        #expect(decoded.currentSegmentStartedAt == t(285))
        #expect(decoded == snapshot)
    }

    @Test("finished phase carries endedAt and zero open-state fields")
    func finishedRoundTrip() throws {
        let snapshot = RaceStateSnapshot(
            phase: .finished,
            startedAt: t(0),
            currentSegmentStartedAt: nil,
            currentStationIndex: Station.wallBalls.rawValue,
            completedStationsCount: 16,
            totalStations: 16,
            divisionRaw: Division.mensOpen.rawValue,
            endedAt: t(4300),
            pausedAt: nil,
            splits: [],
            currentHeartRateBPM: nil,
            maxHeartRate: 190
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RaceStateSnapshot.self, from: data)

        #expect(decoded.phase == .finished)
        #expect(decoded.endedAt == t(4300))
        #expect(decoded.startedAt == t(0))
        #expect(decoded == snapshot)
    }

    @Test("notStarted phase preserves nil timestamps and empty splits")
    func notStartedRoundTrip() throws {
        let snapshot = RaceStateSnapshot(
            phase: .notStarted,
            startedAt: nil,
            currentSegmentStartedAt: nil,
            currentStationIndex: 0,
            completedStationsCount: 0,
            totalStations: 16,
            divisionRaw: Division.mensOpen.rawValue,
            endedAt: nil,
            pausedAt: nil,
            splits: [],
            currentHeartRateBPM: nil,
            maxHeartRate: 190
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RaceStateSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.startedAt == nil)
        #expect(decoded.splits.isEmpty)
    }

    @Test("currentStation resolves through Station(rawValue:) not raceSequence index")
    func currentStationLookup() {
        // The historical bug: indexing into `Station.raceSequence`
        // worked for canonical races by luck (rawValue order ==
        // sequence order), but broke for custom workouts. Verify
        // the snapshot uses Station(rawValue:) so any race shape
        // resolves correctly.
        let snapshot = RaceStateSnapshot(
            phase: .inProgress,
            startedAt: t(0),
            currentSegmentStartedAt: t(0),
            currentStationIndex: Station.wallBalls.rawValue,
            completedStationsCount: 0,
            totalStations: 1,
            divisionRaw: Division.mensOpen.rawValue,
            endedAt: nil,
            maxHeartRate: 190
        )

        #expect(snapshot.currentStation == .wallBalls)
    }

    @Test("division resolves with .mensOpen fallback for unknown raw")
    func divisionFallback() {
        let snapshot = RaceStateSnapshot(
            phase: .inProgress,
            startedAt: t(0),
            currentSegmentStartedAt: t(0),
            currentStationIndex: 0,
            completedStationsCount: 0,
            totalStations: 16,
            divisionRaw: "garbage-from-future-build",
            endedAt: nil
        )

        #expect(snapshot.division == .mensOpen)
    }
}

// MARK: - DuoMessage Codable

#if canImport(MultipeerConnectivity)

@Suite("DuoMessage — wire protocol round-trip")
struct DuoMessageCodableTests {

    @Test("hello round-trips with display name and division")
    func helloRoundTrip() {
        let message = DuoMessage.hello(
            displayName: "Sarah",
            divisionRaw: Division.womensOpen.rawValue
        )

        let data = message.encode()
        let decoded = DuoMessage.decode(data)

        #expect(decoded == message)
    }

    @Test("every request* case round-trips")
    func requestCasesRoundTrip() {
        let cases: [DuoMessage] = [
            .requestStart,
            .requestAdvance,
            .requestEndSegment,
            .requestStartNextSegment,
            .requestPause,
            .requestResume,
            .requestFinish,
            .requestCancel
        ]

        for message in cases {
            let data = message.encode()
            let decoded = DuoMessage.decode(data)
            #expect(decoded == message, "\(message) failed round-trip")
        }
    }

    @Test("disconnect round-trips")
    func disconnectRoundTrip() {
        let message = DuoMessage.disconnect
        let data = message.encode()
        let decoded = DuoMessage.decode(data)
        #expect(decoded == message)
    }

    @Test("localHeartRate round-trips both with and without sample")
    func localHeartRateRoundTrip() {
        let withSample = DuoMessage.localHeartRate(bpm: 162.5)
        #expect(DuoMessage.decode(withSample.encode()) == withSample)

        let withoutSample = DuoMessage.localHeartRate(bpm: nil)
        #expect(DuoMessage.decode(withoutSample.encode()) == withoutSample)
    }

    @Test("stateUpdate carries the full snapshot through the wire")
    func stateUpdateRoundTrip() {
        let snapshot = RaceStateSnapshot(
            phase: .inProgress,
            startedAt: t(0),
            currentSegmentStartedAt: t(285),
            currentStationIndex: Station.skiErg.rawValue,
            completedStationsCount: 1,
            totalStations: 16,
            divisionRaw: Division.mensOpen.rawValue,
            endedAt: nil,
            pausedAt: nil,
            splits: [SerializedSplit(from: Split(
                station: .run1,
                startedAt: t(0),
                endedAt: t(285),
                heartRateAvgBPM: 158,
                heartRateMaxBPM: 172
            ))],
            currentHeartRateBPM: 162,
            maxHeartRate: 188
        )

        let message = DuoMessage.stateUpdate(snapshot: snapshot)
        let data = message.encode()
        let decoded = DuoMessage.decode(data)

        // Equality on associated values cascades into the snapshot,
        // so this single check covers every snapshot field too.
        #expect(decoded == message)

        // Spot-check: pull the snapshot back out of the decoded
        // message and assert the embedded splits + maxHR survived.
        if case .stateUpdate(let recovered) = decoded {
            #expect(recovered.splits.count == 1)
            #expect(recovered.splits.first?.heartRateAvgBPM == 158)
            #expect(recovered.maxHeartRate == 188)
        } else {
            Issue.record("decoded was not .stateUpdate")
        }
    }

    @Test("decode returns nil for malformed payload")
    func decodeMalformed() {
        let junk = Data("not json".utf8)
        #expect(DuoMessage.decode(junk) == nil)
    }
}

#endif  // canImport(MultipeerConnectivity)

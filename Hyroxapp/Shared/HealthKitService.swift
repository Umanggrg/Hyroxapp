import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

// Thin wrapper over `HKHealthStore` that writes completed HYROX races as
// `HKWorkout`s so they appear in Apple Fitness / the Health app alongside
// every other workout the athlete logs.
//
// Guarded on `canImport(HealthKit)` because HealthKit is iOS / iPadOS /
// watchOS / visionOS only — a macOS build of this project skips the
// service entirely and its callers fall through without side effects.
//
// Xcode setup required for this to actually do anything:
//   1. Target → Signing & Capabilities → + Capability → HealthKit
//   2. Target → Info → add NSHealthShareUsageDescription and
//      NSHealthUpdateUsageDescription strings (iOS requires both even if
//      we only write)
// Without those two steps every call here fails silently — no crash, just
// no workout written. Callers log the error and move on.
#if canImport(HealthKit)

@MainActor
final class HealthKitService {

    // Single instance — `HKHealthStore` is cheap but allocating one per
    // call is wasteful and the permission prompt ties to the store.
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    private init() {}

    // MARK: - Availability

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    // Ask for permission to write workouts and read heart rate. Safe to
    // call repeatedly — iOS only shows the prompt once per type (and
    // bundles unseen types into a single prompt). Returns `true` if
    // we're allowed to write workouts; `false` on denial or
    // unavailability. Read permission for HR is requested at the same
    // time but the return value focuses on the primary (write)
    // contract — HR read is best-effort and the UI degrades gracefully
    // when no HR samples are available.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]

        // Read: heart rate. Declared on the same `requestAuthorization`
        // call so users see one consolidated HealthKit prompt rather
        // than two separate ones. If Apple adds more read types later
        // (active energy, VO2 max, etc.), append them here.
        var typesToRead: Set<HKObjectType> = []
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(hrType)
        }

        do {
            try await store.requestAuthorization(
                toShare: typesToShare,
                read: typesToRead
            )
        } catch {
            return false
        }

        // `authorizationStatus` for write returns `.sharingAuthorized`
        // when the user has granted access. Anything else we treat as "no".
        // Note: Apple intentionally does NOT expose read-auth status as
        // a reliable signal — even when the user grants read access, the
        // status reads `.notDetermined`. So we don't gate HR queries on
        // status; we just attempt them and handle "no samples" gracefully.
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }

    // MARK: - Heart rate stats (segment window)

    // Compute avg + max HR over an arbitrary time window. Intended
    // usage: pass `split.startedAt` and `split.endedAt` immediately
    // after a station advances, so the returned values describe the
    // HR profile during that segment specifically.
    //
    // Returns `(nil, nil)` when HealthKit is unavailable, the user
    // denied read access (queries return empty samples in that case),
    // or the Watch simply didn't record HR during that window. Callers
    // should treat all four nil-combinations as "no data" and not
    // surface a placeholder that would imply we tried but got zero.
    //
    // Uses `HKStatisticsQuery` with both `.discreteAverage` and
    // `.discreteMax` options so a single query returns both metrics —
    // no need for two round-trips to HealthKit per station advance.
    func heartRateStats(
        from start: Date,
        to end: Date
    ) async -> (avg: Double?, max: Double?) {
        guard isAvailable else { return (nil, nil) }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }
        // Defensive: a zero-length or inverted window has nothing to
        // aggregate. Return nils rather than letting HealthKit raise.
        guard end > start else { return (nil, nil) }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, stats, _ in
                let avg = stats?.averageQuantity()?.doubleValue(for: bpmUnit)
                let max = stats?.maximumQuantity()?.doubleValue(for: bpmUnit)
                continuation.resume(returning: (avg, max))
            }
            store.execute(query)
        }
    }

    // MARK: - Heart rate read

    // Fetch the most recent heart-rate sample from HealthKit, if one
    // exists within the last 60 seconds. Returns beats per minute as a
    // Double, or nil if:
    //   - HealthKit isn't available on this device
    //   - The user denied read access (query succeeds but returns no
    //     samples, Apple's way of hiding denial from the app)
    //   - No HR sample has been recorded recently (e.g. Watch isn't
    //     on wrist, or Watch isn't paired/streaming)
    //
    // Why a 60-second window: the Apple Watch samples HR roughly every
    // 5–15 seconds in ambient mode and much more often during active
    // workouts. 60s is long enough to catch at least one sample during
    // any HYROX station, but short enough that we're reporting "HR
    // now," not "HR from yesterday."
    func currentHeartRate() async -> Double? {
        guard isAvailable else { return nil }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-60),
            end: now,
            options: .strictEndDate
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierEndDate,
            ascending: false
        )

        // HKSampleQuery is callback-based; wrap in a continuation so
        // the caller can simply `await`. `withCheckedContinuation`
        // gives us runtime safety against accidentally resuming twice.
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                // HealthKit reports HR in `count/min`. Build the unit
                // explicitly so a locale / HealthKit API shift doesn't
                // silently change the interpreted value.
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let bpm = sample.quantity.doubleValue(for: bpmUnit)
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    // MARK: - Save

    // Persist a finished race as an HKWorkout. No-op if the race isn't
    // actually finished (defensive — callers shouldn't call this on an
    // in-progress race anyway).
    func saveRace(_ race: Race) async throws {
        guard isAvailable else { return }
        guard let endedAt = race.endedAt else { return }

        // Implicit authorization — first call triggers the system prompt.
        // If the user denies, `save` below will throw and we propagate.
        _ = await requestAuthorization()

        let config = HKWorkoutConfiguration()
        config.activityType = .crossTraining   // HYROX mixes cardio + functional work; `.crossTraining` is the closest stock Apple category that renders with a sensible icon in Fitness.
        config.locationType = .indoor           // Most HYROX training happens in a box. Can be made configurable later.

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: config,
            device: .local()
        )

        try await builder.beginCollection(at: race.startedAt)

        // Brand the workout so it's obvious which app wrote it. These show
        // up in the Health app's workout detail view.
        let brandedMetadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "HYROX",
            HKMetadataKeyIndoorWorkout: true
        ]
        try await builder.addMetadata(brandedMetadata)

        try await builder.endCollection(at: endedAt)
        _ = try await builder.finishWorkout()
    }
}

#endif

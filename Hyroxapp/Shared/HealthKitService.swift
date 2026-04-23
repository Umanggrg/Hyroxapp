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

    // Ask for permission to write workouts. Safe to call repeatedly — iOS
    // only shows the prompt once. Returns `true` if we're allowed to write
    // (either freshly granted or previously granted); `false` if the user
    // declined or HealthKit isn't available.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]

        do {
            try await store.requestAuthorization(toShare: typesToShare, read: [])
        } catch {
            return false
        }

        // `authorizationStatus` for write returns `.sharingAuthorized`
        // when the user has granted access. Anything else we treat as "no".
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
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

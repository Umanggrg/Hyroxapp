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

        // Read: heart rate + active energy + oxygen saturation
        // (SpO2). Declared on the same `requestAuthorization`
        // call so users see one consolidated HealthKit prompt
        // rather than separate ones for each type. If Apple
        // adds more read types later (VO2 max, distance, etc.),
        // append them here.
        var typesToRead: Set<HKObjectType> = []
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(hrType)
        }
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            typesToRead.insert(energyType)
        }
        // SpO2 — Apple Watch Series 6+. Powers §13.8 Tier 4
        // post-race anaerobic-threshold proxy ("Your SpO2
        // dropped to 92% on Wall Balls"). Series 1-5 users get
        // nil reads; the UI hides the line cleanly.
        if let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            typesToRead.insert(spo2Type)
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

    // MARK: - HR standard deviation (segment window)

    // Standard deviation of HR samples within a window. The
    // pacing-quality signal: smooth controlled effort produces
    // tightly-bunched samples (low std dev); erratic surges
    // and recoveries produce a wide spread (high std dev).
    //
    // Different from `heartRateStats(from:to:)` above which
    // returns avg + max via HKStatisticsQuery's discrete
    // aggregations. Std dev requires individual samples to
    // compute, so this uses HKSampleQuery directly.
    //
    // Returns nil when:
    //   • HealthKit unavailable / read auth denied
    //   • Fewer than 4 samples in the window (below that,
    //     std dev isn't meaningful — single high-HR sample
    //     during a recovery dominates)
    //   • Window is zero or inverted
    func heartRateStdDev(
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard isAvailable else { return nil }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }
        guard end > start else { return nil }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let samples: [Double] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let bpms = (samples as? [HKQuantitySample] ?? [])
                    .map { $0.quantity.doubleValue(for: bpmUnit) }
                continuation.resume(returning: bpms)
            }
            store.execute(query)
        }

        // 4-sample minimum — below that, std dev is single-
        // outlier-dominated and reads as noise rather than
        // signal. A 30-second sled push at 1Hz easily clears
        // this; only abnormally-short stations or sparse-data
        // situations fail.
        guard samples.count >= 4 else { return nil }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples
            .map { pow($0 - mean, 2) }
            .reduce(0, +) / Double(samples.count)
        return sqrt(variance)
    }

    // MARK: - Time in HR zones (sample-level)

    // Bucket time-in-zone over an arbitrary window by querying
    // individual HR samples and weighting each sample's
    // contribution by the gap to the next sample. Solves the
    // "zero splits, zero zone data" problem the Free Run share
    // card hits for runs that haven't crossed a split boundary
    // yet — works regardless of how the upstream model chose to
    // bucket time.
    //
    // Algorithm:
    //   • Pull every HR sample in [start, end] in chronological
    //     order.
    //   • For each sample, the time it represents = gap to the
    //     next sample, capped at 10 seconds (so a long gap from
    //     a dropped Watch connection doesn't mis-attribute lots
    //     of time to a single zone).
    //   • Classify each sample's bpm into one of Z1-Z5 against
    //     `maxBPM`, accumulate the weighted time into that
    //     bucket.
    //
    // Returns an empty dictionary when:
    //   • HealthKit unavailable / read auth denied (call returns
    //     no samples).
    //   • Window has no HR samples (no Watch on wrist, or HK
    //     hasn't received them yet).
    //   • Window is zero-length / inverted.
    func timeInZones(
        from start: Date,
        to end: Date,
        maxBPM: Int
    ) async -> [HRZone: TimeInterval] {
        guard isAvailable else { return [:] }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return [:]
        }
        guard end > start else { return [:] }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierEndDate,
            ascending: true
        )
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        // Pull every HR sample chronologically. Limit-none so
        // we get the full series even on long runs.
        let samples: [(Date, Double)] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let pairs = (samples as? [HKQuantitySample] ?? []).map {
                    ($0.endDate, $0.quantity.doubleValue(for: bpmUnit))
                }
                continuation.resume(returning: pairs)
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return [:] }

        var totals: [HRZone: TimeInterval] = [:]
        // Each sample contributes the time until the NEXT
        // sample, capped at 10s to defend against long gaps
        // (Watch dropped, briefly off-wrist, etc.). The final
        // sample weighs the gap from itself to `end`, also
        // capped — so a final-sample-then-stop case attributes
        // a few seconds to its zone instead of zero.
        let maxGap: TimeInterval = 10
        for index in samples.indices {
            let (sampleDate, bpm) = samples[index]
            let nextDate: Date = (index + 1 < samples.count)
                ? samples[index + 1].0
                : end
            let rawGap = nextDate.timeIntervalSince(sampleDate)
            let weight = max(0, min(rawGap, maxGap))
            guard weight > 0 else { continue }

            let zone = HRZone.zone(for: bpm, maxBPM: maxBPM)
            totals[zone, default: 0] += weight
        }
        return totals
    }

    // MARK: - SpO2 (segment window)

    // Lowest blood-oxygen saturation reading within a window —
    // §13.8 Tier 4 post-race anaerobic-threshold proxy.
    //
    // SpO2 normally sits 95-100% at rest. During high-intensity
    // exercise, even healthy athletes can dip into 92-94% as the
    // body's oxygen demand exceeds delivery — that's the
    // anaerobic-threshold signal. Sustained drops below 92% on
    // a specific station mean the athlete is well above their
    // aerobic threshold there.
    //
    // Returns the LOWEST sample (discreteMin) — peak oxygen
    // debt for the segment. Returns nil when:
    //   • HealthKit unavailable / read auth denied
    //   • Apple Watch model doesn't support SpO2 (Series 1-5)
    //   • No SpO2 samples in the window (the Watch samples SpO2
    //     periodically, not continuously — short stations may
    //     legitimately have no reading)
    //
    // Value comes back as a fraction (0.0-1.0); UI renders as %.
    func lowestOxygenSaturation(
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard isAvailable else { return nil }
        guard let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            return nil
        }
        guard end > start else { return nil }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: spo2Type,
                quantitySamplePredicate: predicate,
                options: .discreteMin
            ) { _, stats, _ in
                let unit = HKUnit.percent()
                let value = stats?.minimumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Active calories (segment window)

    // Sum of active energy burned during the given window, in kcal.
    // Returns nil when HealthKit isn't available, the user hasn't
    // granted read access, or no calorie samples landed in the
    // window (typical when no Watch was streaming during the race).
    //
    // `.cumulativeSum` aggregates all calorie samples in the window
    // — the Watch contributes calorie samples roughly every 10–20
    // seconds during workouts, so over a 2–5 min HYROX station you
    // typically get a meaningful sum.
    func activeCalories(
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard isAvailable else { return nil }
        guard let energyType = HKObjectType.quantityType(
            forIdentifier: .activeEnergyBurned
        ) else { return nil }
        guard end > start else { return nil }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let kcalUnit = HKUnit.kilocalorie()
                let kcal = stats?.sumQuantity()?.doubleValue(for: kcalUnit)
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
    }

    // MARK: - Point-in-time heart rate

    // Fetch the heart-rate sample closest to a specific moment in time.
    // Used by RaceViewModel to capture station-boundary HR values:
    //   • HR at the moment a station started (entry)
    //   • HR at the moment a station ended (end)
    //   • HR 30s after the station ended (recovery 30s)
    //   • HR 60s after the station ended (recovery 60s)
    //
    // Strategy: look for samples in a small window around the target
    // (±tolerance seconds), pick the one with the closest end-date.
    // If multiple samples land in the window, the closest wins; if
    // none, return nil so the caller can leave the field empty.
    //
    // tolerance defaults to 10s — wide enough to catch the Watch's
    // ~1Hz live-workout cadence reliably, narrow enough that the
    // returned value still represents "HR at that moment" rather
    // than a far-flung average.
    //
    // Returns nil when HealthKit is unavailable, no samples are in
    // the window, or read access was denied.
    func heartRate(
        at target: Date,
        tolerance: TimeInterval = 10
    ) async -> Double? {
        guard isAvailable else { return nil }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: target.addingTimeInterval(-tolerance),
            end: target.addingTimeInterval(tolerance),
            options: []
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Pick the sample with end-date closest to the target.
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let closest = samples.min { lhs, rhs in
                    abs(lhs.endDate.timeIntervalSince(target)) <
                    abs(rhs.endDate.timeIntervalSince(target))
                }
                let bpm = closest?.quantity.doubleValue(for: bpmUnit)
                continuation.resume(returning: bpm)
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
        await currentHeartRateWithSource()?.bpm
    }

    /// Same query as `currentHeartRate()` but also returns the
    /// sample's source name — drives the §19 HR source attribution
    /// (Apple Watch vs AirPods Pro 3 vs iPhone) without callers
    /// having to issue their own query. Tuple is nil when no
    /// recent sample exists, otherwise both fields are populated.
    func currentHeartRateWithSource() async -> (bpm: Double, sourceName: String)? {
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
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let bpm = sample.quantity.doubleValue(for: bpmUnit)
                // Source name comes from the writing app/device's
                // bundle display name. For Watch HR it's "Apple
                // Watch" (or the user's customized device name);
                // for AirPods Pro 3 it's "AirPods Pro 3" per
                // Apple's docs. SensorSourceRegistry.HRSource.classify
                // handles the substring matching.
                let sourceName = sample.sourceRevision.source.name
                continuation.resume(returning: (bpm, sourceName))
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

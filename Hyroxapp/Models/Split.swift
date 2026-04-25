import Foundation

// A single completed segment of a race.
//
// Every split carries its own start and end timestamps. Duration is computed
// from those — never accumulated tick-by-tick from a timer — so it's accurate
// regardless of UI refresh rate, backgrounding, or device sleep.
//
// Heart-rate fields capture what HealthKit knew about the athlete during
// the segment's time window:
//   - `heartRateAvgBPM` — HKStatisticsQuery `.discreteAverage` over
//     [startedAt, endedAt]. Best single-number summary of intensity.
//   - `heartRateMaxBPM` — `.discreteMax` over the same window. Useful
//     for spotting peak strain (e.g. last 30s of wall balls).
// Both are optional because HR may be unavailable (no Watch on wrist,
// read auth denied, no samples in window). The UI omits the display
// gracefully when both are nil.
//
// Backward-compat note: earlier builds stored a single `heartRateBPM`
// field (a snapshot at advance time, not a segment average). The
// `CodingKeys` below map that legacy key into the new `heartRateAvgBPM`
// field so old persisted races decode without data loss. The semantic
// difference is small — at typical sampling rates the snapshot
// approximates the segment average — so reading it as "avg" is fine.
struct Split: Codable, Equatable, Hashable, Identifiable, Sendable {
    let station: Station
    let startedAt: Date
    let endedAt: Date
    let heartRateAvgBPM: Double?
    let heartRateMaxBPM: Double?
    // Active calories burned during this segment, queried from
    // HealthKit's `.activeEnergyBurned` cumulative sum over the
    // segment window. Optional for the same reasons HR is optional:
    // no Watch on wrist, read auth denied, no samples, or the split
    // was persisted before this field existed (Codable handles
    // missing key gracefully).
    let activeCaloriesKcal: Double?

    // HYROX-specific manual-entry stats. The killer feature
    // every other HYROX app misses: a sled push at 80kg and a
    // sled push at 152kg are different universes; without
    // weight tracking, "PB" comparisons across attempts are
    // meaningless. Same logic for sandbag, farmers, wall ball.
    // Runs and ergs (ski/row) leave this nil — there's no
    // weight, just the work itself.
    //
    // All three fields are optional so the legacy "tap through
    // the race timer, don't enter anything" flow keeps working
    // unchanged. Athletes who care about progression edit
    // these post-race via the StationStatsSheet; athletes who
    // don't, leave them empty.
    //
    // weightKg — the actual weight used at this station, in kg.
    //   Nil means "not logged" (or N/A for run / erg stations).
    // repsCompleted — actual reps performed. Useful for partial
    //   completions ("could only do 80 wall balls") and for
    //   stations with rep-target variability across divisions.
    // rpe — Rate of Perceived Exertion 1–10. Subjective effort
    //   score; pairs with HR data to give "did I work harder
    //   than I usually do at this HR?" insight.
    let weightKg: Double?
    let repsCompleted: Int?
    let rpe: Int?

    // Roxzone — the transition time (in seconds) BEFORE this
    // segment's work began. The HYROX-specific metric for
    // transition discipline: how long did you spend walking from
    // the run finish line to the sled, picking up gear, getting
    // set up, vs. actually doing the work.
    //
    // Attached to the segment the athlete transitioned INTO
    // (so Sled Push's roxzoneSeconds is the time between Run 1
    // finishing and Sled Push starting). Optional because:
    //   • Run 1 has no preceding segment (no roxzone)
    //   • Roxzone tracking is opt-in via UserProfile —
    //     un-tracked races have nil here
    //   • Pre-roxzone-shipping races decode cleanly with nil
    let roxzoneSeconds: TimeInterval?

    // `Station.rawValue` is stable and unique within a race, so it doubles as
    // the Identifiable id — no extra UUID needed.
    var id: Int { station.rawValue }

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    // Codable keys. The `heartRateAvgBPM` key maps to the JSON key
    // "heartRateBPM" so old persisted splits (before max was added)
    // decode cleanly — their single HR value flows into the avg slot.
    // New encodes also write to "heartRateBPM" (not "heartRateAvgBPM")
    // so writers and readers stay symmetric across versions.
    enum CodingKeys: String, CodingKey {
        case station
        case startedAt
        case endedAt
        case heartRateAvgBPM = "heartRateBPM"
        case heartRateMaxBPM
        case activeCaloriesKcal
        case weightKg
        case repsCompleted
        case rpe
        case roxzoneSeconds
    }

    // Convenience initializer preserving the pre-HR API so all existing
    // call sites (engine, tests) keep working unchanged.
    init(
        station: Station,
        startedAt: Date,
        endedAt: Date,
        heartRateAvgBPM: Double? = nil,
        heartRateMaxBPM: Double? = nil,
        activeCaloriesKcal: Double? = nil,
        weightKg: Double? = nil,
        repsCompleted: Int? = nil,
        rpe: Int? = nil,
        roxzoneSeconds: TimeInterval? = nil
    ) {
        self.station = station
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.heartRateAvgBPM = heartRateAvgBPM
        self.heartRateMaxBPM = heartRateMaxBPM
        self.activeCaloriesKcal = activeCaloriesKcal
        self.weightKg = weightKg
        self.repsCompleted = repsCompleted
        self.rpe = rpe
        self.roxzoneSeconds = roxzoneSeconds
    }

    // Return a new Split with the given HR + calorie statistics
    // attached. Used after a successful HealthKit query batch to
    // patch the just-completed split with all the segment-window
    // metrics that are HR/HK-derived. Manual-entry fields
    // (weight/reps/RPE) are preserved as-is.
    func withSegmentStats(
        heartRateAvg: Double?,
        heartRateMax: Double?,
        activeCalories: Double?
    ) -> Split {
        Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvg,
            heartRateMaxBPM: heartRateMax,
            activeCaloriesKcal: activeCalories,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: roxzoneSeconds
        )
    }

    // Return a new Split with manual-entry station stats (weight,
    // reps, RPE) replaced. Mirror of withSegmentStats but for the
    // user-driven fields. Each parameter is independently
    // settable — passing nil clears that field, omitting the
    // parameter (it has a default that preserves the current
    // value) leaves it unchanged. The double-optional dance
    // (`Optional<Double>?`) lets callers distinguish "explicitly
    // clear" from "leave unchanged."
    func withStationStats(
        weightKg newWeight: Double?? = nil,
        repsCompleted newReps: Int?? = nil,
        rpe newRPE: Int?? = nil
    ) -> Split {
        Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: newWeight ?? weightKg,
            repsCompleted: newReps ?? repsCompleted,
            rpe: newRPE ?? rpe,
            roxzoneSeconds: roxzoneSeconds
        )
    }

    // Builder for the engine's roxzone-close path. Sets the
    // transition time spent before this segment's work began.
    // Other fields preserved.
    func withRoxzone(seconds: TimeInterval) -> Split {
        Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: seconds
        )
    }
}

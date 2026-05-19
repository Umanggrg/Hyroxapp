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

    // Station-boundary HR samples. Where avg/max characterize the
    // segment as a whole, these characterize the *transitions* —
    // the HYROX-specific signal that a sled push was easier than
    // the previous run was hard, or that you started a station
    // already redlined.
    //
    //   • heartRateEntryBPM — HR at (or closest to) startedAt.
    //     "How fatigued were you when you began this station?"
    //   • heartRateEndBPM — HR at (or closest to) endedAt.
    //     "Where did your HR end up by the time you finished?"
    //   • heartRateRecovery30sBPM — HR sample 30s after endedAt.
    //   • heartRateRecovery60sBPM — HR sample 60s after endedAt.
    //     "How fast did your HR drop in the transition?"
    //
    // Recovery samples are captured by a delayed Task that fires
    // 70s after segment end (60s + 10s buffer for HealthKit to
    // catch up). All four are optional because:
    //   1. The race may have ended before the recovery window
    //      elapsed (final station has no follow-up segment;
    //      recovery samples still meaningful as cooldown HR).
    //   2. The user backgrounded / killed the app during the
    //      recovery window, cancelling the delayed Task.
    //   3. Older races persisted before these fields existed —
    //      Codable decodes missing keys as nil, so old races
    //      simply don't carry this data.
    let heartRateEntryBPM: Double?
    let heartRateEndBPM: Double?
    let heartRateRecovery30sBPM: Double?
    let heartRateRecovery60sBPM: Double?

    // Standard deviation of HR samples within the segment window
    // (bpm). Pacing-quality signal: a smooth, controlled effort
    // produces tightly-bunched HR samples (low std dev); erratic
    // surges + recoveries produce a wide spread (high std dev).
    //
    // Useful coaching read at the per-station level — a sled push
    // with high std dev means the athlete was stop-and-go rather
    // than maintaining tension. A run with high std dev means
    // pace surged + collapsed rather than holding steady.
    //
    // Optional because:
    //   • Older races persisted before this field existed
    //   • HealthKit may not have enough samples in the window to
    //     compute meaningful std dev (need 4+ samples)
    //   • No HR data captured at all
    let heartRateStdDevBPM: Double?

    // Lowest blood-oxygen saturation reading during the segment
    // window — §13.8 Tier 4 post-race anaerobic-threshold proxy.
    // Stored as a fraction (0.0-1.0); rendered as %. SpO2 95-100%
    // = aerobic, 92-94% = approaching anaerobic threshold, <92%
    // = anaerobic.
    //
    // Optional because:
    //   • Older races persisted before this field existed
    //   • Apple Watch Series 1-5 doesn't have SpO2 hardware
    //   • Watch samples SpO2 periodically, not continuously —
    //     short stations may have no sample in the window
    let lowestSpO2: Double?

    // Active calories burned during this segment, queried from
    // HealthKit's `.activeEnergyBurned` cumulative sum over the
    // segment window. Optional for the same reasons HR is optional:
    // no Watch on wrist, read auth denied, no samples, or the split
    // was persisted before this field existed (Codable handles
    // missing key gracefully).
    let activeCaloriesKcal: Double?

    // §19 Phase 10I — average vertical oscillation (cm/step)
    // captured during this segment, derived from AirPods Pro
    // 1+ head motion via HeadphoneMotionService. Running-
    // economy metric: lower = more efficient (elite ~6-8cm,
    // recreational 10-14cm). Only meaningful on run-kind
    // splits — workout-kind splits leave this nil because
    // the head motion during sled push / wall balls /
    // burpees has no cadence structure to derive osc from.
    //
    // Optional because:
    //   • AirPods Pro 1+ / 4 / Max not in route (most users)
    //   • Workout-kind split — N/A
    //   • Older races persisted before this field existed
    //     (Codable lightweight migration → nil)
    //
    // Marked `var` (vs the surrounding `let`) so RaceViewModel
    // can stamp it on segment advance without threading a new
    // parameter through every Split builder (withSegmentStats,
    // withRecoveryStats, withStationStats, withRoxzone). Single
    // mutation point keeps the diff small; future v2 could
    // formalize via a withRunningEconomy builder.
    var verticalOscCmAvg: Double? = nil

    // §19.4 Phase 10K — ground contact time, milliseconds.
    // Average per-step duration the foot is in contact with
    // the ground during this run segment. Elite distance
    // runners run 180-220ms; recreational 250-300ms+. Lower =
    // more efficient (less braking on each step, better
    // elastic-recoil energy return).
    //
    // Derived from AirPods head motion: in each step cycle,
    // GCT is the time from the negative Z-axis trough (head
    // dips on impact) to the moment vertical acceleration
    // returns to neutral (flight phase begins). Head motion
    // is a noisier approximation than a foot pod, but it's
    // free (no extra hardware) and trends across races stay
    // meaningful even if the absolute number differs from
    // dedicated kit by ±20-40ms.
    //
    // Gated on the same `airPodsRunningEconomyEnabled`
    // Settings toggle as vertical oscillation. Off → field
    // stays nil; RunningEconomySection on RaceDetail omits
    // the GCT row.
    var groundContactTimeMsAvg: Double? = nil

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

    // §47a — per-rep timestamps captured by the Watch's
    // WatchRepCountingService, encoded as TimeInterval offsets
    // from `startedAt` for compact storage. Powers the stroke-
    // rate curve, DPS computation, and pacing-consistency
    // analytics on the erg detail surface — analytics the
    // running-total `repsCompleted` count alone can't drive.
    //
    // Shape: array of offsets in seconds from startedAt, in
    // ascending order. `repTimestampOffsets[0]` is the time of
    // the first stroke; `repTimestampOffsets.last!` is the
    // time of the final stroke (always <= duration). Array
    // length equals `repsCompleted` for splits where both are
    // populated.
    //
    // Optional because:
    //   • Wall-ball / lunge / burpee splits captured before
    //     §47a shipped don't carry timestamps (only running
    //     count was published).
    //   • Manual-only rep entry via StationStatsSheet doesn't
    //     produce per-rep timing — only the total.
    //   • Race-shipped without a Watch, or Watch hardware
    //     without IMU rep counting support → no timestamps.
    //
    // Marked `var` (vs the surrounding `let`) so RaceViewModel
    // can stamp it on segment advance without threading a new
    // parameter through every Split builder — same single-
    // mutation-point pattern as `verticalOscCmAvg` and
    // `groundContactTimeMsAvg`.
    var repTimestampOffsets: [TimeInterval]? = nil

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
        case heartRateEntryBPM
        case heartRateEndBPM
        case heartRateRecovery30sBPM
        case heartRateRecovery60sBPM
        case heartRateStdDevBPM
        case lowestSpO2
        case activeCaloriesKcal
        case weightKg
        case repsCompleted
        case rpe
        case roxzoneSeconds
        // §19 Phase 10I — added late in the schema lifecycle.
        // Default-nil declaration means old payloads decode
        // cleanly via Codable synthesizer's decodeIfPresent
        // path; new payloads include the key.
        case verticalOscCmAvg
        // §19.4 Phase 10K — same additive-Codable pattern as
        // verticalOscCmAvg above. Pre-existing splits decode
        // as nil; new ones serialize the field.
        case groundContactTimeMsAvg
        // §47a — per-stroke / per-rep timestamps as offsets
        // from startedAt. Same additive-Codable pattern.
        case repTimestampOffsets
    }

    // Convenience initializer preserving the pre-HR API so all existing
    // call sites (engine, tests) keep working unchanged. The new
    // boundary-HR fields all default to nil so existing call sites
    // that don't know about them stay source-compatible.
    init(
        station: Station,
        startedAt: Date,
        endedAt: Date,
        heartRateAvgBPM: Double? = nil,
        heartRateMaxBPM: Double? = nil,
        heartRateEntryBPM: Double? = nil,
        heartRateEndBPM: Double? = nil,
        heartRateRecovery30sBPM: Double? = nil,
        heartRateRecovery60sBPM: Double? = nil,
        heartRateStdDevBPM: Double? = nil,
        lowestSpO2: Double? = nil,
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
        self.heartRateEntryBPM = heartRateEntryBPM
        self.heartRateEndBPM = heartRateEndBPM
        self.heartRateRecovery30sBPM = heartRateRecovery30sBPM
        self.heartRateRecovery60sBPM = heartRateRecovery60sBPM
        self.heartRateStdDevBPM = heartRateStdDevBPM
        self.lowestSpO2 = lowestSpO2
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
    //
    // Entry/end HR are optional because they may not be available
    // even when avg/max are: HealthKit might have samples in the
    // segment window for aggregation but no sample at the exact
    // start or end timestamp.
    func withSegmentStats(
        heartRateAvg: Double?,
        heartRateMax: Double?,
        heartRateEntry: Double? = nil,
        heartRateEnd: Double? = nil,
        heartRateStdDev: Double? = nil,
        lowestSpO2: Double? = nil,
        activeCalories: Double?
    ) -> Split {
        // `var` (vs let) because Split is a value type — we
        // need a mutable local copy to set `verticalOscCmAvg`
        // (§19 10I) after init since the struct's init
        // doesn't take that field as a parameter.
        var newSplit = Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvg,
            heartRateMaxBPM: heartRateMax,
            heartRateEntryBPM: heartRateEntry,
            heartRateEndBPM: heartRateEnd,
            heartRateRecovery30sBPM: heartRateRecovery30sBPM,
            heartRateRecovery60sBPM: heartRateRecovery60sBPM,
            heartRateStdDevBPM: heartRateStdDev,
            lowestSpO2: lowestSpO2,
            activeCaloriesKcal: activeCalories,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: roxzoneSeconds
        )
        // §19 Phase 10I — preserve the existing osc value
        // through HK-stats patches. Split's init doesn't take
        // verticalOscCmAvg (single mutation point); the
        // builders restore it after init so HR-stats updates
        // don't wipe the running-economy reading.
        newSplit.verticalOscCmAvg = verticalOscCmAvg
        newSplit.groundContactTimeMsAvg = groundContactTimeMsAvg
        // §47a — preserve per-stroke timestamps through every
        // HR/recovery/station-stats/roxzone patch. Splits go
        // through multiple builder hops post-race (HK rehydrate,
        // delayed recovery samples, etc.); the timestamps only
        // ever land via the dedicated Watch-rep batch path so
        // every other builder must read-through to avoid wiping.
        newSplit.repTimestampOffsets = repTimestampOffsets
        return newSplit
    }

    // Return a new Split patched with post-segment recovery HR
    // samples. Called by the delayed Task that fires ~70s after a
    // segment ends so HealthKit has had time to receive +30s and
    // +60s samples from the Watch's live workout builder.
    //
    // Preserves all other fields including the segment-window
    // stats already attached by withSegmentStats. Either / both
    // recovery values may be nil if HealthKit had no sample close
    // to the target time (Watch out of range, app killed, etc).
    func withRecoveryStats(
        heartRateRecovery30s: Double?,
        heartRateRecovery60s: Double?
    ) -> Split {
        var newSplit = Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            heartRateEntryBPM: heartRateEntryBPM,
            heartRateEndBPM: heartRateEndBPM,
            heartRateRecovery30sBPM: heartRateRecovery30s,
            heartRateRecovery60sBPM: heartRateRecovery60s,
            heartRateStdDevBPM: heartRateStdDevBPM,
            lowestSpO2: lowestSpO2,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: roxzoneSeconds
        )
        newSplit.verticalOscCmAvg = verticalOscCmAvg
        newSplit.groundContactTimeMsAvg = groundContactTimeMsAvg
        // §47a — preserve per-stroke timestamps through every
        // HR/recovery/station-stats/roxzone patch. Splits go
        // through multiple builder hops post-race (HK rehydrate,
        // delayed recovery samples, etc.); the timestamps only
        // ever land via the dedicated Watch-rep batch path so
        // every other builder must read-through to avoid wiping.
        newSplit.repTimestampOffsets = repTimestampOffsets
        return newSplit
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
        var newSplit = Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            heartRateEntryBPM: heartRateEntryBPM,
            heartRateEndBPM: heartRateEndBPM,
            heartRateRecovery30sBPM: heartRateRecovery30sBPM,
            heartRateRecovery60sBPM: heartRateRecovery60sBPM,
            heartRateStdDevBPM: heartRateStdDevBPM,
            lowestSpO2: lowestSpO2,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: newWeight ?? weightKg,
            repsCompleted: newReps ?? repsCompleted,
            rpe: newRPE ?? rpe,
            roxzoneSeconds: roxzoneSeconds
        )
        newSplit.verticalOscCmAvg = verticalOscCmAvg
        newSplit.groundContactTimeMsAvg = groundContactTimeMsAvg
        // §47a — preserve per-stroke timestamps through every
        // HR/recovery/station-stats/roxzone patch. Splits go
        // through multiple builder hops post-race (HK rehydrate,
        // delayed recovery samples, etc.); the timestamps only
        // ever land via the dedicated Watch-rep batch path so
        // every other builder must read-through to avoid wiping.
        newSplit.repTimestampOffsets = repTimestampOffsets
        return newSplit
    }

    // §47a — Builder for the rep-timestamps stamp path. Sets the
    // per-rep offset array on a just-closed split; called by
    // RaceViewModel.ingestRepTimestamps when a Watch end-of-segment
    // batch arrives. Other fields preserved. Pass nil to clear.
    func withRepTimestamps(_ offsets: [TimeInterval]?) -> Split {
        var newSplit = Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            heartRateEntryBPM: heartRateEntryBPM,
            heartRateEndBPM: heartRateEndBPM,
            heartRateRecovery30sBPM: heartRateRecovery30sBPM,
            heartRateRecovery60sBPM: heartRateRecovery60sBPM,
            heartRateStdDevBPM: heartRateStdDevBPM,
            lowestSpO2: lowestSpO2,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: roxzoneSeconds
        )
        newSplit.verticalOscCmAvg = verticalOscCmAvg
        newSplit.groundContactTimeMsAvg = groundContactTimeMsAvg
        newSplit.repTimestampOffsets = offsets
        return newSplit
    }

    // Builder for the engine's roxzone-close path. Sets the
    // transition time spent before this segment's work began.
    // Other fields preserved.
    func withRoxzone(seconds: TimeInterval) -> Split {
        var newSplit = Split(
            station: station,
            startedAt: startedAt,
            endedAt: endedAt,
            heartRateAvgBPM: heartRateAvgBPM,
            heartRateMaxBPM: heartRateMaxBPM,
            heartRateEntryBPM: heartRateEntryBPM,
            heartRateEndBPM: heartRateEndBPM,
            heartRateRecovery30sBPM: heartRateRecovery30sBPM,
            heartRateRecovery60sBPM: heartRateRecovery60sBPM,
            heartRateStdDevBPM: heartRateStdDevBPM,
            lowestSpO2: lowestSpO2,
            activeCaloriesKcal: activeCaloriesKcal,
            weightKg: weightKg,
            repsCompleted: repsCompleted,
            rpe: rpe,
            roxzoneSeconds: seconds
        )
        newSplit.verticalOscCmAvg = verticalOscCmAvg
        newSplit.groundContactTimeMsAvg = groundContactTimeMsAvg
        // §47a — preserve per-stroke timestamps through every
        // HR/recovery/station-stats/roxzone patch. Splits go
        // through multiple builder hops post-race (HK rehydrate,
        // delayed recovery samples, etc.); the timestamps only
        // ever land via the dedicated Watch-rep batch path so
        // every other builder must read-through to avoid wiping.
        newSplit.repTimestampOffsets = repTimestampOffsets
        return newSplit
    }
}

import Foundation
import SwiftData

// A single free-run session — running for distance + time, untied to
// the HYROX format. Companion to `Race` (the 16-station HYROX race
// flow); the two coexist as separate surfaces and share none of their
// analytics machinery (HYROX score, station signature, fatigue cliff,
// etc. are all race-shaped concepts that don't apply here).
//
// Two location modes:
//   • `.indoor`  — pedometer-only distance via CMPedometer / the
//                  Watch's HKLiveWorkoutBuilder with .indoor activity.
//                  No GPS, no permission prompt, no battery hit.
//   • `.outdoor` — pedometer + GPS via CLLocationManager + the Watch's
//                  HKLiveWorkoutBuilder with .outdoor activity. The GPS
//                  route is recorded into the HKWorkoutRouteBuilder so
//                  Apple Health stores the polyline; we deliberately
//                  do NOT render it in-app (CLAUDE.md §1 — Free Run
//                  intentionally has no map).
//
// Splits auto-fire every km or every mile depending on the user's
// `splitUnit` choice on the start sheet. Each split records its
// duration, the cumulative distance at the split moment, and HR
// stats over the split's window — same shape as `Split` for HYROX
// races, just at distance-based boundaries instead of station
// boundaries.
//
// Persisted via SwiftData same as `Race`. Lives in the same model
// container; the History feed will mix Race rows and FreeRun rows
// chronologically with a per-row card style + filter chips (Phase 4
// of the Free Run roadmap).
//
// Forward-compat for cloud sync: stable UUID, additive-only field
// changes, optional fields default-nil, raw String storage for any
// enum-shaped attribute (matches the `Division` / `ThemePreference`
// pattern that's already proven safe across SwiftData lightweight
// migrations).
@Model
final class FreeRun {

    // Stable identity for resume-by-id and future cloud-sync pairing.
    var id: UUID

    // Timer anchors. `endedAt` nil while the run is in progress.
    var startedAt: Date
    var endedAt: Date?

    // Pause moment; nil unless currently paused. Same persistence
    // semantics as `Race.pausedAt` — survives backgrounding /
    // force-kill so the resume math works on relaunch.
    var pausedAt: Date?

    // Total distance accumulated so far, in metres. Canonical unit
    // is metres regardless of the user's `splitUnit` preference —
    // we convert at the display layer. Updated continuously during
    // the run from the HKLiveWorkoutBuilder's running-distance
    // statistics (Watch) or CMPedometer (iPhone fallback).
    var distanceMetres: Double = 0

    // Indoor vs outdoor — picked on the start sheet, fixed for
    // the duration of the run. Stored as raw String so SwiftData's
    // lightweight migration stays additive-safe (the Division /
    // ThemePreference pattern).
    var locationTypeRaw: String

    // Mile or km — picked on the start sheet (per the user's
    // requested behavior). Drives how often a split auto-fires
    // and what unit the live UI + summary render in. Stored raw
    // for the same migration-safety reason.
    var splitUnitRaw: String

    // Auto-split rows. Captured by `FreeRunEngine` whenever the
    // accumulated distance crosses a split boundary (every 1 mi
    // or 1 km depending on `splitUnit`). The active split is the
    // segment from the LAST entry's distance up to the current
    // running distance — never persisted as a "partial" entry;
    // an in-progress split simply isn't in this array yet.
    //
    // Stored as `[FreeRunSplit]` (Codable struct, same pattern as
    // `Race.splits`). SwiftData encodes it transparently.
    var splits: [FreeRunSplit] = []

    // Race-wide HR aggregates, populated post-finish from
    // HealthKit. Same nil-when-no-data semantic as `Split.heartRateAvgBPM`
    // — UI hides the line when both are nil.
    var heartRateAvgBPM: Double?
    var heartRateMaxBPM: Double?

    // Active calories burned, kcal. Optional like the HR fields.
    var activeCaloriesKcal: Double?

    // Optional human-given title. Same pattern as `Race.name` —
    // empty default, falls back to the auto date stamp at every
    // display site.
    var name: String = ""

    // Free-form athlete notes — "easy 30, felt great" or "first
    // run after the calf strain." Editable from the summary +
    // detail screens. Same additive-default pattern as
    // `Race.notes`.
    var notes: String = ""

    // Optional photo attached to the run — post-run scenery,
    // sweaty selfie, gym mirror. Same compressed-JPEG storage as
    // `Race.photoData` and `UserProfile.avatarData`. External
    // storage attribute means SwiftData stores the bytes outside
    // the SQLite row to keep query performance up.
    @Attribute(.externalStorage) var photoData: Data?

    // Privacy gate — mirrors `Race.isPrivate`. When the social
    // feed lights up in v2, private free runs stay out of any
    // cross-athlete surfaces. Local History + Profile aggregates
    // always include them.
    var isPrivate: Bool = false

    // Sort key for History. Set once at insertion so a paused-
    // and-resumed run keeps its chronological slot.
    var createdAt: Date

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        pausedAt: Date? = nil,
        distanceMetres: Double = 0,
        locationType: FreeRunLocationType,
        splitUnit: FreeRunSplitUnit,
        splits: [FreeRunSplit] = [],
        heartRateAvgBPM: Double? = nil,
        heartRateMaxBPM: Double? = nil,
        activeCaloriesKcal: Double? = nil,
        name: String = "",
        notes: String = "",
        photoData: Data? = nil,
        isPrivate: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.distanceMetres = distanceMetres
        self.locationTypeRaw = locationType.rawValue
        self.splitUnitRaw = splitUnit.rawValue
        self.splits = splits
        self.heartRateAvgBPM = heartRateAvgBPM
        self.heartRateMaxBPM = heartRateMaxBPM
        self.activeCaloriesKcal = activeCaloriesKcal
        self.name = name
        self.notes = notes
        self.photoData = photoData
        self.isPrivate = isPrivate
        self.createdAt = createdAt
    }

    // MARK: - Derived

    // Non-optional accessor with safe fallback. SwiftData migrations
    // can leave raw string fields stale; falling back to `.indoor`
    // ensures the rest of the app never sees a nil location mode.
    var locationType: FreeRunLocationType {
        FreeRunLocationType(rawValue: locationTypeRaw) ?? .indoor
    }

    var splitUnit: FreeRunSplitUnit {
        FreeRunSplitUnit(rawValue: splitUnitRaw) ?? .mile
    }

    // True once `endedAt` has been written — used by History +
    // resume logic to distinguish a finished run from one the
    // athlete force-killed mid-session.
    var isFinished: Bool { endedAt != nil }

    // Total elapsed time, in seconds. For an in-progress run,
    // this is "now − startedAt" (computed at the display site, not
    // here, so it ticks). For a finished run, it's the static
    // delta between start and end timestamps.
    var totalDuration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

// Where the run takes place. Drives:
//   • CMPedometer vs CLLocationManager+CMPedometer for distance
//   • HKWorkoutConfiguration.locationType (.indoor / .outdoor)
//   • Whether to attach a HKWorkoutRouteBuilder to the workout
//   • UI affordance on the start sheet (the indoor card has no
//     "Track route" toggle; the outdoor card does)
//
// Stored on FreeRun as raw String for SwiftData migration safety.
// `String` raw values are explicit so we can later add cases
// (e.g. `.treadmillCalibrated`) without reshuffling integer
// indices and breaking persisted rows.
enum FreeRunLocationType: String, CaseIterable, Identifiable, Sendable {
    case indoor
    case outdoor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indoor:  return "Indoor"
        case .outdoor: return "Outdoor"
        }
    }

    // SF Symbol matching the start sheet card hero. Indoor reads
    // as "treadmill / track" — Apple's `figure.indoor.cycle`
    // family is the closest non-cycle indoor exercise glyph.
    // Outdoor uses the universal running figure.
    var iconName: String {
        switch self {
        case .indoor:  return "figure.run.treadmill"
        case .outdoor: return "figure.run"
        }
    }

    // Short subtitle for the start-sheet card. Sets expectations:
    // indoor needs no permissions, outdoor needs GPS auth.
    var subtitle: String {
        switch self {
        case .indoor:  return "Pedometer only · no GPS"
        case .outdoor: return "GPS + pedometer · auth needed"
        }
    }
}

// Mile or km — splits + the live distance display unit. Picked
// on the start sheet and frozen for the run's lifetime so a
// half-finished run doesn't switch units mid-stride. Future:
// add a per-user default in Settings so repeat athletes don't
// reselect every time.
enum FreeRunSplitUnit: String, CaseIterable, Identifiable, Sendable {
    case mile
    case km

    var id: String { rawValue }

    // Conversion constant — metres per unit. The model stores
    // distance in metres canonically; this value lets the UI
    // convert at render time without any model-level knowledge
    // of the user's preference.
    var metresPerUnit: Double {
        switch self {
        case .mile: return 1609.344
        case .km:   return 1000
        }
    }

    var displayName: String {
        switch self {
        case .mile: return "Miles"
        case .km:   return "Kilometres"
        }
    }

    // Short suffix for HUD-style displays — "5.2 mi" / "8.4 km".
    var shortLabel: String {
        switch self {
        case .mile: return "mi"
        case .km:   return "km"
        }
    }

    // What a single split is called in narration ("Split 3 of 5",
    // "Mile 2 done"). Singular form because mid-run UI usually
    // talks about ONE split at a time.
    var singularSplitNoun: String {
        switch self {
        case .mile: return "mile"
        case .km:   return "km"
        }
    }
}

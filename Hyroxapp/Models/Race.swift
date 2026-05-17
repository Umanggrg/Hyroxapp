import Foundation
import SwiftData

// A HYROX race — either in-progress (`endedAt == nil`) or finished.
//
// Persisted via SwiftData so:
//   1. Completed races populate History.
//   2. An in-progress race survives app backgrounding and force-kill; on next
//      launch we find the unfinished `Race` and offer to resume from it.
//
// `splits` is stored as an array of the existing `Split` value struct.
// SwiftData transparently encodes `Codable` composite types as attributes,
// which keeps v0.1 simple (single table, no relationships). If v1 needs to
// query individual splits for leaderboards (e.g. "fastest wall ball ever"),
// we can promote `Split` to its own `@Model` class then.
@Model
final class Race {

    // Stable identity — useful for resume-by-id and future cloud-sync pairing.
    var id: UUID

    // When the timer began ticking. All elapsed calculations derive from this.
    var startedAt: Date

    // When the final segment was completed. `nil` while the race is in progress.
    var endedAt: Date?

    // Completed splits, in race order. Appended as the athlete advances.
    var splits: [Split]

    // When the current (not-yet-completed) segment began. `nil` once finished.
    var currentSegmentStartedAt: Date?

    // The station sequence this race is following, as raw values. We store it
    // (rather than recomputing from `Station.raceSequence`) so future variants
    // — truncated practice runs, Doubles, etc. — coexist in History without
    // conflating them with full official races.
    var sequenceRaw: [Int]

    // "solo" or "duo" — stored as raw string to avoid SwiftData enum-attribute
    // quirks. Expose the typed value through the `mode` computed property.
    var modeRawValue: String

    // Sort key for History. Set once at insertion, so a paused-and-resumed
    // race keeps its original chronological slot in the list.
    var createdAt: Date

    // Free-form athlete notes — "how did this feel?", what to remember,
    // what to try next time. Editable from `RaceSummaryView` immediately
    // after finishing and from `RaceDetailView` retroactively. Empty
    // string default keeps SwiftData's lightweight migration happy for
    // pre-existing rows: adding a String with a default value is a
    // safe additive schema change (unlike the division-enum case which
    // had to go optional).
    var notes: String = ""

    // Athlete's finish-time goal for this race, set at start time
    // ("I want to beat 1:30:00 today"). Optional because setting a
    // target is opt-in — some training days are just "show up and
    // move," not goal-chasing. Displayed as a subtitle under the
    // in-race timer and on the summary / detail views as a delta
    // ("+5:23 over target" / "1:15 ahead of target").
    //
    // Stored on Race (not UserProfile) because the goal is per-race:
    // the athlete might aim for 1:30 on one day and a relaxed 1:45
    // on another. Profile-level default is a future enhancement.
    var targetDuration: TimeInterval?

    // Optional human-given title for the race ("Tuesday morning race",
    // "First sub-1:30 attempt", "Brick session with Praanshu"). Empty
    // string falls back to the auto-generated date heading at every
    // display site, so untitled races still render fine. Foreshadows
    // the social feed where titles are how Strava activities get
    // character. Same SwiftData additive-schema-safe pattern as
    // `notes` — empty default lets pre-existing rows migrate cleanly.
    var name: String = ""

    // Set to the moment of pause when the race is paused, nil
    // otherwise. Persisting the pause time means a paused race
    // survives backgrounding / force-kill: on relaunch we read
    // `engineState` and bring the engine back as `.paused`, ready
    // to be resumed by the athlete with the original elapsed-time
    // math intact. Same SwiftData additive-default pattern as
    // `notes` / `name`; pre-existing rows decode cleanly with nil.
    var pausedAt: Date?

    // Optional photo attached to this race — gym selfie, workout
    // shot, post-race PR snap. Stored as compressed JPEG bytes
    // (~0.7 quality on save) the same way UserProfile stores
    // avatars, so the whole race travels with its photo as one
    // unit through SwiftData (and later cloud sync). When present,
    // the photo becomes the hero banner on RaceCardView and the
    // shareable race card — the most direct foreshadow of the
    // social feed where photos drive engagement.
    //
    // Migration-safe nil default — pre-existing race rows decode
    // cleanly without a photo, same as `notes` / `name`.
    @Attribute(.externalStorage) var photoData: Data?

    // §37 Whoop pattern 6 — pre-race journal fields. Athletes
    // tap through a 3-question sheet before the race starts:
    // sleep last night, stress this week, anything sore.
    // Captured here so post-race + cross-race analytics can
    // surface patterns like "your back-half pace drops 14% on
    // poor-sleep weeks" or "races logged with high stress show
    // 9% slower transitions." All three fields are optional —
    // the journal sheet is skippable, and any individual
    // question can be left blank.
    //
    // Sleep / stress stored as raw strings (the picker values
    // — "poor"/"ok"/"good"/"great" and "low"/"moderate"/"high")
    // so SwiftData lightweight migration stays additive-safe.
    // No raw-string-to-enum classifier yet because consumers
    // today are display-only; the analytics layer that turns
    // these into insights will add the enum mapping when it
    // ships.
    //
    // `preSoreNotes` is free-form text — body parts, prior
    // injuries, anything qualitative. Short by convention but
    // not enforced.
    //
    // All three default to nil so pre-Phase-37 races decode
    // cleanly without a journal, matching the additive-schema
    // discipline this codebase has held since v0.1.
    var preSleepRating: String? = nil
    var preStressLevel: String? = nil
    var preSoreNotes: String? = nil

    // §28 — Dense HR sample series captured during the race. Every
    // sample ingested through RaceViewModel.ingestHeartRate(_:) (the
    // single funnel for Watch WCSession stream, HK 5s poll fallback,
    // and the future external BLE strap source from §20 Path A) gets
    // appended to an in-memory buffer; the buffer is JSON-encoded
    // and persisted here on `finishRace()`.
    //
    // Why this field exists alongside per-Split `heartRateAvgBPM` /
    // `heartRateMaxBPM` aggregates: those aggregates rehydrate from
    // HK via HKStatisticsQuery per segment window, which works only
    // when HK has dense samples for that window. Garmin / external
    // BLE strap users won't write samples to HK at race-grade
    // density (no HKWorkoutSession from CoreBluetooth path). The
    // in-app series is the only authoritative dense series in that
    // case, and it's also a defense-in-depth for Apple Watch users
    // when HK's storage behavior glitches.
    //
    // Pre-Phase-28 races decode with nil here — backward-compat
    // additive migration, same pattern as `photoData` / `notes`.
    // Downstream consumers (per-station rehydrate, zone-time on
    // RaceSummary / RaceDetail, future Profile-level HR-curve
    // analytics) prefer this series when non-empty and fall back
    // to HK queries when empty.
    @Attribute(.externalStorage) var hrSeriesData: Data?

    // Public URL of the race photo in Supabase Storage's
    // `race-photos` bucket. Set after a successful upload from
    // `RacePhotoSection`'s photo picker; nil for races without a
    // photo or for pre-cloud-sync rows. Pairs with `photoData`
    // the same way `UserProfile.avatarURL` pairs with
    // `avatarData`:
    //   • photoData (bytes) — local-only fast path. Always
    //     preferred when present (zero-latency render, no
    //     network).
    //   • photoURL (URL)   — cloud authoritative copy. Used as
    //     `AsyncImage(url:)` fallback on devices that synced
    //     this race down but don't have the bytes locally
    //     (e.g. signed in on a new phone).
    //
    // Migration-safe nil default — pre-existing rows decode
    // cleanly. Sync layer (RaceSyncService) round-trips it via
    // RemoteRace's `photo_url` column.
    var photoURL: String?

    // Roxzone-mode persistence. When non-nil, the race is
    // currently in Roxzone state — the previous segment closed
    // at this timestamp and the athlete is in transition to the
    // next segment. Cleared when the next segment starts (its
    // duration is captured into `pendingRoxzoneSeconds` for the
    // engine to attach to the upcoming split).
    //
    // Survives force-kill: on relaunch, `engineState` reads this
    // and reconstitutes the engine in `.inRoxzone` so the
    // athlete picks up exactly where they left off.
    var roxzoneStartedAt: Date?

    // Roxzone duration to attach to the next-completed split.
    // Set after the user starts a segment from .inRoxzone via
    // `startNextSegment(at:)` — the engine stashes the duration
    // here, then consumes it on the next advance/endSegment.
    // Survives force-kill so a kill mid-segment-after-roxzone
    // doesn't lose the transition time.
    var pendingRoxzoneSeconds: TimeInterval?

    // Display name of the partner this race was run with, when
    // mode == .duo. Always nil for solo races. Used by History +
    // RaceCardView to render "Duo with Sarah" instead of the
    // generic race title. Set by the host after duo race finish
    // (from `coordinator.session.partnerName`); set by the guest
    // when reconstructing a Race row from a host's broadcast
    // .finished snapshot.
    //
    // Migration-safe additive optional — pre-existing rows
    // decode cleanly with nil. Same SwiftData pattern as
    // `notes` / `name` / `pausedAt`.
    var partner: String?

    // Supabase user UUID of the partner — populated from the
    // duo_races row at race finish (host writes guest's UUID,
    // guest writes host's). Distinct from `partner` (display
    // name): two athletes can share a display name but each
    // has a unique UUID, so this is what the UI uses to deep-
    // link to the right public profile.
    //
    // Nil for solo races and for Tier 1 (Multipeer) duo races,
    // which don't have a Supabase auth concept. RaceCardView
    // only renders the partner name as tappable when this
    // field is present.
    //
    // Migration-safe additive optional — Solo rows / pre-cloud
    // duo rows decode as nil.
    var partnerUserID: String?

    // Set when the duo session dropped during an active race —
    // the moment the link broke (Bluetooth out of range, partner
    // killed the app, etc.). The surviving phone keeps timing
    // solo from that point and the eventual saved race carries
    // this annotation so History can render a small "partner left
    // at MM:SS" note.
    //
    // `nil` when the race finished cleanly with both partners
    // connected, or when the race wasn't a duo at all.
    var partnerDisconnectedAt: Date?

    // Privacy gate. `true` means this race is hidden from any
    // future-public surfaces (the v1 social feed, leaderboards,
    // shared profile). Local History + Profile stats always
    // include it — privacy controls the EXTERNAL visibility,
    // not the athlete's own view.
    //
    // Forward-compatible move: shipping the toggle now means
    // existing races flagged private stay private when v1's
    // feed lights up. Default `false` matches user intent
    // (most training is public-by-default in the Strava model)
    // and is migration-safe — pre-existing rows decode cleanly.
    //
    // Today the only effect is the lock icon on the race card +
    // a subtitle line on summary/detail. Once the social feed
    // ships, the upload pipeline reads this flag and skips
    // private races entirely.
    var isPrivate: Bool = false

    // Wireframe §04.3 edge case — provenance flag for races
    // imported from Apple Health rather than recorded in-app.
    // Future Health-import flow will flip this true; for now
    // every new race starts at false. Drives the small "↓ Health"
    // tag on History list rows. Lightweight migration: existing
    // rows pick up the false default cleanly.
    var importedFromHealth: Bool = false

    // Wireframe §04.2 Edit-Notes screen — optional CONDITIONS
    // metadata the athlete can attach post-race. All optional /
    // empty-by-default so existing rows don't need backfill.
    //
    //   • gym       — free-form location string ("Brooklyn Strength")
    //   • feltRating — 1-10 perceived effort / how-did-this-feel
    //   • sleepHoursLast — hours slept the night before (7.2)
    var gym: String = ""
    var feltRating: Int?
    var sleepHoursLast: Double?

    // §19.2 — primary HR source attribution for this race. Set
    // on finish from `SensorSourceRegistry.shared.lastHRSource.
    // shortLabel` — values like "Apple Watch", "AirPods Pro 3",
    // or "Fused". Nil for races finished before the source-
    // attribution layer landed; the SourceProvenanceCard
    // self-hides in that case. Future v2: extend to track all
    // sources used during the race (when a fallover happens
    // mid-race) rather than just the last one.
    var hrSourcePrimary: String?

    // §14 — what kind of session this Race represents.
    // Stored as a raw string so SwiftData's additive-schema
    // migration accepts it cleanly: pre-existing rows decode
    // as the empty string, which the `kind` accessor below
    // maps to `.race` (the only kind that existed before this
    // field landed). Direct mutation is fine — RaceViewModel
    // sets this at race-start time based on which Train-hub
    // card the athlete tapped.
    //
    // Note: the field is stored separately from `name` even
    // though both are athlete-facing categorizations because
    // they answer different questions: `name` is "what did I
    // call this session?" (free-form), `kindRaw` is "what
    // type of session is this?" (constrained enum). Keeping
    // them separate means History can filter by kind without
    // doing string-search on name, and a kind badge stays
    // present even when the athlete leaves name empty.
    var kindRaw: String = ""

    // §19.4 Phase 10J — posture drift across the race, in
    // degrees of forward head pitch. Positive = head tilted
    // further forward in the second half vs the first half
    // (the direction fatigued runners' heads drift); negative
    // = head went UP (uncommon but real for athletes who run
    // tall when fresh and overcompensate as they tire).
    //
    // Captured from AirPods Pro 1+ / 4 / Max head motion via
    // `HeadphoneMotionService`'s 1Hz pitch sample buffer,
    // computed at race finish as
    // `mean(secondHalfPitch) - mean(firstHalfPitch)` and
    // converted to degrees.
    //
    // Nil when:
    //   • No AirPods (or non-motion AirPods) were paired during
    //     the race — the buffer was empty.
    //   • The race was too short to split into halves (< 60s
    //     of pitch samples — defensive lower bound).
    //
    // Surface: `InsightGenerator.postureDriftInsight` fires a
    // narrative callout when forward drift ≥ 5°. Lower-magnitude
    // values are persisted but silent — the field exists for
    // future profile-level trend charts (am I learning to hold
    // posture under fatigue?) even when no insight fires on a
    // given race.
    //
    // Migration-safe additive nil default — pre-existing rows
    // decode cleanly, same SwiftData pattern as `hrSourcePrimary`.
    var posturePitchDriftDegrees: Double?

    // Athlete-defined organizing tags. Free-form lowercase strings
    // ("zone2", "race-sim", "morning", "brick", "strength-focus")
    // — the athlete picks their own taxonomy. Stored as a single
    // comma-separated string rather than a separate Tag @Model so
    // the schema stays additive-migration-safe and we don't need
    // a relationship table just to slice History.
    //
    // Read/write through the `tags` computed property which handles
    // CSV split/join + trimming. Direct access to `tagsRaw` is
    // discouraged — it's `internal` rather than `private` only
    // because SwiftData's @Model macro rejects private stored
    // properties.
    //
    // Forward-compat: when the social feed lights up in v2, tags
    // become discoverable filters across athletes ("see other
    // athletes' Zone 2 sessions"). The data shape doesn't change;
    // only the visibility layer.
    //
    // Empty-string default is migration-safe — pre-existing rows
    // decode cleanly, same SwiftData additive pattern as
    // `notes` / `name` / `partner`.
    var tagsRaw: String = ""

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        splits: [Split] = [],
        currentSegmentStartedAt: Date? = nil,
        sequence: [Station] = Station.raceSequence,
        mode: RaceMode = .solo,
        createdAt: Date = Date(),
        notes: String = "",
        targetDuration: TimeInterval? = nil,
        name: String = "",
        pausedAt: Date? = nil,
        photoData: Data? = nil,
        partner: String? = nil,
        partnerDisconnectedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.splits = splits
        self.currentSegmentStartedAt = currentSegmentStartedAt
        self.sequenceRaw = sequence.map(\.rawValue)
        self.modeRawValue = mode.rawValue
        self.createdAt = createdAt
        self.notes = notes
        self.targetDuration = targetDuration
        self.name = name
        self.pausedAt = pausedAt
        self.photoData = photoData
        self.partner = partner
        self.partnerDisconnectedAt = partnerDisconnectedAt
    }

    // MARK: - Derived

    var isFinished: Bool { endedAt != nil }

    var sequence: [Station] {
        sequenceRaw.compactMap(Station.init(rawValue:))
    }

    var mode: RaceMode {
        RaceMode(rawValue: modeRawValue) ?? .solo
    }

    // Total duration — `nil` while the race is in progress.
    var totalDuration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    // §28 — decode the persisted HR sample series. Empty array
    // when the BLOB is nil (pre-Phase-28 races) or decoding fails
    // (corrupt data — defensively swallowed so a single bad row
    // can't crash the History feed). Same shape as
    // `FreeRun.hrSeries`.
    var hrSeries: [HRSample] {
        guard let data = hrSeriesData else { return [] }
        return (try? JSONDecoder().decode([HRSample].self, from: data)) ?? []
    }

    // §28 — re-encode and persist a new HR series. Called by
    // RaceViewModel.finishRace after flushing the in-memory
    // buffer. Quiet on encode failure for the same defensive
    // reason — losing the dense series for one race is preferable
    // to a crash.
    func setHRSeries(_ samples: [HRSample]) {
        hrSeriesData = try? JSONEncoder().encode(samples)
    }

    // Reconstitute a `RaceEngine.State` from persisted fields so a resumed
    // race picks up exactly where it left off (splits, current segment start,
    // total elapsed — all accurate to the millisecond).
    var engineState: RaceEngine.State {
        if let endedAt {
            return .finished(
                startedAt: startedAt,
                endedAt: endedAt,
                splits: splits
            )
        }
        // Roxzone has its OWN no-current-segment shape: the
        // previous segment is closed (in `splits`), the next
        // hasn't started, and `roxzoneStartedAt` records the
        // transition's start. Resolved before the in-progress
        // path because it has no `currentSegmentStartedAt`.
        if let roxStart = roxzoneStartedAt, currentSegmentStartedAt == nil {
            return .inRoxzone(
                startedAt: startedAt,
                splits: splits,
                roxzoneStartedAt: roxStart
            )
        }
        if let segStart = currentSegmentStartedAt {
            // Paused state takes precedence over inProgress when both
            // currentSegmentStartedAt and pausedAt are set. The engine
            // state machine resolves cleanly back to .inProgress once
            // the athlete taps Resume.
            if let pausedAt {
                return .paused(
                    startedAt: startedAt,
                    currentSegmentStartedAt: segStart,
                    splits: splits,
                    pausedAt: pausedAt
                )
            }
            return .inProgress(
                startedAt: startedAt,
                currentSegmentStartedAt: segStart,
                splits: splits
            )
        }
        return .notStarted
    }

    // MARK: - Tag accessor

    // Typed view onto the comma-separated `tagsRaw` field. Splits
    // on comma, trims whitespace, drops empties + duplicates,
    // lowercases for canonical form so "Zone2" and "zone2" merge.
    //
    // Setter performs the same cleanup before joining back —
    // callers don't have to sanitize input. A bad tag input ("  ,
    // ZONE 2, , zone2 ") becomes ["zone 2", "zone2"] (preserving
    // first-occurrence order), then back to "zone 2,zone2" on
    // disk. Always read back through this property; never touch
    // tagsRaw directly outside the model.
    //
    // Maximum cap of 5 tags per race — beyond that the UX gets
    // cluttered and the categorization stops being meaningful.
    // Setter trims to 5 silently; UI should also gate at 5.
    // §14 — typed view onto the `kindRaw` field. Empty string
    // (the SwiftData additive-migration default for pre-existing
    // rows that don't carry a kind value) maps to `.race` so
    // every old row continues to read as a full Race Mode
    // session — which is what they were when the schema field
    // didn't exist yet.
    //
    // Always set through this accessor; don't touch kindRaw
    // directly outside the model so the rawValue contract stays
    // in one place.
    var kind: RaceKind {
        get {
            RaceKind(rawValue: kindRaw) ?? .race
        }
        set {
            kindRaw = newValue.rawValue
        }
    }

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { acc, tag in
                    if !acc.contains(tag) { acc.append(tag) }
                }
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { acc, tag in
                    if !acc.contains(tag) { acc.append(tag) }
                }
                .prefix(5)
            tagsRaw = cleaned.joined(separator: ",")
        }
    }
}

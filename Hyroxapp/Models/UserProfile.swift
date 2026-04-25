import Foundation
import SwiftData

// The single user of this v0.1 / v1 build.
//
// Stored as a SwiftData `@Model` so profile edits persist across launches
// alongside `Race` rows. The convention in v1 is "there is exactly one
// `UserProfile` row" — the ProfileView bootstraps a default on first launch
// and never inserts another. When Supabase auth lands later, this same
// model gains an optional `remoteUserID: UUID?` tying it to the cloud
// account; migration is a single additive field.
//
// Avatar is stored as raw `Data` (JPEG, ~0.7 quality). For v1 this is
// bounded by however large the user's picker choice is — we compress on
// save. When cloud sync ships, avatars move to Supabase Storage and the
// field becomes a URL; the on-device copy stays as a cache.
@Model
final class UserProfile {

    // Stable identity, for pairing with a future remote account row.
    var id: UUID

    var displayName: String
    var handle: String
    var location: String
    var bio: String

    // Compressed JPEG of the chosen avatar. `nil` means "show the default
    // SF Symbol fallback". Kept as Data rather than filesystem path so the
    // whole profile travels with the model (and later syncs) as one unit.
    var avatarData: Data?

    // Competitive HYROX division. Determines the wall ball rep count in
    // the race screen and (eventually) sled / sandbag weight defaults.
    //
    // Stored as Optional<Division> on purpose: SwiftData's lightweight
    // migration doesn't reliably populate a new non-optional field on
    // pre-existing rows (observed crash:
    //   "Could not cast value of type 'Swift.Optional<Any>' to 'Division'"
    // on `UserProfile.division.getter`). Optional-plus-default is the
    // robust pattern — existing rows load as `nil`, the `resolvedDivision`
    // computed property below gives every caller a non-optional value.
    //
    // Always read / write via `resolvedDivision`, never this property
    // directly, so the fallback default is consistently applied.
    //
    // Default value written as `Division.mensOpen` (fully qualified) —
    // not `.mensOpen` — because SwiftData's `@Model` macro expansion
    // can't infer the type from the optional declaration context.
    var division: Division? = Division.mensOpen

    // Non-optional accessor with a safe fallback. Views and view models
    // should use this — it insulates them from the stored optional and
    // ensures a consistent default (`.mensOpen`) when the field is nil
    // (freshly migrated rows from before the division field existed).
    var resolvedDivision: Division {
        get { division ?? .mensOpen }
        set { division = newValue }
    }

    // Whether to fire voice cues ("Next: Sled Push") on station
    // transitions during a race. On by default — verbal announcement
    // is the primary value-add for athletes mid-workout who can't
    // glance at the screen. Off for users who train with music or
    // podcasts and don't want spoken interruptions.
    //
    // Bool with a default value is migration-safe out of the box for
    // SwiftData lightweight migration — existing rows pick up `true`
    // on next read.
    var audioCuesEnabled: Bool = true

    // Whether the race screen plays a 3-2-1-GO countdown before
    // the timer actually starts. On by default — gives the
    // athlete a moment to drop the phone, take a breath, and
    // start the race deliberately rather than the timer
    // ticking the instant they tap "Start Race." Off for users
    // who'd rather just begin instantly. Migration-safe via
    // SwiftData default-value lightweight migration.
    var countdownEnabled: Bool = true

    // Master toggle for local notifications (today: only the
    // streak-protection reminder; future: weekly digest, race
    // anniversaries, etc.). Off by default — opt-in respects the
    // user's "don't ping me unless I asked" baseline. Permission
    // is requested contextually when the user first flips this
    // on in Settings, not on launch.
    var notificationsEnabled: Bool = false

    // Roxzone tracking — captures the transition time between
    // segment-end and next-segment-start as a separate metric.
    // Off by default because it's an advanced HYROX-specific
    // feature: changes the in-race advance flow from one-tap to
    // two-tap (end segment → enter roxzone → start next).
    // Athletes who care about transition discipline turn it on;
    // athletes who don't, never know it exists.
    //
    // The metric the HYROX community calls "Roxzone time" — the
    // total time spent in transition, separate from work time.
    // No other fitness app surfaces this.
    var roxzoneEnabled: Bool = false

    // Maximum heart rate (bpm) used to classify HR zones on race
    // detail. Default 190 is a reasonable starting point for most
    // HYROX-age athletes; the "220 minus age" rule-of-thumb gives
    // a per-user value that the athlete can dial in via Settings.
    //
    // Stored as Int because a fractional max HR is meaningless
    // (HealthKit reports per-second integer bpm samples). Default
    // makes this migration-safe for existing rows.
    var maxHeartRate: Int = 190

    // First-launch onboarding completion flag. False on a fresh
    // install (and on rows from before the wizard shipped, via
    // SwiftData's default-value lightweight migration), true once
    // the athlete has walked through the wizard. Drives the
    // wizard sheet on app entry — `bootstrapIfNeeded` creates a
    // default profile on first run, the wizard then walks the user
    // through populating it before they touch the rest of the app.
    var hasCompletedOnboarding: Bool = false

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        handle: String,
        location: String = "",
        bio: String = "",
        avatarData: Data? = nil,
        division: Division? = Division.mensOpen,
        audioCuesEnabled: Bool = true,
        countdownEnabled: Bool = true,
        notificationsEnabled: Bool = false,
        roxzoneEnabled: Bool = false,
        maxHeartRate: Int = 190,
        hasCompletedOnboarding: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.location = location
        self.bio = bio
        self.avatarData = avatarData
        self.division = division
        self.audioCuesEnabled = audioCuesEnabled
        self.countdownEnabled = countdownEnabled
        self.notificationsEnabled = notificationsEnabled
        self.roxzoneEnabled = roxzoneEnabled
        self.maxHeartRate = maxHeartRate
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Convenience for first-launch bootstrapping — values match the
    // placeholders we used in v0.1's hardcoded ProfileHeaderView so the
    // transition is visually seamless for the existing user.
    static func makeDefault() -> UserProfile {
        UserProfile(
            displayName: "Athlete",
            handle: "@athlete",
            location: "",
            bio: "HYROX athlete in training.",
            division: .mensOpen
        )
    }
}

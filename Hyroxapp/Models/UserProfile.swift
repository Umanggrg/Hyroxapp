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

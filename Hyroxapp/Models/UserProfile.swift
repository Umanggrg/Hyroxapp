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
    // Defaults to `.mensOpen` on first install for existing rows that
    // predate this field — users can change it from Settings.
    //
    // Stored as a raw String via SwiftData's default handling of
    // RawRepresentable enums. Adding new cases later is a safe additive
    // change; the field has a default so lightweight migration populates
    // existing rows with `.mensOpen`.
    var division: Division = Division.mensOpen

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        handle: String,
        location: String = "",
        bio: String = "",
        avatarData: Data? = nil,
        division: Division = .mensOpen,
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

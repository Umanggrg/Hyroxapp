import Foundation

// Codable mirror of the Supabase `profiles` table. Matches the
// column names exactly — Supabase's PostgREST API uses Postgres
// snake_case columns by default, so we use `CodingKeys` to bridge
// to Swift's camelCase property names.
//
// This is intentionally a SEPARATE type from the SwiftData
// `UserProfile` @Model class. Reasons:
//   • The shapes diverge: many `UserProfile` fields (theme,
//     voice cues, every in-race display toggle) are device-local
//     preferences that don't sync. Forcing the local model to be
//     directly Codable for the network would conflate "what's
//     persisted on this device" with "what gets shared with my
//     account."
//   • SwiftData @Model classes have macro-generated Codable
//     synthesis that's incompatible with custom decoding.
//     Keeping the network model as a plain `struct` sidesteps
//     that entire class of weirdness.
//   • A separate DTO makes server-side schema changes a small,
//     contained migration: update the columns + this struct.
//     The local model stays untouched until we're ready to
//     surface the new field in UI.
//
// Field selection rationale: identity fields that follow the
// athlete across devices (name, handle, location, bio, division,
// max HR, avatar URL). Device-local preferences (audio cues,
// theme, in-race toggles) are NOT synced — they're per-device.
struct RemoteProfile: Codable, Sendable {
    let id: String
    let displayName: String
    let handle: String
    let location: String
    let bio: String
    let division: String
    let maxHeartRate: Int
    let avatarUrl: String?
    let createdAt: Date?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handle
        case location
        case bio
        case division
        case maxHeartRate = "max_heart_rate"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Insert / update payload — same shape minus the server-managed
// fields (createdAt, updatedAt) which the server fills in via
// the trigger we set up. We don't WRITE timestamps from the
// client; the server is the source of truth.
//
// `id` is included on insert so RLS's "with check (auth.uid() = id)"
// passes — the user is explicitly asserting "this is my row."
struct RemoteProfileWrite: Codable, Sendable {
    let id: String
    let displayName: String
    let handle: String
    let location: String
    let bio: String
    let division: String
    let maxHeartRate: Int
    let avatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handle
        case location
        case bio
        case division
        case maxHeartRate = "max_heart_rate"
        case avatarUrl = "avatar_url"
    }
}

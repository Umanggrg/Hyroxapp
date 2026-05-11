import Foundation

// Codable mirror of the Supabase `public_profiles` view. Same
// snake_case-to-camelCase pattern as the other Remote* DTOs.
//
// This is the shape returned when one athlete looks up another
// — distinct from `RemoteProfile` because the view exposes a
// strict subset of columns (no max_heart_rate, no remote_user_id).
// Any future sensitive field stays out by default — server-side
// the view's column list is the allowlist.
//
// Fields that exist on the underlying table but are NOT here:
//   • max_heart_rate    — reveals fitness level, kept private
//   • updated_at        — internal sync bookkeeping; the
//                         lookup endpoint doesn't need it
//
// Read-only — there's no `RemotePublicProfileWrite` shape
// because writes always go through the owning user's auth
// session via the `profiles` table directly. Lookups are
// pull-only.
struct RemotePublicProfile: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let location: String
    let bio: String
    let division: String
    let avatarUrl: String?
    let createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handle
        case location
        case bio
        case division
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }
}

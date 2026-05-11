import Foundation

// Read shape — mirrors the `public_comments` view (joined
// with profiles for inline identity). Used for the comment
// list under a feed card / detail sheet.
//
// `commenter_*` fields are populated by the view's JOIN so
// rendering avatar + name + handle is single-query. If a
// commenter deletes their account, ON DELETE CASCADE wipes
// the comments — they'll never appear with stale identity.
struct RemoteComment: Codable, Sendable, Identifiable {
    let id: String
    let raceId: String
    let userId: String
    let body: String
    let createdAt: Date

    let commenterDisplayName: String
    let commenterHandle: String
    let commenterAvatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case raceId = "race_id"
        case userId = "user_id"
        case body
        case createdAt = "created_at"
        case commenterDisplayName = "commenter_display_name"
        case commenterHandle = "commenter_handle"
        case commenterAvatarUrl = "commenter_avatar_url"
    }
}

// Insert shape — server fills `id`, `created_at`, and
// joined identity fields. Client only sends the three
// fields it owns.
struct RemoteCommentInsert: Codable, Sendable {
    let raceId: String
    let userId: String
    let body: String

    private enum CodingKeys: String, CodingKey {
        case raceId = "race_id"
        case userId = "user_id"
        case body
    }
}

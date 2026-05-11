import Foundation

// Codable mirror of the Supabase `follows` table. Carries the
// two user UUIDs that form a follow edge, plus the server
// timestamp.
//
// One DTO covers both read + write — unlike profiles / races /
// duo_races we don't have a separate Insert shape because:
//   • created_at is server-generated; clients don't send it
//     (we use `encodeIfPresent` style by leaving it as a let?)
//   • There's no UPDATE path for follows; they're insert /
//     delete only.
//
// For inserts, callers construct with createdAt = nil and the
// custom encoder below omits that field. Reads always carry
// createdAt populated by the server default.
struct RemoteFollow: Codable, Sendable {
    let followerUserId: String
    let followedUserId: String
    let createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case followerUserId = "follower_user_id"
        case followedUserId = "followed_user_id"
        case createdAt = "created_at"
    }

    // Custom encode so nil createdAt on insert doesn't write
    // `null` over the server's default. Same pattern as
    // RemoteDuoRaceUpdate.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(followerUserId, forKey: .followerUserId)
        try container.encode(followedUserId, forKey: .followedUserId)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

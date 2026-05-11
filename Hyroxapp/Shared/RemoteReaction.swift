import Foundation

// Codable mirror of the Supabase `reactions` table. One row
// per (race, user, kind) tuple.
//
// `kind` stored as raw String (matches the table) rather than
// the typed `ReactionKind` enum. Decode-time mapping happens
// at the call site via `ReactionKind(rawValue:)` so a future
// new kind on the server (added via a CHECK alter) doesn't
// crash older clients — they just see an unrecognized kind
// and filter it out. Cleaner than failing the entire payload.
//
// Custom encode so a nil `createdAt` on insert doesn't write
// `null` over the server's default — same pattern as
// RemoteFollow.
struct RemoteReaction: Codable, Sendable {
    let raceId: String
    let userId: String
    let kind: String
    let createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case raceId = "race_id"
        case userId = "user_id"
        case kind
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(raceId, forKey: .raceId)
        try container.encode(userId, forKey: .userId)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    // Typed accessor. Returns nil for unrecognized kinds (a
    // forward-compat add on the server we don't know about
    // yet). Call sites use this to filter / dispatch.
    var typedKind: ReactionKind? {
        ReactionKind(rawValue: kind)
    }
}

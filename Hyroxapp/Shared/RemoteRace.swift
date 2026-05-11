import Foundation

// Codable mirror of the Supabase `races` table. Same DTO pattern
// `RemoteProfile` uses — keep network-shape separate from the
// SwiftData @Model class so the two evolve independently.
//
// Splits are stored as a JSONB column on the server; here we
// model them as `[Split]` and let the encoder/decoder serialize
// the inner array as JSON. Date strategy propagates through the
// type tree (supabase-swift configures the encoder with
// .iso8601), so nested Split.startedAt round-trips correctly
// without per-type encoding ceremony.
//
// What's synced today (text + numeric + JSONB):
//   • id, user_id, started_at, ended_at, splits,
//     sequence_raw, mode, name, notes, target_duration,
//     paused_at, partner, is_private, tags_raw, created_at,
//     updated_at
// What's deferred:
//   • photoData bytes → Supabase Storage holds the JPEG (the
//     `race-photos` bucket); only the public URL travels in
//     this row via `photo_url`. The bytes themselves stay
//     local-only as a render cache.
//   • currentSegmentStartedAt, roxzoneStartedAt,
//     pendingRoxzoneSeconds → in-progress state, only
//     finished races sync
struct RemoteRace: Codable, Sendable {
    let id: String
    let userId: String
    let startedAt: Date
    let endedAt: Date?
    let splits: [Split]
    let sequenceRaw: [Int]
    let mode: String
    let createdAt: Date?
    let notes: String
    let targetDuration: Double?
    let name: String
    let pausedAt: Date?
    let partner: String?
    let partnerUserId: String?
    let isPrivate: Bool
    let tagsRaw: String
    let photoUrl: String?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case splits
        case sequenceRaw = "sequence_raw"
        case mode
        case createdAt = "created_at"
        case notes
        case targetDuration = "target_duration"
        case name
        case pausedAt = "paused_at"
        case partner
        case partnerUserId = "partner_user_id"
        case isPrivate = "is_private"
        case tagsRaw = "tags_raw"
        case photoUrl = "photo_url"
        case updatedAt = "updated_at"
    }
}

// Insert/update payload — same shape minus server-managed fields
// (created_at, updated_at). The server fills these via defaults
// and the trigger.
struct RemoteRaceWrite: Codable, Sendable {
    let id: String
    let userId: String
    let startedAt: Date
    let endedAt: Date?
    let splits: [Split]
    let sequenceRaw: [Int]
    let mode: String
    let notes: String
    let targetDuration: Double?
    let name: String
    let pausedAt: Date?
    let partner: String?
    let partnerUserId: String?
    let isPrivate: Bool
    let tagsRaw: String
    let photoUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case splits
        case sequenceRaw = "sequence_raw"
        case mode
        case notes
        case targetDuration = "target_duration"
        case name
        case pausedAt = "paused_at"
        case partner
        case partnerUserId = "partner_user_id"
        case isPrivate = "is_private"
        case tagsRaw = "tags_raw"
        case photoUrl = "photo_url"
    }
}

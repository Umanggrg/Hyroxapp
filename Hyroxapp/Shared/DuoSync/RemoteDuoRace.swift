import Foundation

// Codable mirror of the Supabase `duo_races` table. Same DTO
// pattern profiles + races + free_runs use — keep network shape
// distinct from any local @Model so they evolve independently.
//
// Note: there is NO local @Model for duo races. The room is a
// shared, ephemeral coordination surface — not durable user
// data. When a duo race finishes, both athletes' RaceViewModels
// each create their own local Race row, identical to a solo
// race in History (the `partner` field on Race + the `mode = .duo`
// flag tag the entry as a duo). The duo_races row gets marked
// `finished` and is otherwise irrelevant from then on.
//
// Two shapes (read vs write) for the same reason as RemoteRace
// — server-managed timestamps shouldn't appear in upserts.
struct RemoteDuoRace: Codable, Sendable {
    let id: String
    let pairCode: String
    let hostUserId: String
    let guestUserId: String?
    let status: String
    let startedAt: Date?
    let endedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case pairCode = "pair_code"
        case hostUserId = "host_user_id"
        case guestUserId = "guest_user_id"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Insert payload — host-side row creation. `id`, `created_at`,
// `updated_at` are server defaults; `pair_code` is generated
// client-side via `DuoRoomCode.random()` so the host can show
// it immediately without a round-trip wait.
struct RemoteDuoRaceInsert: Codable, Sendable {
    let pairCode: String
    let hostUserId: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case pairCode = "pair_code"
        case hostUserId = "host_user_id"
        case status
    }
}

// Update payload — guest-side join (sets guest_user_id +
// status='paired'), host-side start (sets started_at +
// status='racing'), or end-of-race (sets ended_at + status).
//
// Every field is Optional<T> with a nested Optional? wrapping
// (handled at write time by only encoding present keys via
// `encodeIfPresent`). Clients only pass the fields they're
// intentionally mutating; PostgREST UPDATEs leave the rest
// alone.
struct RemoteDuoRaceUpdate: Codable, Sendable {
    let guestUserId: String?
    let status: String?
    let startedAt: Date?
    let endedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case guestUserId = "guest_user_id"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    // Custom encode so nil fields don't write `null` over
    // existing values — they get omitted from the JSON payload.
    // Without this, `RemoteDuoRaceUpdate(status: "paired", ...)`
    // would null out the started_at / ended_at columns even
    // when we only intended to update status.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(guestUserId, forKey: .guestUserId)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}

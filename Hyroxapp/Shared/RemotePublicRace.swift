import Foundation

// Codable mirror of the Supabase `public_races` view. One row
// per finished, non-private race, with the athlete's identity
// embedded inline so feed rendering is one query, not N.
//
// Distinct from `RemoteRace` (the full per-race shape used by
// the owning user's sync) because:
//   • The view exposes a whitelist of safe-to-share columns
//     only — no splits, notes, pause state, etc.
//   • Athlete identity (display_name, handle, avatar_url) is
//     embedded via the JOIN. RemoteRace doesn't carry these.
//
// Read-only — there's no Write shape. Writes always go
// through `RaceSyncService` against the owning user's
// `races` row.
//
// `totalDuration` computed on the fly from ended_at -
// started_at since the view doesn't pre-aggregate it (raw
// timestamps are simpler to filter / sort on). nil on
// truly-pathological rows where the timestamps don't make
// sense; ended_at is filtered to NOT NULL by the view so
// these should never appear in practice.
struct RemotePublicRace: Codable, Sendable, Identifiable {

    let id: String
    let userId: String
    let startedAt: Date
    let endedAt: Date
    let name: String
    let sequenceRaw: [Int]
    let mode: String
    let partner: String?
    let partnerUserId: String?
    let tagsRaw: String
    let photoUrl: String?
    let targetDuration: Double?
    let createdAt: Date?

    // Embedded athlete identity from the JOIN.
    let athleteDisplayName: String
    let athleteHandle: String
    let athleteAvatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case name
        case sequenceRaw = "sequence_raw"
        case mode
        case partner
        case partnerUserId = "partner_user_id"
        case tagsRaw = "tags_raw"
        case photoUrl = "photo_url"
        case targetDuration = "target_duration"
        case createdAt = "created_at"
        case athleteDisplayName = "athlete_display_name"
        case athleteHandle = "athlete_handle"
        case athleteAvatarUrl = "athlete_avatar_url"
    }

    // Total race duration in seconds. Computed from the
    // timestamp pair so the view stays simple — clients
    // format on demand via `RaceStats.format`.
    var totalDuration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    // True for races that ran the canonical 16-segment HYROX
    // race format. Lets the feed card label "HYROX Race" vs
    // "Custom Workout" without a separate column on the view.
    var isHyroxRace: Bool {
        sequenceRaw.count == 16
    }
}

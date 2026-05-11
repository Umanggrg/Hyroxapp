import Foundation

// Codable mirror of the Supabase `public_race_detail` view.
// Same shape as `RemotePublicRace` plus a projected splits
// array. Used by `PublicRaceDetailSheet` when the local user
// taps a feed card.
//
// `PublicSplit` is the safe subset — station, duration,
// startedAt, roxzoneSeconds. The view projects these via
// jsonb_build_object, stripping the athlete-private fields
// (notes, reps, rpe, weights, HR samples) at the SQL level.
// Clients never see the sensitive bits over the wire.
struct RemotePublicRaceDetail: Codable, Sendable, Identifiable {

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
    let splits: [PublicSplit]

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
        case splits
        case athleteDisplayName = "athlete_display_name"
        case athleteHandle = "athlete_handle"
        case athleteAvatarUrl = "athlete_avatar_url"
    }

    var totalDuration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var isHyroxRace: Bool {
        sequenceRaw.count == 16
    }
}

// Whitelisted split projection for public consumption. The
// view's jsonb_build_object emits these four fields per split;
// the Codable types here match exactly.
//
// Optional fields reflect server-side nulls:
//   • roxzoneSeconds — null when the athlete didn't have
//     roxzone tracking on for this race.
struct PublicSplit: Codable, Sendable, Identifiable {
    let station: Int
    let duration: Double
    let startedAt: Date
    let roxzoneSeconds: Double?

    // Identifiable via (startedAt + station) — stable within
    // a race because no two splits start at the same instant.
    // Used by SwiftUI `ForEach` without a separate id field
    // on the row.
    var id: String { "\(startedAt.timeIntervalSince1970)-\(station)" }

    // Typed Station accessor — returns nil if the server's
    // raw value isn't in our Station enum (a future server
    // could add a new station kind we don't know about yet).
    var typedStation: Station? {
        Station(rawValue: station)
    }
}

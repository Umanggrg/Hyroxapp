import Foundation

// Codable mirror of the Supabase `public_race_stats` view. One
// row per athlete — server-side `group by user_id` makes the
// rollup, this DTO carries it.
//
// All fields are read-only — the view has no writeable shape.
// `pbSeconds` is the smallest total finish time across the
// user's finished, non-private races. `lastRaceAt` is the most
// recent ended_at.
//
// Optional fields reflect "this user has no finished public
// races yet":
//   • race_count returns 0 rows from the view when the user
//     has nothing eligible — so absence-of-row is the v1
//     signal for "show 'No races yet' state." Both pbSeconds
//     and lastRaceAt are non-optional inside a present row
//     (every row aggregates at least one race), but we mark
//     them Optional<T> defensively in case the view picks up
//     edge cases later (zero-duration race, NULL ended_at
//     slipping through).
//
// Read-only — no Insert/Write variant. Writes always go
// through the owning user's own `races` table via
// RaceSyncService.
struct RemotePublicRaceStats: Codable, Sendable, Identifiable {
    let userId: String
    let raceCount: Int
    let pbSeconds: Double?
    let lastRaceAt: Date?

    // Identifiable conformance for SwiftUI lists / sheets that
    // want to dispatch on these rows. Aligns with the foreign-
    // key shape so the same string usable across profile /
    // stats lookups.
    var id: String { userId }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case raceCount = "race_count"
        case pbSeconds = "pb_seconds"
        case lastRaceAt = "last_race_at"
    }
}

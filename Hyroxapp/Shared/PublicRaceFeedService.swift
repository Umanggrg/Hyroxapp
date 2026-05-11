import Foundation
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// Fetches `RemotePublicRace` rows for feed + public profile
// surfaces. Two consumer paths:
//
//   • `feed(followedBy:limit:)` — the social feed. Two-step
//     query: find user IDs the local user follows, then
//     pull recent public_races rows for those user IDs.
//   • `recent(forUserID:limit:)` — a single athlete's most
//     recent public races. Powers a future "recent races"
//     section on PublicProfileCard.
//
// Error policy mirrors PublicProfileService: every method
// returns `[]` on failure. View layer treats empty as
// "nothing to show" — same render path as a genuinely empty
// feed. When error UX gets richer we can switch to throwing.
//
// Pagination deferred for v1. `.limit(N)` plus
// `.order("ended_at", desc)` returns the N most-recent rows;
// when feeds get long enough to need infinite-scroll, we add
// cursor-based pagination (ended_at + id) here. For now N=50
// covers any realistic v1 feed without thrashing the
// network.
@MainActor
enum PublicRaceFeedService {

    // MARK: - Feed

    // Build the social feed for `userID` — recent public
    // races from the athletes they follow. Returns the
    // newest `limit` rows across the followed set, ordered
    // by race end time descending.
    //
    // Two round-trips:
    //   1. SELECT follower_user_id (= userID) from follows →
    //      list of followed user IDs
    //   2. SELECT * from public_races WHERE user_id IN (...)
    //      [AND ended_at < before]
    //      ORDER BY ended_at DESC LIMIT N
    //
    // Pagination is cursor-based on `ended_at`: the caller
    // passes `before:` set to the oldest race's ended_at they
    // already have, and we fetch the next chunk older than
    // that. Cursor over offset because feeds grow at the
    // head (new races appended) — offset-based pagination
    // would skip races as the head shifts.
    //
    // Returns [] if the user follows nobody (the first
    // query returns []) or on network failure.
    static func feed(
        followedBy userID: String,
        limit: Int = 25,
        before: Date? = nil,
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemotePublicRace] {
        let followedIDs = await FollowService.following(of: userID)
        guard !followedIDs.isEmpty else { return [] }

        do {
            let query = client
                .from("public_races")
                .select()
                .in("user_id", values: followedIDs)

            // PostgREST's strongly-typed builder doesn't let us
            // chain a conditional `.lt(...)` cleanly without
            // re-binding the var — split into the cursor and
            // first-page branches so each path stays linear.
            let rows: [RemotePublicRace]
            if let before {
                rows = try await query
                    .lt("ended_at", value: before)
                    .order("ended_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            } else {
                rows = try await query
                    .order("ended_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            }
            return rows
        } catch {
            return []
        }
    }

    // MARK: - Detail

    // Per-race detail fetch — hits `public_race_detail` (the
    // splits-projected view). Used by `PublicRaceDetailSheet`
    // when the user taps a feed card. Returns nil on
    // network failure or row-not-found (the race may have
    // been deleted between feed-fetch and detail-fetch).
    static func detail(
        forRaceID raceID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> RemotePublicRaceDetail? {
        do {
            let detail: RemotePublicRaceDetail = try await client
                .from("public_race_detail")
                .select()
                .eq("id", value: raceID)
                .single()
                .execute()
                .value
            return detail
        } catch {
            return nil
        }
    }

    // MARK: - Single user

    // Recent public races for ONE athlete. Used for
    // PublicProfileCard's "recent races" section (deferred
    // UI piece; service is ready when the UI lands).
    static func recent(
        forUserID userID: String,
        limit: Int = 5,
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemotePublicRace] {
        do {
            let rows: [RemotePublicRace] = try await client
                .from("public_races")
                .select()
                .eq("user_id", value: userID)
                .order("ended_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }
}

#else

@MainActor
enum PublicRaceFeedService {
    static func feed(followedBy userID: String, limit: Int = 25, before: Date? = nil) async -> [RemotePublicRace] { [] }
    static func recent(forUserID userID: String, limit: Int = 5) async -> [RemotePublicRace] { [] }
    static func detail(forRaceID raceID: String) async -> RemotePublicRaceDetail? { nil }
}

#endif

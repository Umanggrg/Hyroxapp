import Foundation
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// Lookup helper for `RemotePublicProfile` rows. Used anywhere
// the app needs to display info about another athlete — duo
// race partner names, future social feed cards, follow lists,
// public profile pages.
//
// Two lookup paths cover every entry point the UI has:
//   • lookup(userID:)  — when we already have the foreign-key
//                        UUID (e.g. duo_races.host_user_id)
//   • lookup(handle:)  — when we have the @handle (e.g. user
//                        types one in / taps a mention)
//
// Caller-side caching: this service intentionally has no cache.
// PostgREST + URLSession's HTTP cache + the small profile size
// make repeat fetches cheap. If/when we hit ratelimits or
// surface long lists of profiles in a feed, we add an
// in-memory cache here keyed by id.
//
// Errors: every method returns `nil` on failure rather than
// throwing — for v1 the caller's behavior is the same in
// either case (show a placeholder). When we have richer error
// surfaces (banners, retry UX), we'll switch to throwing
// signatures.
@MainActor
enum PublicProfileService {

    // Look up a public profile by Supabase user UUID. Returns
    // nil when the row doesn't exist or the network failed.
    // Caller should treat both as "show a generic placeholder."
    static func lookup(
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> RemotePublicProfile? {
        do {
            let profile: RemotePublicProfile = try await client
                .from("public_profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            return profile
        } catch {
            return nil
        }
    }

    // Look up a public profile by handle. Handles are stored
    // in their normalized lowercase form (see EditProfileView's
    // `normalizedHandle`); callers should pre-normalize the
    // search term so `@SARAH` and `Sarah` both resolve to the
    // same row.
    //
    // Returns nil when no match exists or the network failed.
    static func lookup(
        handle: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> RemotePublicProfile? {
        let normalized = handle
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard !normalized.isEmpty else { return nil }

        do {
            let profile: RemotePublicProfile = try await client
                .from("public_profiles")
                .select()
                .eq("handle", value: normalized)
                .single()
                .execute()
                .value
            return profile
        } catch {
            return nil
        }
    }

    // Fuzzy search across handle + display name. Returns up to
    // `limit` rows, ranked by Postgres default (insertion order
    // — good enough for v1; can swap to a relevance score when
    // we have enough users for it to matter).
    //
    // `.ilike` is case-insensitive LIKE with `%` wildcards on
    // either side, so typing "sar" matches "sarah" / "Sarah B"
    // / "musar". The `.or()` filter PostgREST exposes lets us
    // hit both columns in one round-trip — much simpler than
    // doing two SELECTs + merging client-side.
    //
    // Empty query returns []; this is a search box, not a "list
    // every user in the app" surface (RLS would deny that
    // anyway, but the empty-input semantics belongs here).
    //
    // Why this exists separately from `lookup(handle:)`: that
    // older method does an EXACT match for deep-linking flows
    // (`@sarah` mention → fetch that exact profile). Search is
    // discovery, exact lookup is navigation. Two different
    // intents; two different shapes.
    static func search(
        query: String,
        limit: Int = 20,
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemotePublicProfile] {
        let trimmed = query
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard !trimmed.isEmpty else { return [] }

        // Escape the user's query so a stray `%` or `,` doesn't
        // break the .or filter syntax. PostgREST treats `,` as
        // an argument separator inside .or(), and `%` is the
        // SQL wildcard — both need to be neutralized in user
        // input before we wrap with our own `%…%` pattern.
        let escaped = trimmed
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let pattern = "%\(escaped)%"

        do {
            let profiles: [RemotePublicProfile] = try await client
                .from("public_profiles")
                .select()
                .or("handle.ilike.\(pattern),display_name.ilike.\(pattern)")
                .limit(limit)
                .execute()
                .value
            return profiles
        } catch {
            return []
        }
    }

    // MARK: - Race stats

    // Look up race aggregates (count, PB, last race) for one
    // user. Returns nil when the user has no finished
    // non-private races OR on network failure — caller
    // renders the "No races yet" placeholder either way.
    //
    // The `public_race_stats` view's GROUP BY means a user
    // with zero eligible races simply doesn't appear in the
    // result set; `single()` errors which we map to nil.
    static func stats(
        for userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> RemotePublicRaceStats? {
        do {
            let stats: RemotePublicRaceStats = try await client
                .from("public_race_stats")
                .select()
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value
            return stats
        } catch {
            return nil
        }
    }

    // Bulk stats lookup — used when rendering many profiles
    // at once (followers list, future feed). Avoids N
    // round-trips. Same shape contract as `lookup(userIDs:)`
    // for profiles.
    static func stats(
        for userIDs: [String],
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemotePublicRaceStats] {
        guard !userIDs.isEmpty else { return [] }

        do {
            let rows: [RemotePublicRaceStats] = try await client
                .from("public_race_stats")
                .select()
                .in("user_id", values: userIDs)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    // Bulk lookup by a set of user IDs. Used by future feed /
    // follow-list surfaces that render N profiles at once and
    // want to avoid N round-trips.
    //
    // Returns the rows in whatever order Postgres returned them
    // (no guaranteed match to input order). Caller indexes by
    // `id` if order matters.
    static func lookup(
        userIDs: [String],
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemotePublicProfile] {
        guard !userIDs.isEmpty else { return [] }

        do {
            let profiles: [RemotePublicProfile] = try await client
                .from("public_profiles")
                .select()
                .in("id", values: userIDs)
                .execute()
                .value
            return profiles
        } catch {
            return []
        }
    }
}

#else

// Non-Supabase build (preview / unit-test targets without the
// SDK). Stub returns nil so call sites compile and degrade
// gracefully.
@MainActor
enum PublicProfileService {
    static func lookup(userID: String) async -> RemotePublicProfile? { nil }
    static func lookup(handle: String) async -> RemotePublicProfile? { nil }
    static func lookup(userIDs: [String]) async -> [RemotePublicProfile] { [] }
    static func search(query: String, limit: Int = 20) async -> [RemotePublicProfile] { [] }
    static func stats(for userID: String) async -> RemotePublicRaceStats? { nil }
    static func stats(for userIDs: [String]) async -> [RemotePublicRaceStats] { [] }
}

#endif

import Foundation
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// CRUD + lookups for the `follows` table. Every method takes
// the OTHER user's id as a parameter and pulls the local
// user's id from `AuthService.shared`; callers never have to
// thread `currentUserID` through.
//
// Error policy mirrors PublicProfileService: predicates return
// false on failure (treat as "not following / no data"), state
// mutations throw so the caller can revert optimistic UI on
// failure.
//
// No in-memory cache for v1 — calls are cheap and the surfaces
// using them (PublicProfileSearchSheet, future Profile counts)
// fire on view-appear, not per-frame. When the social feed
// lands and we render N follow states at once, a cache moves
// in here keyed by followed_user_id.
@MainActor
enum FollowService {

    enum FollowServiceError: Error {
        case notAuthenticated
        case selfFollowRejected
    }

    // MARK: - Mutations

    // Create a follow edge from the current user to `userID`.
    // Idempotent — the composite primary key on (follower,
    // followed) means a duplicate insert errors with 23505;
    // we swallow that case so the caller can call freely
    // without first checking isFollowing.
    static func follow(
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        let me = try requireUserID()
        guard me != userID else { throw FollowServiceError.selfFollowRejected }

        let row = RemoteFollow(
            followerUserId: me,
            followedUserId: userID,
            createdAt: nil
        )

        do {
            try await client
                .from("follows")
                .insert(row)
                .execute()
        } catch {
            // Duplicate-edge ON CONFLICT — Postgres returns
            // unique_violation (23505). PostgREST surfaces it
            // as a generic error in supabase-swift; we treat
            // any insert failure on an already-following edge
            // as a no-op. Re-check by fetching back, and if
            // the edge exists, swallow the error.
            //
            // Cheaper alternative: ON CONFLICT DO NOTHING at
            // the SQL level. We'd need an `upsert` variant in
            // the Swift SDK that maps to that — not standard.
            // For v1 the round-trip is acceptable.
            if await isFollowing(userID: userID, client: client) {
                return  // already-following: idempotent success
            }
            throw error
        }
    }

    // Remove the follow edge from the current user to
    // `userID`. Idempotent — deleting a row that doesn't
    // exist is a no-op in PostgREST.
    static func unfollow(
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        let me = try requireUserID()

        try await client
            .from("follows")
            .delete()
            .eq("follower_user_id", value: me)
            .eq("followed_user_id", value: userID)
            .execute()
    }

    // MARK: - Predicates

    // Is the current user following `userID`? Returns false on
    // error so the UI shows the safer state ("not following,
    // can follow") rather than locking the user out.
    static func isFollowing(
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> Bool {
        #if canImport(Auth)
        guard let me = AuthService.shared.user?.id.uuidString else {
            return false
        }
        #else
        return false
        #endif

        do {
            let rows: [RemoteFollow] = try await client
                .from("follows")
                .select()
                .eq("follower_user_id", value: me)
                .eq("followed_user_id", value: userID)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Lists + counts

    // All user IDs that `userID` follows. Returns [] on error.
    static func following(
        of userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> [String] {
        do {
            let rows: [RemoteFollow] = try await client
                .from("follows")
                .select()
                .eq("follower_user_id", value: userID)
                .execute()
                .value
            return rows.map(\.followedUserId)
        } catch {
            return []
        }
    }

    // All user IDs that follow `userID`. Returns [] on error.
    static func followers(
        of userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> [String] {
        do {
            let rows: [RemoteFollow] = try await client
                .from("follows")
                .select()
                .eq("followed_user_id", value: userID)
                .execute()
                .value
            return rows.map(\.followerUserId)
        } catch {
            return []
        }
    }

    // Both counts in one struct. Used by ProfileView to
    // replace the placeholder "—" social-stats cells.
    // Returns (0, 0) on error.
    static func counts(
        for userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> (followers: Int, following: Int) {
        async let followersList = followers(of: userID, client: client)
        async let followingList = following(of: userID, client: client)
        let (f, g) = await (followersList, followingList)
        return (f.count, g.count)
    }

    // MARK: - Helpers

    private static func requireUserID() throws -> String {
        #if canImport(Auth)
        guard let me = AuthService.shared.user?.id.uuidString else {
            throw FollowServiceError.notAuthenticated
        }
        return me
        #else
        throw FollowServiceError.notAuthenticated
        #endif
    }
}

#else

// Non-Supabase build (preview / unit-test targets without the
// SDK). Stubs degrade gracefully.
@MainActor
enum FollowService {
    enum FollowServiceError: Error {
        case notAuthenticated
        case selfFollowRejected
    }

    static func follow(userID: String) async throws {
        throw FollowServiceError.notAuthenticated
    }
    static func unfollow(userID: String) async throws {
        throw FollowServiceError.notAuthenticated
    }
    static func isFollowing(userID: String) async -> Bool { false }
    static func following(of userID: String) async -> [String] { [] }
    static func followers(of userID: String) async -> [String] { [] }
    static func counts(for userID: String) async -> (followers: Int, following: Int) {
        (0, 0)
    }
}

#endif

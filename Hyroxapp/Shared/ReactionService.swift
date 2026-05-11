import Foundation
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// CRUD + bulk lookups for the `reactions` table. Mirrors
// FollowService's shape — pulls the local user from
// AuthService.shared, never thread userID through call sites.
//
// Error policy:
//   • Mutations throw — caller can revert optimistic UI on
//     failure.
//   • Lookups return [] on failure — view treats empty as
//     "no reactions yet", same render path as a genuinely
//     empty race.
//
// Idempotency:
//   • react()  — the (race, user, kind) PK rejects duplicate
//                inserts with 23505. We catch and treat as
//                "already reacted, no-op success." Allows
//                fire-and-forget calls without pre-checking
//                state.
//   • unreact() — DELETE-WHERE returns 0 rows when none
//                 match; PostgREST surfaces that as success.
@MainActor
enum ReactionService {

    enum ReactionServiceError: Error {
        case notAuthenticated
    }

    // MARK: - Mutations

    // Add a reaction. Idempotent — re-reacting with the same
    // kind on the same race is a no-op success.
    static func react(
        raceID: String,
        kind: ReactionKind,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        let me = try requireUserID()
        let row = RemoteReaction(
            raceId: raceID,
            userId: me,
            kind: kind.rawValue,
            createdAt: nil
        )

        do {
            try await client
                .from("reactions")
                .insert(row)
                .execute()
        } catch {
            // Already-reacted is a no-op success; we can't
            // cleanly introspect PostgREST errors for 23505
            // without parsing the error message, so we
            // fall back to "verify by fetch + treat
            // matched-row as already-done."
            let mine = await myReactions(forRaceIDs: [raceID], client: client)
            if mine.contains(where: { $0.kind == kind.rawValue }) {
                return  // idempotent success
            }
            throw error
        }
    }

    // Remove a reaction. Idempotent — deleting an edge that
    // doesn't exist is a no-op.
    static func unreact(
        raceID: String,
        kind: ReactionKind,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        let me = try requireUserID()

        try await client
            .from("reactions")
            .delete()
            .eq("race_id", value: raceID)
            .eq("user_id", value: me)
            .eq("kind", value: kind.rawValue)
            .execute()
    }

    // MARK: - Lookups

    // All reactions on the given races, across all users.
    // Used by FeedView to compute counts per kind per race in
    // one round-trip.
    static func reactions(
        forRaceIDs raceIDs: [String],
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemoteReaction] {
        guard !raceIDs.isEmpty else { return [] }

        do {
            let rows: [RemoteReaction] = try await client
                .from("reactions")
                .select()
                .in("race_id", values: raceIDs)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    // Local user's reactions across the given races. Drives
    // the "you reacted" highlight on each reaction button.
    // Empty array on auth failure (UI degrades to "no
    // highlights" — equivalent to "not signed in").
    static func myReactions(
        forRaceIDs raceIDs: [String],
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemoteReaction] {
        guard !raceIDs.isEmpty else { return [] }

        #if canImport(Auth)
        guard let me = AuthService.shared.user?.id.uuidString else {
            return []
        }
        #else
        return []
        #endif

        do {
            let rows: [RemoteReaction] = try await client
                .from("reactions")
                .select()
                .in("race_id", values: raceIDs)
                .eq("user_id", value: me)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    // MARK: - Helpers

    private static func requireUserID() throws -> String {
        #if canImport(Auth)
        guard let me = AuthService.shared.user?.id.uuidString else {
            throw ReactionServiceError.notAuthenticated
        }
        return me
        #else
        throw ReactionServiceError.notAuthenticated
        #endif
    }
}

#else

@MainActor
enum ReactionService {
    enum ReactionServiceError: Error {
        case notAuthenticated
    }

    static func react(raceID: String, kind: ReactionKind) async throws {
        throw ReactionServiceError.notAuthenticated
    }
    static func unreact(raceID: String, kind: ReactionKind) async throws {
        throw ReactionServiceError.notAuthenticated
    }
    static func reactions(forRaceIDs raceIDs: [String]) async -> [RemoteReaction] { [] }
    static func myReactions(forRaceIDs raceIDs: [String]) async -> [RemoteReaction] { [] }
}

#endif

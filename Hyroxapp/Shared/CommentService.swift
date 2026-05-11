import Foundation
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// CRUD + lookups for the comments table / public_comments
// view. Same shape as ReactionService / FollowService —
// pulls local userID from AuthService.shared, swallow-and-
// return-empty on read failure, throw on write failure so
// callers can revert optimistic UI.
//
// Reads via the `public_comments` view (joined with
// profiles); writes via the underlying `comments` table.
// Postgres CHECK on body length (1–500 chars) is server-of-
// truth; clients enforce the same range client-side so the
// UI catches early.
@MainActor
enum CommentService {

    enum CommentServiceError: Error {
        case notAuthenticated
        case bodyEmpty
        case bodyTooLong
    }

    // MARK: - Constraints

    // Mirror the Postgres CHECK constraint client-side so
    // the UI catches violations before the round-trip.
    static let minBodyLength = 1
    static let maxBodyLength = 500

    // MARK: - Mutations

    // Post a comment. Validates length client-side first to
    // avoid wasting a round-trip on a known-bad body.
    static func post(
        raceID: String,
        body: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        let me = try requireUserID()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minBodyLength else {
            throw CommentServiceError.bodyEmpty
        }
        guard trimmed.count <= maxBodyLength else {
            throw CommentServiceError.bodyTooLong
        }

        let payload = RemoteCommentInsert(
            raceId: raceID,
            userId: me,
            body: trimmed
        )

        try await client
            .from("comments")
            .insert(payload)
            .execute()
    }

    // Delete a comment by id. RLS gates ownership — Postgres
    // returns "0 rows deleted" if the local user isn't the
    // commenter, which PostgREST surfaces as success. The
    // optimistic delete on the client will appear to work
    // either way; reload to see the truth.
    static func delete(
        commentID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        try await client
            .from("comments")
            .delete()
            .eq("id", value: commentID)
            .execute()
    }

    // MARK: - Lookups

    // All comments on a race, oldest first. Drives the
    // CommentsSheet thread. Joins via the public_comments
    // view to get commenter identity inline.
    static func comments(
        forRaceID raceID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async -> [RemoteComment] {
        do {
            let rows: [RemoteComment] = try await client
                .from("public_comments")
                .select()
                .eq("race_id", value: raceID)
                .order("created_at", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    // Counts for many races in one query — drives the
    // "💬 N" pill on each feed card without N round-trips.
    // Returns a dict keyed by race_id; missing keys = 0
    // comments.
    static func counts(
        forRaceIDs raceIDs: [String],
        client: SupabaseClient = SupabaseService.shared
    ) async -> [String: Int] {
        guard !raceIDs.isEmpty else { return [:] }

        // PostgREST doesn't expose `group by` directly; we
        // fetch the rows and bucket client-side. For typical
        // page sizes (25 cards × 0–20 comments each), this
        // is at most ~500 rows. Cheap.
        do {
            let rows: [RemoteComment] = try await client
                .from("public_comments")
                .select("id,race_id,user_id,body,created_at,commenter_display_name,commenter_handle,commenter_avatar_url")
                .in("race_id", values: raceIDs)
                .execute()
                .value
            var bucket: [String: Int] = [:]
            for row in rows {
                bucket[row.raceId, default: 0] += 1
            }
            return bucket
        } catch {
            return [:]
        }
    }

    // MARK: - Helpers

    private static func requireUserID() throws -> String {
        #if canImport(Auth)
        guard let me = AuthService.shared.user?.id.uuidString else {
            throw CommentServiceError.notAuthenticated
        }
        return me
        #else
        throw CommentServiceError.notAuthenticated
        #endif
    }
}

#else

@MainActor
enum CommentService {
    enum CommentServiceError: Error {
        case notAuthenticated
        case bodyEmpty
        case bodyTooLong
    }
    static let minBodyLength = 1
    static let maxBodyLength = 500

    static func post(raceID: String, body: String) async throws {
        throw CommentServiceError.notAuthenticated
    }
    static func delete(commentID: String) async throws {
        throw CommentServiceError.notAuthenticated
    }
    static func comments(forRaceID raceID: String) async -> [RemoteComment] { [] }
    static func counts(forRaceIDs raceIDs: [String]) async -> [String: Int] { [:] }
}

#endif

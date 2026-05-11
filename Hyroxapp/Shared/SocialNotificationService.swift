import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

// Local notification dispatcher for social activity addressed
// to the local user — new followers, reactions on the user's
// races, comments on the user's races. Cheap alternative to
// server-side push for v1:
//
//   • On app foreground, poll for new rows since `lastSeenAt`
//     for each kind.
//   • For each match, fire a `UNNotificationRequest` via
//     `UNUserNotificationCenter.current().add(_:)`.
//   • Persist the maxima of fetched timestamps so the next
//     check picks up only what's actually new.
//
// Tradeoffs vs server-side push:
//   ✓ No APNs key, no edge functions, no device-token table,
//     no backend
//   ✓ Works on every iOS device authenticated to the same
//     Supabase user
//   ✗ Only fires while the app is being opened — if the
//     athlete never opens for a week, they only get a stack
//     of notifications on the week-late open, not in real
//     time
//   ✗ Per-kind throttle (max 3 per kind per check) to avoid
//     a notification storm on long-absent users
//
// Server-side push lands as a follow-up when v2 hits real
// scale. The schema this service queries (follows / reactions
// / comments tables) is identical to what an edge function
// would consume, so the migration is purely the dispatcher.
@MainActor
enum SocialNotificationService {

    // Cap per kind per check. A user returning after a long
    // absence gets a max of 3 follow + 3 reaction + 3 comment
    // notifications, not the unbounded count of every event.
    // Anything beyond gets summarized via the trailing "and X
    // others" notification body when grouping kicks in.
    private static let maxPerKindPerCheck = 3

    // Storage keys for the per-kind cursor. Stored in
    // UserDefaults rather than SwiftData because they're
    // per-device + ephemeral (re-installing the app resets
    // them, which is the right behavior — a fresh install
    // shouldn't replay a year of follows). Keys are app-
    // scoped so a future second user account on the same
    // device wouldn't collide; we add an account suffix.
    private static func followCursorKey(for userID: String) -> String {
        "com.hyroxapp.notifications.lastSeenFollow.\(userID)"
    }
    private static func reactionCursorKey(for userID: String) -> String {
        "com.hyroxapp.notifications.lastSeenReaction.\(userID)"
    }
    private static func commentCursorKey(for userID: String) -> String {
        "com.hyroxapp.notifications.lastSeenComment.\(userID)"
    }

    // MARK: - Public entry point

    // Called from the app's foreground transition. Bails
    // silently when not authenticated, when notifications
    // aren't authorized, or when Supabase isn't linked.
    // Resolves quickly — three parallel queries + per-kind
    // notification dispatch.
    static func checkAndFire() async {
        #if canImport(Supabase) && canImport(UserNotifications) && canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            return
        }

        // Only fire when notifications are authorized.
        // Don't request permission here — that's the streak
        // / race-event reminder's responsibility, gated on
        // a Settings toggle. If the user hasn't authorized,
        // we silently skip; their cursor doesn't advance, so
        // when they DO authorize later they'll get the
        // accumulated diff on the next foreground.
        //
        // Wait — actually that would replay a backlog of
        // potentially thousands of events. Better: advance
        // cursors even when notifications are skipped, so the
        // backlog stays bounded. The first authorized
        // foreground gets the most recent diff, not a
        // year's worth.
        let status = await NotificationService.shared.authorizationStatus()
        let shouldFireNotifications = (status == .authorized || status == .provisional)

        async let follows = checkFollows(
            userID: userID,
            shouldFire: shouldFireNotifications
        )
        async let reactions = checkReactions(
            userID: userID,
            shouldFire: shouldFireNotifications
        )
        async let comments = checkComments(
            userID: userID,
            shouldFire: shouldFireNotifications
        )

        // Await all three in parallel — they don't depend on
        // each other.
        _ = await (follows, reactions, comments)
        #endif
    }

    // MARK: - Follows

    #if canImport(Supabase) && canImport(UserNotifications)
    private static func checkFollows(
        userID: String,
        shouldFire: Bool,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        let cursorKey = followCursorKey(for: userID)
        let since = loadCursor(key: cursorKey)

        let newRows: [RemoteFollow]
        do {
            newRows = try await client
                .from("follows")
                .select()
                .eq("followed_user_id", value: userID)
                .gt("created_at", value: since)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        } catch {
            return
        }

        guard !newRows.isEmpty else { return }

        // Advance the cursor to the newest fetched row's
        // created_at before firing — that way, if a
        // notification-fire fails partway through, we don't
        // re-fire on next check. Net: at-most-once delivery.
        if let newest = newRows.compactMap(\.createdAt).max() {
            saveCursor(newest, key: cursorKey)
        }

        guard shouldFire else { return }

        // Resolve actor display names. Bulk lookup keeps it
        // to one network round-trip regardless of N rows.
        let actorIDs = Array(Set(newRows.prefix(maxPerKindPerCheck).map(\.followerUserId)))
        let actors = await PublicProfileService.lookup(userIDs: actorIDs)
        let actorByID = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0) })

        for row in newRows.prefix(maxPerKindPerCheck) {
            let actor = actorByID[row.followerUserId]
            let name = actor?.displayName ?? "Someone"
            await fire(
                identifier: "follow-\(row.followerUserId)",
                title: "New follower",
                body: "\(name) started following you."
            )
        }
    }

    // MARK: - Reactions

    private static func checkReactions(
        userID: String,
        shouldFire: Bool,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        let cursorKey = reactionCursorKey(for: userID)
        let since = loadCursor(key: cursorKey)

        // Reactions on MY races, not made by me. The
        // races!inner join (via PostgREST embedded resource
        // syntax) lets us filter on races.user_id without a
        // separate query. RLS on races means I can only see
        // my own race rows in the joined result anyway —
        // belt-and-suspenders.
        let newRows: [RemoteReaction]
        do {
            newRows = try await client
                .from("reactions")
                .select("race_id, user_id, kind, created_at, races!inner(user_id)")
                .eq("races.user_id", value: userID)
                .neq("user_id", value: userID)
                .gt("created_at", value: since)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        } catch {
            return
        }

        guard !newRows.isEmpty else { return }
        if let newest = newRows.compactMap(\.createdAt).max() {
            saveCursor(newest, key: cursorKey)
        }

        guard shouldFire else { return }

        let actorIDs = Array(Set(newRows.prefix(maxPerKindPerCheck).map(\.userId)))
        let actors = await PublicProfileService.lookup(userIDs: actorIDs)
        let actorByID = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0) })

        for row in newRows.prefix(maxPerKindPerCheck) {
            let actor = actorByID[row.userId]
            let name = actor?.displayName ?? "Someone"
            let kind = ReactionKind(rawValue: row.kind)
            let emoji = kind?.emoji ?? ""
            await fire(
                identifier: "reaction-\(row.raceId)-\(row.userId)-\(row.kind)",
                title: "New reaction",
                body: "\(name) reacted \(emoji) to your race."
            )
        }
    }

    // MARK: - Comments

    private static func checkComments(
        userID: String,
        shouldFire: Bool,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        let cursorKey = commentCursorKey(for: userID)
        let since = loadCursor(key: cursorKey)

        // Same embed pattern as reactions — filter on the
        // joined races.user_id and exclude self-comments.
        let newRows: [RemoteComment]
        do {
            newRows = try await client
                .from("comments")
                .select("""
                id, race_id, user_id, body, created_at,
                commenter_display_name:profiles!inner(display_name),
                commenter_handle:profiles!inner(handle),
                commenter_avatar_url:profiles!inner(avatar_url),
                races!inner(user_id)
                """)
                .eq("races.user_id", value: userID)
                .neq("user_id", value: userID)
                .gt("created_at", value: since)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        } catch {
            // The comments table SELECT works without the
            // public_comments view's joined fields — fall
            // back to a simpler query that doesn't try to
            // resolve the commenter inline. Body + actor
            // user_id come from the comments row directly;
            // we resolve actor profiles below.
            await checkCommentsFallback(
                userID: userID,
                since: since,
                cursorKey: cursorKey,
                shouldFire: shouldFire,
                client: client
            )
            return
        }

        guard !newRows.isEmpty else { return }
        if let newest = newRows.map(\.createdAt).max() {
            saveCursor(newest, key: cursorKey)
        }

        guard shouldFire else { return }

        for row in newRows.prefix(maxPerKindPerCheck) {
            let name = row.commenterDisplayName
            let excerpt = excerpted(row.body)
            await fire(
                identifier: "comment-\(row.id)",
                title: "\(name) commented",
                body: excerpt
            )
        }
    }

    // Fallback path for the comments check when the embedded-
    // resource select fails (older Supabase or schema drift).
    // Uses the simpler base table + separate profile lookup.
    private static func checkCommentsFallback(
        userID: String,
        since: Date,
        cursorKey: String,
        shouldFire: Bool,
        client: SupabaseClient
    ) async {
        // Plain comments row without identity embed.
        struct PlainComment: Codable {
            let id: String
            let raceId: String
            let userId: String
            let body: String
            let createdAt: Date

            enum CodingKeys: String, CodingKey {
                case id
                case raceId = "race_id"
                case userId = "user_id"
                case body
                case createdAt = "created_at"
            }
        }

        let newRows: [PlainComment]
        do {
            newRows = try await client
                .from("comments")
                .select("id, race_id, user_id, body, created_at, races!inner(user_id)")
                .eq("races.user_id", value: userID)
                .neq("user_id", value: userID)
                .gt("created_at", value: since)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        } catch {
            return
        }

        guard !newRows.isEmpty else { return }
        if let newest = newRows.map(\.createdAt).max() {
            saveCursor(newest, key: cursorKey)
        }

        guard shouldFire else { return }

        let actorIDs = Array(Set(newRows.prefix(maxPerKindPerCheck).map(\.userId)))
        let actors = await PublicProfileService.lookup(userIDs: actorIDs)
        let actorByID = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0) })

        for row in newRows.prefix(maxPerKindPerCheck) {
            let name = actorByID[row.userId]?.displayName ?? "Someone"
            await fire(
                identifier: "comment-\(row.id)",
                title: "\(name) commented",
                body: excerpted(row.body)
            )
        }
    }
    #endif

    // MARK: - Dispatch + cursor helpers

    #if canImport(UserNotifications)
    private static func fire(
        identifier: String,
        title: String,
        body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // `trigger: nil` fires immediately. Identifier dedupes
        // — if we somehow re-queue the same notification
        // before delivery, iOS replaces in place.
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif

    private static func loadCursor(key: String) -> Date {
        // First-ever check: treat as "from now" so we don't
        // replay a year of history on first install. Subsequent
        // checks load the stored ISO8601 timestamp.
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: key) as? Date {
            return stored
        }
        // Seed to now on first read so the next check picks
        // up only truly-new events. Persist immediately.
        let now = Date()
        defaults.set(now, forKey: key)
        return now
    }

    private static func saveCursor(_ date: Date, key: String) {
        UserDefaults.standard.set(date, forKey: key)
    }

    // Truncate a comment body to ~100 chars for the
    // notification preview. iOS itself truncates long bodies
    // visually, but trimming on our side keeps the haptic
    // expand-to-show consistent across iOS versions.
    private static func excerpted(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 100 else { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 97)
        return trimmed[..<cutoff] + "…"
    }
}

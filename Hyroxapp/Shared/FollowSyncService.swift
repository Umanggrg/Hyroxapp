import Foundation
#if canImport(Supabase)
import Supabase
import Realtime
#endif

// §16 — Supabase Realtime subscription on the `follows` table,
// filtered to rows that involve the currently-signed-in user
// (either as follower or as followed). Drives reactive updates
// across follower-list surfaces so a viewer staring at their
// FollowersListView sees a new entry pop in when another user
// follows them, without a pull-to-refresh.
//
// Design pattern: token-based observation rather than payload
// broadcasting. The service exposes monotonically-increasing
// counters (`followingChangeToken`, `followerChangeToken`) that
// SwiftUI views can `.onChange(of:)`-watch. When a counter
// ticks, the view re-fetches via the existing `FollowService`
// query helpers. This avoids:
//
//   • Sharing decoded Postgres row payloads across files (the
//     SDK's row format isn't 1:1 with our RemoteFollow shape
//     for all event kinds).
//   • Diverging optimistic / authoritative state — every
//     surface continues to use FollowService as the single
//     source of truth; Realtime is just an invalidation
//     signal.
//   • Coupling tightly to the Realtime payload structure if
//     the SDK changes it across versions.
//
// Lifecycle: started on auth state change (signin), stopped on
// signout. Re-subscribed when the user_id changes (e.g.
// account switch in v2+). The singleton observes
// AuthService.shared.user via the auth callback wiring set
// up by HyroxappApp on launch.
//
// Forward-compat for Duo Tier 2: the channel-per-user pattern
// established here is the same shape the cloud Duo Mode
// already uses for room channels (see CloudDuoSession).
// Re-using the conventions keeps the realtime architecture
// coherent across the app.
//
// Only iOS/macOS — watchOS doesn't subscribe to Realtime
// (the watch is a thin client mirroring race state from the
// iPhone; follower changes don't impact wrist UX).
#if canImport(Supabase)

@MainActor
@Observable
final class FollowSyncService {

    static let shared = FollowSyncService()

    // Monotonic counter for outgoing-follow changes (rows where
    // the local user is the `follower_user_id`). Bumped on every
    // postgres_changes event matching the filter — insert,
    // update (unused today but defensive), or delete. SwiftUI
    // views .onChange-watch this and re-fetch via
    // FollowService.following(of:) when it ticks.
    private(set) var followingChangeToken: Int = 0

    // Monotonic counter for incoming-follow changes (rows where
    // the local user is the `followed_user_id`). Same semantics
    // as `followingChangeToken` — drives FollowersListView and
    // profile follower-count re-fetches.
    //
    // Separate from followingChangeToken because the two flows
    // are observed by different views; bumping only the one
    // that actually changed minimizes spurious re-fetches.
    private(set) var followerChangeToken: Int = 0

    // Last-seen event metadata. Optional; consumers that want
    // the lightweight "what changed" hint (e.g. for a future
    // toast: "Alice followed you") can read this. Most consumers
    // just watch the token. Cleared on stop().
    private(set) var lastEvent: Event?

    // The user_id this service is currently subscribed for.
    // Tracking it lets `start(forUserID:)` skip a no-op
    // resubscribe when the auth state churns without actually
    // changing user.
    private var subscribedUserID: String?

    // Active Realtime channel. RealtimeChannelV2 owns the
    // websocket lifecycle for this topic. Held strongly while
    // subscribed; nil between start/stop or when subscribe
    // fails. Same pattern CloudDuoSession uses for its room
    // channel.
    private var channel: RealtimeChannelV2?

    // Background tasks consuming the channel's postgres_changes
    // streams. Cancelled on stop() so the websocket subscription
    // can tear down cleanly.
    private var followerStreamTask: Task<Void, Never>?
    private var followingStreamTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    /// Subscribe to follow changes for the given user. Idempotent
    /// — calling with the already-subscribed user is a no-op.
    /// Calling with a different user first tears down the old
    /// subscription so we don't accidentally observe two users'
    /// channels at once.
    ///
    /// `forUserID` is the authenticated user's UUID string —
    /// typically `AuthService.shared.user?.id.uuidString`.
    func start(
        forUserID userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        if subscribedUserID == userID, channel != nil {
            return  // already subscribed for this user
        }
        if subscribedUserID != nil {
            await stop()
        }
        subscribedUserID = userID

        let topic = "follow-sync:\(userID)"
        let newChannel = client.channel(topic)
        channel = newChannel

        // Outgoing follows (this user → others). Filter pins the
        // postgres_changes subscription to rows where this user
        // is the follower, so we only get callbacks for OUR
        // outgoing edges — not every follow happening in the
        // whole `follows` table.
        let outgoing = newChannel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "follows",
            filter: "follower_user_id=eq.\(userID)"
        )

        // Incoming follows (others → this user). Same filter
        // shape on the opposite column.
        let incoming = newChannel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "follows",
            filter: "followed_user_id=eq.\(userID)"
        )

        // Consume both streams in their own tasks so a slow
        // consumer of one doesn't backpressure the other.
        followingStreamTask = Task { [weak self] in
            for await action in outgoing {
                guard let self else { return }
                await self.handleAction(action, kind: .outgoing)
            }
        }
        followerStreamTask = Task { [weak self] in
            for await action in incoming {
                guard let self else { return }
                await self.handleAction(action, kind: .incoming)
            }
        }

        // Open the websocket + join the topic. The streams above
        // start receiving events as soon as this completes. Error
        // path: keep subscribedUserID set so the caller's retry
        // doesn't immediately short-circuit on the
        // already-subscribed guard at the top — but null the
        // channel so a retry creates a fresh one.
        do {
            try await newChannel.subscribeWithError()
        } catch {
            // Subscribe failed — best-effort tear down. The
            // app continues to work, just without Realtime
            // follow sync. Pull-to-refresh fallback remains.
            channel = nil
            followingStreamTask?.cancel()
            followerStreamTask?.cancel()
            followingStreamTask = nil
            followerStreamTask = nil
            subscribedUserID = nil
        }
    }

    /// Tear down the active subscription. Safe to call when
    /// not subscribed.
    func stop() async {
        followingStreamTask?.cancel()
        followerStreamTask?.cancel()
        followingStreamTask = nil
        followerStreamTask = nil
        if let existing = channel {
            await existing.unsubscribe()
        }
        channel = nil
        subscribedUserID = nil
        lastEvent = nil
    }

    // MARK: - Event handling

    enum Direction {
        case outgoing
        case incoming
    }

    enum Kind {
        case insert
        case delete
        case update
    }

    struct Event: Equatable {
        let direction: Direction
        let kind: Kind
        let occurredAt: Date
    }

    private func handleAction(_ action: AnyAction, kind: Direction) async {
        // Classify the row event. `AnyAction` is the SDK's
        // erased shape that wraps insert / update / delete
        // payloads; switching on the underlying type tells us
        // which kind fired. Inserts mean "new follow," deletes
        // mean "unfollow." Updates on the follows table are
        // rare (no UPDATE path in FollowService) but harmless
        // — we treat them the same as inserts for token
        // bookkeeping.
        let eventKind: Kind
        switch action {
        case .insert:
            eventKind = .insert
        case .delete:
            eventKind = .delete
        case .update:
            eventKind = .update
        default:
            return
        }

        let event = Event(
            direction: kind,
            kind: eventKind,
            occurredAt: Date()
        )
        lastEvent = event

        switch kind {
        case .outgoing:
            followingChangeToken &+= 1
        case .incoming:
            followerChangeToken &+= 1
        }
    }
}

#else

// Compile-stub for builds without the Supabase SDK (test
// environments, etc.). Same interface, no-op everything.
@MainActor
@Observable
final class FollowSyncService {
    static let shared = FollowSyncService()
    private(set) var followingChangeToken: Int = 0
    private(set) var followerChangeToken: Int = 0
    private init() {}
    func start(forUserID: String) async {}
    func stop() async {}
}

#endif

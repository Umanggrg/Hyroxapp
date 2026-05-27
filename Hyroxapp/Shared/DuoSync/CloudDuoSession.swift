import Foundation
#if canImport(Supabase)
import Supabase
import Realtime
import PostgREST
#endif

#if canImport(Supabase)

// Tier 2 cloud-backed Duo session — the cross-city counterpart
// to `DuoSession` (Multipeer / Tier 1). Keeps the same wire
// protocol (`DuoMessage`) so the coordinator + race controller
// + pairing UI can be made transport-agnostic via a future
// `DuoTransport` protocol (next session's refactor).
//
// Architecture:
//   • Pairing — host INSERTs a `duo_races` row with a random
//     6-char code; guest types the code, finds the row, UPDATEs
//     setting guest_user_id = themselves.
//   • Messaging — both clients subscribe to a Supabase Realtime
//     broadcast channel named `duo-room:{room_id}`. Every
//     `DuoMessage` (advance / pause / state update / HR / hello)
//     gets sent as one broadcast event with a JSON payload.
//   • Discovery — when the guest's `hello` broadcast arrives at
//     the host, the host knows pairing is complete and promotes
//     to .connected. Symmetric: the guest sees the host's
//     `hello` and does the same.
//
// Why broadcast over Postgres-changes for in-race messages?
// Race events (advance, HR ticks, state updates) fire many
// times per minute. Writing each into a Postgres row would
// thrash the trigger + RLS + WAL pipeline for no real durability
// benefit — duo races are inherently ephemeral. Broadcast is
// the right tool: low-latency pub/sub, no Postgres writes per
// message. The `duo_races` row stays as the room metadata only
// (host/guest/status/timing).
//
// State model — same shape as DuoSession's, with cloud-specific
// transitions instead of advertise/browse:
//
//   .idle                — nothing started
//   .creatingRoom        — host: INSERT in flight
//   .hostingRoom(code)   — host: row created + channel subscribed,
//                          waiting for guest's hello
//   .joiningRoom         — guest: SELECT + UPDATE in flight
//   .connected(peerName) — hello exchanged, ready for race
//   .disconnected(reason)
//
// Threading: Realtime callbacks come back as async streams from
// MainActor-friendly Tasks; we mutate `@Observable` state on the
// MainActor so SwiftUI sees consistent values. Same pattern as
// DuoSession.
@Observable
@MainActor
final class CloudDuoSession {

    // Mirrors `DuoSession.State` semantics where it makes sense.
    // Cases that don't apply to cloud (advertising/browsing) are
    // replaced with cloud-specific equivalents.
    enum State: Equatable {
        case idle
        case creatingRoom
        case hostingRoom(code: String)
        case joiningRoom
        case connected(peerName: String)
        case disconnected(reason: String?)
    }

    // Public state, observed by views.
    private(set) var state: State = .idle

    // Pair code displayed to the host once the room exists.
    // Host UI binds to this and renders it as a 6-digit pill.
    // Nil before the room is created or after disconnect.
    private(set) var pairCode: String?

    // The partner's display name + division, populated after
    // their `hello` broadcast arrives. Same fields as
    // DuoSession's so a future transport protocol can expose
    // them uniformly.
    private(set) var partnerName: String?
    private(set) var partnerDivisionRaw: String?

    // Supabase user UUID of the partner. Populated from the
    // duo_races row directly — for the guest from the
    // `select` response in `joinRoom` (the row's host_user_id),
    // for the host from a row refetch fired after the guest's
    // hello arrives (reads guest_user_id). Distinct from the
    // partner's display name; this is what RaceCardView uses
    // to deep-link into the partner's public profile.
    //
    // Stays nil until the partner actually joins (host before
    // hello, or any state pre-pairing). Stamped onto Race rows
    // at finish via `DuoRaceController.broadcastCurrent`.
    private(set) var partnerUserID: String?

    // Inbound message handler — set by the coordinator that
    // wraps this session. Called on MainActor for every
    // successfully-decoded DuoMessage.
    var onReceive: (@MainActor @Sendable (DuoMessage) -> Void)?

    // Local user identity. Used in our own `hello` broadcast so
    // the partner can render "Connected to X" — symmetric with
    // DuoSession.
    private let localDisplayName: String
    private let localDivisionRaw: String
    private let localUserID: String

    // Active room metadata. Populated after startHosting() or
    // joinRoom() succeeds.
    private var roomID: String?

    // Active broadcast channel. Held strongly so the underlying
    // websocket stays subscribed for the duration of the
    // session. Released on disconnect().
    private var channel: RealtimeChannelV2?

    // Cancellation handle for the receive-loop Task. Stored so
    // disconnect() can tear it down cleanly.
    private var receiveTask: Task<Void, Never>?

    // Whether this session has already broadcast its `hello`
    // payload at least once during the current pairing. Gates
    // the auto-reply in `handleBroadcastEvent` so the host
    // replies exactly once and the guest doesn't re-broadcast
    // when it receives the host's reciprocal hello.
    //
    // Why this matters: Supabase Realtime broadcasts don't
    // loop back to the sender by default. With an unconditional
    // auto-reply, every received hello would generate a fresh
    // outbound hello to the other side — which would generate
    // another inbound, ad infinitum. Each side broadcasts hello
    // exactly once: guest from `joinRoom` step 4, host from
    // its receive handler when the guest's hello lands.
    private var hasSentHello = false

    // The Supabase client. Default to the shared singleton; let
    // tests inject a mock by initializing with their own client.
    private let client: SupabaseClient

    // Channel-level event name we send DuoMessage payloads
    // under. Constant — both sides agree, the receiver filters
    // on this event so unrelated broadcasts (presence, etc.)
    // don't trip the decoder.
    private static let messageEvent = "duo-message"

    // MARK: - Init

    init(
        localDisplayName: String,
        localDivisionRaw: String,
        localUserID: String,
        client: SupabaseClient = SupabaseService.shared
    ) {
        self.localDisplayName = localDisplayName
        self.localDivisionRaw = localDivisionRaw
        self.localUserID = localUserID
        self.client = client
    }

    // No deinit. Swift 6 strict concurrency rejects nonisolated
    // access to MainActor-isolated `receiveTask`, and the receive
    // loop's `[weak self]` capture means the Task dies naturally
    // on the next iteration once `self` deallocates. Explicit
    // teardown happens via `disconnect()`; nothing else to clean
    // up here.

    // MARK: - Host

    // Create a new duo room. INSERTs a row in `duo_races`,
    // generates a random pair code (retries on the rare unique-
    // constraint collision), then opens the broadcast channel.
    //
    // After this returns, `state` is either `.hostingRoom(code)`
    // or `.disconnected(reason)`. View binds `state` and renders
    // the code on success.
    func startHosting() async {
        state = .creatingRoom

        // Try up to 5 times to insert with a fresh random code.
        // 887M-code space + low concurrent load means a collision
        // is astronomically unlikely; this is purely defensive.
        var lastError: Error?
        for _ in 0..<5 {
            let code = DuoRoomCode.random()
            let payload = RemoteDuoRaceInsert(
                pairCode: code,
                hostUserId: localUserID,
                status: "waiting"
            )

            do {
                let row: RemoteDuoRace = try await client
                    .from("duo_races")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                    .value

                // Insert succeeded — row carries the server-
                // assigned id and timestamps.
                roomID = row.id
                pairCode = row.pairCode
                await openChannel(roomID: row.id)
                state = .hostingRoom(code: row.pairCode)
                return
            } catch {
                lastError = error
                // Retry on duplicate-key; bail on anything else.
                // PostgREST surfaces unique-violation as code
                // 23505. We don't have clean error introspection
                // for the supabase-swift client today, so we
                // retry generically — at most 5 tries — and
                // fall through to a real error after.
                continue
            }
        }

        state = .disconnected(
            reason: "Couldn't create room: \(lastError?.localizedDescription ?? "unknown")"
        )
    }

    // MARK: - Join

    // Look up a waiting room by its pair code and claim it.
    // Three steps under the hood:
    //   1. SELECT the row by pair_code (RLS allows this for
    //      waiting rooms).
    //   2. UPDATE setting guest_user_id = self + status = 'paired'.
    //      RLS allows the claim because status was 'waiting'
    //      and guest_user_id was null.
    //   3. Open the broadcast channel.
    //   4. Send our `hello` so the host promotes to `.connected`.
    //
    // After this returns, `state` is either still `.joiningRoom`
    // (waiting for the host's hello back) or `.disconnected` on
    // failure. The host's hello arrival promotes us to
    // `.connected(peerName)`.
    func joinRoom(code: String) async {
        state = .joiningRoom

        // Defense-in-depth: normalize the code at the session
        // boundary too. The pairing view's `attemptJoin` already
        // passes the validated/normalized form, but callers in
        // tests or future entry points may not — and a single
        // stray lowercase character or whitespace silently
        // turns a correct code into a 0-rows lookup. Cheap to
        // do twice, expensive to debug if it's missing.
        let normalizedCode = DuoRoomCode.normalize(code)

        // 1) SELECT the waiting room.
        //
        // We deliberately avoid `.single()` here. PostgREST's
        // `.single()` collapses three very different conditions
        // into one indistinguishable error: (a) no row matched,
        // (b) RLS denied the read, (c) the row decoded to the
        // wrong shape. The old generic "Code not found or room
        // is no longer waiting" message was almost always
        // misleading — most production failures are actually
        // an un-deployed RLS policy or a Realtime/auth glitch,
        // not a typo.
        //
        // Switch to `.limit(1)` and decode into `[RemoteDuoRace]`.
        // Then:
        //   • Empty array         → "Code not found..." (legit)
        //   • Thrown error        → network / decode / RLS — surface
        //                            the real message so the user
        //                            sees what to fix.
        let matchingRooms: [RemoteDuoRace]
        do {
            matchingRooms = try await client
                .from("duo_races")
                .select()
                .eq("pair_code", value: normalizedCode)
                .eq("status", value: "waiting")
                .limit(1)
                .execute()
                .value
        } catch {
            // Real backend error — RLS denial, network failure,
            // missing table, etc. Surface the actual error so the
            // user (or a tester) has a fighting chance to debug.
            state = .disconnected(
                reason: "Couldn't reach the room: \(error.localizedDescription)"
            )
            return
        }

        guard let waitingRoom = matchingRooms.first else {
            // SELECT succeeded but no row matched — the code is
            // wrong OR the host's row has already been claimed by
            // someone else / abandoned / finished. Show the
            // historical message verbatim.
            state = .disconnected(
                reason: "Code not found or room is no longer waiting"
            )
            return
        }

        // 2) Claim the room (UPDATE guest + status). The UPDATE
        // is also gated by RLS (`duo_races_update_join`) — if
        // that policy is missing or the row was claimed between
        // our SELECT and UPDATE, the request returns 0 rows.
        // Chain `.select()` after the update so PostgREST sends
        // back the affected rows; without it, a zero-row UPDATE
        // looks indistinguishable from a successful one and we'd
        // open the channel only to never see the host's hello.
        // The extra `.eq("status", "waiting")` filter on the
        // UPDATE is a defensive concurrency guard — if another
        // guest claimed the row a few ms before us, status is
        // already 'paired' and our UPDATE matches 0 rows.
        let claim = RemoteDuoRaceUpdate(
            guestUserId: localUserID,
            status: "paired",
            startedAt: nil,
            endedAt: nil
        )
        let claimedRows: [RemoteDuoRace]
        do {
            claimedRows = try await client
                .from("duo_races")
                .update(claim)
                .eq("id", value: waitingRoom.id)
                .eq("status", value: "waiting")
                .select()
                .execute()
                .value
        } catch {
            state = .disconnected(
                reason: "Couldn't join room: \(error.localizedDescription)"
            )
            return
        }

        guard !claimedRows.isEmpty else {
            // Either RLS denied the claim (the policy is missing
            // or scoped wrong) or another guest beat us to it in
            // the last few milliseconds. Either way, the host
            // isn't going to receive our hello.
            state = .disconnected(
                reason: "Room was claimed by someone else or pairing is unavailable. Try again."
            )
            return
        }

        // 3) Open the channel.
        roomID = waitingRoom.id
        pairCode = waitingRoom.pairCode
        // Guest learns the partner's UUID directly from the row
        // — the host is the only other user_id on the row at
        // this point (the guest hasn't been written yet via
        // the UPDATE above; for the SELECT response we read,
        // host_user_id is the only candidate).
        partnerUserID = waitingRoom.hostUserId
        await openChannel(roomID: waitingRoom.id)

        // 4) Send hello so the host's UI promotes to .connected.
        // We don't promote our own state to .connected yet — we
        // wait for the host's reciprocal hello so we know the
        // channel is healthy in both directions.
        sendHello()
    }

    // MARK: - Send

    // Broadcast a `DuoMessage` on the active channel. No-op when
    // there's no channel (idle / disconnected) — same forgiving
    // contract as DuoSession.send.
    func send(_ message: DuoMessage) {
        guard let channel else { return }
        let data = message.encode()
        let base64 = data.base64EncodedString()

        // Realtime broadcast payloads are JSON objects. We
        // wrap our DuoMessage's encoded bytes inside a single
        // string-keyed field. Base64 keeps things ASCII-clean
        // for the JSON encoder; the decode side reverses.
        Task { [weak self] in
            do {
                try await channel.broadcast(
                    event: Self.messageEvent,
                    message: ["payload": AnyJSON.string(base64)]
                )
            } catch {
                // Broadcast errors are non-fatal — the next
                // message attempt will retry the underlying
                // socket. Log via assertionFailure in debug so
                // we notice if this becomes systemic.
                #if DEBUG
                print("CloudDuoSession.broadcast failed: \(error)")
                #endif
                _ = self  // silence unused-capture warning
            }
        }
    }

    // Convenience for the hello-on-connect handshake. Symmetric
    // with `DuoCoordinator.sendHello()`. Idempotent — once per
    // session — to break the auto-reply ping-pong (see the
    // `hasSentHello` doc comment for why).
    func sendHello() {
        guard !hasSentHello else { return }
        hasSentHello = true
        send(.hello(
            displayName: localDisplayName,
            divisionRaw: localDivisionRaw
        ))
    }

    // MARK: - Disconnect

    // Tear down the channel and reset state. Idempotent.
    func disconnect() {
        send(.disconnect)

        receiveTask?.cancel()
        receiveTask = nil

        if let channel {
            Task {
                await channel.unsubscribe()
            }
        }
        channel = nil

        // Optionally update the room status to 'abandoned' so
        // the partner's row-watching UI knows we left. Best-
        // effort; if the network's down, the partner detects
        // disconnect via the `.disconnect` broadcast above (or
        // a receive-stream timeout).
        if let roomID {
            let abandon = RemoteDuoRaceUpdate(
                guestUserId: nil,
                status: "abandoned",
                startedAt: nil,
                endedAt: nil
            )
            Task { [client, roomID] in
                try? await client
                    .from("duo_races")
                    .update(abandon)
                    .eq("id", value: roomID)
                    .execute()
            }
        }

        roomID = nil
        pairCode = nil
        partnerName = nil
        partnerDivisionRaw = nil
        partnerUserID = nil
        // Reset the one-shot hello gate so a fresh pairing
        // attempt (Tier 1 cancel → re-host, or guest cancel →
        // re-join) can send hello again. Without this, a
        // re-paired session would silently never identify
        // itself to the partner.
        hasSentHello = false
        state = .disconnected(reason: nil)
    }

    // One-shot fetch of the duo_races row to read whichever of
    // host_user_id / guest_user_id is NOT us. Called by the
    // host after the guest's hello arrives — at that point the
    // row's guest_user_id has been populated by the guest's
    // claim UPDATE and we can read it. Idempotent; bails if
    // partnerUserID is already set.
    private func refetchPartnerUserID(roomID: String) async {
        guard partnerUserID == nil else { return }

        do {
            let row: RemoteDuoRace = try await client
                .from("duo_races")
                .select()
                .eq("id", value: roomID)
                .single()
                .execute()
                .value
            // Pick whichever side isn't us. The local user is
            // whichever endpoint matches `localUserID`; the
            // partner is the other.
            if row.hostUserId == localUserID {
                partnerUserID = row.guestUserId
            } else if row.guestUserId == localUserID {
                partnerUserID = row.hostUserId
            }
        } catch {
            // Non-fatal — partner-tap UX degrades to "name
            // only, not tappable." Acceptable for v1 since
            // this path only fires once per duo race start.
        }
    }

    // MARK: - Channel plumbing

    // Subscribe to `duo-room:{id}` and start the receive loop.
    // Idempotent — replaces any existing channel reference.
    private func openChannel(roomID: String) async {
        // Tear down any prior channel.
        receiveTask?.cancel()
        if let existing = channel {
            await existing.unsubscribe()
        }

        let topic = "duo-room:\(roomID)"
        let newChannel = client.channel(topic)
        channel = newChannel

        // Receive loop — async stream of broadcast events.
        // Stored as a Task so disconnect() can cancel it. The
        // task captures `newChannel` strongly to keep the
        // websocket alive even if the SDK's caller-side ref
        // gets dropped; we hold one in `self.channel` too for
        // outbound sends.
        let stream = newChannel.broadcastStream(event: Self.messageEvent)
        receiveTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handleBroadcastEvent(event)
            }
        }

        // Subscribe — opens the websocket if not already open
        // and joins this topic. Throws on transport failure,
        // which we surface via `state` so the view can show
        // an error banner. Channel reference is dropped on
        // failure to keep `state` and `channel` consistent.
        do {
            try await newChannel.subscribeWithError()
        } catch {
            channel = nil
            receiveTask?.cancel()
            receiveTask = nil
            state = .disconnected(
                reason: "Realtime subscribe failed: \(error.localizedDescription)"
            )
        }
    }

    // Decode a single broadcast event and dispatch it to the
    // onReceive callback (after consuming hello internally).
    private func handleBroadcastEvent(_ event: JSONObject) async {
        // Payload shape (matches `send`): { "payload": "<base64>" }
        guard let payloadValue = event["payload"],
              case let .string(base64) = payloadValue,
              let data = Data(base64Encoded: base64),
              let message = DuoMessage.decode(data)
        else {
            return
        }

        // Hello is processed here so the session's @Observable
        // state + partner fields are updated atomically before
        // anyone else sees the message. After the stash, we ALSO
        // forward hello through `onReceive` — without that step
        // the higher-level coordinator never gets a "the
        // handshake completed" trigger and its `.ready` state
        // never flips. Tier 1 (`DuoSession`) does the same:
        // intercept-then-forward.
        switch message {
        case let .hello(displayName, divisionRaw):
            partnerName = displayName
            partnerDivisionRaw = divisionRaw
            state = .connected(peerName: displayName)
            // If we're the host who hadn't yet sent our own
            // hello, send it now so the guest knows we
            // received them. Idempotent send — multiple
            // hellos on the wire are harmless because the
            // receiver just re-sets the same partner fields.
            sendHello()

            // Host needs the partner's UUID for stamping onto
            // the Race row at finish. The duo_races row's
            // guest_user_id has just been populated by the
            // guest's claim UPDATE; one refetch gets it. Skip
            // when we already know the partner's UUID (guest
            // path, set in joinRoom — host fetches once and
            // is done).
            if partnerUserID == nil, let roomID {
                await refetchPartnerUserID(roomID: roomID)
            }

            // CRITICAL: forward hello to the coordinator so it
            // can promote its CoordState from .joining/.hosting
            // to .ready. The coordinator reads `session.state`
            // and `session.partnerDivisionRaw` (both already
            // set above) when this callback fires, so the
            // promote check has everything it needs.
            onReceive?(message)

        case .disconnect:
            // Partner deliberately left. Best-effort tear down
            // our side so the UI surfaces a clean state.
            state = .disconnected(reason: "Partner left")
            // Don't auto-disconnect() here — let the
            // coordinator (or view) decide whether to
            // continue solo or fully disengage.
            onReceive?(message)

        default:
            onReceive?(message)
        }
    }
}

#else

// Non-Supabase build (preview / macOS / unit-test targets that
// don't link the SDK). Stub to keep call sites compiling.
@MainActor
final class CloudDuoSession {
    enum State: Equatable {
        case idle
        case creatingRoom
        case hostingRoom(code: String)
        case joiningRoom
        case connected(peerName: String)
        case disconnected(reason: String?)
    }

    private(set) var state: State = .idle
    private(set) var pairCode: String?
    private(set) var partnerName: String?
    private(set) var partnerDivisionRaw: String?
    var onReceive: (@MainActor @Sendable (DuoMessage) -> Void)?

    init(
        localDisplayName: String,
        localDivisionRaw: String,
        localUserID: String
    ) {}

    func startHosting() async {}
    func joinRoom(code: String) async {}
    func send(_ message: DuoMessage) {}
    func sendHello() {}
    func disconnect() {}
}

#endif

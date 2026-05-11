import Foundation
import SwiftUI

#if canImport(MultipeerConnectivity)

// Higher-level wrapper around `DuoSession` that adds Duo-specific
// behavior: role tracking, the `hello` handshake on connect, and the
// public request methods that views call (`requestAdvance()` etc.)
// instead of poking raw `DuoMessage` cases.
//
// Why a layer above DuoSession? DuoSession knows about Multipeer; it
// doesn't know about HYROX, race state, or what makes a sensible
// hello payload. Splitting concerns means we can replace the
// transport (e.g. swap to Supabase Realtime in Tier 2) without
// touching every view. Coordinators stay; sessions get swapped.
//
// State model:
//   .idle             — nothing started; waiting for user to pick role
//   .hosting(state)   — local user tapped Host; reflects DuoSession.state
//   .joining(state)   — local user tapped Join; reflects DuoSession.state
//   .ready(name, div) — handshake complete, ready to start the race
//
// Lives at the RaceStartView level — created when the user opens the
// Duo flow, torn down when they back out or finish the race.
@MainActor
@Observable
final class DuoCoordinator: DuoTransport {

    // Backward-compatible alias for the top-level `DuoRole`.
    // Existing call sites that say `DuoCoordinator.Role`
    // continue to compile; new code in transport-agnostic
    // surfaces uses `DuoRole` directly.
    typealias Role = DuoRole

    enum CoordState: Equatable {
        case idle
        case hosting(transport: DuoSession.State)
        case joining(transport: DuoSession.State)
        case ready(partnerName: String, partnerDivision: Division)
    }

    // The transport-layer session this coordinator wraps. Public
    // (read-only) so views can render `nearbyPeers` directly when
    // browsing — no need to mirror that list at this layer.
    let session: DuoSession

    // Local user identity, captured at init time. Sent in the hello
    // payload after connection so the partner's UI can show
    // "Connected to Umang."
    let localDisplayName: String
    let localDivision: Division
    // Local user's max HR. Threaded through to the host's
    // snapshot construction so the watch + duo guest can compute
    // effort scores using the host's true max instead of the
    // 190 fallback default.
    let localMaxHeartRate: Int

    // Current high-level coordinator state. Views render from this.
    private(set) var state: CoordState = .idle

    // Role chosen by the local user. Nil before they pick.
    private(set) var role: Role?

    // Inbound message handler for the in-race coordinator slice
    // (next chunk). Set by the race-side coordinator when a race
    // becomes active so this layer can hand off race-specific
    // messages without knowing about RaceViewModel.
    //
    // Pre-race / pairing-flow messages (hello, disconnect) are
    // handled inside this coordinator directly; only the race
    // messages bubble up.
    var onRaceMessage: (@MainActor @Sendable (DuoMessage) -> Void)?

    // MARK: - DuoTransport conformance shims

    // Bridging property — exposes the Multipeer session's
    // partner name through the transport-agnostic surface so
    // `DuoRaceController` doesn't need to know there's an
    // `MCSession` underneath.
    var partnerName: String? { session.partnerName }

    // Multipeer has no Supabase auth concept — peers are
    // identified by MCPeerID display names only. The
    // protocol-required UUID stays nil here so the partner-
    // tap UX on Race cards renders as plain text instead of
    // a navigation link for Multipeer-saved races.
    var partnerUserID: String? { nil }

    // True once the hello handshake has completed. Mirrors the
    // `.ready` case of CoordState into a simple bool the
    // controller can read without pattern-matching on transport
    // state.
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    // Forwarding send. `DuoRaceController.startHeartRatePollingIfGuest`
    // wants to send `localHeartRate` directly without going
    // through one of the request* shortcuts; this exposes the
    // raw `DuoMessage` channel via the protocol.
    func send(_ message: DuoMessage) {
        session.send(message)
    }

    init(localDisplayName: String, localDivision: Division, localMaxHeartRate: Int = 190) {
        self.localDisplayName = localDisplayName
        self.localDivision = localDivision
        self.localMaxHeartRate = localMaxHeartRate
        self.session = DuoSession(localDisplayName: localDisplayName)

        // Subscribe to the session's inbound messages. This is the
        // single dispatch point for everything received from the
        // partner.
        self.session.onReceive = { [weak self] message in
            self?.handleInbound(message)
        }
    }

    // MARK: - Role + flow

    // User tapped "Host" on the pairing sheet.
    func startHosting() {
        role = .host
        session.startHosting()
        state = .hosting(transport: session.state)
        observeSessionState()
    }

    // User tapped "Join" on the pairing sheet.
    func startJoining() {
        role = .guest
        session.startBrowsing()
        state = .joining(transport: session.state)
        observeSessionState()
    }

    // Guest tapped a peer in the discovered list. Sends the
    // invitation; on accept the session transitions to .connected
    // and the hello exchange runs.
    func invite(_ peer: PeerHandle) {
        session.invite(peer)
    }

    // User backed out of the pairing sheet, or finished a race.
    // Resets everything to a clean idle state so the next Duo
    // attempt starts fresh.
    func cancel() {
        session.send(.disconnect)
        session.disconnectFromSession()
        role = nil
        state = .idle
    }

    // MARK: - Race actions (called by views)

    // Each method maps to a DuoMessage. The in-race coordinator (next
    // slice) routes these correctly based on role: a host's tap
    // mutates its local engine + broadcasts state; a guest's tap
    // sends a request and waits for the host's broadcast.
    //
    // For now (transport-only slice) these methods just send the
    // message. Hooking them into RaceViewModel happens in the
    // in-race coordinator chunk.
    func requestStart() { session.send(.requestStart) }
    func requestAdvance() { session.send(.requestAdvance) }
    func requestEndSegment() { session.send(.requestEndSegment) }
    func requestStartNextSegment() { session.send(.requestStartNextSegment) }
    func requestPause() { session.send(.requestPause) }
    func requestResume() { session.send(.requestResume) }
    func requestFinish() { session.send(.requestFinish) }
    func requestCancel() { session.send(.requestCancel) }

    // Host pushes state to the guest after every engine mutation.
    func broadcastState(_ snapshot: RaceStateSnapshot) {
        session.send(.stateUpdate(snapshot: snapshot))
    }

    // MARK: - Private

    // Mirror DuoSession.state into our higher-level CoordState.
    // Triggered by the session's `@Observable` state changes — we
    // re-read on every modification because SwiftUI doesn't give us
    // a "did change" callback for raw observable properties. The
    // view's `.onChange(of: coordinator.session.state)` triggers a
    // call into this method.
    func observeSessionState() {
        let transport = session.state
        switch (role, transport) {
        case (.host, _):
            state = .hosting(transport: transport)
        case (.guest, _):
            state = .joining(transport: transport)
        case (nil, _):
            state = .idle
        }

        // If we just connected and the partner has already
        // identified themselves, promote to .ready. Otherwise
        // the .ready transition happens when hello arrives below.
        if case .connected = transport,
           let partnerName = session.partnerName,
           let partnerDivisionRaw = session.partnerDivisionRaw,
           let partnerDivision = Division(rawValue: partnerDivisionRaw) {
            state = .ready(partnerName: partnerName, partnerDivision: partnerDivision)
        }
    }

    private func handleInbound(_ message: DuoMessage) {
        switch message {
        case .hello:
            // Session already stashed partnerName / partnerDivisionRaw.
            // Promote to .ready if connected.
            if case .connected = session.state,
               let partnerName = session.partnerName,
               let partnerDivisionRaw = session.partnerDivisionRaw,
               let partnerDivision = Division(rawValue: partnerDivisionRaw) {
                state = .ready(partnerName: partnerName, partnerDivision: partnerDivision)
            }

        case .disconnect:
            // Partner deliberately left. Drop the channel and
            // surface to the user. View layer is responsible for
            // showing "partner left" and offering solo continuation
            // (during a race) or returning to start (pre-race).
            session.disconnectFromSession()
            role = nil
            state = .idle

        case .requestStart, .requestAdvance, .requestEndSegment,
             .requestStartNextSegment, .requestPause, .requestResume,
             .requestFinish, .requestCancel, .stateUpdate, .localHeartRate:
            // Forward to the in-race coordinator if one's hooked up.
            // Pre-race these are dropped silently.
            onRaceMessage?(message)
        }
    }

    // MARK: - Hello

    // Sends our identity to the partner. Called by the view when it
    // detects a transition into the .connected state. We don't
    // auto-fire on .connected from inside the coordinator because
    // hello requires the local user's display name and division —
    // those are passed at init, and we want to send hello exactly
    // once per connection (the view's .onChange watcher gives us
    // that gate naturally).
    func sendHello() {
        session.send(.hello(
            displayName: localDisplayName,
            divisionRaw: localDivision.rawValue
        ))
    }
}

#endif  // canImport(MultipeerConnectivity)

import Foundation

// Local user's role in a duo race. Used by `DuoRaceController`
// to branch on host-vs-guest behavior. Identical for Multipeer
// (Tier 1) and Cloud (Tier 2) — promoted to top-level so the
// transport-agnostic controller doesn't need to know which
// coordinator type to import the enum from.
enum DuoRole: String, Sendable {
    case host
    case guest
}

// Transport-agnostic surface for the in-race duo controller.
// Both Multipeer (Tier 1) and Cloud (Tier 2) coordinators
// conform; `DuoRaceController` takes `any DuoTransport` so the
// host-engine / guest-mirror wiring works identically regardless
// of which transport's underneath.
//
// Lives outside any `#if canImport(...)` gate — pure Swift, no
// transport-specific types. The conformances are gated on the
// backends they need (Multipeer on `canImport(MultipeerConnectivity)`,
// Cloud on `canImport(Supabase)`).
//
// Method shapes match `DuoCoordinator`'s existing public API so
// the conformance is trivially additive — DuoCoordinator already
// has every method this protocol declares; we just add `:
// DuoTransport` to its declaration.
@MainActor
protocol DuoTransport: AnyObject {

    // MARK: - Identity

    // Local user's identity. Used by the host's snapshot
    // construction (the guest sees the host's division, max
    // HR, etc. — HYROX Doubles convention is one shared
    // ruleset per race).
    var localDisplayName: String { get }
    var localDivision: Division { get }
    var localMaxHeartRate: Int { get }

    // Partner's display name, populated after the hello
    // exchange. Surfaced in the in-race banner ("Connected to
    // Sarah") and stamped onto the saved Race row at finish.
    var partnerName: String? { get }

    // Partner's Supabase user UUID. Populated by transports
    // that have a real auth concept (Cloud — from the
    // duo_races row); always nil for Multipeer since peers
    // there are just MCPeerIDs with display names. Stamped
    // onto the Race row at finish so RaceCardView can render
    // the partner name as a tappable link to their public
    // profile.
    var partnerUserID: String? { get }

    // True when the handshake is complete and the controller
    // can start the race. Both transports promote to ready on
    // first hello arrival.
    var isReady: Bool { get }

    // MARK: - Inbound dispatch

    // The race-time message handler. `DuoRaceController` sets
    // this in its init; the transport forwards every received
    // `DuoMessage` (except hello / disconnect, which it
    // handles internally) through here. Settable so the
    // controller can swap or clear it.
    var onRaceMessage: (@MainActor @Sendable (DuoMessage) -> Void)? { get set }

    // MARK: - Outbound user actions

    // Each maps to a DuoMessage on the wire. Same semantics as
    // DuoCoordinator's existing methods — the role-aware
    // controller decides whether to mutate its local engine
    // (host) or send a request (guest).
    func requestStart()
    func requestAdvance()
    func requestEndSegment()
    func requestStartNextSegment()
    func requestPause()
    func requestResume()
    func requestFinish()
    func requestCancel()

    // Host-only: push the current race state to the guest.
    // Guest implementations can still send these — the
    // protocol doesn't enforce role gating; that's
    // `DuoRaceController`'s job.
    func broadcastState(_ snapshot: RaceStateSnapshot)

    // Generic message send — used by `localHeartRate` updates
    // that flow symmetrically in both directions and don't
    // map to one of the request* methods above.
    func send(_ message: DuoMessage)
}

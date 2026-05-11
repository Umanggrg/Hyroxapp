import Foundation
import SwiftUI

#if canImport(Supabase)
import Supabase

// Tier 2 cloud-backed counterpart to `DuoCoordinator`. Wraps a
// `CloudDuoSession` (Supabase Realtime broadcast + duo_races
// table) the same way `DuoCoordinator` wraps `DuoSession`
// (Multipeer). Exposes the transport-agnostic `DuoTransport`
// surface so `DuoRaceController` can drive either backend
// identically.
//
// Pairing flow:
//   • startHosting()     — INSERT a duo_races row, generate a
//                          6-char code, open the Realtime
//                          broadcast channel.
//   • joinRoom(code:)    — guest looks up the row by code,
//                          UPDATE-claims it, opens the channel,
//                          sends hello.
//   • Hello arrives      — promote to .ready(partnerName, partnerDivision).
//   • cancel()           — disconnect channel + tear down.
//
// All in-race traffic (advance / pause / state updates / HR)
// flows over the Realtime broadcast channel via DuoMessage —
// same wire protocol Multipeer uses.
@MainActor
@Observable
final class CloudDuoCoordinator: DuoTransport {

    // Same alias pattern as DuoCoordinator — `DuoRole` lives at
    // the top of `DuoTransport.swift` so the in-race controller
    // can use it without picking a transport-specific import.
    typealias Role = DuoRole

    enum CoordState: Equatable {
        case idle
        case hosting(transport: CloudDuoSession.State)
        case joining(transport: CloudDuoSession.State)
        case ready(partnerName: String, partnerDivision: Division)
    }

    let session: CloudDuoSession

    let localDisplayName: String
    let localDivision: Division
    let localMaxHeartRate: Int

    private(set) var state: CoordState = .idle
    private(set) var role: Role?

    // MARK: - DuoTransport surface

    var partnerName: String? { session.partnerName }

    // Forwards CloudDuoSession's partnerUserID. Populated
    // from the duo_races row (host's row read on guest's
    // joinRoom, guest's row re-fetched by host after hello).
    var partnerUserID: String? { session.partnerUserID }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var onRaceMessage: (@MainActor @Sendable (DuoMessage) -> Void)?

    // MARK: - Init

    init(
        localDisplayName: String,
        localDivision: Division,
        localMaxHeartRate: Int = 190,
        localUserID: String,
        client: SupabaseClient = SupabaseService.shared
    ) {
        self.localDisplayName = localDisplayName
        self.localDivision = localDivision
        self.localMaxHeartRate = localMaxHeartRate
        self.session = CloudDuoSession(
            localDisplayName: localDisplayName,
            localDivisionRaw: localDivision.rawValue,
            localUserID: localUserID,
            client: client
        )

        // Forward inbound DuoMessages through the same dispatch
        // path DuoCoordinator uses. CloudDuoSession already
        // consumes hello / disconnect internally and only
        // forwards race messages here, so the dispatcher is
        // simpler than DuoCoordinator's (no need to re-handle
        // hello).
        session.onReceive = { [weak self] message in
            self?.handleInbound(message)
        }
    }

    // MARK: - Pairing flow

    // Host taps "Host Cloud Duo." Spins up the room and the
    // Realtime channel. Caller should observe `session.state`
    // and `state` to render the pair code + waiting UI.
    func startHosting() async {
        role = .host
        await session.startHosting()
        state = .hosting(transport: session.state)
        // If hello already arrived (race condition where the
        // guest joined and broadcast hello before our state
        // assignment), promote immediately.
        promoteIfHelloArrived()
    }

    // Guest taps "Enter a Code." Switches to the join flow
    // without doing any network work — the actual SELECT +
    // UPDATE happens when the guest hits Go after typing the
    // code. Two-phase so the UI can show the code-entry field
    // before any backend round-trip fires.
    func beginJoinFlow() {
        role = .guest
        state = .joining(transport: .idle)
    }

    // Guest hits "Go" with a typed code. Performs the SELECT +
    // UPDATE + channel subscribe + hello send via
    // CloudDuoSession.joinRoom.
    func joinRoom(code: String) async {
        role = .guest
        await session.joinRoom(code: code)
        state = .joining(transport: session.state)
        promoteIfHelloArrived()
    }

    // User backed out of the pairing sheet, or finished a race.
    // Disconnects the channel and resets to idle so the next
    // attempt starts fresh.
    func cancel() {
        session.disconnect()
        role = nil
        state = .idle
    }

    // MARK: - DuoTransport: outbound user actions

    // All these forward to `session.send` with the matching
    // DuoMessage. Identical shape to DuoCoordinator's request*
    // methods so the protocol surface is symmetric.
    func requestStart() { session.send(.requestStart) }
    func requestAdvance() { session.send(.requestAdvance) }
    func requestEndSegment() { session.send(.requestEndSegment) }
    func requestStartNextSegment() { session.send(.requestStartNextSegment) }
    func requestPause() { session.send(.requestPause) }
    func requestResume() { session.send(.requestResume) }
    func requestFinish() { session.send(.requestFinish) }
    func requestCancel() { session.send(.requestCancel) }

    func broadcastState(_ snapshot: RaceStateSnapshot) {
        session.send(.stateUpdate(snapshot: snapshot))
    }

    func send(_ message: DuoMessage) {
        session.send(message)
    }

    // MARK: - Private

    // Watch the underlying CloudDuoSession's state — when it
    // transitions to `.connected(peerName)` and we have a
    // partner division on hand, promote to `.ready`. Called
    // after every async session method and after hello arrival.
    private func promoteIfHelloArrived() {
        if case let .connected(peerName) = session.state,
           let partnerDivisionRaw = session.partnerDivisionRaw,
           let partnerDivision = Division(rawValue: partnerDivisionRaw) {
            state = .ready(
                partnerName: peerName,
                partnerDivision: partnerDivision
            )
        }
    }

    // CloudDuoSession already handled hello / disconnect
    // internally — by the time a message arrives here it's a
    // race-time event the controller cares about. Forward
    // unconditionally; controller decides if it cares.
    private func handleInbound(_ message: DuoMessage) {
        // If this is the first message after hello, promote.
        // Idempotent — promoting twice is a no-op.
        promoteIfHelloArrived()
        onRaceMessage?(message)
    }
}

#endif

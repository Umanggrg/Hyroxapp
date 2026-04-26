import Foundation

// `MultipeerConnectivity` is iOS / iPadOS / macOS / tvOS / visionOS — but
// not watchOS. The Duo bridge only runs phone-to-phone; the watch keeps
// using its existing WCSession path with whichever phone it's paired with.
// This file no-ops on platforms without the framework so the shared module
// compiles cleanly everywhere.
#if canImport(MultipeerConnectivity)
import MultipeerConnectivity

// The phone-to-phone Duo bridge. Wraps Apple's MultipeerConnectivity
// stack into a single `@Observable` service that views can read.
//
// Why three concrete MultipeerConnectivity types? Apple split the work:
//   • `MCSession` owns the encrypted channel + send/receive
//   • `MCNearbyServiceAdvertiser` makes a peer discoverable to others
//   • `MCNearbyServiceBrowser` finds advertised peers
// A host advertises but doesn't browse; a guest browses but doesn't
// advertise. Both create a session at hello.
//
// State model:
//   .idle             — nothing going on, no advertising or browsing
//   .advertising(name)— host: visible to nearby guests as "name"
//   .browsing         — guest: looking for nearby hosts; populates `nearbyPeers`
//   .connecting(peer) — invitation in flight, brief intermediate state
//   .connected(peer)  — channel open, can send/receive
//   .disconnected(reason) — link dropped, optional reason
//
// Threading: MultipeerConnectivity's delegate methods fire on an
// arbitrary queue. We hop to MainActor before mutating @Observable
// state so SwiftUI sees consistent values. Same pattern as
// WatchRaceClient.
//
// Service type identifier — must be 1-15 lowercase ASCII chars,
// optional hyphens. Pinned to a project-specific value so we don't
// accidentally connect to other apps' Multipeer sessions on the same
// network.
@Observable
@MainActor
final class DuoSession: NSObject {

    // App-unique service type. Must match between host and guest or
    // they'll never see each other on the network. Include the bundle
    // ID's tail so future apps from the same developer don't collide.
    static let serviceType = "hyrox-duo"

    // Current state of the bridge. Views render from this; transitions
    // are mostly driven by Multipeer's delegate callbacks.
    enum State: Equatable {
        case idle
        case advertising(localName: String)
        case browsing
        case connecting(peerName: String)
        case connected(peerName: String)
        case disconnected(reason: String?)
    }

    private(set) var state: State = .idle

    // Peers the browser has discovered. Updated as advertisers come and
    // go on the network. Guest's "Looking for hosts" UI binds to this.
    // Cleared when browsing stops.
    private(set) var nearbyPeers: [PeerHandle] = []

    // The partner's display name + division, set after the `hello`
    // exchange completes. Surfaced in the in-race "Connected to X"
    // banner. Nil before exchange (or after disconnect).
    private(set) var partnerName: String?
    private(set) var partnerDivisionRaw: String?

    // Inbound message handler — set by the coordinator that wraps
    // this session. Called on MainActor for every successfully-decoded
    // DuoMessage. Drop the closure to disengage; the session keeps
    // running but messages are no-ops.
    var onReceive: (@MainActor @Sendable (DuoMessage) -> Void)?

    // Local peer identity. The display name shown to nearby guests
    // when this device is hosting. Pinned at init so changing it
    // mid-session would require re-creating MCSession.
    private let myPeerID: MCPeerID
    private let session: MCSession

    // Created lazily when the device starts advertising / browsing
    // (since most users will only ever be one of the two). Torn
    // down when stopping. Holding both at once is wasteful and
    // confusing — a peer that advertises AND browses can race
    // itself.
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // MARK: - Init

    init(localDisplayName: String) {
        // MCPeerID's display name is what nearby browsers see. We
        // pad to a non-empty string because Multipeer crashes on
        // empty display names. Uses the user's UserProfile.displayName
        // when available (passed in from RaceStartView).
        let safeName = localDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Athlete"
            : localDisplayName
        self.myPeerID = MCPeerID(displayName: safeName)
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            // `.required` enables encryption + authentication. Apple's
            // recommendation for any session carrying user data; the
            // tradeoff is a tiny CPU cost per message. Worth it.
            encryptionPreference: .required
        )
        super.init()
        session.delegate = self
    }

    // MARK: - Host

    // Starts advertising this device as a Duo host. Nearby guests
    // running the browser will see this peer in their `nearbyPeers`
    // list. The advertiser auto-rejects an invitation if we're
    // already connected.
    func startHosting() {
        stopAll()
        let advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            // The discoveryInfo dictionary is sent alongside the
            // advertisement; we keep it empty for now. Future use:
            // declare race target time so a guest can pre-filter
            // hosts running compatible workouts.
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        self.state = .advertising(localName: myPeerID.displayName)
        print("[DuoSession] start advertising as '\(myPeerID.displayName)'")
    }

    // MARK: - Guest

    // Starts browsing for nearby hosts. Discovered peers populate
    // `nearbyPeers`. Tap a peer in the UI → `invite(peer:)`.
    func startBrowsing() {
        stopAll()
        let browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: Self.serviceType
        )
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        self.nearbyPeers = []
        self.state = .browsing
        print("[DuoSession] start browsing for hosts")
    }

    // Send an invitation to a discovered peer. The peer's advertiser
    // delegate fires; advertiser auto-accepts (we don't show a prompt
    // — Duo invitations only happen when the host has explicitly
    // tapped "Host" so they've already opted in). 30s timeout matches
    // Apple's recommended default.
    func invite(_ peer: PeerHandle) {
        guard let browser else {
            print("[DuoSession] invite called but no browser active")
            return
        }
        browser.invitePeer(
            peer.peerID,
            to: session,
            withContext: nil,
            timeout: 30
        )
        state = .connecting(peerName: peer.peerID.displayName)
        print("[DuoSession] inviting \(peer.peerID.displayName)")
    }

    // MARK: - Send

    // Encode and broadcast a message to every connected peer.
    // (We only ever have one peer in v1 of Duo, but Multipeer's
    // API is set-of-peers; future cohorts of 3+ would just work.)
    // Uses `.reliable` mode — guaranteed delivery in order, which
    // we want for race-state changes. The latency cost is tiny
    // (~10ms) compared to `.unreliable` UDP-style mode.
    func send(_ message: DuoMessage) {
        guard !session.connectedPeers.isEmpty else {
            print("[DuoSession] send skipped — no connected peers")
            return
        }
        let data = message.encode()
        do {
            try session.send(
                data,
                toPeers: session.connectedPeers,
                with: .reliable
            )
            print("[DuoSession] sent \(messageLabel(message)) (\(data.count) bytes)")
        } catch {
            print("[DuoSession] send FAILED — \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle

    // Tear down advertising and browsing. The session itself stays
    // alive — call disconnectFromSession() to also drop the channel.
    func stopAll() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        nearbyPeers = []
    }

    // Hard reset — drops the channel, stops advertising/browsing,
    // returns to .idle. Use when the user backs out of the Duo
    // pairing flow or finishes a race.
    func disconnectFromSession() {
        stopAll()
        session.disconnect()
        partnerName = nil
        partnerDivisionRaw = nil
        state = .idle
    }

    // MARK: - Helpers

    // Compact label for the per-send log line. Avoids dumping the
    // whole snapshot on every state update.
    private func messageLabel(_ message: DuoMessage) -> String {
        switch message {
        case .hello: return "hello"
        case .requestStart: return "requestStart"
        case .requestAdvance: return "requestAdvance"
        case .requestEndSegment: return "requestEndSegment"
        case .requestStartNextSegment: return "requestStartNextSegment"
        case .requestPause: return "requestPause"
        case .requestResume: return "requestResume"
        case .requestFinish: return "requestFinish"
        case .requestCancel: return "requestCancel"
        case .stateUpdate(let s): return "stateUpdate(\(s.phase.rawValue))"
        case .disconnect: return "disconnect"
        }
    }
}

// MARK: - PeerHandle

// A SwiftUI-friendly wrapper around `MCPeerID`. Why? `MCPeerID`
// inherits from NSObject and isn't `Identifiable` out of the box —
// using it directly as a `ForEach` data source requires manual
// `id` keypaths and the type leaks into views that shouldn't know
// about MultipeerConnectivity.
//
// Also conforms to `Hashable` so it can drive `.sheet(item:)` and
// other identity-keyed SwiftUI APIs cleanly.
struct PeerHandle: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String

    // The underlying peer ID is needed when sending invitations
    // back through the browser. Held weakly via the displayName
    // matched against `nearbyPeers` would be safer for Sendable
    // conformance — but MCPeerID conforms to Sendable on the
    // Apple-side typing, so we can hold it directly here.
    let peerID: MCPeerID

    init(peerID: MCPeerID) {
        self.id = peerID.displayName + "-" + UUID().uuidString
        self.displayName = peerID.displayName
        self.peerID = peerID
    }
}

// MARK: - MCSessionDelegate

extension DuoSession: MCSessionDelegate {

    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        let stateName: String
        switch state {
        case .notConnected: stateName = "notConnected"
        case .connecting:   stateName = "connecting"
        case .connected:    stateName = "connected"
        @unknown default:   stateName = "unknown"
        }
        print("[DuoSession] peer '\(peerID.displayName)' state → \(stateName)")

        Task { @MainActor in
            switch state {
            case .connected:
                // Channel is up. We move to .connected immediately;
                // the `hello` exchange happens in parallel — either
                // side sends one once they observe the connected
                // state, and the receiver fills in `partnerName` /
                // `partnerDivisionRaw` once it arrives.
                self.state = .connected(peerName: peerID.displayName)
                self.stopAll()  // stop advertising/browsing now that we're paired
            case .connecting:
                self.state = .connecting(peerName: peerID.displayName)
            case .notConnected:
                // Channel dropped. If we were connected, surface that;
                // otherwise we got here from a failed invitation /
                // timeout and the user just sees an idle state again.
                if case .connected = self.state {
                    self.state = .disconnected(reason: "Partner disconnected")
                } else {
                    self.state = .disconnected(reason: nil)
                }
                self.partnerName = nil
                self.partnerDivisionRaw = nil
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        guard let message = DuoMessage.decode(data) else {
            print("[DuoSession] received undecodable payload from \(peerID.displayName)")
            return
        }
        Task { @MainActor in
            // `hello` is handled inside the session itself so partner
            // identity is always set before the higher-level coordinator
            // sees subsequent messages. Other messages dispatch to the
            // coordinator's onReceive callback.
            if case .hello(let displayName, let divisionRaw) = message {
                self.partnerName = displayName
                self.partnerDivisionRaw = divisionRaw
                print("[DuoSession] hello from '\(displayName)' (\(divisionRaw))")
            }
            self.onReceive?(message)
        }
    }

    // The next three callbacks aren't used by Duo today (we only send
    // small Codable messages, no streams or files). Required by the
    // protocol; left as no-ops with a log for visibility.
    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        print("[DuoSession] unexpected stream '\(streamName)' from \(peerID.displayName)")
    }

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        print("[DuoSession] unexpected resource '\(resourceName)' starting from \(peerID.displayName)")
    }

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        print("[DuoSession] unexpected resource '\(resourceName)' finished from \(peerID.displayName)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension DuoSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        print("[DuoSession] advertiser received invitation from \(peerID.displayName)")
        // Auto-accept. Hosting is an explicit user action ("I tapped
        // Host"), so any invitation that arrives is desired. If we
        // ever expose a confirm prompt for stranger danger, this is
        // where it'd live.
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension DuoSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        print("[DuoSession] browser found \(peerID.displayName)")
        Task { @MainActor in
            // Avoid duplicate entries — Multipeer can re-emit the
            // same peer if discovery info changes. We dedupe by
            // displayName since that's what the user sees.
            if !self.nearbyPeers.contains(where: { $0.displayName == peerID.displayName }) {
                self.nearbyPeers.append(PeerHandle(peerID: peerID))
            }
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        print("[DuoSession] browser lost \(peerID.displayName)")
        Task { @MainActor in
            self.nearbyPeers.removeAll { $0.displayName == peerID.displayName }
        }
    }
}

#endif  // canImport(MultipeerConnectivity)

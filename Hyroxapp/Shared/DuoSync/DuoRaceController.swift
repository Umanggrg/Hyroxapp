import Foundation
import SwiftUI
import SwiftData

#if canImport(MultipeerConnectivity)

// In-race orchestrator that bridges DuoCoordinator (transport) and
// RaceViewModel (engine). One instance per active duo race, created
// when the local user taps Start on the pairing sheet, torn down when
// the race ends or the partner disconnects.
//
// Two roles, one class — branches on `role` internally so the call
// sites in views stay symmetric.
//
//   role == .host
//     • Owns the local RaceViewModel — every state mutation runs on
//       this device's engine first, then broadcasts the new snapshot
//       to the guest.
//     • Receives request* messages from the guest and forwards them
//       to RaceViewModel as if they were local taps.
//
//   role == .guest
//     • Holds a `latestSnapshot` updated on every host stateUpdate
//       message. Guest views render from this snapshot rather than
//       a local engine.
//     • The guest's own button taps (Start / Next / Pause / etc.)
//       become outbound request messages. The local engine is
//       never mutated on the guest.
//
// Why a single class: the alternative (HostController + GuestController)
// duplicates the inbound-message switch and the wiring from views.
// Branching on `role` once at the top of each method is the cleaner
// shape given how symmetric the two sides are.
@MainActor
@Observable
final class DuoRaceController {

    let role: DuoCoordinator.Role
    private let coordinator: DuoCoordinator

    // Host-only: the local view model whose engine state we own
    // and broadcast. Held weakly so we don't extend its lifetime
    // beyond the view that owns it. Nil on the guest side.
    private weak var viewModel: RaceViewModel?

    // Guest-only: latest race state received from the host. Nil
    // until the first snapshot arrives. Guest views read this and
    // re-render on assignment (via @Observable).
    private(set) var latestSnapshot: RaceStateSnapshot?

    // Partner's latest heart rate, in bpm. Updated when the
    // partner's `localHeartRate` message arrives. Host displays
    // this alongside its own HR; guest displays this if it ever
    // wants to (today the guest reads host HR from
    // `latestSnapshot.currentHeartRateBPM` instead).
    //
    // Nil before the first sample, or when the partner has no
    // HealthKit authorization / no Watch streaming.
    private(set) var partnerHeartRateBPM: Double?

    // Local user's HR — populated by the guest's own HealthKit
    // polling and broadcast to the host. Host doesn't poll
    // through the controller (its RaceViewModel already polls
    // and writes to `currentHeartRateBPM`); this property is
    // primarily a guest-side cursor.
    private(set) var localHeartRateBPM: Double?

    // Polling task for the guest's own HR. Runs while the guest
    // is in an active duo race; cancelled on disconnect or view
    // disappear via `stopHeartRatePolling`.
    private var heartRatePollTask: Task<Void, Never>?

    // Same poll interval RaceViewModel uses on iOS. Five seconds
    // matches the cadence Apple Watch typically writes HR samples
    // to HealthKit in workout mode.
    private static let heartRatePollInterval: TimeInterval = 5

    // Surfaced to the UI so banners can render "Connected to X" and
    // gracefully degrade on disconnect.
    var partnerName: String? { coordinator.session.partnerName }

    var isConnected: Bool {
        if case .ready = coordinator.state { return true }
        return false
    }

    // MARK: - Init

    init(
        role: DuoCoordinator.Role,
        coordinator: DuoCoordinator,
        viewModel: RaceViewModel? = nil
    ) {
        self.role = role
        self.coordinator = coordinator
        self.viewModel = viewModel

        // Hook inbound race messages to our dispatcher. This
        // displaces the no-op default in DuoCoordinator with the
        // real handler.
        coordinator.onRaceMessage = { [weak self] message in
            self?.handleInbound(message)
        }
    }

    // MARK: - Outbound (from local taps)

    // Each method maps one user action to the right behavior for
    // the current role. Host: mutate engine, then broadcast. Guest:
    // send a request and wait for the host's snapshot.

    func start(targetDuration: TimeInterval?, sequence: [Station]? = nil) {
        switch role {
        case .host:
            guard let vm = viewModel else { return }
            // Use the same start path the solo flow uses; the
            // post-mutation broadcast hook below picks up the new
            // state and pushes it. Coalesce the optional sequence
            // to the canonical 16-station HYROX race when not
            // specified — same default the VM uses.
            vm.startRace(
                sequence: sequence ?? Station.raceSequence,
                targetDuration: targetDuration
            )
            broadcastCurrent()
        case .guest:
            coordinator.requestStart()
        }
    }

    func advance() {
        switch role {
        case .host:
            viewModel?.advance()
            broadcastCurrent()
        case .guest:
            coordinator.requestAdvance()
        }
    }

    func endSegment() {
        switch role {
        case .host:
            viewModel?.endSegmentRace()
            broadcastCurrent()
        case .guest:
            coordinator.requestEndSegment()
        }
    }

    func startNextSegment() {
        switch role {
        case .host:
            viewModel?.startNextSegmentRace()
            broadcastCurrent()
        case .guest:
            coordinator.requestStartNextSegment()
        }
    }

    func pause() {
        switch role {
        case .host:
            viewModel?.pauseRace()
            broadcastCurrent()
        case .guest:
            coordinator.requestPause()
        }
    }

    func resume() {
        switch role {
        case .host:
            viewModel?.resumeRace()
            broadcastCurrent()
        case .guest:
            coordinator.requestResume()
        }
    }

    // MARK: - Broadcasting (host)

    // Build a snapshot from the host's current engine state and push
    // it to the guest. Called after every state-mutating action above
    // and also exposed publicly so the host's RaceView can re-broadcast
    // when external state changes happen (HR sample arrives, photo
    // attached, etc.) — anywhere RaceViewModel changes.
    //
    // No-op when role is guest or no view model is bound.
    func broadcastCurrent() {
        guard role == .host, let vm = viewModel else { return }
        // Use the host's division as the canonical race-rules
        // division. The guest sees the host's wall-ball rep count,
        // sled weights, etc. — matches the HYROX Doubles convention
        // where one race = one ruleset.
        guard let snapshot = vm.makeRaceStateSnapshot(division: coordinator.localDivision) else { return }
        coordinator.broadcastState(snapshot)

        // When the host's race is now .finished, stamp the
        // partner's display name onto the active Race row so it
        // shows up in History as "Duo with Sarah" instead of a
        // generic title. Idempotent — `race.partner == nil` guard
        // means subsequent .finished broadcasts skip the assign.
        //
        // The cascade RaceView.onChange → publishWatchState +
        // broadcast already fires after `engine.advance()`'s
        // saveContextSilently call. We modify the SwiftData
        // object AFTER that save, so we trigger one more save
        // here through the model's own context to persist the
        // partner field.
        if snapshot.phase == .finished,
           let partner = coordinator.session.partnerName,
           let race = vm.activeRace,
           race.partner == nil {
            race.partner = partner
            try? race.modelContext?.save()
        }
    }

    // MARK: - Inbound (from partner)

    private func handleInbound(_ message: DuoMessage) {
        switch role {
        case .host:
            handleHostInbound(message)
        case .guest:
            handleGuestInbound(message)
        }
    }

    // MARK: - Guest HR polling

    // Start polling HealthKit for the guest's own HR and broadcast
    // each new sample to the host via `localHeartRate`. No-op on
    // the host side — the host already polls through RaceViewModel
    // and ships HR via the snapshot's `currentHeartRateBPM`.
    //
    // Caller (DuoGuestRaceView's onAppear) is responsible for the
    // pairing with `stopHeartRatePolling()` on disappear so we
    // don't leak the task or burn battery between races.
    func startHeartRatePollingIfGuest() {
        #if canImport(HealthKit)
        guard role == .guest else { return }
        stopHeartRatePolling()

        heartRatePollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let bpm = await HealthKitService.shared.currentHeartRate() {
                    self.localHeartRateBPM = bpm
                    self.coordinator.session.send(.localHeartRate(bpm: bpm))
                }
                try? await Task.sleep(for: .seconds(Self.heartRatePollInterval))
            }
        }
        #endif
    }

    // Stop the guest's HR polling and clear local state. Sends one
    // final `localHeartRate(nil)` so the host UI clears its
    // partner-HR chip rather than displaying a stale last-known
    // value indefinitely.
    func stopHeartRatePolling() {
        heartRatePollTask?.cancel()
        heartRatePollTask = nil
        if role == .guest, localHeartRateBPM != nil {
            coordinator.session.send(.localHeartRate(bpm: nil))
        }
        localHeartRateBPM = nil
    }

    // Host receives guest requests and forwards them to RaceViewModel
    // as if they were local taps. The post-action broadcast pushes
    // the new state back so the guest sees the result.
    private func handleHostInbound(_ message: DuoMessage) {
        guard let vm = viewModel else { return }
        switch message {
        case .requestStart:
            // Host shouldn't normally honor a guest's start request
            // before the host has set up sequence + target — those
            // are local choices on the host's start screen. Ignore
            // for safety; if we want guest-initiated start later,
            // the start request would carry sequence/target in
            // its payload.
            print("[DuoRaceController] guest requestStart ignored — host owns start config")

        case .requestAdvance:
            vm.advance()
            broadcastCurrent()

        case .requestEndSegment:
            vm.endSegmentRace()
            broadcastCurrent()

        case .requestStartNextSegment:
            vm.startNextSegmentRace()
            broadcastCurrent()

        case .requestPause:
            vm.pauseRace()
            broadcastCurrent()

        case .requestResume:
            vm.resumeRace()
            broadcastCurrent()

        case .requestFinish:
            // Same model as the iOS hold-to-finish — guest's
            // request is treated as the final advance call.
            // Race engine will transition to .finished on the
            // last segment.
            vm.advance()
            broadcastCurrent()

        case .requestCancel:
            // Guest abandoned. Surface to the host with a banner;
            // the host's own state is still authoritative. We don't
            // auto-cancel the host's race here — losing both a
            // partner's connection AND the user's race in one go
            // is too aggressive. Host can finish solo if they
            // choose.
            print("[DuoRaceController] guest requested cancel — surfaces as 'partner left' on host")

        case .localHeartRate(let bpm):
            // Guest's own HR sample. Host stores it as
            // partnerHeartRateBPM; the in-race UI surfaces it as
            // a second HR chip alongside the host's own.
            partnerHeartRateBPM = bpm

        case .stateUpdate, .hello, .disconnect:
            // Host shouldn't receive these — guest never sends
            // stateUpdate, hello is handled in DuoSession,
            // disconnect is handled in DuoCoordinator.
            break
        }
    }

    // Guest receives stateUpdate broadcasts and stores them. Views
    // re-render automatically because `latestSnapshot` is observed.
    private func handleGuestInbound(_ message: DuoMessage) {
        switch message {
        case .stateUpdate(let snapshot):
            self.latestSnapshot = snapshot

        case .localHeartRate(let bpm):
            // Host shouldn't typically send this — its HR rides on
            // snapshot.currentHeartRateBPM — but if it does, we
            // honor it. Lets the same path serve both directions
            // symmetrically without a second message type.
            partnerHeartRateBPM = bpm

        case .requestStart, .requestAdvance, .requestEndSegment,
             .requestStartNextSegment, .requestPause, .requestResume,
             .requestFinish, .requestCancel, .hello, .disconnect:
            // Guest doesn't process these; only the host does.
            break
        }
    }
}

#endif  // canImport(MultipeerConnectivity)

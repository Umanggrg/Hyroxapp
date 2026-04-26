import SwiftUI
import SwiftData

#if canImport(MultipeerConnectivity)

// The guest's race screen during a co-located Duo race.
//
// Doesn't run a local engine. Reads everything from
// `controller.latestSnapshot` — that's the broadcast the host's
// phone sends after every state mutation. The guest's UI stays in
// step with the host because both render from the same snapshot.
//
// Why a separate view (vs. reusing RaceView)? RaceView is built
// around RaceViewModel + a local engine; refactoring it to also
// read from a remote snapshot would require deep surgery (every
// "current station" / "elapsed" / "splits" read would branch on
// solo-vs-guest). Cleaner to ship a focused read-only view that
// renders the same shape from a different data source.
//
// Includes the same brand identity language as the iOS RaceView's
// in-progress block: HeroBackdrop, fingerprint progress (via the
// existing iOS pattern), big monospaced timer, station name +
// target line, advance button. The advance button sends a
// `requestAdvance` to the host instead of mutating a local engine.
struct DuoGuestRaceView: View {

    @Bindable var controller: DuoRaceController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    // True after we've saved a local Race row for this duo race.
    // Latches so we don't insert duplicates if the host re-emits
    // a .finished snapshot (broadcast hooks fire on every state
    // mutation; .finished is terminal but the host could emit
    // post-finish snapshots if the engine state changes again).
    @State private var didSaveGuestRace = false

    var body: some View {
        ZStack {
            HeroBackdrop(.standard)

            // No snapshot yet (or notStarted) shouldn't happen here
            // — fullScreenCover only presents this view when an
            // active-race snapshot exists. Guard for safety so a
            // mid-race disconnect that wipes the snapshot doesn't
            // crash; instead falls back to a benign waiting state.
            if let snapshot = controller.latestSnapshot,
               snapshot.phase != .notStarted {
                content(snapshot: snapshot)
            } else {
                connectingPlaceholder
            }
        }
        .navigationBarBackButtonHidden(true)
        // When the host's race finishes, the snapshot's phase flips
        // to .finished. We save a local Race row at that moment so
        // the guest's History reflects this duo race independently
        // of the host's. HYROX Doubles credits identical times to
        // both partners — same convention the live race UI uses.
        .onChange(of: controller.latestSnapshot?.phase) { _, newPhase in
            if newPhase == .finished, !didSaveGuestRace {
                saveGuestRaceIfPossible()
            }
        }
        // Guest also polls HealthKit for its own HR and broadcasts
        // each sample to the host via `localHeartRate`. Host stores
        // the value as `partnerHeartRateBPM` and shows it as a
        // second chip in its in-race header. Cleaned up on
        // disappear so polling doesn't outlive the race.
        .onAppear {
            controller.startHeartRatePollingIfGuest()
        }
        .onDisappear {
            controller.stopHeartRatePolling()
        }
    }

    // MARK: - Guest history persistence

    // Build a `Race` row from the host's broadcast `.finished`
    // snapshot and insert it into local SwiftData. Idempotent via
    // the `didSaveGuestRace` latch — broadcasts may re-emit the
    // same .finished state but only the first attempts a save.
    //
    // The reconstructed race uses:
    //   • mode = .duo
    //   • partner = host's display name
    //   • startedAt / endedAt from snapshot timestamps
    //   • sequence derived from the splits (in order)
    //   • splits round-tripped via SerializedSplit.toSplit()
    //   • name = "" (default), notes = "" — guest can edit later
    //
    // Failures (no snapshot, no end time, no splits) skip silently
    // and leave the latch unflipped, so a transient bad payload
    // can be retried on the next snapshot. Real failure modes are
    // rare; this is defensive.
    private func saveGuestRaceIfPossible() {
        guard let snapshot = controller.latestSnapshot,
              snapshot.phase == .finished,
              let startedAt = snapshot.startedAt,
              let endedAt = snapshot.endedAt
        else { return }

        // Reconstruct real Splits from the wire form. Filter nils
        // (unknown station rawValue from a forward-compat host).
        let splits = snapshot.splits.compactMap { $0.toSplit() }
        guard !splits.isEmpty else { return }

        // Derive the race sequence from the splits — preserves
        // custom-workout sequences automatically without needing
        // to ship the raw sequence array separately. For a standard
        // 16-station HYROX race this matches Station.raceSequence;
        // for a custom workout it's whatever the host built.
        let sequence = splits.map(\.station)

        let race = Race(
            startedAt: startedAt,
            endedAt: endedAt,
            splits: splits,
            sequence: sequence,
            mode: .duo,
            partner: controller.partnerName
        )
        modelContext.insert(race)
        try? modelContext.save()

        didSaveGuestRace = true
    }

    // MARK: - Branches

    @ViewBuilder
    private func content(snapshot: RaceStateSnapshot) -> some View {
        switch snapshot.phase {
        case .inProgress:
            inProgressView(snapshot: snapshot)
        case .paused:
            pausedView(snapshot: snapshot)
        case .inRoxzone:
            roxzoneView(snapshot: snapshot)
        case .finished:
            finishedView(snapshot: snapshot)
        case .notStarted:
            connectingPlaceholder
        }
    }

    // MARK: - In Progress

    private func inProgressView(snapshot: RaceStateSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            VStack(spacing: 0) {
                connectionBanner

                Spacer(minLength: 12)

                stationHeader(snapshot: snapshot)
                    .padding(.horizontal, Layout.screenMargin)

                Spacer(minLength: 24)

                timerHero(snapshot: snapshot, now: context.date)
                    .padding(.horizontal, Layout.screenMargin)

                Spacer(minLength: 24)

                stationFooter(snapshot: snapshot)
                    .padding(.horizontal, Layout.screenMargin)

                Spacer()

                advanceButton(snapshot: snapshot)
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.bottom, 24)
            }
        }
    }

    private func stationHeader(snapshot: RaceStateSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption.weight(.heavy))
                Text("STATION \(snapshot.completedStationsCount + 1) OF \(snapshot.totalStations)")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.accent.opacity(0.14)))

            Text(snapshot.currentStation?.displayName ?? "—")
                .font(.stationTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
    }

    private func timerHero(snapshot: RaceStateSnapshot, now: Date) -> some View {
        let total = snapshot.startedAt.map { now.timeIntervalSince($0) } ?? 0
        let segment = snapshot.currentSegmentStartedAt.map { now.timeIntervalSince($0) } ?? 0

        return VStack(spacing: 6) {
            Text(RaceStats.format(total))
                .font(.raceTimer)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.20),
                    radius: 24,
                    y: 0
                )

            HStack(spacing: 16) {
                Text("Segment · \(RaceStats.format(segment))")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                // Live HR from the host. Beats next to the segment
                // timer so the eye reads "this is what's happening
                // right now." Stays consistent with the iOS host's
                // own HR chip so both partners see the same data
                // shape.
                if let hr = snapshot.currentHeartRateBPM {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.heavy))
                        Text("\(Int(hr.rounded()))")
                            .font(.callout.weight(.heavy))
                            .monospacedDigit()
                        Text("bpm")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private func stationFooter(snapshot: RaceStateSnapshot) -> some View {
        VStack(spacing: 6) {
            if let station = snapshot.currentStation {
                Text(station.target(for: snapshot.division))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func advanceButton(snapshot: RaceStateSnapshot) -> some View {
        // Final-station guard mirrors the host's hold-to-finish:
        // a stray tap on the final segment locks in the race time
        // with no undo. We render a hold-to-confirm there too.
        let isFinal = snapshot.completedStationsCount + 1 == snapshot.totalStations

        return Group {
            if isFinal {
                HoldToConfirmButton(title: "Hold to Finish") {
                    controller.advance()
                }
            } else {
                Button {
                    Haptics.impact(.heavy)
                    controller.advance()
                } label: {
                    Text("Next Station")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.raceButtonHeight)
                        .background(
                            LinearGradient(
                                colors: [Color.accent, Color.accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                        .shadow(
                            color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.22),
                            radius: 18,
                            y: 0
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Paused

    private func pausedView(snapshot: RaceStateSnapshot) -> some View {
        let frozen: TimeInterval = {
            guard let start = snapshot.startedAt,
                  let pause = snapshot.pausedAt
            else { return 0 }
            return pause.timeIntervalSince(start)
        }()

        return VStack(spacing: 16) {
            connectionBanner

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "pause.fill")
                    .font(.caption.weight(.heavy))
                Text("PAUSED")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.surfaceElevated))

            Text(RaceStats.format(frozen))
                .font(.raceTimer)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let station = snapshot.currentStation {
                Text("on \(station.displayName)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Text("\(controller.partnerName ?? "Host") will resume on their phone.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // MARK: - In Roxzone

    private func roxzoneView(snapshot: RaceStateSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let transition = snapshot.currentSegmentStartedAt
                .map { context.date.timeIntervalSince($0) } ?? 0

            VStack(spacing: 16) {
                connectionBanner

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption.weight(.heavy))
                    Text("IN ROXZONE")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.warning.opacity(0.16)))

                Text(RaceStats.format(transition))
                    .font(.raceTimer)
                    .monospacedDigit()
                    .foregroundStyle(Color.warning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(
                        color: Color.warning.opacity(colorScheme == .dark ? 0.35 : 0.18),
                        radius: 18,
                        y: 0
                    )

                if let upcoming = snapshot.currentStation {
                    Text("Up next · \(upcoming.displayName)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    Haptics.impact(.heavy)
                    controller.startNextSegment()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .heavy))
                        Text("Start \(snapshot.currentStation?.displayName ?? "Next")")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                    .shadow(
                        color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.22),
                        radius: 18,
                        y: 0
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, Layout.screenMargin)
        }
    }

    // MARK: - Finished

    private func finishedView(snapshot: RaceStateSnapshot) -> some View {
        let total: TimeInterval = {
            guard let start = snapshot.startedAt,
                  let end = snapshot.endedAt
            else { return 0 }
            return end.timeIntervalSince(start)
        }()

        return VStack(spacing: 18) {
            connectionBanner

            Spacer(minLength: 24)

            HStack(spacing: 6) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.caption.weight(.heavy))
                Text("FINISHED")
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
            }
            .foregroundStyle(Color.success)

            Text(RaceStats.format(total))
                .font(.displayHero)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(
                    color: Color.success.opacity(colorScheme == .dark ? 0.35 : 0.18),
                    radius: 24,
                    y: 0
                )

            Text("Duo with \(controller.partnerName ?? "your partner")")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Button {
                Haptics.impact(.medium)
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // MARK: - Connection / waiting state

    private var connectionBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: controller.isConnected
                  ? "person.2.fill"
                  : "exclamationmark.triangle.fill")
                .font(.caption2.weight(.heavy))
            Text(controller.isConnected
                 ? "Duo · \(controller.partnerName ?? "partner")"
                 : "Disconnected")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(controller.isConnected ? Color.accent : Color.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                (controller.isConnected ? Color.accent : Color.warning)
                    .opacity(0.12)
            )
        )
        .padding(.top, 12)
    }

    private var connectingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)
            Text("Waiting for host…")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
            Text("\(controller.partnerName ?? "Your partner") will start the race.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#endif

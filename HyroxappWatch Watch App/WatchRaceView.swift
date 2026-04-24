import SwiftUI

// Live race screen for the watchOS companion app.
//
// Reads `WatchRaceClient.shared.snapshot` via `@Environment` and renders
// one of three states:
//   - `.waiting`   — no snapshot received yet (launched before the phone
//                    pushed anything, or paired phone not reachable).
//   - `.inProgress` — live race: computes its own timer from
//                     `snapshot.startedAt` every frame via TimelineView,
//                     shows current station + target + advance button.
//   - `.finished`   — frozen final time (from `endedAt - startedAt`),
//                     labeled "Finished".
// A separate `notStarted` phase rolls into `.waiting` visually — an
// idle phone with no active race looks the same to the athlete as a
// watch that hasn't heard from the phone yet.
//
// The watch does NOT own race state. Every field rendered here comes
// from the snapshot pushed by the phone. The only thing the watch
// computes locally is elapsed time (to avoid per-frame pushes eating
// the battery and network).
struct WatchRaceView: View {

    @Environment(WatchRaceClient.self) private var client

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            // Switch on phase. The `case` bindings pull the snapshot into
            // each branch so we can pass concrete values to the subviews
            // without having to unwrap optional fields everywhere.
            if let snapshot = client.snapshot {
                switch snapshot.phase {
                case .inProgress:
                    inProgressView(snapshot: snapshot)
                case .finished:
                    finishedView(snapshot: snapshot)
                case .notStarted:
                    waitingView
                }
            } else {
                waitingView
            }
        }
    }

    // MARK: - In-progress

    // Live race layout. TimelineView re-evaluates every animation frame;
    // we pass `context.date` into the timer formatter so the digits tick
    // without any manual `Timer` bookkeeping.
    private func inProgressView(snapshot: RaceStateSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            VStack(spacing: 8) {
                stationHeader(snapshot: snapshot)

                Spacer(minLength: 4)

                timerDisplay(snapshot: snapshot, now: context.date)

                Spacer(minLength: 4)

                advanceButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func stationHeader(snapshot: RaceStateSnapshot) -> some View {
        VStack(spacing: 2) {
            // 1-based station counter — matches the phone's "Station 3 of 16" label.
            Text("STATION \(snapshot.completedStationsCount + 1) OF \(snapshot.totalStations)")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.textSecondary)

            Text(snapshot.currentStation?.displayName ?? "—")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // Station target uses the user's division (from the snapshot)
            // so wall balls renders 75 reps / 100 reps correctly on the
            // watch too — no need for the watch to know about UserProfile.
            if let station = snapshot.currentStation {
                Text(station.target(for: snapshot.division))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func timerDisplay(snapshot: RaceStateSnapshot, now: Date) -> some View {
        // Compute elapsed locally from startedAt so the watch ticks in
        // sync with the phone without per-second pushes. `startedAt` is
        // always present in inProgress snapshots — but we guard with ??
        // for safety.
        let total = snapshot.startedAt.map { now.timeIntervalSince($0) } ?? 0
        let segment = snapshot.currentSegmentStartedAt.map { now.timeIntervalSince($0) } ?? 0

        return VStack(spacing: 2) {
            Text(RaceStats.format(total))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("segment \(RaceStats.format(segment))")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Finished

    private func finishedView(snapshot: RaceStateSnapshot) -> some View {
        let total: TimeInterval = {
            guard let start = snapshot.startedAt, let end = snapshot.endedAt else {
                return 0
            }
            return end.timeIntervalSince(start)
        }()

        return VStack(spacing: 10) {
            Text("FINISHED")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.accent)

            Text(RaceStats.format(total))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("\(snapshot.completedStationsCount) / \(snapshot.totalStations) stations")
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Waiting / idle

    // Shown when no snapshot has arrived yet, OR the phone reports
    // `.notStarted` (no race active). Visually identical for both —
    // from the athlete's perspective, nothing's happening yet.
    private var waitingView: some View {
        VStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.textTertiary)

            Text("Ready")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("Start a race on your iPhone")
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Advance button

    // On tap: fire a light haptic for immediate tactile confirmation
    // ("your tap was seen"), then send the advance action to the paired
    // iPhone. The iPhone's `RaceViewModel.advance()` handles the state
    // transition; the resulting state change propagates back to the
    // Watch via the application-context push, updating this view's
    // `snapshot` within 1-2 seconds.
    //
    // No hold-to-finish on Watch yet — the phone still requires it on
    // the final station, so the Watch's tap on station 16 is a safety
    // risk if mistapped. Worth addressing in a polish pass; for MVP we
    // rely on the user being deliberate with their wrist.
    private var advanceButton: some View {
        Button {
            Haptics.impact(.medium)
            WatchRaceClient.shared.send(.advance)
        } label: {
            Text("Next Station")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WatchRaceView()
        .environment(WatchRaceClient.shared)
}

import SwiftUI

// Watch-side live screen for an in-progress Free Run.
//
// Reads `FreeRunStateSnapshot` pushed from the iPhone every time the
// run state advances (start / pause / resume / end / split fired /
// distance update). Local TimelineView keeps the elapsed-time HUD
// ticking smoothly between snapshot pushes.
//
// Renders:
//   • Hero elapsed time (computed locally from snapshot.startedAt).
//   • Distance in the user's chosen unit.
//   • Average pace.
//   • HR chip (when sample present).
//   • Pause/Resume + End controls — send WatchAction.pauseFreeRun /
//     .resumeFreeRun / .endFreeRun back to iPhone.
//
// Mutually exclusive with WatchRaceView's race surface — the parent
// (WatchRaceView's body) dispatches to whichever snapshot is active.
struct WatchFreeRunView: View {

    let snapshot: FreeRunStateSnapshot

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(now: context.date)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 6) {
            header

            Spacer(minLength: 2)

            elapsedTime(now: now)

            distanceLabel

            paceLabel(now: now)

            hrChip

            Spacer(minLength: 4)

            controlBar
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.run")
                .font(WatchMetrics.font(size: 11, weight: .heavy))
            Text("FREE RUN")
                .font(WatchMetrics.font(size: 10, weight: .heavy))
                .tracking(0.6)
            Spacer()
            // Indoor/outdoor mini-pill
            Image(systemName: locationIconName)
                .font(WatchMetrics.font(size: 10, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
        }
        .foregroundStyle(Color.accent)
    }

    private func elapsedTime(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        return Text(RaceStats.format(elapsed))
            .font(WatchMetrics.font(size: 38, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var distanceLabel: some View {
        let units = snapshot.distanceMetres / metresPerUnit
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(String(format: "%.2f", units))
                .font(WatchMetrics.font(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(unitShortLabel)
                .font(WatchMetrics.font(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func paceLabel(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        let pace: TimeInterval? = {
            guard snapshot.distanceMetres > 0, elapsed > 0 else { return nil }
            return elapsed / (snapshot.distanceMetres / metresPerUnit)
        }()
        return Text(pace.map { "\(formatPace($0)) /\(unitShortLabel)" } ?? "—")
            .font(WatchMetrics.font(size: 12, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(Color.textSecondary)
    }

    @ViewBuilder
    private var hrChip: some View {
        // HR source priority — same dual-source approach the
        // race screen uses:
        //   1. Local Watch builder (zero-latency, ~1Hz from
        //      HKLiveWorkoutBuilder.didCollectDataOf)
        //   2. Snapshot HR from iPhone (1-3s roundtrip via
        //      WCSession application-context push)
        // Local always wins when present.
        if let hr = WatchWorkoutManager.shared.currentHeartRateBPM
            ?? snapshot.currentHeartRateBPM {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(WatchMetrics.font(size: 9, weight: .heavy))
                Text("\(Int(hr.rounded()))")
                    .font(WatchMetrics.font(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Color.accent)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            pauseResumeButton
            endButton
        }
    }

    private var pauseResumeButton: some View {
        let isPaused = (snapshot.phase == .paused)
        return Button {
            Haptics.impact(.medium)
            WatchRaceClient.shared.send(isPaused ? .resumeFreeRun : .pauseFreeRun)
        } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(WatchMetrics.font(size: 12, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: WatchMetrics.dim(34))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.surface)
                )
        }
        .buttonStyle(.plain)
    }

    private var endButton: some View {
        Button {
            Haptics.warning()
            WatchRaceClient.shared.send(.endFreeRun)
        } label: {
            Image(systemName: "stop.fill")
                .font(WatchMetrics.font(size: 12, weight: .heavy))
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: WatchMetrics.dim(34))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accent)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func computeElapsed(now: Date) -> TimeInterval {
        guard let started = snapshot.startedAt else { return 0 }
        switch snapshot.phase {
        case .notStarted: return 0
        case .inProgress: return now.timeIntervalSince(started)
        case .paused:
            return (snapshot.pausedAt ?? now).timeIntervalSince(started)
        case .finished:
            return (snapshot.endedAt ?? now).timeIntervalSince(started)
        }
    }

    private var metresPerUnit: Double {
        FreeRunSplitUnit(rawValue: snapshot.splitUnitRaw)?.metresPerUnit ?? 1609.344
    }

    private var unitShortLabel: String {
        FreeRunSplitUnit(rawValue: snapshot.splitUnitRaw)?.shortLabel ?? "mi"
    }

    private var locationIconName: String {
        FreeRunLocationType(rawValue: snapshot.locationTypeRaw)?.iconName ?? "figure.run"
    }

    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

import SwiftUI

// Watch-side live screen for an in-progress Free Run.
//
// Visually distinct from the race surface in three ways:
//   1. Distance is the hero — for a run, the question the athlete
//      glances down to answer is "how far have I gone," not "how
//      long has it been." Race mode hero is elapsed time because
//      the race is judged by total finish time; for a free run
//      that ranking flips.
//   2. Live recording dot pulses in the header — a Strava
//      convention that signals "we're actively capturing."
//   3. The accent gradient leans on a calmer running blue rather
//      than the race-mode coral, so a glance immediately reads as
//      "you're in a Run, not a Race."
//
// Reads `FreeRunStateSnapshot` pushed from the iPhone every time
// the run state advances. Local TimelineView keeps the elapsed-
// time HUD ticking smoothly between snapshot pushes.
struct WatchFreeRunView: View {

    let snapshot: FreeRunStateSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Drives the recording-dot pulse. Toggles on appear; the
    // animation modifier handles the actual breathing scale.
    @State private var dotPulsing = false

    // Free-Run-specific accent — calmer blue tone reads as
    // "running, not racing." Coral stays exclusive to race
    // surfaces so the two modes don't visually overlap.
    private let runAccent = Color(hex: 0x5BC0EB)

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(now: context.date)
            }
        }
        .onAppear {
            dotPulsing = true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 4) {
            header

            Spacer(minLength: 2)

            distanceHero

            elapsedAndPaceRow(now: now)

            hrChip

            Spacer(minLength: 4)

            controlBar
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // Header: live recording dot + "FREE RUN" + indoor/outdoor.
    // The pulsing dot is the at-a-glance "we're recording" cue
    // every running app from Strava onward uses.
    private var header: some View {
        HStack(spacing: 5) {
            recordingDot
            Text("FREE RUN")
                .font(WatchMetrics.font(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(runAccent)
            Spacer()
            Image(systemName: locationIconName)
                .font(WatchMetrics.font(size: 10, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // Pulsing red dot — running-app convention for "actively
    // recording." Frozen when paused. Reduce-motion-friendly:
    // collapses to a static dim dot when the accessibility
    // setting is on.
    private var recordingDot: some View {
        Circle()
            .fill(Color.accent)
            .frame(width: 8, height: 8)
            .opacity(snapshot.phase == .paused ? 0.35 : (dotPulsing ? 1.0 : 0.4))
            .animation(
                reduceMotion || snapshot.phase == .paused
                    ? .none
                    : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: dotPulsing
            )
    }

    // DISTANCE HERO — the headline metric for a run. Big,
    // monospaced, with a trailing unit suffix at a smaller weight.
    // Different from race mode where elapsed time is the hero;
    // for a run the question is "how far," not "how long."
    private var distanceHero: some View {
        let units = snapshot.distanceMetres / metresPerUnit
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(format: "%.2f", units))
                .font(WatchMetrics.font(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unitShortLabel)
                .font(WatchMetrics.font(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(runAccent)
        }
    }

    // Side-by-side time + pace row. Both are secondary to
    // distance but still glance-readable. Pace is the more
    // actionable of the two for a runner ("am I going at the
    // right effort?").
    private func elapsedAndPaceRow(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        let pace: TimeInterval? = {
            guard snapshot.distanceMetres > 0, elapsed > 0 else { return nil }
            return elapsed / (snapshot.distanceMetres / metresPerUnit)
        }()

        return HStack(spacing: 6) {
            // Time
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(WatchMetrics.font(size: 9, weight: .heavy))
                Text(RaceStats.format(elapsed))
                    .font(WatchMetrics.font(size: 13, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.textSecondary)

            Text("·")
                .font(WatchMetrics.font(size: 11, weight: .heavy))
                .foregroundStyle(Color.textTertiary)

            // Pace
            HStack(spacing: 3) {
                Image(systemName: "stopwatch")
                    .font(WatchMetrics.font(size: 9, weight: .heavy))
                Text(pace.map { formatPace($0) } ?? "—")
                    .font(WatchMetrics.font(size: 13, weight: .heavy))
                    .monospacedDigit()
                Text("/\(unitShortLabel)")
                    .font(WatchMetrics.font(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private var hrChip: some View {
        // HR source priority — local Watch builder first
        // (zero-latency, ~1Hz from HKLiveWorkoutBuilder), snapshot
        // HR fallback (1-3s WCSession roundtrip).
        if let hr = WatchWorkoutManager.shared.currentHeartRateBPM
            ?? snapshot.currentHeartRateBPM {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(WatchMetrics.font(size: 9, weight: .heavy))
                Text("\(Int(hr.rounded()))")
                    .font(WatchMetrics.font(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(WatchMetrics.font(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.surface)
            )
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

    // End button uses the run-accent blue rather than coral —
    // visually consistent with the rest of the free-run surface
    // and reinforces "you're stopping a run, not finishing a
    // race." Coral is reserved for race-mode primary actions.
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
                        .fill(
                            LinearGradient(
                                colors: [runAccent, runAccent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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

import SwiftUI
import SwiftData

#if canImport(UIKit)

// Live screen for an in-progress Free Run.
//
// Reads cumulative distance + HR from FreeRunViewModel (which is
// fed by FreeRunWorkoutManager's HKLiveWorkoutBuilder). Renders:
//   • Hero elapsed timer (recomputed from `phase`'s anchor — never
//     accumulated tick-by-tick).
//   • Distance HUD in the user's chosen unit (mile or km).
//   • Live pace (current — last 30s avg) + average pace (whole run).
//   • HR chip — fades in once a sample lands.
//   • Splits ribbon — chips for each completed split with split's
//     duration + pace.
//   • Pause/Resume + End controls.
//
// On end, persists the run, kicks off the post-finish HK rehydrate
// (~8s after to give buffered samples time to flush), and pushes
// FreeRunSummaryView. End is two-step (alert) so a sweaty mis-tap
// doesn't kill the run.
struct FreeRunView: View {

    let locationType: FreeRunLocationType
    let splitUnit: FreeRunSplitUnit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = FreeRunViewModel()
    @State private var isShowingEndConfirm = false

    // After end, pushes the summary view as a navigation
    // destination. Set to the just-finished run; cleared on
    // back-nav so the view can dismiss cleanly.
    @State private var finishedRun: FreeRun?

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                content(now: context.date)
            }
        }
        .navigationTitle("Free Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.modelContext = modelContext
            if !viewModel.hasActiveSession {
                viewModel.start(
                    locationType: locationType,
                    splitUnit: splitUnit
                )
            }

            #if canImport(WatchConnectivity)
            // Wire the Watch → iPhone action callback. The wrist's
            // pause/resume/end buttons send WatchAction.pauseFreeRun
            // / .resumeFreeRun / .endFreeRun via WCSession; this
            // routes them to the view model. Race-mode actions
            // (.advance, .pause, etc.) are ignored here — they're
            // handled by RaceView when a race is active.
            //
            // Mutually exclusive registration: a free run and a
            // HYROX race can't be active at the same time, so
            // overwriting the callback is safe.
            WatchCompanionService.shared.onAction = { action in
                switch action {
                case .pauseFreeRun: viewModel.pause()
                case .resumeFreeRun: viewModel.resume()
                case .endFreeRun:
                    let run = viewModel.activeRun
                    viewModel.end()
                    finishedRun = run
                    viewModel.finishSession()
                default: break
                }
            }
            #endif
        }
        .onDisappear {
            #if canImport(WatchConnectivity)
            // Clear the action handler so a stale closure doesn't
            // reference a torn-down view's state. RaceView re-
            // registers its own handler when its onAppear fires.
            WatchCompanionService.shared.onAction = nil
            #endif
        }
        .alert(
            "End run?",
            isPresented: $isShowingEndConfirm
        ) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                let run = viewModel.activeRun
                viewModel.end()
                // Snapshot the finished run BEFORE finishSession
                // tears down the view model — finishedRun drives
                // the navigation push to the summary.
                finishedRun = run
                viewModel.finishSession()
            }
        } message: {
            Text("Saves to your history. You can edit details after.")
        }
        .navigationDestination(item: $finishedRun) { run in
            FreeRunSummaryView(run: run, onClose: {
                dismiss()
            })
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 20) {
            heroTime(now: now)

            distanceAndPaceRow(now: now)

            hrChip

            splitsRibbon

            Spacer(minLength: 8)

            controlBar
        }
        .padding(.horizontal, Layout.screenMargin)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // Hero — big elapsed-time number.
    private func heroTime(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        return VStack(spacing: 4) {
            Text("ELAPSED")
                .font(.caption.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
            Text(RaceStats.format(elapsed))
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // Distance + pace tiles, side-by-side.
    private func distanceAndPaceRow(now: Date) -> some View {
        HStack(spacing: 12) {
            distanceTile
            paceTile(now: now)
        }
    }

    private var distanceTile: some View {
        let metres = viewModel.engine?.distanceMetres ?? 0
        let units = metres / splitUnit.metresPerUnit
        return VStack(spacing: 4) {
            Text("DISTANCE")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.2f", units))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(splitUnit.shortLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func paceTile(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        let metres = viewModel.engine?.distanceMetres ?? 0
        let pace: TimeInterval? = {
            guard metres > 0, elapsed > 0 else { return nil }
            return elapsed / (metres / splitUnit.metresPerUnit)
        }()

        return VStack(spacing: 4) {
            Text("AVG PACE")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(pace.map { formatPace($0) } ?? "—")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("/\(splitUnit.shortLabel)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Heart-rate chip — same visual language as RaceView's HR chip.
    @ViewBuilder
    private var hrChip: some View {
        if let bpm = viewModel.currentHeartRateBPM {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption.weight(.heavy))
                Text("\(Int(bpm.rounded()))")
                    .font(.callout.weight(.heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color.surface)
            )
        }
    }

    // Splits ribbon — small chip per completed split. Empty until
    // the first km/mile boundary fires.
    @ViewBuilder
    private var splitsRibbon: some View {
        let splits = viewModel.engine?.splits ?? []
        if !splits.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(splits) { split in
                        splitChip(for: split)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func splitChip(for split: FreeRunSplit) -> some View {
        VStack(spacing: 2) {
            Text("\(split.index + 1)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accent)
            Text(RaceStats.format(split.duration))
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .frame(width: 56, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            pauseResumeButton
            endButton
        }
    }

    private var pauseResumeButton: some View {
        let isPaused = viewModel.engine?.isPaused ?? false
        return Button {
            Haptics.impact(.medium)
            if isPaused {
                viewModel.resume()
            } else {
                viewModel.pause()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text(isPaused ? "Resume" : "Pause")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private var endButton: some View {
        Button {
            Haptics.warning()
            isShowingEndConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text("End")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color.accent.opacity(0.35), radius: 14, y: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func computeElapsed(now: Date) -> TimeInterval {
        guard let engine = viewModel.engine else { return 0 }
        switch engine.phase {
        case .notStarted: return 0
        case .inProgress(let startedAt): return now.timeIntervalSince(startedAt)
        case .paused(let startedAt, let pausedAt):
            return pausedAt.timeIntervalSince(startedAt)
        case .finished(let startedAt, let endedAt):
            return endedAt.timeIntervalSince(startedAt)
        }
    }

    // Pace renders as M:SS — typical conversational form for
    // running pace ("8:30 mile, 5:15 km").
    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#endif

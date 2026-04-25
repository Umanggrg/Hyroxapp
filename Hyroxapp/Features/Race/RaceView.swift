import SwiftUI
import SwiftData

// UIKit is iOS/iPadOS/visionOS/Mac-Catalyst only. The project's current target
// settings include macOS, where UIKit doesn't exist — guard the import so the
// file compiles on every platform the scheme may build for. The only thing we
// actually need from UIKit here is `UIApplication.isIdleTimerDisabled` to keep
// the screen awake mid-race (CLAUDE.md §6).
#if canImport(UIKit)
import UIKit
#endif

// Orchestrator for the Race flow. Owns the `RaceViewModel` and switches
// between the phase subviews (`RaceStartView`, in-progress, `RaceSummaryView`,
// `ResumePromptView`) based on VM state. Also hosts the `TimelineView` that
// drives the 20Hz timer while a race is in progress — the engine derives
// elapsed time from `context.date`, so no drift.
struct RaceView: View {

    // `@State` owns the VM's lifetime (iOS 17+ pattern for `@Observable`
    // classes — `@StateObject` is only for legacy `ObservableObject`).
    @State private var viewModel = RaceViewModel()

    // The user's profile — single row guaranteed by the ProfileView
    // bootstrap. We read `.division` from it to show the right wall ball
    // rep count on the final station. Falls back to `.mensOpen` if the
    // bootstrap hasn't run yet (first launch, Race tab tapped before
    // Profile) — harmless default.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Safe accessor — `resolvedDivision` coalesces the optional-stored
    // division to `.mensOpen` for rows that predate the field. Reading
    // `profile.division` directly would crash on old rows post-migration.
    private var division: Division {
        profiles.first?.resolvedDivision ?? .mensOpen
    }

    // Drives the "cancel race" confirmation alert. Kept in the view because
    // it's pure UI state (modal presentation) with no persistence meaning.
    @State private var showingCancelConfirm = false

    // Drives the mid-race splits peek sheet. Read-only view of completed
    // splits so the athlete can glance at their pace without abandoning the
    // race screen.
    @State private var showingSplits = false

    // SwiftUI injects the app's `ModelContext` via the environment. We hand
    // it to the VM on appear so it can insert / update / delete `Race` rows.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            Group {
                if let pending = viewModel.pendingResume {
                    ResumePromptView(
                        race: pending,
                        onResume: viewModel.resumePending,
                        onDiscard: viewModel.discardPending
                    )
                } else if !viewModel.hasStarted {
                    RaceStartView(viewModel: viewModel)
                } else if viewModel.isFinished {
                    RaceSummaryView(viewModel: viewModel)
                } else {
                    inProgressView
                }
            }
            .padding(.horizontal, Layout.screenMargin)
        }
        .onAppear {
            // Bind first so the subsequent fetch has a context to query.
            viewModel.bindModelContext(modelContext)
            viewModel.checkForResumableRace()
            // Push initial state so the watch is in sync on launch,
            // even if no race action has happened yet.
            publishWatchState()
            // Register a handler for actions coming from the Watch.
            // This view owns the race lifecycle, so it's the right
            // place to dispatch. The handler is cleared on disappear
            // so stray messages after the user leaves the Race tab
            // don't advance a race the user isn't watching.
            registerWatchActionHandler()
            // Ask HealthKit for read/write authorization now (if not
            // already granted) so the first race's HR queries during
            // station advances have permission to return samples. iOS
            // shows the prompt once ever; subsequent calls are no-ops.
            // Non-blocking — auth arrives in parallel with the user
            // prepping to tap Start Race.
            requestHealthKitAuthIfNeeded()
        }
        .onDisappear {
            #if canImport(WatchConnectivity)
            WatchCompanionService.shared.onAction = nil
            #endif
            // Cancel any in-flight speech so a stale "next: sled push"
            // doesn't fire after the user navigates away from Race.
            VoiceCueService.shared.stop()
        }
        // Fires when the user starts a new race, taps Done after finish,
        // or abandons mid-race — any transition in/out of an active-or-
        // finished race. Covers the "race began" and "race reset" cases.
        .onChange(of: viewModel.hasStarted) { _, isStarted in
            publishWatchState()
            // Stop any pending speech when the race ends or is reset
            // so a stale "next: ski erg" doesn't fire mid-summary.
            if !isStarted {
                VoiceCueService.shared.stop()
            } else {
                // Race just started — announce the first station so
                // the athlete hears their cue immediately on Start
                // (otherwise the first announcement would only fire
                // when they advance OUT of station 1).
                announceCurrentStationIfEnabled()
            }
        }
        // Fires on every station advance (0 → 1 → ... → 16). When the
        // final advance transitions the engine to `.finished`, this still
        // fires because the count increments as part of the advance.
        .onChange(of: viewModel.completedSegmentsCount) { _, _ in
            publishWatchState()
            announceTransitionIfEnabled()
        }
        // Keep the screen awake for the duration of an active race.
        // CLAUDE.md §6: the display must not dim mid-workout. Toggled off
        // again on finish, abandonment, or view-dismiss so we don't burn the
        // user's battery outside of a race.
        .onChange(of: viewModel.isRacing) { _, isRacing in
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = isRacing
            #endif
        }
        .onDisappear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .alert("Cancel this race?", isPresented: $showingCancelConfirm) {
            Button("Cancel Race", role: .destructive) {
                Haptics.warning()
                viewModel.abandon()
            }
            Button("Keep Racing", role: .cancel) { }
        } message: {
            Text("Your splits and total time will be discarded.")
        }
    }

    // MARK: - In-progress

    // `TimelineView(.periodic(...))` is SwiftUI's native way to re-render on
    // a fixed cadence. `context.date` is the current "now" snapshot; passing
    // it into the engine yields drift-free elapsed time. Replaces the manual
    // `Timer.publish` loop that would otherwise live in the view model.
    private var inProgressView: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    splitsChipButton
                    Text("Station \(viewModel.completedSegmentsCount + 1) of \(viewModel.totalSegments)")
                        .capsLabelStyle()
                    Spacer()
                    // Pace chip — only when a target was set on race
                    // start. Reads "+1:23 ahead" / "-0:45 behind" /
                    // "on pace" based on a naive even-split of the
                    // target across all stations.
                    paceChip(now: context.date)
                    // Live HR readout — only appears once a sample
                    // arrives from HealthKit. Positioned next to the
                    // cancel button so the four header controls read
                    // as "status · pace · HR · cancel" left to right.
                    liveHeartRateChip
                    cancelButton
                }
                .padding(.top, 8)

                Spacer()

                stationHeadline

                Spacer()

                timerColumn(now: context.date)

                Spacer()

                nextStationPreview

                advanceButton
                    .padding(.bottom, 16)
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showingSplits) {
            RaceSplitsSheetView(viewModel: viewModel)
        }
        #endif
    }

    private var stationHeadline: some View {
        VStack(spacing: 6) {
            if let station = viewModel.currentStation {
                Text(station.displayName)
                    .font(.stationTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                // Pass the user's division so wall balls renders the
                // correct rep count (75 for Women's Open, 100 otherwise).
                Text(station.target(for: division))
                    .font(.metadata)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func timerColumn(now: Date) -> some View {
        // Read the target once so both the color-check and the subtitle
        // reference the same value. `viewModel.activeRace` is the
        // single source of truth for per-race metadata like this.
        let target = viewModel.activeRace?.targetDuration
        let elapsed = viewModel.elapsed(at: now)
        // Warning tint kicks in exactly when the athlete crosses their
        // goal time — gives a visual "you're past your target now"
        // glance without needing to compute a delta in their head.
        let isOverTarget = (target.map { elapsed > $0 }) ?? false

        return VStack(spacing: 6) {
            Text(RaceStats.format(elapsed))
                .font(.raceTimer)
                .monospacedDigit()
                .foregroundStyle(isOverTarget ? Color.warning : Color.textPrimary)

            Text("segment \(RaceStats.format(viewModel.currentSegmentElapsed(at: now)))")
                .font(.metadata)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)

            // Target subtitle — only rendered when the athlete set
            // one. Tiny caps-label style so it reads as metadata, not
            // a second timer. Color matches the main timer so the
            // "I'm over goal" cue reinforces itself across both rows.
            if let target {
                Text("target \(RaceStats.format(target))")
                    .font(.metadata)
                    .monospacedDigit()
                    .foregroundStyle(isOverTarget ? Color.warning : Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var nextStationPreview: some View {
        if let upcoming = viewModel.upcomingStation {
            Text("Up next · \(upcoming.displayName)")
                .capsLabelStyle()
                .padding(.bottom, 12)
        } else {
            Text("Final station")
                .capsLabelStyle()
                .foregroundStyle(Color.accent)
                .padding(.bottom, 12)
        }
    }

    // Pace chip in the in-race header. Compares the athlete's actual
    // elapsed time vs. an even split of their target finish time
    // across the race's segments. Hidden when no target was set on
    // race start (the comparison is meaningless without a goal).
    //
    // Three visual states based on the signed delta:
    //   • "on pace" (textSecondary) when within 15s either way —
    //     a small dead zone keeps the chip from flickering between
    //     ahead/behind on every tick when the athlete is right on
    //     the line.
    //   • "+X:XX ahead" (success green) when faster than expected.
    //   • "-X:XX behind" (warning) when slower than expected.
    @ViewBuilder
    private func paceChip(now: Date) -> some View {
        if let target = viewModel.activeRace?.targetDuration {
            let actual = viewModel.elapsed(at: now)
            let expected = RaceStats.naiveExpectedElapsed(
                segmentsCompleted: viewModel.completedSegmentsCount,
                totalSegments: viewModel.totalSegments,
                target: target
            )
            let delta = RaceStats.paceDelta(
                actualElapsed: actual,
                expectedElapsed: expected
            )
            let absDelta = Swift.abs(delta)
            let onPace = absDelta < 15
            let label: String
            let color: Color
            if onPace {
                label = "on pace"
                color = Color.textSecondary
            } else if delta < 0 {
                // Negative delta = ahead of pace (actual < expected)
                label = "\(RaceStats.format(absDelta)) ahead"
                color = Color.success
            } else {
                label = "\(RaceStats.format(absDelta)) behind"
                color = Color.warning
            }

            HStack(spacing: 4) {
                Image(systemName: onPace
                      ? "equal.circle.fill"
                      : (delta < 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .monospacedDigit()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            .accessibilityLabel("Pace: \(label)")
        }
    }

    // Live HR readout in the in-progress header. Only rendered when
    // the VM has a value — hidden before the first poll returns, and
    // hidden entirely when HealthKit is unavailable / auth denied /
    // no Watch streaming samples.
    //
    // Tight pill styling matches the splits chip on the other side
    // of the header — the two read as peers in weight / hierarchy.
    @ViewBuilder
    private var liveHeartRateChip: some View {
        if let bpm = viewModel.currentHeartRateBPM {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(bpm.rounded()))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                Text("bpm")
                    .font(.caption2)
                    .tracking(0.3)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            .accessibilityLabel("Current heart rate \(Int(bpm.rounded())) beats per minute")
        }
    }

    // Small X in the top-right of the in-progress header. Confirmation alert
    // prevents an accidental tap from nuking an in-progress race.
    private var cancelButton: some View {
        Button {
            showingCancelConfirm = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.surface)
                )
        }
        .accessibilityLabel("Cancel race")
    }

    // A chip-style count of completed splits in the header's top-left. Taps
    // open the splits peek sheet — a low-friction way to glance at pace
    // without leaving the race screen. Hidden before the first split is
    // logged; nothing to show there.
    @ViewBuilder
    private var splitsChipButton: some View {
        if viewModel.completedSegmentsCount > 0 {
            Button {
                showingSplits = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(viewModel.completedSegmentsCount) Split\(viewModel.completedSegmentsCount == 1 ? "" : "s")")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.surface)
                )
            }
            .accessibilityLabel("View completed splits")
        }
    }

    // MARK: - Voice cues

    // Announce whatever station is currently active, gated on the
    // user's audio-cues preference. Called on race start so the
    // first station fires its cue immediately.
    private func announceCurrentStationIfEnabled() {
        guard profiles.first?.audioCuesEnabled ?? true else { return }
        if let station = viewModel.currentStation {
            VoiceCueService.shared.announceNextStation(station)
        }
    }

    // Called on every advance. After the engine moves to the next
    // station, announce that new station — or, if the engine just
    // transitioned to `.finished`, announce race completion instead.
    // The two messages are mutually exclusive: a finished race has
    // no `currentStation`, and an advanced-but-not-finished race
    // always has one.
    private func announceTransitionIfEnabled() {
        guard profiles.first?.audioCuesEnabled ?? true else { return }
        if viewModel.isFinished {
            VoiceCueService.shared.announceFinish()
        } else if let station = viewModel.currentStation {
            VoiceCueService.shared.announceNextStation(station)
        }
    }

    // MARK: - HealthKit

    // Kick off a one-time HealthKit authorization request. Fired from
    // `.onAppear` so the prompt appears when the user arrives at the
    // Race tab — contextual ("you're about to record a workout, here's
    // the permission ask"), not at cold launch (which would feel
    // invasive). Idempotent: iOS shows the system prompt once per
    // install regardless of how many times this runs.
    private func requestHealthKitAuthIfNeeded() {
        #if canImport(HealthKit)
        Task {
            _ = await HealthKitService.shared.requestAuthorization()
        }
        #endif
    }

    // MARK: - Watch sync

    // Install a handler for actions initiated on the Watch (tap Next
    // Station from the wrist, etc.). The handler is held by the
    // `WatchCompanionService` singleton and invoked on MainActor when
    // a message arrives. Cleared in `.onDisappear` so actions received
    // while the Race tab isn't on screen don't silently advance a race.
    private func registerWatchActionHandler() {
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.onAction = { action in
            switch action {
            case .advance:
                // Fire the same haptic + advance path as the iPhone's
                // Next Station button so a wrist tap feels identical
                // to a phone tap from the user's perspective.
                Haptics.impact(.medium)
                viewModel.advance()
            }
        }
        #endif
    }

    // Build a snapshot of the current race + user profile state and push
    // it to the watch companion. Called on view appear and on every
    // meaningful viewModel state change (see `.onChange` modifiers
    // above). Skips on platforms where WatchConnectivity isn't available
    // (macOS-native builds).
    //
    // Deriving the snapshot here rather than inside `RaceViewModel` keeps
    // the view model free of cross-cutting sync concerns — it stays the
    // single source of race truth, and the orchestrating view layer
    // handles the "what other surfaces need to know" plumbing.
    private func publishWatchState() {
        #if canImport(WatchConnectivity)
        let phase: RaceStateSnapshot.Phase
        let startedAt: Date?
        let segmentStartedAt: Date?
        let endedAt: Date?

        switch viewModel.engine.state {
        case .notStarted:
            phase = .notStarted
            startedAt = nil
            segmentStartedAt = nil
            endedAt = nil
        case .inProgress(let raceStart, let segStart, _):
            phase = .inProgress
            startedAt = raceStart
            segmentStartedAt = segStart
            endedAt = nil
        case .finished(let raceStart, let raceEnd, _):
            phase = .finished
            startedAt = raceStart
            segmentStartedAt = nil
            endedAt = raceEnd
        }

        // `currentStation` is nil once the race has finished (no next
        // station to point at). Fall back to the last station's index
        // (`totalSegments - 1`) so the watch still shows Wall Balls
        // on its finished state.
        let stationIndex: Int = {
            if let station = viewModel.currentStation {
                return station.rawValue
            } else {
                return max(0, viewModel.totalSegments - 1)
            }
        }()

        let snapshot = RaceStateSnapshot(
            phase: phase,
            startedAt: startedAt,
            currentSegmentStartedAt: segmentStartedAt,
            currentStationIndex: stationIndex,
            completedStationsCount: viewModel.completedSegmentsCount,
            totalStations: viewModel.totalSegments,
            divisionRaw: division.rawValue,
            endedAt: endedAt
        )

        WatchCompanionService.shared.publish(snapshot)
        #endif
    }

    // Intermediate stations get an instant-tap button — no risk in advancing
    // early, you're just moving to the next segment. The final station gets
    // a hold-to-confirm button because a stray tap there locks the race's
    // total time with no undo. The branch is pure UI; the view model's
    // `advance()` contract is identical in both cases.
    @ViewBuilder
    private var advanceButton: some View {
        if viewModel.upcomingStation == nil {
            HoldToConfirmButton(title: "Hold to Finish") {
                // `HoldToConfirmButton` fires its own success haptic on
                // completion — don't double-buzz.
                viewModel.advance()
            }
        } else {
            Button {
                // Fire the haptic before advancing so the buzz confirms
                // the tap was received even if the next state transition
                // happens to lag one frame.
                Haptics.impact(.medium)
                viewModel.advance()
            } label: {
                Text("Next Station")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(Color.accent)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
        }
    }
}

#Preview("Pre-race") {
    RaceView()
        .preferredColorScheme(.dark)
}

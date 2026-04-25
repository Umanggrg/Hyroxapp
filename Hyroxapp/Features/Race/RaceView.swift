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

    // Tracks the most recent zone we've fired a verbal cue for, so we
    // only announce on UPWARD entries (Z2 → Z3, Z3 → Z4, etc.) and
    // suppress noisy flutters back into lower zones. Reset to nil on
    // race end / abandon so a subsequent race re-announces from
    // scratch. Nil before the first HR sample arrives.
    @State private var lastAnnouncedZone: HRZone?

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
                    .padding(.horizontal, Layout.screenMargin)
                } else if !viewModel.hasStarted {
                    // RaceStartView owns its own padding so the hero
                    // backdrop can bleed full-width.
                    RaceStartView(viewModel: viewModel)
                } else if viewModel.isFinished {
                    // Same — RaceSummaryView controls its own bleed
                    // so the finish-moment backdrop reaches the edges.
                    RaceSummaryView(viewModel: viewModel)
                } else if viewModel.isInRoxzone {
                    // Two-tap-advance mode: between segments the
                    // user lands here. Big "Start [next station]"
                    // button + countup transition timer.
                    inRoxzoneView
                        .padding(.horizontal, Layout.screenMargin)
                } else {
                    inProgressView
                        .padding(.horizontal, Layout.screenMargin)
                }
            }

            // Countdown overlay — full-screen, sits above the
            // start screen so the athlete sees a clean 3 → 2 → 1
            // → GO ritual before the race timer takes over. Tap
            // anywhere to skip straight to the race. Bound to
            // viewModel.countdownValue so cancellation (race
            // abandoned, view dismissed) clears the overlay.
            if let value = viewModel.countdownValue {
                countdownOverlay(value: value)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.countdownValue)
        // Per-tick side effects for the countdown — voice cue +
        // haptic. Fires exactly once per integer change. The voice
        // cue speaks the number ("3", "2", "1", "GO"); the haptic
        // pattern uses medium impact for 3/2/1 and a heavier
        // notification on GO so the start of the race is
        // physically felt.
        .onChange(of: viewModel.countdownValue) { _, newValue in
            guard let newValue else { return }
            handleCountdownTick(newValue)
        }
        // Mid-race HR-zone monitor. Each time a new HR sample
        // arrives, classify it and fire a "Zone X" cue if the
        // athlete just crossed UPWARD into Z3+. Suppresses
        // downward flutters and Z1/Z2 entries (athletes don't
        // need a "Zone 1, recovery" reminder mid-race).
        .onChange(of: viewModel.currentHeartRateBPM) { _, newBpm in
            handleHeartRateZoneChange(newBpm)
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
        //
        // Also resets the HR zone-announcement tracker on race end —
        // without this, a subsequent race would suppress its own
        // first Z3+ entry because the previous race's final zone was
        // still in @State.
        .onChange(of: viewModel.isRacing) { _, isRacing in
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = isRacing
            #endif
            if !isRacing {
                lastAnnouncedZone = nil
            }
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
                    pauseResumeButton
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
            // PAUSED indicator on top — small caps-style ribbon that
            // makes the frozen-timer state unmistakable. Hidden while
            // running, otherwise it's the most prominent thing in the
            // column.
            if viewModel.isPaused {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill")
                        .font(.caption.weight(.bold))
                    Text("PAUSED")
                        .font(.caption.weight(.heavy))
                        .tracking(1.0)
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.warning.opacity(0.15))
                )
            }

            Text(RaceStats.format(elapsed))
                .font(.raceTimer)
                .monospacedDigit()
                // Paused dims the timer to textTertiary so the freeze
                // is visually obvious — the cue stacks with the
                // PAUSED ribbon above for redundant signaling.
                .foregroundStyle(
                    viewModel.isPaused
                        ? Color.textTertiary
                        : (isOverTarget ? Color.warning : Color.textPrimary)
                )

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
            VStack(spacing: 4) {
                Text("UP NEXT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
                Text(upcoming.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 16)
        } else {
            // Final station — heightened treatment so the moment
            // before the finish reads as significant. Coral text
            // with a subtle pulse-by-presence (we don't animate
            // here, just elevate the typography).
            VStack(spacing: 4) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.accent)
                Text("FINAL STATION")
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(Color.accent)
            }
            .padding(.bottom, 16)
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
        if let state = paceChipState(now: now) {
            HStack(spacing: 4) {
                Image(systemName: state.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(state.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .monospacedDigit()
            }
            .foregroundStyle(state.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            .accessibilityLabel("Pace: \(state.label)")
        }
    }

    // Snapshot of what to render in the pace chip — computed
    // outside the @ViewBuilder so the body of paceChip stays a
    // pure view expression. @ViewBuilder closures don't allow
    // multi-statement assignment blocks inside `if let ...` —
    // returning a small struct from this helper keeps the View
    // composition trivial.
    private struct PaceChipState {
        let label: String
        let color: Color
        let icon: String
    }

    private func paceChipState(now: Date) -> PaceChipState? {
        guard let target = viewModel.activeRace?.targetDuration else {
            return nil
        }
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

        // 15-second dead zone keeps the chip from flickering between
        // ahead/behind on every tick when the athlete is right on
        // the line.
        if absDelta < 15 {
            return PaceChipState(
                label: "on pace",
                color: Color.textSecondary,
                icon: "equal.circle.fill"
            )
        } else if delta < 0 {
            // Negative = actual elapsed is less than expected = ahead.
            return PaceChipState(
                label: "\(RaceStats.format(absDelta)) ahead",
                color: Color.success,
                icon: "arrow.up.right"
            )
        } else {
            return PaceChipState(
                label: "\(RaceStats.format(absDelta)) behind",
                color: Color.warning,
                icon: "arrow.down.right"
            )
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
            // Compute zone live from current HR + the athlete's max
            // HR setting. Tints the entire chip in the zone color so
            // the athlete can pace by zone color at a glance, not
            // just by BPM number — much faster to read mid-sprint.
            let zone = HRZone.zone(for: bpm, maxBPM: maxHeartRate)

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(bpm.rounded()))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                // Zone label appears as a small "Z3" suffix so the
                // athlete sees both the raw number and the zone in
                // one glance. Strava-watch-face style.
                Text("Z\(zone.rawValue)")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(zone.color.opacity(0.25))
                    )
            }
            .foregroundStyle(zone.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            .accessibilityLabel("Current heart rate \(Int(bpm.rounded())) beats per minute, \(zone.displayName)")
        }
    }

    // The athlete's configured max HR — drives zone classification on
    // the live HR chip. Falls back to a sensible 190 default when no
    // profile is bootstrapped yet (defensive — the bootstrap should
    // always have run by the time the user starts a race).
    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // Full-screen pre-race countdown overlay. Massive number,
    // animated transition between values, tap anywhere to skip.
    // 0 renders as "GO" (the final beat before the race screen
    // takes over). Voice cues + haptics fire from the
    // `.onChange(of: viewModel.countdownValue)` side-effect
    // attached at the body level so they play exactly once per
    // tick.
    private func countdownOverlay(value: Int) -> some View {
        ZStack {
            // Solid blackout — covers the start screen behind so
            // there's no visual competition with the giant number.
            Color.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(value > 0 ? "\(value)" : "GO")
                    .font(.system(
                        size: value > 0 ? 220 : 160,
                        weight: .black,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(value > 0 ? Color.textPrimary : Color.accent)
                    // Spring scale-in per tick — value-keyed so
                    // each new number gets its own animation,
                    // making the count read as a rhythm rather
                    // than a static replacement.
                    .id(value)
                    .transition(
                        .scale(scale: 0.5).combined(with: .opacity)
                    )

                Text("Tap to skip")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 80)
            }
        }
        .contentShape(Rectangle())  // make whole area tappable
        .onTapGesture {
            viewModel.skipCountdown(targetDuration: viewModel.activeRace?.targetDuration)
            Haptics.impact(.heavy)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: value)
    }

    // Pause / Resume toggle. Shows a pause glyph while the race is
    // running, swaps to a play glyph when paused. Tapping freezes
    // (or resumes) the timer, the engine handles the elapsed-time
    // math via timestamp shifts so splits already captured are
    // unaffected. Useful for real-world interruptions — phone call,
    // someone hogging the sled, an unplanned break — that previously
    // forced an athlete to abandon and lose the race.
    private var pauseResumeButton: some View {
        Button {
            if viewModel.isPaused {
                viewModel.resumeRace()
                Haptics.success()
            } else {
                viewModel.pauseRace()
                Haptics.warning()
            }
        } label: {
            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(viewModel.isPaused ? Color.success : Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.surface)
                )
        }
        .accessibilityLabel(viewModel.isPaused ? "Resume race" : "Pause race")
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

    // Mid-race zone-entry handler. Fires when the live HR poll
    // returns a new sample. We classify the sample, compare against
    // `lastAnnouncedZone`, and announce ONLY when the new zone is
    // strictly higher AND is Z3 or above. Lower-zone entries
    // (recovery, aerobic) are suppressed because mid-race they
    // create noise — the athlete doesn't need a "Zone 1, recovery"
    // reminder when they're trying to push.
    //
    // Even when the announcement is suppressed (audio cues off or
    // zone too low), we still update `lastAnnouncedZone` so a
    // subsequent UPWARD crossing through the suppressed zone
    // doesn't re-fire spuriously.
    private func handleHeartRateZoneChange(_ bpm: Double?) {
        guard let bpm else {
            // HR poll cleared — race ended, profile not authorized,
            // or simply between samples. Don't reset state here;
            // the isRacing handler does that on race end. Mid-race
            // we want a missing sample to be a no-op rather than a
            // reset that re-announces on the next sample.
            return
        }

        let zone = HRZone.zone(for: bpm, maxBPM: maxHeartRate)
        let previous = lastAnnouncedZone ?? .z1

        let isUpward = zone.rawValue > previous.rawValue
        let isInteresting = zone.rawValue >= HRZone.z3.rawValue

        if isUpward && isInteresting {
            if profiles.first?.audioCuesEnabled ?? true {
                VoiceCueService.shared.announceZoneEntry(zone)
            }
            // Light haptic alongside the voice — same idea as
            // station-transition cues. Subtle confirmation that the
            // app noticed the zone change even when audio is off.
            Haptics.impact(.light)
        }

        // Always update the tracker, even when no announcement
        // fired. Re-entering a higher zone after a dip (Z4 → Z3 →
        // Z4) DOES re-fire because the second Z3→Z4 transition is
        // still "upward" relative to the just-updated Z3. That's
        // intentional: re-entering threshold mid-race is worth
        // calling out again — it means the athlete pushed back.
        lastAnnouncedZone = zone
    }

    // Per-tick handler for the pre-race countdown. Fires a haptic
    // (heavier on GO than on the digits) and a voice cue ("3", "2",
    // "1", "Go"). Voice gated on the audio-cues setting; haptic
    // always fires because it's silent and reinforces the rhythm
    // even when the phone is muted.
    private func handleCountdownTick(_ value: Int) {
        // Haptic: medium for digits, heavy for the GO beat.
        if value == 0 {
            Haptics.success()
        } else {
            Haptics.impact(.medium)
        }

        // Voice: gated on the same audioCuesEnabled flag the rest
        // of the race screen uses, so users who train without
        // verbal cues stay silent through the countdown too.
        guard profiles.first?.audioCuesEnabled ?? true else { return }
        VoiceCueService.shared.announceCountdownTick(value)
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
        case .paused(let raceStart, let segStart, _, _):
            // Watch sync currently has no .paused phase, so map
            // pause to .inProgress and let the watch keep ticking
            // visually. The phone is the authoritative timer; on
            // resume we publish a fresh snapshot with shifted
            // timestamps and the watch catches up. A proper
            // .paused-aware snapshot phase is tracked in the §13
            // backlog as a v2 polish.
            phase = .inProgress
            startedAt = raceStart
            segmentStartedAt = segStart
            endedAt = nil
        case .inRoxzone(let raceStart, _, let roxStart):
            // Watch sync similarly has no .inRoxzone phase.
            // Treat as inProgress for the watch — overall race
            // time keeps ticking, and the watch surface's
            // segment timer will reset when the next segment
            // starts on the phone. Same v2-polish caveat.
            phase = .inProgress
            startedAt = raceStart
            segmentStartedAt = roxStart
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
            // Disable while paused — the timer is frozen so advancing
            // would close the segment with a stale split duration.
            // Tap pause-to-resume first.
            .disabled(viewModel.isPaused)
            .opacity(viewModel.isPaused ? 0.4 : 1.0)
        } else {
            // Roxzone-mode: button reads "End [station]" and routes
            // through endSegmentRace so the engine enters .inRoxzone
            // (where startNextSegment-Race takes over).
            //
            // Single-tap mode: button reads "Next Station" and calls
            // advance() directly, preserving the v1 behavior.
            let useRoxzone = (profiles.first?.roxzoneEnabled ?? false)
            Button {
                Haptics.impact(.medium)
                if useRoxzone {
                    viewModel.endSegmentRace()
                } else {
                    viewModel.advance()
                }
            } label: {
                Text(useRoxzone ? "End Station" : "Next Station")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(Color.accent)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            .disabled(viewModel.isPaused)
            .opacity(viewModel.isPaused ? 0.4 : 1.0)
        }
    }

    // MARK: - Roxzone view

    // Shown when the engine is in `.inRoxzone` between segments.
    // Big countup transition timer + "Start [next]" CTA. Same
    // header chips as the in-progress view so the athlete still
    // sees overall race time, HR, pace, etc.
    private var inRoxzoneView: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    splitsChipButton
                    Text("Station \(viewModel.completedSegmentsCount + 1) of \(viewModel.totalSegments)")
                        .capsLabelStyle()
                    Spacer()
                    paceChip(now: context.date)
                    liveHeartRateChip
                    pauseResumeButton
                    cancelButton
                }
                .padding(.top, 8)

                Spacer()

                // Hero block — "IN ROXZONE" caps wordmark in
                // warning orange, big countup transition timer
                // below it, then the next-station prompt.
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption.weight(.heavy))
                        Text("IN ROXZONE")
                            .font(.caption.weight(.heavy))
                            .tracking(2.0)
                    }
                    .foregroundStyle(Color.warning)

                    Text(RaceStats.format(viewModel.currentRoxzoneElapsed(at: context.date)))
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.warning)
                        .shadow(color: Color.warning.opacity(0.35), radius: 18, x: 0, y: 0)

                    Text("TRANSITION TIME")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.4)
                        .foregroundStyle(Color.textSecondary)

                    if let upcoming = viewModel.currentStation {
                        Text("Up next · \(upcoming.displayName)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.top, 12)
                    }
                }

                Spacer()

                // Primary CTA — start the next segment. Same
                // gradient + glow language as RaceStartView's
                // primary so the action reads as "you're
                // starting work again."
                Button {
                    Haptics.impact(.heavy)
                    viewModel.startNextSegmentRace()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .heavy))
                        Text("Start \(viewModel.currentStation?.displayName ?? "Next")")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.accent.opacity(0.4), radius: 18, x: 0, y: 0)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPaused)
                .opacity(viewModel.isPaused ? 0.4 : 1.0)
                .padding(.bottom, 16)
            }
        }
    }
}

#Preview("Pre-race") {
    RaceView()
        .preferredColorScheme(.dark)
}

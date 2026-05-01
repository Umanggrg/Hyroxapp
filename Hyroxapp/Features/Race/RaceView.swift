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

    // Historical races — needed to derive the personal HR baseline
    // for the live coaching cue. Sorted descending so the baseline
    // helper's "recent N races" prefix grabs the most recent ones.
    // Wrapped in a @Query rather than passed in because the cue is
    // used from many entrypoints (live race, finished race summary
    // peek, etc.) and each consumer would otherwise have to thread
    // the array through manually. SwiftData @Query is cheap enough
    // for tens of races that we don't bother memoizing.
    @Query(sort: [SortDescriptor(\Race.createdAt, order: .reverse)])
    private var allRaces: [Race]

    // Personalized HR band — derived once per render from
    // `allRaces`. Returns nil until the athlete has 8+ run-split
    // HR samples (roughly one full HYROX race with HR data); the
    // coaching cue falls back to textbook Z3 in that case. We
    // recompute on every body re-evaluation; the underlying
    // helper is O(N runs * sort) which is microseconds for any
    // realistic history size.
    private var personalHRBaseline: RaceStats.PersonalHRBaseline? {
        RaceStats.personalHRBaseline(across: allRaces)
    }

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

    // MARK: - Duo state (lifted from RaceStartView)
    //
    // These outlive RaceStartView: the user pairs on the start
    // screen, RaceStartView disappears when the race begins, and the
    // duo coordinator + controller need to keep running through the
    // whole race. Owned here at RaceView level; bindings passed down
    // to RaceStartView so the chip + pairing sheet still mutate the
    // same state.

    // The user's currently-selected race format. Defaults to .solo;
    // flips to .duo only after a successful pairing flow.
    @State private var selectedMode: RaceMode = .solo

    // Pairing-level coordinator. Created on first Duo chip tap;
    // torn down when the user reverts to Solo or finishes a duo race.
    @State private var duoCoordinator: DuoCoordinator?

    // In-race controller. Created when pairing reaches .ready and
    // the local user starts the race (host) OR receives the first
    // running snapshot (guest). Owns the bridge between the
    // RaceViewModel + DuoCoordinator while a duo race is active.
    @State private var duoController: DuoRaceController?

    // Drives the DuoPairingView sheet presented from RaceStartView.
    @State private var isPairingPresented = false

    // Drives the "Start Run" overlay shown when the athlete enters
    // a run station with manual run start enabled. Lifetime: set
    // true on the run-station transition (in the .onChange watcher
    // below), cleared when the user taps Start Run or when the
    // station changes again.
    @State private var isAwaitingRunStart = false

    // Active mode — drives shadow / glow opacity scaling on the
    // in-race CTAs and overlays. Coral spotlights tuned for OLED
    // black would read as a heavy wash on warm off-white, so we
    // dial them back ~50% in light.
    @Environment(\.colorScheme) private var colorScheme

    // Drives the in-race motion bypass: when the system
    // accessibility setting is on, all spring/scale animations
    // collapse to .none and the race screen reads as static
    // (vestibular-sensitive users can still race without
    // the visual motion).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    RaceStartView(
                        viewModel: viewModel,
                        selectedMode: $selectedMode,
                        duoCoordinator: $duoCoordinator,
                        duoController: $duoController,
                        isPairingPresented: $isPairingPresented
                    )
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
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    // Roxzone slides in from below
                                    // with a slight scale-up — reads
                                    // as the screen "lifting up to
                                    // surface the transition timer."
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.96)),
                                    // Slides back down on dismiss
                                    // (start next segment) so the
                                    // exit reverses the entry.
                                    removal: .move(edge: .bottom)
                                        .combined(with: .opacity)
                                )
                        )
                } else {
                    inProgressView
                        .padding(.horizontal, Layout.screenMargin)
                        .transition(.opacity)
                }
            }
            // Roxzone enter/exit drives the asymmetric transitions
            // above. Same spring shape used by onboarding step
            // transitions so the motion feels coherent across
            // surfaces.
            .animation(
                reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.85),
                value: viewModel.isInRoxzone
            )

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
            // Manual run start overlay — only shown when the
            // athlete enters a run station with the setting on.
            // Z-stacks over the in-progress view so the regular
            // race UI stays in place underneath. Total race
            // timer keeps ticking; only the segment timer (and
            // the athlete) is paused at the start line until
            // they tap Start Run.
            if isAwaitingRunStart {
                startRunOverlay
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96))
                    )
            }
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85),
            value: viewModel.countdownValue
        )
        .animation(
            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85),
            value: isAwaitingRunStart
        )
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
            // Push the athlete's max HR into the view model so
            // currentLiveActivityState() can pre-compute the HR
            // zone for the Live Activity. The view-side
            // `maxHeartRate` reads from the user profile via
            // @Query; if the profile is loaded by now, that's the
            // value; otherwise the viewModel keeps its 190 default
            // until the .onChange below fires.
            viewModel.maxHeartRate = maxHeartRate
        }
        .onDisappear {
            #if canImport(WatchConnectivity)
            WatchCompanionService.shared.onAction = nil
            WatchCompanionService.shared.onHeartRate = nil
            #endif
            // Cancel any in-flight speech so a stale "next: sled push"
            // doesn't fire after the user navigates away from Race.
            VoiceCueService.shared.stop()
        }
        // Keep the viewModel's maxHR in sync with the profile so
        // the Live Activity's HR zone classification reflects any
        // edits the user makes in Settings while a race is in
        // flight (rare but possible — and harmless to wire).
        .onChange(of: profiles.first?.maxHeartRate) { _, newValue in
            if let newValue {
                viewModel.maxHeartRate = newValue
            }
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
        // Fires on EVERY engine-state mutation, including pause /
        // resume / endSegment / startNextSegment that the two
        // hooks above miss (those only see hasStarted + advance
        // transitions). Covers the watch and duo broadcasts so
        // pausing / roxzoning the race propagates to both.
        //
        // Equatable comparison is cheap: enum case + a few Date
        // values + an array of up to 16 Splits. No heavy work.
        .onChange(of: viewModel.engine.state) { _, _ in
            publishWatchState()
            #if canImport(MultipeerConnectivity)
            duoController?.broadcastCurrent()
            #endif
        }
        // HR samples land asynchronously every ~5s during an active
        // race. They don't change engine.state, so the hook above
        // doesn't catch them — without this dedicated watcher the
        // watch + guest would only see HR updates piggybacked on
        // the next state change, which could be a minute away.
        // Pushing on every HR change keeps both surfaces fresh.
        // WCSession's updateApplicationContext deduplicates
        // identical payloads internally, so a redundant push is
        // free.
        .onChange(of: viewModel.currentHeartRateBPM) { _, _ in
            publishWatchState()
            #if canImport(MultipeerConnectivity)
            duoController?.broadcastCurrent()
            #endif
        }
        // Watch the underlying duo session state directly. When it
        // transitions to .disconnected during an active race, stamp
        // the active Race with the moment of disconnect via the
        // helper below. We observe the session (not the
        // coordinator's higher-level CoordState) because the
        // session has a clean top-level .disconnected case; the
        // coordinator wraps it inside .hosting / .joining variants
        // that would require nested pattern-matching.
        #if canImport(MultipeerConnectivity)
        .onChange(of: duoCoordinator?.session.state) { _, newState in
            handleDuoSessionStateChange(newState)
        }
        #endif
        // Manual run start trigger. When the active station flips
        // to a run AND the athlete has the setting on, raise the
        // overlay so they can pre-position before timing begins.
        // Skip the very first run (race start) — the existing
        // 3-2-1-GO countdown ritual already handles that case.
        .onChange(of: viewModel.currentStation) { _, newStation in
            handleStationChangedForManualRun(newStation)
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
        // Guest's race screen — full-screen cover routed in when
        // the local user paired as a guest AND a snapshot has
        // arrived from the host. The binding + content live in
        // separate helpers so the body's modifier chain stays
        // small enough for Swift's type inferencer.
        #if canImport(MultipeerConnectivity)
        .fullScreenCover(isPresented: guestRaceCoverBinding) {
            guestRaceCoverContent
        }
        #endif
    }

    // True once the local user is acting as a guest AND the host
    // has broadcast at least one running snapshot. Drives the
    // fullScreenCover binding below.
    #if canImport(MultipeerConnectivity)
    private var isGuestRaceActive: Bool {
        guard let controller = duoController,
              controller.role == .guest,
              let snapshot = controller.latestSnapshot
        else { return false }
        return snapshot.phase != .notStarted
    }

    // Custom binding for the fullScreenCover. Pulled into its own
    // property because Swift's type-checker chokes on `Binding(get:
    // set:)` literals nested inside a long modifier chain — see
    // "compiler unable to type-check this expression" failures.
    // Pulling this out trims the body's expression complexity and
    // the inferencer resolves everything cleanly.
    private var guestRaceCoverBinding: Binding<Bool> {
        Binding(
            get: { isGuestRaceActive },
            set: { newValue in
                if !newValue {
                    // User dismissed (deliberate or post-finish).
                    // Tear down the duo connection so a fresh
                    // race can start cleanly.
                    duoController = nil
                    duoCoordinator?.cancel()
                    duoCoordinator = nil
                    selectedMode = .solo
                }
            }
        )
    }

    @ViewBuilder
    private var guestRaceCoverContent: some View {
        if let controller = duoController {
            DuoGuestRaceView(controller: controller)
        }
    }

    // Handler for `.onChange(of: duoCoordinator?.session.state)`.
    // Stamps `partnerDisconnectedAt` on the active race when the
    // duo session drops mid-race. Pulled out as a function so the
    // body's modifier chain stays small enough for Swift's type
    // inferencer (inline `case` + multi-line `guard` in a
    // closure-passed-to-onChange tripped it earlier).
    private func handleDuoSessionStateChange(_ newState: DuoSession.State?) {
        guard case .disconnected = newState else { return }
        guard let race = viewModel.activeRace,
              race.endedAt == nil,
              race.partnerDisconnectedAt == nil
        else { return }
        race.partnerDisconnectedAt = Date()
        try? race.modelContext?.save()
    }
    #endif

    // Watcher for `viewModel.currentStation` changes. Shows the
    // Start Run overlay when:
    //   1. The new station is a run (Station.kind == .run)
    //   2. The athlete has manualRunStartEnabled in their profile
    //   3. We're past the race's first station (the 3-2-1 countdown
    //      already gives the athlete a moment to prep before run1;
    //      a second prompt would be redundant)
    //   4. The race is running, not paused / inRoxzone / finished
    //
    // Otherwise dismisses any open overlay (e.g. station changes to
    // a workout, or race ends).
    private func handleStationChangedForManualRun(_ newStation: Station?) {
        guard let station = newStation,
              station.kind == .run,
              profiles.first?.manualRunStartEnabled == true,
              viewModel.hasStarted,
              !viewModel.isFinished,
              viewModel.completedSegmentsCount > 0
        else {
            isAwaitingRunStart = false
            return
        }
        isAwaitingRunStart = true
    }

    // MARK: - In-progress

    // `TimelineView(.periodic(...))` is SwiftUI's native way to re-render on
    // a fixed cadence. `context.date` is the current "now" snapshot; passing
    // it into the engine yields drift-free elapsed time. Replaces the manual
    // `Timer.publish` loop that would otherwise live in the view model.
    private var inProgressView: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            VStack(spacing: 0) {
                #if canImport(MultipeerConnectivity)
                // Duo connection chip — only when a duo race is
                // active on the host side. Mirrors the guest's
                // connectionBanner so both partners see the same
                // "Duo · with Sarah" / "Disconnected" status at a
                // glance. Sits above the header row so it gets a
                // dedicated line — the header is already packed
                // with splits / station / pace / HR / pause /
                // cancel.
                if let controller = duoController, controller.role == .host {
                    duoConnectionChip(controller: controller)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                }
                #endif

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
                    #if canImport(MultipeerConnectivity)
                    // Partner's HR during a duo race. Sits next to
                    // the local HR chip so a glance reads "us
                    // (165) — them (172)". Only renders when a
                    // duo is active and the partner has streamed a
                    // sample at least once.
                    partnerHeartRateChip
                    #endif
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
        // Keying by station + applying a content transition makes
        // SwiftUI crossfade the station name + target on advance
        // rather than snapping. The user feels the race progress
        // through the motion. Numeric-text content transition
        // animates between distinct text contents at the
        // typography level — Apple's recommended pattern for
        // info that changes.
        .id(viewModel.currentStation)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .animation(
            reduceMotion ? .none : .smooth(duration: 0.4),
            value: viewModel.currentStation
        )
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

            // Predicted finish projection — naive linear extrapolation
            // of current pace forward to the full race. Different
            // question than the pace chip above: pace says "are you
            // ahead/behind your target *right now*"; this says "at
            // this rate, when will you actually finish?" Both are
            // useful — one's about the moment, one's about the
            // outcome.
            //
            // Tinted green when projecting under the athlete's
            // target (on track to beat goal), warning amber when
            // projecting over (going to miss). Without a target
            // set, renders neutral textTertiary — informational
            // rather than a verdict.
            if let predicted = RaceStats.predictedFinishTime(
                segmentsCompleted: viewModel.completedSegmentsCount,
                totalSegments: viewModel.totalSegments,
                actualElapsed: elapsed
            ) {
                let predictedDelta = RaceStats.predictedFinishDelta(
                    predicted: predicted,
                    target: target
                )
                let predictedColor: Color = {
                    guard let predictedDelta else { return .textTertiary }
                    return predictedDelta <= 0 ? .success : .warning
                }()

                Text("projected \(RaceStats.format(predicted))")
                    .font(.metadata)
                    .monospacedDigit()
                    .foregroundStyle(predictedColor)
                    // Numeric content transition keeps the digits
                    // animating smoothly as the projection updates
                    // each tick — at 0.05s timeline cadence the
                    // digits would otherwise jitter.
                    .contentTransition(.numericText())
                    .animation(
                        reduceMotion ? .none : .smooth(duration: 0.4),
                        value: predictedColor
                    )
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
                    // Content transition for the icon glyph swap
                    // when crossing pace thresholds (chevron-up
                    // → equal → chevron-down). The default jump
                    // would feel binary; symbolEffect smooths it.
                    .contentTransition(.symbolEffect(.replace))
                Text(state.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    // Numeric-text content transition keeps the
                    // delta number ("+0:12") animating smoothly
                    // as the gap to expected pace evolves second
                    // by second rather than snapping each tick.
                    .contentTransition(.numericText())
            }
            .foregroundStyle(state.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            // Color crossfade when crossing thresholds — going
            // from amber "behind" to green "ahead" should feel
            // like a victory, not a snap. The animation hooks
            // both the foreground tint and the icon symbol
            // replacement at once.
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.4),
                value: state.label
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
            // Coaching cue translates the zone into actionable
            // language while running: HOLD / SLOW / PUSH. Workout
            // stations get .workout (no pace cue — see RaceStats
            // comment). Replaces the previous bare "Z3" tag —
            // coaching language is more useful mid-race than the
            // training-plan zone number.
            let cue = RaceStats.coachingCue(
                currentHR: bpm,
                maxHR: maxHeartRate,
                currentStation: viewModel.engine.currentStation,
                personalLowerHR: personalHRBaseline?.lowerQuartile,
                personalUpperHR: personalHRBaseline?.upperQuartile
            )
            // For run stations the chip tint follows the cue
            // (green hold / red slow / blue push) so the same
            // color signal reads at a glance whether you're racing
            // it right. For workout stations there's no pace cue,
            // so we fall back to the zone color (still meaningful
            // — Z5 redline mid-sled-push reads as red without
            // commanding "slow down").
            let chipColor: Color = {
                switch cue {
                case .hold:    return Color.success
                case .slow:    return Color.accent
                case .push:    return Color(hex: 0x5B9BD5)
                case .workout, .none: return zone.color
                }
            }()

            HStack(spacing: 4) {
                // Heartbeat icon — pulses at a tempo synced with
                // the actual displayed HR (rough proxy for the
                // athlete's heart rate). Period = 60/bpm seconds.
                // Subtle scale 0.9 → 1.1 with ease-out for the
                // "beat" feel. Off when reduce-motion is set.
                HeartbeatIcon(bpm: bpm)
                Text("\(Int(bpm.rounded()))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    // Numeric content transition smooths the BPM
                    // digits so the chip ticks rather than snaps
                    // between samples. ~5s polling interval makes
                    // the difference visible — without this each
                    // refresh would jump.
                    .contentTransition(.numericText())
                // Coaching pill — HOLD / SLOW / PUSH on runs;
                // WORK on workout stations. Hidden when the cue
                // is .none (no HR or no station).
                if cue != .none {
                    Text(cue.displayText)
                        .font(.caption2.weight(.heavy))
                        .tracking(0.3)
                        .contentTransition(.identity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(chipColor.opacity(0.25))
                        )
                }
            }
            .foregroundStyle(chipColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            // Zone color crossfade when crossing zone boundaries.
            // The chip's tint cascade (text + icon + Z-pill bg)
            // all animate together for a unified feel — the
            // athlete sees the chip "warm up" toward Z5 / "cool
            // down" toward Z2 rather than flicking discretely.
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.4),
                value: cue
            )
            .accessibilityLabel("Current heart rate \(Int(bpm.rounded())) beats per minute, \(zone.displayName), \(cue.displayText)")
        }
    }

    // The athlete's configured max HR — drives zone classification on
    // the live HR chip. Falls back to a sensible 190 default when no
    // profile is bootstrapped yet (defensive — the bootstrap should
    // always have run by the time the user starts a race).
    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    #if canImport(MultipeerConnectivity)
    // Partner's HR readout — visible only during an active duo
    // race when the partner has actually streamed at least one
    // sample. Tighter / dimmer styling than the local chip so a
    // glance hierarchy reads "this is yours, that is theirs."
    // Same heart icon + bpm but with the partner's name as a
    // tracking-tight prefix ("Sarah · 172") to disambiguate.
    @ViewBuilder
    private var partnerHeartRateChip: some View {
        if let controller = duoController,
           let bpm = controller.partnerHeartRateBPM {
            HStack(spacing: 4) {
                Image(systemName: "heart")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(bpm.rounded()))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.accentDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surface)
            )
            .accessibilityLabel("Partner heart rate \(Int(bpm.rounded())) beats per minute")
        }
    }
    #endif

    #if canImport(MultipeerConnectivity)
    // Status banner shown above the in-race header when a duo
    // race is active. Mirrors `DuoGuestRaceView.connectionBanner`
    // shape and tinting so both partners see the same chip
    // structure — coral when paired, amber-warning if the link
    // drops mid-race.
    //
    // Centered horizontally so it reads as a status anchor for
    // the screen rather than competing with the per-station
    // header below.
    @ViewBuilder
    private func duoConnectionChip(controller: DuoRaceController) -> some View {
        HStack {
            Spacer()
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
            Spacer()
        }
    }
    #endif

    // Manual run start overlay — full-screen blackout with a big
    // "Ready?" caps label, the upcoming run's name, and a single
    // tap-to-start CTA. Total race timer keeps ticking through
    // (the race is in progress; the athlete is just pre-positioning),
    // but the visual emphasis is on the prompt so they know the
    // segment hasn't begun timing yet.
    //
    // On confirm: rebases the engine's currentSegmentStartedAt to
    // now, dismisses the overlay, fires a haptic + voice cue. Same
    // pattern as the start-of-race countdown — a single decisive
    // tap.
    private var startRunOverlay: some View {
        ZStack {
            HeroBackdrop(.intense)

            VStack(spacing: 18) {
                Text("READY?")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(Color.accent)

                Text(viewModel.currentStation?.displayName ?? "Run")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Pre-position at the start line. The segment timer begins when you tap.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                Button {
                    Haptics.impact(.heavy)
                    viewModel.rebaseCurrentSegment(at: Date())
                    isAwaitingRunStart = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .heavy))
                        Text("Start Run")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
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
                .padding(.horizontal, Layout.screenMargin)
            }
        }
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
                // The Watch's snapshot doesn't carry the user's
                // roxzone-enabled flag, so the phone routes
                // .advance based on its own engine state:
                //   • .inRoxzone → startNextSegment (begin work)
                //   • .inProgress + roxzone on → endSegment (close
                //     segment, enter roxzone)
                //   • .inProgress + roxzone off → advance (close
                //     segment, begin next instantly)
                //   • other → engine ignores no-op call
                // Same effect: a wrist tap always advances the race
                // state correctly without the Watch needing to know
                // the user's settings.
                Haptics.impact(.medium)
                routeWatchAdvance()
            case .endSegment:
                Haptics.impact(.medium)
                viewModel.endSegmentRace()
            case .startNextSegment:
                Haptics.impact(.medium)
                viewModel.startNextSegmentRace()
            case .pause:
                Haptics.warning()
                viewModel.pauseRace()
            case .resume:
                Haptics.success()
                viewModel.resumeRace()
            }
        }

        // HR samples published from the Watch's HKLiveWorkoutBuilder.
        // The handler forwards each sample into the view model which
        // writes to `currentHeartRateBPM` (the same property the
        // phone-side HealthKit poll writes to). Watch samples arrive
        // at ~1Hz so they dominate the displayed value when active;
        // the phone poll continues as a fallback when no Watch is
        // paired or its workout session isn't running.
        WatchCompanionService.shared.onHeartRate = { update in
            viewModel.ingestHeartRate(update)
        }
        #endif
    }

    // Smart routing for the Watch's `.advance` action so a single
    // wrist button works through the full race state machine
    // including the roxzone two-step flow. Pulled out as a helper
    // so the registerWatchActionHandler closure stays small for
    // Swift's type-checker.
    private func routeWatchAdvance() {
        switch viewModel.engine.state {
        case .inRoxzone:
            viewModel.startNextSegmentRace()
        case .inProgress:
            if profiles.first?.roxzoneEnabled == true {
                viewModel.endSegmentRace()
            } else {
                viewModel.advance()
            }
        default:
            viewModel.advance()
        }
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
        // Snapshot construction now lives in `RaceViewModel` — same
        // helper feeds both the watch path here and the duo
        // broadcast path on `DuoRaceController`. Returning nil
        // means engine is .notStarted (nothing meaningful to
        // publish); we still send a stub for the watch's idle
        // state so it transitions out of .finished cleanly.
        if let snapshot = viewModel.makeRaceStateSnapshot(
            division: division,
            maxHR: maxHeartRate,
            personalHRBaseline: personalHRBaseline
        ) {
            WatchCompanionService.shared.publish(snapshot)
        } else {
            // Engine is in .notStarted — synthesize a minimal
            // notStarted snapshot so the watch returns to its
            // waiting state instead of holding the last finished
            // snapshot indefinitely. Same payload the make helper
            // would build if it didn't early-exit.
            let snapshot = RaceStateSnapshot(
                phase: .notStarted,
                startedAt: nil,
                currentSegmentStartedAt: nil,
                currentStationIndex: 0,
                completedStationsCount: 0,
                totalStations: viewModel.totalSegments,
                divisionRaw: division.rawValue,
                endedAt: nil,
                pausedAt: nil,
                maxHeartRate: maxHeartRate
            )
            WatchCompanionService.shared.publish(snapshot)
        }
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
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(Color.accent)
                    // White-on-coral is the brand contract for
                    // primary CTAs — `Color.textPrimary` would flip
                    // to near-black warm in light mode and read as
                    // muted on the coral surface.
                    .foregroundStyle(Color.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            // Pressable-card style scales the button to 0.98 on
            // press with a 0.3s spring. Same tactile feedback as
            // the rest of the app's tappable surfaces — sweaty
            // mid-race fingers get clear "your tap registered"
            // confirmation through the scale instead of waiting
            // for the next-station screen to render.
            .buttonStyle(.pressableCard)
            .disabled(viewModel.isPaused)
            .opacity(viewModel.isPaused ? 0.4 : 1.0)
            // Pause-state opacity now animates rather than
            // snapping when the athlete pauses/resumes mid-race.
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.25),
                value: viewModel.isPaused
            )
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
                        // Amber glow scales with mode — same logic
                        // as the accent shadow on the start button.
                        .shadow(
                            color: Color.warning.opacity(colorScheme == .dark ? 0.35 : 0.18),
                            radius: 18,
                            x: 0,
                            y: 0
                        )

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
                    // Brand-contract white-on-coral; see Color.onAccent.
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
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    // Glow scales with mode — full strength on OLED
                    // black, dialed back on warm off-white to keep
                    // the button from looking like it's leaking
                    // coral fog onto the bg.
                    .shadow(
                        color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.22),
                        radius: 18,
                        x: 0,
                        y: 0
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPaused)
                .opacity(viewModel.isPaused ? 0.4 : 1.0)
                .padding(.bottom, 16)
            }
        }
    }
}

// Pulsing heart icon for the live HR chip — beats at the tempo of
// the actual displayed HR (60/bpm period). Subtle scale 0.9 → 1.15
// with ease-out so the icon "thumps" rather than wobbles. Pure
// visual cue; conveys aliveness when the athlete glances at the
// timer column.
//
// Off when accessibilityReduceMotion is set — replaced with a
// static heart so vestibular-sensitive users get the same data
// without the rhythm.
private struct HeartbeatIcon: View {
    let bpm: Double

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Period of one full beat in seconds, derived from the displayed
    // HR. At 60bpm = 1.0s per beat; 180bpm = 0.33s per beat. Clamped
    // to a 0.3s minimum so very-high-HR readings don't strobe at
    // distracting frequencies (and to stay safe for photosensitive
    // users — 0.3s = ~3.3Hz, well below the 4Hz photosensitivity
    // safety threshold).
    private var beatPeriod: Double {
        let raw = 60.0 / max(bpm, 30)
        return max(0.3, raw)
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 10, weight: .semibold))
            .scaleEffect(pulsing && !reduceMotion ? 1.15 : 0.9)
            .animation(
                reduceMotion
                    ? .none
                    : .easeOut(duration: beatPeriod * 0.5)
                        .repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear {
                if !reduceMotion {
                    pulsing = true
                }
            }
    }
}

#Preview("Pre-race") {
    RaceView()
        .preferredColorScheme(.dark)
}

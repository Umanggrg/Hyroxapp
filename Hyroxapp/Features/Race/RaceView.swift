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

    // Wireframe §03.4 — finish hero is the 3-second celebration
    // overlay that plays after a race ends, before the summary
    // view takes the screen. State flag flipped true via the
    // `viewModel.isFinished` onChange watcher; auto-dismissed by
    // a scheduled Task; can also be skipped via tap.
    @State private var isShowingFinishHero = false
    @State private var finishHeroDismissTask: Task<Void, Never>?

    // §19 — mid-race HR source fallover banner. Fires when
    // SensorSourceRegistry's lastHRSource changes during an
    // active race (Watch disconnects → AirPods take over, or
    // vice versa). 2s auto-dismiss; no haptic — informational
    // only.
    @State private var hrSourceBanner: HRSourceBannerInfo?
    @State private var hrSourceBannerDismissTask: Task<Void, Never>?
    @State private var lastObservedHRSource: SensorSourceRegistry.HRSource = .unknown

    // Wireframe 03.4 — pause-sheet presentation state. Set true
    // when athlete taps the in-race pause button; the engine is
    // paused alongside so the underlying timer freezes while the
    // sheet is visible. Resume / Restart actions flip it false
    // and resume the engine; End / Discard actions chain into
    // their respective confirm alerts before mutating state.
    @State private var isShowingPauseSheet = false

    // Two separate confirm alerts for the destructive paths the
    // pause sheet exposes. Distinct from the legacy
    // showingCancelConfirm (still wired to long-press on Pause
    // for back-compat) — these are the wireframe §03.4 routes.
    @State private var showingEndEarlyConfirm = false
    @State private var showingDiscardConfirm = false

    // Wireframe 03.3 — coaching banner overlay state.
    //
    // `activeCoachingCue` holds the cue currently being displayed
    // by the banner (nil = banner hidden). `lastBannerFiredCue`
    // remembers the last cue we showed so we don't re-fire the
    // same banner on every HR tick — only on transitions.
    // `lastBannerFiredAt` enforces a 10s cooldown between any
    // two banners. `lastHRSampleForCue` retains the previous HR
    // for trend computation (recover state).
    @State private var activeCoachingCue: RaceStats.CoachingCue?
    @State private var lastBannerFiredCue: RaceStats.CoachingCue?
    @State private var lastBannerFiredAt: Date?
    @State private var lastHRSampleForCue: Double?
    @State private var coachingBannerDismissTask: Task<Void, Never>?

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

    // Cloud-backed (Tier 2) counterpart to `duoCoordinator`. The
    // user picks the transport mode after tapping the Duo chip:
    // Local Duo → `duoCoordinator`, Cross-city Duo →
    // `cloudDuoCoordinator`. Only one is ever non-nil at a time.
    // Both conform to `DuoTransport`, so the in-race
    // `duoController` works identically regardless of which is
    // populated.
    @State private var cloudDuoCoordinator: CloudDuoCoordinator?

    // In-race controller. Created when pairing reaches .ready and
    // the local user starts the race (host) OR receives the first
    // running snapshot (guest). Owns the bridge between the
    // RaceViewModel + transport coordinator while a duo race is
    // active.
    @State private var duoController: DuoRaceController?

    // Drives the DuoPairingView sheet (Local Duo) presented from
    // RaceStartView.
    @State private var isPairingPresented = false

    // Drives the CloudDuoPairingView sheet (Cross-city Duo).
    @State private var isCloudPairingPresented = false

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
        // The body is split deliberately: the ZStack carries only
        // a small set of modifiers (animations + presentations),
        // and the observer modifiers (.onChange, .onAppear,
        // .onDisappear) live on a child via `attachObservers(to:)`.
        // This splits the type-inference graph in two — Swift was
        // hitting its budget when ~20 modifiers were stacked on a
        // single ZStack expression. Each half now type-checks
        // independently and well under the limit.
        ZStack {
            Color.background.ignoresSafeArea()

            // Main phase content + ALL the .onChange / .onAppear /
            // .onDisappear observer modifiers live on this child.
            // Wrapping mainPhaseContent in `attachObservers(to:)`
            // gives the observers their own `some View` type
            // rather than nesting them onto the ZStack's type.
            attachObservers(to: mainPhaseContent)

            countdownOverlayIfActive
            startRunOverlayIfActive
            coachingBannerOverlay
            hrSourceBannerOverlay
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85),
            value: viewModel.countdownValue
        )
        .animation(
            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85),
            value: isAwaitingRunStart
        )
        .alert("Cancel this race?", isPresented: $showingCancelConfirm) {
            Button("Cancel Race", role: .destructive) {
                Haptics.warning()
                viewModel.abandon()
            }
            Button("Keep Racing", role: .cancel) { }
        } message: {
            Text("Your splits and total time will be discarded.")
        }
        // Wireframe §03.4 — pause sheet. Content closure +
        // onDismiss handler extracted into helpers below so the
        // body's modifier chain doesn't balloon SwiftUI's
        // type-check time. Was previously inline with 4 closures
        // (Resume/Restart/End/Discard) which is enough nesting to
        // tip the compiler over.
        .sheet(
            isPresented: $isShowingPauseSheet,
            onDismiss: handlePauseSheetDismiss,
            content: { pauseSheetContent }
        )
        // End-race-here confirm. Wireframe §03.4 final phone:
        // "End race here?" + partial-save explanation.
        .alert("End race here?", isPresented: $showingEndEarlyConfirm) {
            Button("End race, save partial", role: .destructive) {
                Haptics.warning()
                viewModel.endEarlyAndSave()
                isShowingPauseSheet = false
            }
            Button("Keep going", role: .cancel) { }
        } message: {
            Text(endEarlyConfirmMessage)
        }
        // Discard confirm — throw away the race entirely.
        // Distinct from end-early: no partial save, no row in
        // History, no Live Activity finish ribbon.
        .alert("Discard race?", isPresented: $showingDiscardConfirm) {
            Button("Discard", role: .destructive) {
                Haptics.warning()
                viewModel.abandon()
                isShowingPauseSheet = false
            }
            Button("Keep racing", role: .cancel) { }
        } message: {
            Text("Your splits and total time will be thrown away. This race won't appear in your history.")
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

    // Wireframe §03 observer attachment — splits the type-check
    // graph by hosting all .onChange / .onAppear / .onDisappear
    // modifiers on a child view rather than the root ZStack.
    //
    // SwiftUI's type-checker had been hitting its complexity
    // budget with ~20 modifiers stacked on a single ZStack
    // expression (deep generic nesting:
    // `ModifiedContent<ModifiedContent<...<ZStack<...>>>`). By
    // wrapping the child here and returning `some View`, the
    // resulting modifier chain is opaque from the body's point
    // of view — Swift treats it as a single anonymous View type,
    // not a deeply-nested generic. The body's modifier chain
    // shrinks from ~20 modifiers to ~7, well within budget.
    @ViewBuilder
    private func attachObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: viewModel.countdownValue) { _, newValue in
                handleCountdownValueChange(newValue)
            }
            .onChange(of: viewModel.currentHeartRateBPM) { _, newBpm in
                handleHeartRateChange(newBpm)
            }
            .onChange(of: viewModel.completedSegmentsCount) { _, _ in
                evaluateCoachingBanner(newHR: viewModel.currentHeartRateBPM)
            }
            .onChange(of: viewModel.hasStarted) { _, hasStarted in
                handleHasStartedChangeForBannerCleanup(hasStarted)
            }
            .onChange(of: viewModel.isFinished) { _, finished in
                if finished {
                    presentFinishHero()
                }
            }
            .onAppear(perform: handleRaceViewAppear)
            .onDisappear(perform: handleRaceViewDisappear)
            .onChange(of: profiles.first?.maxHeartRate) { _, newValue in
                handleProfileMaxHRChange(newValue)
            }
            .onChange(of: viewModel.hasStarted) { _, isStarted in
                handleHasStartedChangeForVoiceCues(isStarted)
            }
            .onChange(of: viewModel.completedSegmentsCount) { _, _ in
                handleSegmentsCountChangeForWatchSync()
            }
            .onChange(of: viewModel.engine.state) { _, _ in
                handleEngineStateChange()
            }
            .onChange(of: viewModel.currentHeartRateBPM) { _, _ in
                handleHeartRateChangeForWatchSync()
            }
            // §19 — mid-race HR source fallover. Watch the
            // registry's lastHRSource; if it changes while a
            // race is in progress AND the previous value was
            // a real source (not .unknown — that's the initial
            // assignment), fire a 2s informational banner so
            // the athlete knows their HR data is intact under
            // a different sensor.
            .onChange(of: SensorSourceRegistry.shared.lastHRSource) { oldValue, newValue in
                handleHRSourceChange(from: oldValue, to: newValue)
            }
            #if canImport(MultipeerConnectivity)
            .onChange(of: duoCoordinator?.session.state) { _, newState in
                handleDuoSessionStateChange(newState)
            }
            #endif
            #if canImport(Supabase)
            .onChange(of: cloudDuoCoordinator?.session.state) { _, newState in
                handleCloudDuoSessionStateChange(newState)
            }
            #endif
            .onChange(of: viewModel.currentStation) { _, newStation in
                handleStationChangedForManualRun(newStation)
            }
            .onChange(of: viewModel.isRacing) { _, isRacing in
                handleIsRacingChange(isRacing)
            }
    }

    // Elapsed-time label rendered in the pause sheet hero. Uses
    // the engine's frozen elapsed (since the engine is paused
    // when this sheet shows). Formats as MM:SS or H:MM:SS.
    private var pauseSheetElapsedLabel: String {
        let elapsed = viewModel.elapsed(at: Date())
        return RaceStats.format(elapsed)
    }

    // Wireframe §03.4 — pause sheet content. Extracted into a
    // computed property so the body's modifier chain doesn't
    // balloon SwiftUI's type-check time. Each action closure is
    // tiny but four-of-them-in-line was enough to tip the
    // compiler over when the body already had alerts, sheets,
    // and a dozen onChange handlers stacked.
    @ViewBuilder
    private var pauseSheetContent: some View {
        RacePauseSheetView(
            elapsedLabel: pauseSheetElapsedLabel,
            stationLabel: pauseSheetStationLabel,
            onResume: handlePauseResume,
            onRestart: handlePauseRestart,
            onEnd: handlePauseEnd,
            onDiscard: handlePauseDiscard
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // Pause sheet action handlers — pulled to functions so the
    // pauseSheetContent property stays a pure view expression and
    // the action wiring is easy to scan side-by-side.

    private func handlePauseResume() {
        Haptics.success()
        viewModel.resumeRace()
        isShowingPauseSheet = false
    }

    private func handlePauseRestart() {
        Haptics.impact(.medium)
        // Resume first so the engine transitions back to
        // .inProgress (rebase is a .inProgress-only mutation;
        // while paused it's a no-op). Then rebase to "now" so
        // the segment timer resets visually. Total elapsed is
        // unchanged — we're restarting THIS segment, not the
        // whole race.
        viewModel.resumeRace()
        viewModel.rebaseCurrentSegment(at: Date())
        isShowingPauseSheet = false
    }

    private func handlePauseEnd() {
        // Open the End-race confirm. Sheet stays mounted so the
        // athlete sees the underlying pause context while reading
        // the confirm copy.
        showingEndEarlyConfirm = true
    }

    private func handlePauseDiscard() {
        showingDiscardConfirm = true
    }

    // Pause sheet dismiss handler — fires on drag-away or
    // tap-outside (i.e., the user dismissed without picking a
    // button). Treats dismissal as Resume so the race continues
    // without the athlete having to tap Pause again.
    private func handlePauseSheetDismiss() {
        if viewModel.isPaused {
            viewModel.resumeRace()
        }
    }

    // MARK: - View lifecycle handlers (extracted from body)
    //
    // The body's `.onAppear` and `.onDisappear` closures were
    // contributing meaningfully to the body's type-check time —
    // each closure expression is part of the body's overall view
    // graph and Swift type-checks them as part of the whole.
    // Pulling them into named functions lets the body reference
    // them via method-value syntax (`.onAppear(perform: ...)`),
    // which side-steps the closure type-inference work.

    private func handleRaceViewAppear() {
        // Bind first so the subsequent fetch has a context to
        // query.
        viewModel.bindModelContext(modelContext)
        viewModel.checkForResumableRace()
        // Push initial state so the watch is in sync on launch.
        publishWatchState()
        // Register the Watch-action handler so a wrist tap can
        // advance the race even when the phone isn't in front.
        registerWatchActionHandler()
        // Ask HealthKit for read/write authorization now (if not
        // already granted) so the first race's HR queries during
        // station advances have permission to return samples.
        requestHealthKitAuthIfNeeded()
        // Push the athlete's max HR into the view model so
        // currentLiveActivityState() can pre-compute the HR
        // zone. The view-side `maxHeartRate` reads from the user
        // profile via @Query; the .onChange watcher below keeps
        // it in sync after this initial push.
        //
        // `self.maxHeartRate` here is the RaceView's computed
        // property (not viewModel.maxHeartRate which is the
        // assignment target). The explicit `self.` disambiguates
        // the two same-named properties for the type-checker.
        viewModel.maxHeartRate = self.maxHeartRate
        // §19.4 10I/10J — mirror the AirPods running-economy opt-in
        // from UserProfile into the viewModel so the stamping
        // paths can gate without re-querying SwiftData mid-race.
        viewModel.airPodsRunningEconomyEnabled =
            profiles.first?.airPodsRunningEconomyEnabled ?? false
    }

    private func handleRaceViewDisappear() {
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.onAction = nil
        WatchCompanionService.shared.onHeartRate = nil
        // §13.8 Tier 2 — clear the rep count handler so a stale
        // closure can't fire after the user navigates away from
        // Race. Same teardown discipline as onAction / onHeartRate.
        WatchCompanionService.shared.onRepCount = nil
        // §47a — same discipline for the end-of-segment timestamp
        // batch. Even though this only fires at segment-end (so
        // a stale closure would rarely matter), keeping the
        // teardown symmetric with the other Watch callbacks
        // avoids surprising leaks if the close window races with
        // navigation.
        WatchCompanionService.shared.onRepTimestamps = nil
        #endif
        // Cancel any in-flight speech so a stale "next: sled push"
        // doesn't fire after the user navigates away from Race.
        VoiceCueService.shared.stop()
        // Release the screen-awake lock acquired during a race.
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    // Extracted .onChange handler for `viewModel.isRacing`. Same
    // type-check reasoning as the lifecycle handlers above.
    private func handleIsRacingChange(_ isRacing: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = isRacing
        #endif
        if !isRacing {
            lastAnnouncedZone = nil
        }
    }

    // .onChange handler for `viewModel.countdownValue` — voice
    // cue + haptic per tick. Voice cue gated on the audio-cues
    // setting; haptic always fires (silent, reinforces rhythm
    // even when phone is muted).
    private func handleCountdownValueChange(_ newValue: Int?) {
        guard let newValue else { return }
        handleCountdownTick(newValue)
    }

    // .onChange handler for `viewModel.currentHeartRateBPM` —
    // updates the HR-zone announcement state + evaluates the
    // wireframe §03.3 coaching-banner trigger.
    private func handleHeartRateChange(_ newBpm: Double?) {
        handleHeartRateZoneChange(newBpm)
        evaluateCoachingBanner(newHR: newBpm)
    }

    // .onChange handler for `viewModel.hasStarted` — race-reset
    // cleanup for the coaching banner + finish-hero state.
    private func handleHasStartedChangeForBannerCleanup(_ hasStarted: Bool) {
        if !hasStarted {
            coachingBannerDismissTask?.cancel()
            activeCoachingCue = nil
            lastBannerFiredCue = nil
            lastBannerFiredAt = nil
            lastHRSampleForCue = nil
            finishHeroDismissTask?.cancel()
            isShowingFinishHero = false
        }
    }

    // .onChange handler for `profiles.first?.maxHeartRate` —
    // mirrors profile edits into the view model so the Live
    // Activity's HR zone classification stays fresh.
    private func handleProfileMaxHRChange(_ newValue: Int?) {
        if let newValue {
            viewModel.maxHeartRate = newValue
        }
    }

    // .onChange handler for `viewModel.hasStarted` — voice cue
    // lifecycle + watch state publish. Distinct from the
    // banner-cleanup handler above; both fire on the same value
    // change but they're independent concerns.
    private func handleHasStartedChangeForVoiceCues(_ isStarted: Bool) {
        publishWatchState()
        if !isStarted {
            VoiceCueService.shared.stop()
        } else {
            announceCurrentStationIfEnabled()
        }
    }

    // .onChange handler for `viewModel.completedSegmentsCount` —
    // publishes watch state + voice-announces the new station.
    private func handleSegmentsCountChangeForWatchSync() {
        publishWatchState()
        announceTransitionIfEnabled()
    }

    // .onChange handler for `viewModel.engine.state` — catches
    // every engine mutation (pause / resume / endSegment /
    // startNextSegment) and re-publishes to the watch + duo
    // broadcasts so partner surfaces stay in sync.
    private func handleEngineStateChange() {
        publishWatchState()
        #if canImport(MultipeerConnectivity)
        duoController?.broadcastCurrent()
        #endif
    }

    // .onChange handler for `viewModel.currentHeartRateBPM` —
    // re-publishes to the watch + duo on every fresh HR sample
    // so partner HR + Live Activity stay in sync. (Distinct
    // from `handleHeartRateChange` which drives the banner.)
    private func handleHeartRateChangeForWatchSync() {
        publishWatchState()
        #if canImport(MultipeerConnectivity)
        duoController?.broadcastCurrent()
        #endif
    }

    // MARK: - Finish hero (wireframe §03.4)

    // Race total duration for the finish hero. Reads from the
    // just-finished active race; falls back to "now − engine
    // startedAt" if the race row hasn't yet been mirrored from
    // the engine (rare — persistActiveRace runs synchronously on
    // advance, so by the time isFinished fires this is set).
    private var finishHeroTotalDuration: TimeInterval {
        if let race = viewModel.activeRace, let total = race.totalDuration {
            return total
        }
        // Engine fallback — `viewModel.elapsed(at:)` returns the
        // engine's computed elapsed regardless of state.
        return viewModel.elapsed(at: Date())
    }

    // PB delta for the finish hero. Negative = new PB (faster
    // than prior best). nil = no prior PB to compare, OR not a
    // PB. Filters out the just-finished race itself by checking
    // the race row's id.
    private var finishHeroPBDelta: TimeInterval? {
        let currentDuration = finishHeroTotalDuration
        guard currentDuration > 0 else { return nil }

        let currentRaceID = viewModel.activeRace?.id
        let priorPB: TimeInterval? = allRaces
            .filter { $0.isFinished && $0.id != currentRaceID }
            .compactMap(\.totalDuration)
            .min()

        guard let prior = priorPB else {
            // First finished race ever — count it as a PB
            // moment but no comparison surface. Returning nil
            // here means the hero renders the standard quote
            // ("well raced.") rather than the PB-specific one.
            // Athletes can still see their absolute time.
            return nil
        }

        let delta = currentDuration - prior
        // Only return the delta if it's a real improvement.
        // Same-time-as-PB or slower → nil → no PB line on the hero.
        return delta < 0 ? delta : nil
    }

    // Trigger the 3-second finish hero overlay. Cancels any
    // existing dismiss task so re-entering doesn't double-schedule.
    // Schedules the auto-dismiss for 3s out; user tap routes
    // through `dismissFinishHero` to short-circuit.
    private func presentFinishHero() {
        finishHeroDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            isShowingFinishHero = true
        }
        finishHeroDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            dismissFinishHero()
        }
    }

    // Dismiss the finish hero overlay. Fades out and reveals the
    // summary view underneath. Idempotent — safe to call from
    // both the auto-dismiss Task and the tap handler.
    private func dismissFinishHero() {
        finishHeroDismissTask?.cancel()
        finishHeroDismissTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
            isShowingFinishHero = false
        }
    }

    // Wireframe §03.4 end-race confirm message. Quantifies what
    // the athlete is committing to: how many stations they're
    // in, plus the "won't count as a full HYROX" disclaimer if
    // they're ending before all 16 segments. Identical phrasing
    // to the wireframe.
    private var endEarlyConfirmMessage: String {
        let completed = viewModel.completedSegmentsCount
        let total = viewModel.totalSegments
        if completed >= total {
            // Edge case: athlete somehow opened the sheet on the
            // last segment after completing it. End just
            // finishes naturally.
            return "Your finished race will be saved to History."
        }
        let plural = completed == 1 ? "" : "s"
        return "You're \(completed) station\(plural) in. We'll save what you did, but it won't count as a full HYROX."
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
                    // race can start cleanly. Both transports get
                    // canceled here — only one will actually have
                    // an active session, but cancel is idempotent
                    // on a nil ref so the symmetry is fine.
                    duoController = nil
                    duoCoordinator?.cancel()
                    duoCoordinator = nil
                    #if canImport(Supabase)
                    cloudDuoCoordinator?.cancel()
                    cloudDuoCoordinator = nil
                    #endif
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

    // Cross-city Duo (Tier 2) counterpart to
    // `handleDuoSessionStateChange`. Same logic against
    // CloudDuoSession.State's `.disconnected` case. Kept as a
    // separate function because the two state enums are
    // independent types — a generic helper would need protocol
    // gymnastics that doesn't pay off for two cases.
    #if canImport(Supabase)
    private func handleCloudDuoSessionStateChange(_ newState: CloudDuoSession.State?) {
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
    // v1 wireframe cathedral (03.2). Vertical rhythm top→bottom:
    //
    //   1. Compact header: "RUN · 3/8" caps + ● LIVE pulse + close X.
    //      Replaces the prior dense two-row chip cluster — the
    //      athlete needs orientation ("where am I in the race") and
    //      a kill-switch, nothing else, at this position.
    //
    //   2. Big hero timer with an "elapsed" sub-caption. The cathedral's
    //      anchor — this is what gets glanced at from arm's length
    //      mid-sprint.
    //
    //   3. Pace ghost panel — a colored card that flips green / amber
    //      / coral based on whether the athlete is ahead, on-pace, or
    //      behind their target split. Includes a one-sentence coaching
    //      callout so the athlete doesn't have to interpret a number.
    //
    //   4. Three-up stat strip: HR (with zone), TARGET (this station's
    //      prescribed distance/reps), CAL (cumulative race calories
    //      from completed splits). Each tile self-hides gracefully
    //      when its source is unavailable.
    //
    //   5. HR zones bar — five-cell visualization tinted by the
    //      athlete's current zone. Reads as "where on the effort
    //      scale am I right now" at a glance without the BPM number
    //      mattering.
    //
    //   6. UP NEXT card — the next station's name + historical
    //      context ("your avg 2:08 · best 1:54"). Mental cue:
    //      "what's coming, and how have I run it before."
    //
    //   7. Bottom row: small transparent-border Pause + big coral
    //      Next Station CTA with glow. Wireframe explicitly calls
    //      for the pause to NOT compete with the CTA visually.
    //
    // Spacing rhythm uses Spacing.md (20pt) between regions and
    // Spacing.sm (12pt) within cards — matches the v1 audit.
    private var inProgressView: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            cathedralBody(now: context.date)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showingSplits) {
            RaceSplitsSheetView(viewModel: viewModel)
        }
        #endif
    }

    // Cathedral body — extracted from inProgressView so the
    // TimelineView's closure stays a single expression. With
    // everything inline the SwiftUI type-checker hit its
    // complexity budget; pulling the body out lets each helper
    // type-check independently.
    @ViewBuilder
    private func cathedralBody(now: Date) -> some View {
        let isWorkout = (viewModel.currentStation?.kind == .workout)

        VStack(spacing: Spacing.md) {
            cathedralDuoChipIfHost

            cathedralHeader
                .padding(.top, 4)

            // Wireframe 03.2 splits the in-race layout in two
            // shapes — RUN (hero=elapsed-time, pace ghost) vs
            // STATION (hero=station name, reps/dist tracker, no
            // pace ghost). Each variant is its own helper to
            // keep the type-check graph small.
            if isWorkout {
                cathedralStationVariant(now: now)
            } else {
                cathedralRunVariant(now: now)
            }

            Spacer(minLength: 8)

            cathedralBottomRow
                .padding(.bottom, 16)
        }
    }

    // Duo host chip — only renders when a duo race is active on
    // the host side. Mirrors the guest's connectionBanner so
    // both partners see the same "Duo · with Sarah" /
    // "Disconnected" status. The `#if canImport` gate keeps the
    // body's conditional shape clean across builds without the
    // MultipeerConnectivity framework.
    @ViewBuilder
    private var cathedralDuoChipIfHost: some View {
        #if canImport(MultipeerConnectivity)
        if let controller = duoController, controller.role == .host {
            duoConnectionChip(controller: controller)
        }
        #endif
    }

    // Run-variant cathedral body. Renders hero timer + pace
    // ghost + stat strip + HR zones + UP NEXT in order.
    @ViewBuilder
    private func cathedralRunVariant(now: Date) -> some View {
        cathedralTimer(now: now)
        paceGhostPanel(now: now)
        cathedralStatStrip(now: now, isWorkout: false)
        hrZonesBar
        cathedralUpNext
    }

    // Station-variant cathedral body. Renders station headline +
    // reps/dist tracker + stat strip + HR zones (no pace ghost,
    // no UP NEXT — they don't apply mid-station).
    @ViewBuilder
    private func cathedralStationVariant(now: Date) -> some View {
        cathedralStationHeadline(now: now)
        cathedralRepsDistTracker(now: now)
        cathedralStatStrip(now: now, isWorkout: true)
        hrZonesBar
    }

    // MARK: - Body sub-views (extracted to keep type-check time sane)

    // Main phase content — routes to one of five sub-views based
    // on the race's lifecycle phase. Pulled out of body so the
    // ZStack expression stays small.
    //
    // Phase priority (first match wins):
    //   1. Resume prompt   — there's an interrupted race to resume
    //   2. Pre-race        — race hasn't started yet
    //   3. Finished        — race ended; show hero or summary
    //   4. In Roxzone      — between segments
    //   5. In progress     — actively racing
    @ViewBuilder
    private var mainPhaseContent: some View {
        Group {
            if let pending = viewModel.pendingResume {
                resumePromptPhase(pending: pending)
            } else if !viewModel.hasStarted {
                preRacePhase
            } else if viewModel.isFinished {
                finishedPhase
            } else if viewModel.isInRoxzone {
                roxzonePhase
            } else {
                inProgressPhase
            }
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.85),
            value: viewModel.isInRoxzone
        )
    }

    @ViewBuilder
    private func resumePromptPhase(pending: Race) -> some View {
        ResumePromptView(
            race: pending,
            onResume: viewModel.resumePending,
            onDiscard: viewModel.discardPending
        )
        .padding(.horizontal, Layout.screenMargin)
    }

    // Pre-race phase — wireframe §14 Train tab. The hub renders
    // the 2×2 action grid (Race Mode / Race Simulation / Quick
    // Station / Compromised) + recommended workout card, and
    // navigates into RaceStartView (existing setup screen) when
    // the athlete picks Race Mode or Race Simulation. Quick
    // Station + Compromised open CustomWorkoutBuilderView as a
    // sheet from inside the hub.
    //
    // RaceStartView's existing bindings flow through TrainHubView
    // unchanged so the Duo + pairing surfaces stay wired without
    // any callsite-level adjustments here.
    private var preRacePhase: some View {
        TrainHubView(
            viewModel: viewModel,
            selectedMode: $selectedMode,
            duoCoordinator: $duoCoordinator,
            cloudDuoCoordinator: $cloudDuoCoordinator,
            duoController: $duoController,
            isPairingPresented: $isPairingPresented,
            isCloudPairingPresented: $isCloudPairingPresented
        )
    }

    // Finished phase routes between two sub-views: the 3-second
    // hero overlay (wireframe §03.4) and the post-race summary.
    @ViewBuilder
    private var finishedPhase: some View {
        Group {
            if isShowingFinishHero {
                RaceFinishHeroView(
                    totalDuration: finishHeroTotalDuration,
                    pbDelta: finishHeroPBDelta,
                    onTap: dismissFinishHero
                )
                .transition(.opacity)
            } else {
                // RaceSummaryView controls its own bleed so the
                // finish-moment backdrop reaches the edges.
                RaceSummaryView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        // Tab bar hidden through the finish hero + summary so
        // the post-race moment isn't interrupted by chrome.
        // Reappears when the user taps Done and the engine
        // resets to .notStarted (preRacePhase / Train hub).
        .hideCustomTabBar()
    }

    // Two-tap-advance mode: between segments the user lands here.
    // Big "Start [next station]" button + countup transition timer.
    private var roxzonePhase: some View {
        inRoxzoneView
            .padding(.horizontal, Layout.screenMargin)
            .transition(roxzoneTransition)
            // Cathedral mode — bottom tab bar hides so the
            // Start Next CTA owns the full bottom edge.
            .hideCustomTabBar()
    }

    // Active in-progress cathedral phase.
    private var inProgressPhase: some View {
        inProgressView
            .padding(.horizontal, Layout.screenMargin)
            .transition(.opacity)
            // Cathedral mode — bottom tab bar hides so the
            // big advance CTA isn't crowded by Feed / History
            // / Profile / Watch chrome. The race is the only
            // thing on screen now.
            .hideCustomTabBar()
    }

    // Roxzone slides in from below with a slight scale-up — reads
    // as the screen "lifting up to surface the transition timer."
    // Slides back down on dismiss (start next segment) so the exit
    // reverses the entry. Extracted into a computed property so the
    // `.transition(...)` call in roxzonePhase stays a single
    // expression for the type-checker.
    private var roxzoneTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.96)),
            removal: .move(edge: .bottom)
                .combined(with: .opacity)
        )
    }

    // Countdown overlay — full-screen, sits above the start
    // screen so the athlete sees a clean 3 → 2 → 1 → GO ritual
    // before the race timer takes over. Tap anywhere to skip
    // straight to the race. Bound to viewModel.countdownValue
    // so cancellation (race abandoned, view dismissed) clears
    // the overlay.
    @ViewBuilder
    private var countdownOverlayIfActive: some View {
        if let value = viewModel.countdownValue {
            countdownOverlay(value: value)
                .transition(.opacity)
        }
    }

    // Manual run start overlay — only shown when the athlete
    // enters a run station with the setting on. Z-stacks over
    // the in-progress view so the regular race UI stays in
    // place underneath. Total race timer keeps ticking; only
    // the segment timer (and the athlete) is paused at the
    // start line until they tap Start Run.
    @ViewBuilder
    private var startRunOverlayIfActive: some View {
        if isAwaitingRunStart {
            startRunOverlay
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96))
                )
        }
    }

    // MARK: - Coaching banner overlay (wireframe §03.3)

    // Wireframe 03.3 — coaching banner overlay. Renders at the top
    // of the cathedral, slides in from the top edge, hangs for
    // 2.5s, then slides out. Doesn't intercept taps on the
    // underlying race UI — tap-on-banner dismisses it early.
    //
    // Extracted into its own computed property so the body's
    // ZStack stays small enough for SwiftUI's type-check budget.
    // Inline (as the original draft was), the body's expression
    // complexity tipped over and triggered the "compiler is unable
    // to type-check this expression in reasonable time" warning.
    @ViewBuilder
    private var coachingBannerOverlay: some View {
        if let cue = activeCoachingCue, viewModel.hasStarted, !viewModel.isFinished {
            VStack {
                CoachingBanner(
                    cue: cue,
                    currentHR: viewModel.currentHeartRateBPM
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .onTapGesture {
                    coachingBannerDismissTask?.cancel()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        activeCoachingCue = nil
                    }
                }
                Spacer()
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(10)  // above any other overlay
        }
    }

    // MARK: - HR source fallover banner overlay (§19)

    // Quiet 2s banner that fires when the HR source changes
    // mid-race (Watch disconnects → AirPods take over, etc.).
    // Sits below the coaching banner's z-index — coaching cues
    // are higher-priority interruptions. No haptic — this is
    // informational, not actionable.
    @ViewBuilder
    private var hrSourceBannerOverlay: some View {
        if let info = hrSourceBanner, viewModel.hasStarted, !viewModel.isFinished {
            VStack {
                HRSourceBanner(info: info)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .onTapGesture {
                        hrSourceBannerDismissTask?.cancel()
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            hrSourceBanner = nil
                        }
                    }
                Spacer()
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(9)  // just below the coaching banner
        }
    }

    // Called by attachObservers' .onChange(of: lastHRSource).
    // Only fires the banner when:
    //   1. The race is actually running (hasStarted, not
    //      finished, not pre-race).
    //   2. The previous observed source was a real source
    //      (.unknown is the registry's initial state — we
    //      don't want to fire the banner on first-sample
    //      arrival, just on real fallovers between two
    //      known sources).
    //   3. The change isn't a transient flicker we already
    //      banner'd 2s ago.
    private func handleHRSourceChange(
        from oldValue: SensorSourceRegistry.HRSource,
        to newValue: SensorSourceRegistry.HRSource
    ) {
        guard viewModel.hasStarted, !viewModel.isFinished else {
            lastObservedHRSource = newValue
            return
        }
        // Suppress the initial transition from .unknown into
        // the first known source — that's normal warmup, not
        // a fallover.
        guard lastObservedHRSource != .unknown else {
            lastObservedHRSource = newValue
            return
        }
        guard oldValue != newValue else { return }

        lastObservedHRSource = newValue

        // Build the banner copy from the new source's label.
        let info = HRSourceBannerInfo(
            text: "HR source switched to \(newValue.shortLabel)",
            symbolName: newValue.symbolName
        )

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            hrSourceBanner = info
        }

        // Auto-dismiss after 2 seconds. Cancel any in-flight
        // dismiss task first so a second fallover before the
        // first one cleared resets the clock cleanly.
        hrSourceBannerDismissTask?.cancel()
        hrSourceBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                hrSourceBanner = nil
            }
        }
    }

    // MARK: - Cathedral surface components

    // Row 1 — wireframe 03.2 lean header. Just two elements:
    //   • Caps "RUN · 3/8" or "STATION · 4/8" anchor label LEFT.
    //     Station kind colors differ — RUN is textSecondary, STATION
    //     reads in coral so the visual cue of "you're at a station"
    //     is unmistakable.
    //   • ● LIVE coral pulse + caps label RIGHT, confirming the
    //     race is actively recording.
    //
    // The wireframe pointedly OMITS a header cancel/end-race
    // affordance — that decision sits behind Pause (wireframe
    // 03.4's Pause sheet, future). Until 03.4 ships, end-race is
    // available via long-press on the bottom pause button. Tapping
    // the station label here opens the splits-peek sheet, double-
    // duty for the chip we removed.
    private var cathedralHeader: some View {
        HStack(spacing: 10) {
            Button {
                if viewModel.completedSegmentsCount > 0 {
                    showingSplits = true
                }
            } label: {
                Text(cathedralStationLabel)
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(
                        viewModel.currentStation?.kind == .workout
                            ? Color.accent
                            : Color.textSecondary
                    )
                    .accessibilityLabel("\(cathedralStationLabel) of the race. Tap to peek splits.")
            }
            .buttonStyle(.plain)

            Spacer()

            liveBadge
        }
    }

    // Caps progress label. Runs return "RUN · N/8"; workouts return
    // "WORK · N/8" where N is the 1-indexed position within the 8
    // workouts (skiErg=1, sledPush=2, … wallBalls=8). Wireframe spec.
    private var cathedralStationLabel: String {
        guard let station = viewModel.currentStation else { return "" }
        switch station.kind {
        case .run:
            // run1..run8 → 1..8
            let idx: Int = {
                switch station {
                case .run1: return 1
                case .run2: return 2
                case .run3: return 3
                case .run4: return 4
                case .run5: return 5
                case .run6: return 6
                case .run7: return 7
                case .run8: return 8
                default: return 1
                }
            }()
            return "RUN · \(idx)/8"
        case .workout:
            let idx: Int = {
                switch station {
                case .skiErg:           return 1
                case .sledPush:         return 2
                case .sledPull:         return 3
                case .burpeeBroadJumps: return 4
                case .rowing:           return 5
                case .farmersCarry:     return 6
                case .sandbagLunges:    return 7
                case .wallBalls:        return 8
                default: return 1
                }
            }()
            return "STATION · \(idx)/8"
        }
    }

    // ● LIVE indicator — small coral pulse + caps label confirming
    // the race is actively recording. Pulse animation is the brand
    // "ambient" motion (Motion.ambient, 1.4s ease-in-out, scale
    // 0.85 ↔ 1.0) so it reads as a heartbeat rather than a strobe.
    // Disabled under Reduce Motion — the dot stays static and the
    // label is sufficient.
    private var liveBadge: some View {
        HStack(spacing: 6) {
            LivePulseDot()
            Text("LIVE")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.accent.opacity(0.10))
        )
        .accessibilityLabel("Race is recording")
    }

    // Row 2 — wireframe 03.2 hero timer. xxl elapsed time + small
    // "elapsed" caption directly beneath. When the athlete has a
    // prior PB AND we can compute a pace delta, a colored second
    // line shows "−18s vs PB pace" (green when ahead) or
    // "+34s vs PB pace" (coral when behind) — gives an outcome
    // narrative on top of the bare elapsed number.
    //
    // Aligned LEFT per wireframe (not centered) — the cathedral
    // reads as a column with the big number anchoring the
    // left edge.
    @ViewBuilder
    private func cathedralTimer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            cathedralPausedRibbon
            cathedralElapsedHero(now: now)
            cathedralElapsedCaption
            cathedralPBDeltaLine(now: now)
            cathedralProjectedFinishLine(now: now)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // PAUSED ribbon — sits directly above the timer when the
    // engine is frozen so the freeze is unmistakable.
    @ViewBuilder
    private var cathedralPausedRibbon: some View {
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
                Capsule().fill(Color.warning.opacity(0.15))
            )
            .padding(.bottom, 4)
        }
    }

    // The big race-timer Text — color depends on paused / over-
    // target state.
    private func cathedralElapsedHero(now: Date) -> some View {
        let target = viewModel.activeRace?.targetDuration
        let elapsed = viewModel.elapsed(at: now)
        let isOverTarget = (target.map { elapsed > $0 }) ?? false
        let tint: Color
        if viewModel.isPaused {
            tint = Color.textTertiary
        } else if isOverTarget {
            tint = Color.warning
        } else {
            tint = Color.textPrimary
        }
        return Text(RaceStats.format(elapsed))
            .font(.raceTimer)
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // "elapsed" caption directly beneath the hero timer.
    private var cathedralElapsedCaption: some View {
        Text("elapsed")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.textSecondary)
    }

    // PB-pace delta line — "−18s vs PB pace" / "+34s vs PB pace"
    // when a prior PB exists. Hidden on a first race or when the
    // delta is too small to be meaningful.
    @ViewBuilder
    private func cathedralPBDeltaLine(now: Date) -> some View {
        if let pbDelta = pbPaceDelta(at: now) {
            Text(pbDelta.label)
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(pbDelta.tint)
                .contentTransition(.numericText())
                .padding(.top, 2)
        }
    }

    // Projected-finish line — renders when there's an active
    // target AND the projection feature is on. Color reflects
    // whether the athlete is on track to beat their goal.
    @ViewBuilder
    private func cathedralProjectedFinishLine(now: Date) -> some View {
        let elapsed = viewModel.elapsed(at: now)
        let target = viewModel.activeRace?.targetDuration
        let projectionEnabled = profiles.first?.predictedFinishEnabled ?? true

        if projectionEnabled,
           let predicted = RaceStats.predictedFinishTime(
            segmentsCompleted: viewModel.completedSegmentsCount,
            totalSegments: viewModel.totalSegments,
            actualElapsed: elapsed
           ) {
            let predictedColor = projectedFinishTint(predicted: predicted, target: target)
            Text("projected \(RaceStats.format(predicted))")
                .font(.metadata)
                .monospacedDigit()
                .foregroundStyle(predictedColor)
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? .none : .smooth(duration: 0.4),
                    value: predictedColor
                )
        }
    }

    // Color for the projected-finish line. Green when on track
    // to beat the target, amber when projecting to miss, neutral
    // when no target is set. Extracted so the @ViewBuilder
    // helper above stays a clean view expression — IIFEs inside
    // @ViewBuilder closures balloon the type-checker.
    private func projectedFinishTint(
        predicted: TimeInterval,
        target: TimeInterval?
    ) -> Color {
        guard let delta = RaceStats.predictedFinishDelta(
            predicted: predicted,
            target: target
        ) else {
            return .textTertiary
        }
        return delta <= 0 ? .onPace : .slow
    }

    // PB-pace delta — wireframe's "−18s vs PB pace" line. Computes
    // expected-elapsed at the current race progress based on the
    // athlete's prior personal best, compares to actual elapsed,
    // returns a signed delta + tint. Nil when no PB exists or when
    // we're at zero progress (no comparison surface yet).
    private func pbPaceDelta(at now: Date) -> (label: String, tint: Color)? {
        // `Race.totalDuration` is TimeInterval? — only set on
        // finished races. compactMap strips nils so `.min()`
        // operates on a clean `[TimeInterval]`.
        let finished = allRaces.filter { $0.isFinished }
        let priorTotals = finished.compactMap(\.totalDuration)
        guard let pb = priorTotals.min(),
              viewModel.completedSegmentsCount > 0 else {
            return nil
        }
        let progressFraction = Double(viewModel.completedSegmentsCount) / Double(viewModel.totalSegments)
        guard progressFraction > 0 else { return nil }
        let expectedAtNow = pb * progressFraction
        let delta = viewModel.elapsed(at: now) - expectedAtNow
        // Hide deltas under 3 seconds to avoid a noisy first-tick
        // flicker right after each station advance.
        guard abs(delta) >= 3 else { return nil }
        let sign = delta < 0 ? "−" : "+"
        let absStr = RaceStats.format(abs(delta))
        return (
            label: "\(sign)\(absStr) vs PB pace",
            tint: delta < 0 ? Color.onPace : Color.accent
        )
    }

    // MARK: - Station variant (workout segments)
    //
    // Wireframe 03.2 fourth phone mockup: workout stations get a
    // different cathedral shape. The ATHLETE's mental model on
    // a workout is "how far through this station am I?" — not
    // "how far through the race am I?" — so the layout pivots:
    //
    //   • Big station NAME (Sled Push) replaces RUN · 3/8 as the
    //     visual anchor
    //   • Segment timer (this station's elapsed) takes the hero
    //     slot, not total race elapsed
    //   • A reps/dist progress card sits where the pace ghost
    //     would on a run — visible progress toward the prescribed
    //     work
    //   • Stat strip swaps DIST for SPLIT (the current station's
    //     elapsed)
    //   • No pace ghost (pace doesn't apply mid-station)
    //   • No UP NEXT card (the next thing is "finish this station")
    //
    // The header anchor "STATION · 4/8" + LIVE pulse persists, so
    // the cathedral identity holds across both variants.

    // Station headline — big station name as the hero typography
    // identity, segment timer beneath, "your best · avg" history
    // sub-line so the athlete sees what they're chasing.
    @ViewBuilder
    private func cathedralStationHeadline(now: Date) -> some View {
        if let station = viewModel.currentStation {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.displayName)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(RaceStats.format(viewModel.currentSegmentElapsed(at: now)))
                    .font(.raceTimer)
                    .monospacedDigit()
                    .foregroundStyle(
                        viewModel.isPaused ? Color.textTertiary : Color.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let history = stationHistorySubline(for: station) {
                    Text(history)
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 2)
                } else {
                    Text(station.target(for: division))
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // "your best 1:54 · avg 2:08" sub-line beneath a station's
    // segment timer. Pulled from finished historical splits for
    // this station type. Nil when no history exists; caller falls
    // back to the prescribed target ("50 m") so the row is never
    // blank.
    private func stationHistorySubline(for station: Station) -> String? {
        let priorDurations: [TimeInterval] = allRaces
            .filter { $0.isFinished }
            .flatMap(\.splits)
            .filter { $0.station == station }
            .map(\.duration)

        guard !priorDurations.isEmpty else { return nil }
        let best = priorDurations.min() ?? 0
        let avg = priorDurations.reduce(0, +) / Double(priorDurations.count)
        return "your best \(RaceStats.format(best)) · avg \(RaceStats.format(avg))"
    }

    // Reps / Dist tracker card. Wireframe 03.2 station variant:
    //
    //   ┌─────────────────────────────────┐
    //   │ REPS / DIST            25 / 50 m│
    //   │ ███████████░░░░░░░░░░░░░░░░░░░ │  progress bar
    //   └─────────────────────────────────┘
    //
    // We don't have live rep counting yet (Watch IMU rep-counting
    // is wireframe-aspirational — CLAUDE.md §13.8 Tier 2). Until
    // that ships, the progress bar fills based on the athlete's
    // TIME progress vs their prior best for this station — so the
    // bar still gives "am I on track" signal without needing rep
    // detection. The right-side number shows the prescribed
    // target so the athlete knows what work remains.
    @ViewBuilder
    private func cathedralRepsDistTracker(now: Date) -> some View {
        if let station = viewModel.currentStation,
           station.kind == .workout {
            let target = station.target(for: division)
            let fraction = stationProgressFraction(for: station, now: now)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("REPS / DIST")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(target)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // Progress bar. Outer rounded track + inner coral
                // fill that grows with `fraction`. Animated so
                // approaching prior-best reads as a continuous
                // chase, not a discrete jump.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.divider)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accent)
                            .frame(width: geo.size.width * fraction)
                            .animation(
                                reduceMotion ? .none : .smooth(duration: 0.3),
                                value: fraction
                            )
                    }
                }
                .frame(height: 6)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surfaceElevated)
            )
        }
    }

    // Station progress fraction — clamped 0...1. Uses the athlete's
    // prior best for this station as the denominator: if they're
    // on track to match their best, the bar fills as time elapses;
    // crossing their best caps the bar at 100% (so the bar reads
    // "you've reached prior best, anything beyond is bonus").
    // When no prior best exists, the bar grows linearly with
    // elapsed time mod 5 minutes as a rough visual.
    private func stationProgressFraction(for station: Station, now: Date) -> Double {
        let elapsed = viewModel.currentSegmentElapsed(at: now)
        let prior = allRaces
            .filter { $0.isFinished }
            .flatMap(\.splits)
            .filter { $0.station == station }
            .map(\.duration)
            .min()
        guard let prior, prior > 0 else {
            // No prior — fall back to a 0..1 ramp over 5 minutes
            // so the bar still moves visibly. Most stations finish
            // well under 5min; this just gives the bar life on a
            // first attempt.
            return min(1.0, elapsed / 300.0)
        }
        return min(1.0, elapsed / prior)
    }

    // Row 3 — Pace Ghost. Wireframe 03.2 spec:
    //
    //   ┌─────────────────────────────────┐
    //   │ PACE · ON              −2s      │  caps label + mono delta
    //   │ Holding 4:48/km. Target 4:50.   │  coaching sentence
    //   └─────────────────────────────────┘
    //
    // Three variants:
    //   • ON      → amber tint (slow.opacity(0.12)) — wireframe
    //               specifies amber for "on pace" because it's the
    //               "holding the line" state, not the celebratory
    //               one. Athletes are ON-pace by default; the visual
    //               doesn't reward neutral.
    //   • AHEAD   → green tint (onPace.opacity(0.12)) — earned.
    //   • BEHIND  → coral tint (accent.opacity(0.12)) — honest.
    //
    // No left icon column; the visual identity comes from the tint
    // band and the caps label. Self-hides when no target set.
    @ViewBuilder
    private func paceGhostPanel(now: Date) -> some View {
        if let state = paceChipState(now: now),
           let target = viewModel.activeRace?.targetDuration {
            let kind = paceGhostKind(state: state)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PACE · \(kind.caps)")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(kind.tint)
                    Spacer()
                    Text(paceDeltaCompact(state: state))
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(kind.tint)
                        .contentTransition(.numericText())
                }

                Text(paceGhostSentence(now: now, target: target, state: state))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(kind.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(kind.tint.opacity(0.30), lineWidth: 1)
            )
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.4),
                value: kind.caps
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pace: \(kind.caps). \(state.label).")
        }
    }

    // Compact signed delta for the pace ghost — "−2s", "+18s",
    // "+34s". Stripped of the "ahead"/"behind" suffix the chip
    // label carries (the caps tag PACE · AHEAD/BEHIND already
    // names the direction).
    private func paceDeltaCompact(state: PaceChipState) -> String {
        let label = state.label
        if label == "on pace" {
            // The PaceChipState's on-pace label has no signed
            // delta. Synthesize one centered around zero so the
            // right side of the row still carries a number.
            return "0s"
        }
        let trimmed = label
            .replacingOccurrences(of: " ahead", with: "")
            .replacingOccurrences(of: " behind", with: "")
        let prefix = state.icon == "arrow.up.right" ? "−" : "+"
        return "\(prefix)\(trimmed)"
    }

    // Visual variant for the pace ghost panel — derived from the
    // pace state. Separated from `paceChipState` because the chip
    // and the panel have different visual languages (chip = compact
    // capsule with one tint, panel = card with tint + bg pair).
    private struct PaceGhostKind {
        let caps: String        // "ON PACE" / "AHEAD" / "BEHIND"
        let tint: Color         // accent color for label + delta
        let background: Color   // panel fill
    }

    private func paceGhostKind(state: PaceChipState) -> PaceGhostKind {
        // Discriminate by icon — Color comparisons across light/dark
        // adaptive colors aren't reliable, and the icon name is the
        // stable identity assigned in paceChipState() above.
        switch state.icon {
        case "arrow.up.right":
            return PaceGhostKind(
                caps: "AHEAD",
                tint: Color.onPace,
                background: Color.onPace.opacity(0.12)
            )
        case "arrow.down.right":
            // Wireframe spec: BEHIND uses coral, not amber.
            // Coral = "honest" (something to act on), amber is
            // reserved for the "holding the line" ON state.
            return PaceGhostKind(
                caps: "BEHIND",
                tint: Color.accent,
                background: Color.accent.opacity(0.12)
            )
        default:
            // Wireframe spec: ON variant uses amber (slow). Amber
            // reads as "holding pace" — present and accounted for
            // without rewarding neutral. Distinct from a celebratory
            // green and from a "do something" coral.
            return PaceGhostKind(
                caps: "ON",
                tint: Color.slow,
                background: Color.slow.opacity(0.12)
            )
        }
    }

    // One-line coaching sentence for the pace ghost. Phrased as the
    // wireframe's voice ("Holding 4:48/km. Target 4:50." / "Faster
    // than your last sim. Don't blow the next station." / "Pick it
    // up — 12s recoverable on the next run."). Adapts to the
    // current station kind (running vs workout) so a "Holding
    // X:XX/km" message doesn't fire mid-sled-push.
    private func paceGhostSentence(now: Date, target: TimeInterval, state: PaceChipState) -> String {
        let totalSegments = viewModel.totalSegments
        let perSegment = totalSegments > 0 ? target / Double(totalSegments) : target / 16
        let isRun = viewModel.currentStation?.kind == .run

        // Discriminate by icon (stable identity from paceChipState).
        switch state.icon {
        case "arrow.up.right":
            // Ahead: celebrate but suggest holding form.
            if isRun {
                return "Ahead of your goal pace. Hold this rhythm into the next station."
            } else {
                return "Banking time on this station. Stay efficient — don't burn the next run."
            }
        case "arrow.down.right":
            // Behind: actionable, not punitive. Reference the gap
            // and what's recoverable.
            let gap = state.label.replacingOccurrences(of: " behind", with: "")
            return "\(gap) off your target split. Recover on the next segment — pace is still in range."
        default:
            // On pace: confirm + a target rhythm cue.
            let perStr = RaceStats.format(perSegment)
            if isRun {
                return "Right on your goal split. Holding \(perStr) per station to hit your target."
            } else {
                return "On target. Move with intent — runs are where the time is made up."
            }
        }
    }

    // Row 4 — wireframe 03.2 stat strip. Three columns, FLAT (no
    // individual card backgrounds — the strip reads as a single
    // row of inline stats, not three separate tiles). Caps label
    // ABOVE, big rounded number BELOW.
    //
    // Run variant:        HR (with zone)  |  DIST  |  CAL   |  CAD (if AirPods)
    // Workout variant:    HR (with zone)  |  CAL   |  SPLIT
    //
    // The split swap on workout stations is wireframe-prescribed:
    // mid-station the athlete cares about THIS station's split
    // time, not cumulative race distance.
    //
    // §19.4 Phase 10H — when AirPods Pro 1+ / 4 / Max are in
    // the audio route AND a cadence reading is available, a
    // CAD cell appears at the trailing edge of the run-variant
    // strip. Self-hides on the workout variant (head motion
    // during sled push / wall balls isn't a meaningful cadence
    // signal) and during the first ~2s before the rolling
    // buffer fills.
    private func cathedralStatStrip(now: Date, isWorkout: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            statCellHR
            if isWorkout {
                statCell(caption: "CAL", value: cumulativeCaloriesString)
                statCell(caption: "SPLIT", value: RaceStats.format(viewModel.currentSegmentElapsed(at: now)))
                // §13.8 Tier 2 — REPS cell appears only on rep-
                // counting workout stations (Phase 1 = wall balls)
                // AND only when the Watch's WatchRepCountingService
                // has published a count. Self-hides when no Watch
                // is paired, no rep station is active, or no count
                // has been received yet. The cell shows the live
                // tally so the athlete can glance at the phone
                // (e.g. propped on the floor) and see progress
                // without counting in their head.
                if let count = viewModel.currentRepCount {
                    statCellReps(
                        count: count,
                        station: viewModel.currentStation
                    )
                }
            } else {
                statCell(caption: "DIST", value: cumulativeDistanceString(now: now))
                statCell(caption: "CAL", value: cumulativeCaloriesString)
                if let spm = viewModel.currentCadenceSPM {
                    statCellCadence(spm: spm)
                }
            }
        }
    }

    // §13.8 Tier 2 — live rep / stroke / pull cell. Caps label +
    // watch glyph above the big rounded count number below. Mirrors
    // the cadence cell's structure since they're sibling sensor-
    // sourced metrics. Watch glyph signals "this came from your
    // wrist," distinguishing it from the eventual manual-edit
    // path in StationStatsSheet.
    //
    // §46 — label + accessibility text adapt to the active station
    // so "STROKES" reads on rowing and "PULLS" reads on SkiErg.
    // Falls back to "REPS" for Wall Balls and any future rep
    // station that defaults to the original vocabulary.
    private func statCellReps(count: Int, station: Station?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(repCellLabel(for: station))
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "applewatch")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
            }
            Text("\(count)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel("\(count) \(repCellAccessibility(for: station))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func repCellLabel(for station: Station?) -> String {
        switch station {
        case .rowing:   return "STROKES"
        case .skiErg:   return "PULLS"
        default:        return "REPS"
        }
    }

    private func repCellAccessibility(for station: Station?) -> String {
        switch station {
        case .rowing:   return "strokes counted"
        case .skiErg:   return "pulls counted"
        default:        return "reps counted"
        }
    }

    // HR cell — caps "HR" label above, big rounded BPM number
    // with inline zone tag ("162 Z4") below. Tint follows the
    // zone color so a quick glance reads as "where on the dial
    // am I right now."
    @ViewBuilder
    private var statCellHR: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("HR")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                // §19 — source attribution glyph. Tiny SF Symbol
                // next to the HR caption telling the athlete
                // whether the current sample came from the
                // Watch, the AirPods Pro 3 in their ears, or a
                // fused stream. Hidden when no source is
                // attributed yet (pre-first-sample).
                hrSourceGlyph
            }
            if let bpm = viewModel.currentHeartRateBPM {
                let zone = HRZone.zone(for: bpm, maxBPM: maxHeartRate)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(bpm.rounded()))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(zone.color)
                        .contentTransition(.numericText())
                    Text(zone.displayName.split(separator: " ").first.map(String.init) ?? "Z?")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(zone.color.opacity(0.85))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int(bpm.rounded())) beats per minute, \(zone.displayName), source \(SensorSourceRegistry.shared.lastHRSource.shortLabel)")
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // §19 — HR source attribution glyph. Tiny SF Symbol that
    // tells the athlete which device produced the BPM number
    // they're reading. `applewatch` for Watch, `airpodspro` for
    // AirPods Pro 3, `arrow.triangle.merge` when both are
    // publishing within the same window. EmptyView before the
    // first sample lands so the caption row stays clean.
    @ViewBuilder
    private var hrSourceGlyph: some View {
        let source = SensorSourceRegistry.shared.lastHRSource
        if source != .unknown {
            Image(systemName: source.symbolName)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
    }

    // §19.4 Phase 10H — cadence stat cell. Renders the live
    // steps-per-minute derived from AirPods head motion. Caps
    // "CAD" label + AirPods glyph above the number to signal
    // *which* device produced the metric (Trakrr never gets
    // cadence from the Watch on this path — Watch cadence
    // lives in its own pedometer pipeline that we don't
    // surface in this row). Only rendered when
    // `viewModel.currentCadenceSPM` is non-nil — caller
    // (cathedralStatStrip) handles the nil case by omitting
    // the cell entirely.
    private func statCellCadence(spm: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("CAD")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "airpodspro")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
            Text("\(spm)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spm) steps per minute from AirPods")
    }

    // Generic flat stat cell — caps label + big number. Used for
    // DIST, CAL, SPLIT, and any future per-state column. Value
    // string supplied by caller so the cell stays presentation-
    // only.
    private func statCell(caption: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Cumulative race distance across COMPLETED segments + the
    // currently-active segment's prescribed distance (estimate).
    // Each segment contributes its prescribed meter count
    // (runs = 1000m, sled push = 50m, etc — pulled from
    // Station.target). Wall balls is rep-based; we count it as
    // 0m since no distance applies. Formatted as "X.X km" once
    // we cross 1km, otherwise "Xm" for short totals.
    private func cumulativeDistanceString(now: Date) -> String {
        let completed = viewModel.splits.reduce(0.0) { sum, split in
            sum + distanceMeters(for: split.station)
        }
        let total = completed
        if total >= 1000 {
            return String(format: "%.1f km", total / 1000.0)
        }
        return "\(Int(total)) m"
    }

    // Per-station distance in meters. Pulled inline rather than
    // adding a property on Station because this is purely a
    // distance-tracking concern; the Station model already has
    // `target(for:)` for the human-readable label.
    private func distanceMeters(for station: Station) -> Double {
        switch station {
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8: return 1000
        case .skiErg:           return 1000
        case .sledPush:         return 50
        case .sledPull:         return 50
        case .burpeeBroadJumps: return 80
        case .rowing:           return 1000
        case .farmersCarry:     return 200
        case .sandbagLunges:    return 100
        case .wallBalls:        return 0
        }
    }

    // Total active calories across all completed splits. Renders
    // a dash when no splits have HK data yet so the column stays
    // present in the layout.
    private var cumulativeCaloriesString: String {
        let total: Double = viewModel.splits
            .compactMap(\.activeCaloriesKcal)
            .reduce(0, +)
        return total > 0 ? "\(Int(total.rounded()))" : "—"
    }

    // Row 5 — five-cell HR zones bar. Each cell represents one
    // training zone (Z1–Z5). The cell matching the athlete's CURRENT
    // zone fills with that zone's color; the rest stay dimmed. A
    // sub-label row beneath maps cell positions to caps Hyrox
    // zone names (Easy / Steady / Race / Hard / Redline). Reads as
    // "where on the effort dial is my heart right now" at a glance,
    // independent of the actual BPM number.
    @ViewBuilder
    private var hrZonesBar: some View {
        if let bpm = viewModel.currentHeartRateBPM {
            let currentZone = HRZone.zone(for: bpm, maxBPM: maxHeartRate)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(HRZone.allCases, id: \.self) { zone in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(zone == currentZone
                                  ? zone.color
                                  : zone.color.opacity(0.20))
                            .frame(height: 10)
                            .animation(
                                reduceMotion ? .none : .smooth(duration: 0.4),
                                value: currentZone
                            )
                    }
                }
                HStack(spacing: 0) {
                    ForEach(HRZone.allCases, id: \.self) { zone in
                        Text(zone.hyroxLabel)
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(zone == currentZone
                                             ? zone.color
                                             : Color.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityHidden(true) // already announced via statTileHR
        }
    }

    // Row 6 — UP NEXT card with historical context. The wireframe
    // calls for "next station name + your avg X · best Y" so the
    // athlete can mentally rehearse what's coming. Avg + best are
    // computed across all FINISHED prior races; if there's no
    // history yet (first race ever, or a station never logged
    // before), the sub-line goes quiet rather than showing zeros.
    //
    // On the final station of a race, this card flips to a
    // celebratory "FINAL STATION" treatment — the historical
    // context would be misleading there because the next station
    // is finish itself.
    @ViewBuilder
    private var cathedralUpNext: some View {
        if let upcoming = viewModel.upcomingStation {
            let history = upcomingStationHistory(upcoming)
            VStack(alignment: .leading, spacing: 6) {
                Text("UP NEXT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(Color.textTertiary)
                HStack(spacing: 10) {
                    Image(systemName: upcoming.glyph)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(upcoming.displayName)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let history {
                            Text(history)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                        } else {
                            Text(upcoming.target(for: division))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        } else {
            // Final station — wireframe-spec celebratory treatment.
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FINAL STATION")
                        .font(.caption.weight(.heavy))
                        .tracking(1.6)
                        .foregroundStyle(Color.accent)
                    Text("Empty the tank.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(Color.accent.opacity(0.30), lineWidth: 1)
            )
        }
    }

    // Helper — computes "your avg X · best Y" for an upcoming
    // station given the athlete's @Query'd race history. Returns
    // nil when there's no prior split for this station type, so
    // the UP NEXT card can fall back to a target-distance sub-line.
    //
    // Iterates `allRaces` and matches every Split with the same
    // station kind. For run stations we match by ALL run cases
    // (run1..run8) so the avg is across runs in general, not just
    // run-of-position. For workouts the match is exact (sledPush
    // only matches prior sledPush splits).
    private func upcomingStationHistory(_ station: Station) -> String? {
        let finishedRaces = allRaces.filter { $0.isFinished }
        let priorDurations: [TimeInterval] = finishedRaces
            .flatMap(\.splits)
            .filter { split in
                if station.kind == .run {
                    return split.station.kind == .run
                } else {
                    return split.station == station
                }
            }
            .map(\.duration)

        guard !priorDurations.isEmpty else { return nil }
        let avg = priorDurations.reduce(0, +) / Double(priorDurations.count)
        let best = priorDurations.min() ?? avg
        return "your avg \(RaceStats.format(avg)) · best \(RaceStats.format(best))"
    }

    // Row 7 — bottom CTA row. Two elements:
    //   • A small Pause button (transparent border, secondary) on
    //     the left — wireframe wants this de-emphasized so the
    //     CTA dominates. Different visual language from the
    //     existing pauseResumeButton chip (which lives in inRoxzone
    //     where space is tighter).
    //   • The big coral Next Station CTA on the right, taking
    //     the rest of the row width.
    private var cathedralBottomRow: some View {
        HStack(spacing: Spacing.sm) {
            cathedralPauseButton
            advanceButton
        }
    }

    // Larger transparent-border pause button for the cathedral's
    // bottom row. Distinct from `pauseResumeButton` (small circle
    // chip used in the header of inRoxzoneView). Reads as
    // "secondary action" — visible but doesn't compete with the
    // primary CTA.
    private var cathedralPauseButton: some View {
        Button {
            // Wireframe 03.4 — tap opens the pause sheet (not a
            // direct toggle). Pause the engine first so the
            // underlying timer freezes while the sheet is
            // visible; the sheet's Resume button restores it.
            // If the engine is already paused (the user tapped
            // Pause once via a different surface), just open
            // the sheet without re-pausing.
            if !viewModel.isPaused {
                viewModel.pauseRace()
                Haptics.warning()
            }
            isShowingPauseSheet = true
        } label: {
            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(viewModel.isPaused ? Color.success : Color.textSecondary)
                .frame(width: 64, height: Layout.raceButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .stroke(Color.divider, lineWidth: 1.5)
                )
        }
        .accessibilityLabel("Pause race")
        .accessibilityHint("Opens pause options — resume, restart, end, or discard")
    }

    // Wireframe 03.4 station-progress label shown in the pause
    // sheet. "Run 5/8" for run segments; "Sled Push · 2/8" for
    // workout segments. Quieter than the in-race header's caps
    // version — the sheet's typography wants Sentence-case here.
    private var pauseSheetStationLabel: String {
        guard let station = viewModel.currentStation else { return "" }
        switch station.kind {
        case .run:
            let idx: Int = {
                switch station {
                case .run1: return 1
                case .run2: return 2
                case .run3: return 3
                case .run4: return 4
                case .run5: return 5
                case .run6: return 6
                case .run7: return 7
                case .run8: return 8
                default: return 1
                }
            }()
            return "Run \(idx)/8"
        case .workout:
            let idx: Int = {
                switch station {
                case .skiErg:           return 1
                case .sledPush:         return 2
                case .sledPull:         return 3
                case .burpeeBroadJumps: return 4
                case .rowing:           return 5
                case .farmersCarry:     return 6
                case .sandbagLunges:    return 7
                case .wallBalls:        return 8
                default: return 1
                }
            }()
            return "\(station.displayName) · \(idx)/8"
        }
    }

    // (Legacy helpers `stationHeadline`, `timerColumn(now:)`, and
    // `nextStationPreview` were removed here — they were unused
    // after the cathedral redesign but still type-checked as part
    // of the file, contributing meaningfully to compile time. The
    // wireframe-aligned replacements live as `cathedralStationHeadline`,
    // `cathedralTimer`, and `cathedralUpNext` in the cathedral
    // surface-components section above.)

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
        // Gated on Settings → In-race displays → "Pace chip."
        // Off → no chip at all, even with a target set. Athletes
        // who race by feel rather than by clock benefit from
        // turning this off and seeing only the timer.
        guard profiles.first?.paceChipEnabled ?? true else {
            return nil
        }
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
            // Dead-zone state intentionally muted — celebrate
            // ahead, flag behind, but don't reward "exactly on
            // target" with a brand-color win. textSecondary
            // keeps the chip present but emotionally flat here.
            return PaceChipState(
                label: "on pace",
                color: Color.textSecondary,
                icon: "equal.circle.fill"
            )
        } else if delta < 0 {
            // Negative = actual elapsed is less than expected = ahead.
            // Tinted with the v1 race-state token `Color.onPace`
            // (`#2BC758`) — a colder green than `Color.success`
            // so it reads as a coaching signal ("you're ahead")
            // rather than a celebration. Distinct from coral
            // brand moments.
            return PaceChipState(
                label: "\(RaceStats.format(absDelta)) ahead",
                color: Color.onPace,
                icon: "arrow.up.right"
            )
        } else {
            // Behind target → v1 race-state `Color.slow`
            // (`#FFB020`) instead of the generic `Color.warning`.
            // Same amber family, but `slow` is the dedicated
            // in-race "ease back" tool color — matches the
            // wireframe's SLOW coaching cue overlay tint.
            return PaceChipState(
                label: "\(RaceStats.format(absDelta)) behind",
                color: Color.slow,
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
            // Settings → In-race displays → "Coaching cues" gates
            // the HOLD/SLOW/PUSH/WORK pill. When off, we resolve
            // to .none so the chip still renders zone color + BPM
            // but skips the prescriptive command. The chip's
            // shape stays identical either way; only the inner
            // pill toggles.
            let coachingCuesEnabled = profiles.first?.coachingCuesEnabled ?? true
            let cue: RaceStats.CoachingCue = coachingCuesEnabled
                ? RaceStats.coachingCue(
                    currentHR: bpm,
                    maxHR: maxHeartRate,
                    currentStation: viewModel.engine.currentStation,
                    personalLowerHR: personalHRBaseline?.lowerQuartile,
                    personalUpperHR: personalHRBaseline?.upperQuartile
                )
                : .none
            // For run stations the chip tint follows the cue
            // (green hold / red slow / blue push) so the same
            // color signal reads at a glance whether you're racing
            // it right. For workout stations there's no pace cue,
            // so we fall back to the zone color. Extracted into a
            // helper because IIFEs inside @ViewBuilder closures
            // balloon SwiftUI's type-check time.
            let chipColor = liveHRChipColor(for: cue, fallbackZone: zone)

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

    // Tint resolution for the live HR chip. Maps each coaching cue
    // to its visible color; falls back to the current HR zone's
    // own color when there's no cue to apply (workout stations,
    // no HR yet). Extracted from `liveHeartRateChip` so the chip's
    // body stays light for the SwiftUI type-checker.
    private func liveHRChipColor(
        for cue: RaceStats.CoachingCue,
        fallbackZone: HRZone
    ) -> Color {
        switch cue {
        case .hold:    return Color.success
        case .slow:    return Color.slow
        case .redline: return Color.redline
        case .recover: return Color.recover
        case .push:    return Color(hex: 0x5B9BD5)
        case .workout, .none: return fallbackZone.color
        }
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
            // Forward the same Settings flags the countdown was
            // started with so a tap-to-skip race honors privacy +
            // Live Activity prefs. Without these, skip would fall
            // back to defaults (public, live activity on) — wrong
            // for athletes who set Privacy → "default private."
            viewModel.skipCountdown(
                targetDuration: viewModel.activeRace?.targetDuration,
                defaultPrivate: profiles.first?.defaultRacePrivate ?? false,
                liveActivityEnabled: profiles.first?.liveActivityEnabled ?? true
            )
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

    // Wireframe 03.3 — evaluate whether to fire the coaching banner.
    // Called on HR change AND on station advance.
    //
    // Decision flow:
    //   1. Gate on the user's coachingOverlaysEnabled toggle.
    //   2. Compute the current cue via coachingOverlayCue(...).
    //   3. If the cue is .workout / .none (no banner state), retain
    //      whatever's currently shown but don't fire new ones. Update
    //      lastHRSampleForCue and return.
    //   4. If the cue matches lastBannerFiredCue → no transition,
    //      skip.
    //   5. If we've fired any banner within the last 10 seconds →
    //      cooldown, skip.
    //   6. Otherwise: fire — set activeCoachingCue, schedule a
    //      2.5s auto-dismiss, update transition trackers, fire haptic.
    //
    // The 10s cooldown is essential — without it the athlete would
    // see banners flashing every few seconds as HR oscillates through
    // zone boundaries. The cooldown plus the "transition required"
    // logic together produce ~1-2 banners per race segment.
    private func evaluateCoachingBanner(newHR: Double?) {
        guard profiles.first?.coachingOverlaysEnabled ?? true else {
            // Setting off — clear any in-flight banner so the
            // toggle takes effect immediately.
            if activeCoachingCue != nil {
                coachingBannerDismissTask?.cancel()
                activeCoachingCue = nil
            }
            return
        }
        guard viewModel.hasStarted, !viewModel.isFinished else { return }

        let cue = RaceStats.coachingOverlayCue(
            currentHR: newHR,
            maxHR: maxHeartRate,
            currentStation: viewModel.currentStation,
            completedSegmentsCount: viewModel.completedSegmentsCount,
            totalSegments: viewModel.totalSegments,
            priorHR: lastHRSampleForCue,
            personalLowerHR: personalHRBaseline?.lowerQuartile,
            personalUpperHR: personalHRBaseline?.upperQuartile
        )

        // Always update prior-HR before any early-return so trend
        // detection has fresh data on the next tick.
        defer { lastHRSampleForCue = newHR }

        // Skip non-banner cue states (.workout, .none).
        guard cue.firesBanner else { return }

        // Skip if this is the same cue we just showed.
        if cue == lastBannerFiredCue { return }

        // Cooldown — 10s minimum between any two banner fires so the
        // overlay doesn't flicker on rapid HR oscillation.
        if let lastFiredAt = lastBannerFiredAt,
           Date().timeIntervalSince(lastFiredAt) < 10 {
            return
        }

        // Fire the banner.
        coachingBannerDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            activeCoachingCue = cue
        }
        lastBannerFiredCue = cue
        lastBannerFiredAt = Date()

        // Fire the per-cue haptic pattern.
        Haptics.coachingCue(cue)

        // Auto-dismiss after 2.5s. Stored as a task so a manual tap
        // can cancel + clear in one shot.
        coachingBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                activeCoachingCue = nil
            }
        }
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
            case .pauseFreeRun, .resumeFreeRun, .endFreeRun:
                // Free-run wrist actions are handled by
                // FreeRunView's own onAction registration —
                // RaceView ignores them. The two surfaces are
                // mutually exclusive on iPhone (you're either in
                // a HYROX race or a free run, never both); the
                // active screen owns the action handler. If a
                // stale free-run action lands here (race active
                // when wrist sends free-run), silently drop it
                // rather than misrouting to race controls.
                break
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

        // §13.8 Tier 2 — rep count samples from the Watch's wrist
        // IMU during a rep-counting station (wall balls in Phase 1).
        // The handler routes into the view model where the latest
        // count is held until engine.advance closes the station's
        // Split, at which point it's stamped onto Split.repsCompleted.
        // Late samples (after advance has fired) get patched onto
        // the just-closed split if its repsCompleted is still nil.
        WatchCompanionService.shared.onRepCount = { update in
            viewModel.ingestRepCount(update)
        }

        // §47a — End-of-segment timestamp batch from the Watch.
        // Fires once when WatchRepCountingService.stop() runs (i.e.
        // when the athlete leaves a rep-counting station). Routes
        // into the view model to stamp the just-closed split's
        // repTimestampOffsets — same catch-up pattern as
        // ingestRepCount, scoped to the batch instead of the count.
        WatchCompanionService.shared.onRepTimestamps = { batch in
            viewModel.ingestRepTimestamps(batch)
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
            personalHRBaseline: personalHRBaseline,
            guardrailHistory: allRaces,
            coachingCuesEnabled: profiles.first?.coachingCuesEnabled ?? true,
            // §13.8 Tier 2 — Watch reads this from the snapshot
            // to decide whether to spin up WatchRepCountingService
            // when entering a rep-counting station. nil → off (the
            // conservative legacy default).
            wristRepCountingEnabled: profiles.first?.wristRepCountingEnabled ?? false
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
            .disabled(viewModel.isPaused)
            .opacity(viewModel.isPaused ? 0.4 : 1.0)
        } else {
            let useRoxzone = (profiles.first?.roxzoneEnabled ?? false)
            // Wireframe 03.2 spec: CTA copy varies by what's
            // currently happening. On a run (current kind == .run)
            // the next thing is a workout station → "Next Station".
            // On a workout (current kind == .workout) the next
            // thing is a run → "Done · Next Run". When roxzone is
            // on, the engine routes through `endSegmentRace`, so
            // we prefix "End" to match the transition intent.
            let label = advanceCTALabel(useRoxzone: useRoxzone)

            Button {
                Haptics.impact(.medium)
                if useRoxzone {
                    viewModel.endSegmentRace()
                } else {
                    viewModel.advance()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18, weight: .heavy))
                    Text(label)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Layout.raceButtonHeight)
                .background(Color.accent)
                .foregroundStyle(Color.onAccent)
                .clipShape(RoundedRectangle(cornerRadius: Layout.sheetCornerRadius))
                // Wireframe spec: coral glow on the CTA. Stadium-
                // light feel; the cathedral's primary action wants
                // emphasis. Glow dialed back in light mode so the
                // off-white bg doesn't read as a coral wash.
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.40 : 0.22),
                    radius: 18,
                    x: 0,
                    y: 0
                )
            }
            .buttonStyle(.pressableCard)
            .disabled(viewModel.isPaused)
            .opacity(viewModel.isPaused ? 0.4 : 1.0)
            .animation(
                reduceMotion ? .none : .smooth(duration: 0.25),
                value: viewModel.isPaused
            )
        }
    }

    // Wireframe-prescribed CTA copy. Varies by current station kind:
    //   • Run station (next thing is a workout)  → "Next Station"
    //   • Workout (next thing is a run)          → "Done · Next Run"
    //   • Roxzone mode  prefixes "End " to either.
    private func advanceCTALabel(useRoxzone: Bool) -> String {
        guard let current = viewModel.currentStation else {
            return useRoxzone ? "End Station" : "Next Station"
        }
        switch current.kind {
        case .run:
            return useRoxzone ? "End Run" : "Next Station"
        case .workout:
            return useRoxzone ? "End Station" : "Done · Next Run"
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
                // Same two-row top-bar pattern as the in-progress
                // view. See the comment block on inProgressView's
                // header for the split rationale — controls on
                // top, live signals on a second row beneath.
                HStack(spacing: 10) {
                    splitsChipButton
                    Text("Station \(viewModel.completedSegmentsCount + 1) of \(viewModel.totalSegments)")
                        .capsLabelStyle()
                    Spacer()
                    pauseResumeButton
                    cancelButton
                }
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Spacer()
                    paceChip(now: context.date)
                    liveHeartRateChip
                }
                .padding(.top, 6)

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

                roxzoneStartButton
                    .padding(.bottom, 16)
            }
        }
    }

    // Roxzone "Start [next station]" primary CTA. Extracted from
    // inRoxzoneView's inline VStack to keep that view's
    // type-check time small. Same coral-gradient + glow language
    // as RaceStartView's primary CTA so the visual reads as
    // "you're starting work again."
    private var roxzoneStartButton: some View {
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
            .clipShape(RoundedRectangle(cornerRadius: Layout.sheetCornerRadius))
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

// Small filled coral dot that pulses at the brand "ambient" cadence
// (Motion.ambient — 1.4s ease-in-out, repeat forever). Sits inside
// the ● LIVE badge on the in-race cathedral header to confirm the
// race is actively recording. Disabled under Reduce Motion — the
// dot stays static at its rest scale so vestibular-sensitive users
// still get the same visual signal without the rhythm.
private struct LivePulseDot: View {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Color.accent)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing && !reduceMotion ? 1.0 : 0.7)
            .opacity(pulsing && !reduceMotion ? 1.0 : 0.55)
            .animation(
                reduceMotion
                    ? .none
                    : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear {
                if !reduceMotion {
                    pulsing = true
                }
            }
    }
}

// Wireframe 03.3 coaching banner. A full-width pill-card that drops
// in from the top of the race screen when a new HR state fires.
//
//   ┌────────────────────────────────────────────────────────┐
//   │ HOLD     Zone 4 lock-in                                │
//   │          162 bpm · clean                               │
//   └────────────────────────────────────────────────────────┘
//
// Background color comes from the cue's `bannerColorHex` (blue,
// amber, red, green, coral). Text is always white-on-color
// (Color.onAccent) for contrast against the saturated bg. Shadow
// scales with mode — heavier on dark for stadium-light feel,
// dialed back on warm light bg so it doesn't read as a wash.
//
// The banner is non-interactive on a touch level — the parent
// RaceView attaches a tap-to-dismiss gesture in its overlay
// layer rather than wiring it into the banner itself, so the
// banner stays presentation-only.
struct CoachingBanner: View {
    let cue: RaceStats.CoachingCue
    let currentHR: Double?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Verb — caps, large, white. The cathedral-headline
            // equivalent for the banner.
            Text(cue.displayText)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(Color.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(cue.bannerActionLine)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.white)

                Text(cue.bannerDetail(currentHR: currentHR))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: cue.bannerColorHex))
        )
        .shadow(
            color: Color(hex: cue.bannerColorHex)
                .opacity(colorScheme == .dark ? 0.45 : 0.30),
            radius: colorScheme == .dark ? 24 : 18,
            x: 0,
            y: 8
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cue.displayText). \(cue.bannerActionLine). \(cue.bannerDetail(currentHR: currentHR)).")
    }
}

#Preview("Pre-race") {
    RaceView()
        .preferredColorScheme(.dark)
}

// MARK: - HR source banner (§19)

// Plain value payload for the 2s mid-race fallover banner.
// Stored on `RaceView.hrSourceBanner` and consumed by
// `HRSourceBanner` for display. Kept as a value type so
// SwiftUI `@State` reacts cleanly when a new fallover
// replaces an existing banner.
struct HRSourceBannerInfo: Equatable {
    let text: String
    let symbolName: String
}

// Quiet pill banner — small SF Symbol + caption text in a
// surface-fill capsule. Mirrors the Live Activity HR pill's
// visual weight so the in-app banner reads in the same
// language as the lock-screen treatment. No coaching tint —
// this isn't an action cue, it's a "your data is still
// flowing under a different sensor" reassurance.
struct HRSourceBanner: View {
    let info: HRSourceBannerInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.symbolName)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.accent)
            Text(info.text)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.surfaceElevated)
                .overlay(
                    Capsule()
                        .stroke(Color.accent.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityLabel(info.text)
    }
}

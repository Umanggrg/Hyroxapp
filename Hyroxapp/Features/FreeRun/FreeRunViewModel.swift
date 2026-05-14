import Foundation
import Observation
import SwiftData

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(Auth)
// Required for `AuthService.shared.user?.id` property access —
// the User type is defined in supabase-swift's Auth submodule
// and Swift's implicit-member-access rule needs the defining
// module imported in any file that touches the type's members.
import Auth
#endif

// View model for the Free Run flow. Owns the FreeRunEngine, the
// active SwiftData FreeRun row, and the lifecycle bridge to whichever
// distance source is feeding metres into the engine.
//
// Phase 1 scope (this file's current state): lifecycle (start /
// pause / resume / end / abandon), persistence to SwiftData, engine
// state passthrough. The HK plumbing (HKWorkoutSession on iPhone for
// pedometer/GPS, distance ingest from CMPedometer, HR observation,
// route building, post-finish HK save) lands in Phase 2 — stubbed
// here with TODO markers so the wiring shape is visible.
//
// Watch parity (Phase 3) will reuse these same methods through
// WatchCompanionService control commands; the iPhone-side calls
// `sendControl(.startFreeRun(...))` and the Watch's free-run manager
// drives its own HKWorkoutSession in lockstep — same architecture as
// HYROX races where the iPhone is the engine of record and the Watch
// mirrors.
//
// Threading: `@Observable` + `@MainActor` so SwiftUI views read
// state directly and writes don't race against the UI tree.
@Observable
@MainActor
final class FreeRunViewModel {

    // MARK: - State

    // Engine — created lazily on `start`. Until then the view
    // model is in an "idle / no run" state.
    private(set) var engine: FreeRunEngine?

    // The persisted row backing the active run. Created on
    // start, updated on every state transition, finalized on end.
    private(set) var activeRun: FreeRun?

    // Live HR sample, in bpm. Same field shape as `RaceViewModel`'s
    // currentHeartRateBPM — fed by either the Watch's HR streaming
    // (Phase 3) or the iPhone's HK polling (Phase 2). Nil when no
    // recent sample exists.
    private(set) var currentHeartRateBPM: Double?

    // §27 — in-memory HR sample buffer accumulated during the
    // run. Every Watch WCSession sample (primary) and HK 5s poll
    // sample (fallback) gets appended here, deduped to a 0.5s
    // minimum interval so the two sources don't double-count
    // sub-second collisions. Flushed to `activeRun.hrSeriesData`
    // on `end()` so post-run analytics have a dense, accurate
    // series instead of relying on HK's stored sample density
    // (which is sparse on outdoor runs where the optical sensor
    // struggles or HK writes are delayed).
    //
    // Reset at start. Cleared at teardown. Not persisted mid-run
    // — the cost of re-encoding a growing JSON blob on every HR
    // sample would dwarf the value, and we never use the
    // mid-run buffer for anything other than the post-run flush.
    private var hrBuffer: [HRSample] = []

    // Convenience accessor — true while a run is in progress
    // (engine exists AND it's in .inProgress phase). View layer
    // gates UI on this.
    var isRunning: Bool {
        engine?.isRunning ?? false
    }

    // True for both .inProgress AND .paused — in either case
    // there's an active session that can be resumed/ended. View
    // layer uses this to decide between "show start button" and
    // "show in-progress UI."
    var hasActiveSession: Bool {
        guard let engine else { return false }
        return engine.isRunning || engine.isPaused
    }

    // SwiftData context — injected via .modelContext from the
    // hosting view. Required for persistence; calls bail silently
    // when nil so previews compile.
    var modelContext: ModelContext?

    // MARK: - Lifecycle

    // Begin a new run. Configures the engine with the user's
    // chosen split unit, persists a new FreeRun row, kicks off
    // the distance source (Phase 2) and starts HR observation
    // (Phase 2).
    //
    // Idempotent against double-taps: bails silently if a session
    // is already active.
    func start(
        locationType: FreeRunLocationType,
        splitUnit: FreeRunSplitUnit,
        defaultPrivate: Bool = false
    ) {
        guard !hasActiveSession else { return }

        let now = Date()

        let engine = FreeRunEngine(splitUnit: splitUnit)
        engine.start(at: now)
        self.engine = engine

        // §27 — reset HR buffer at start so a previous session's
        // samples can't bleed into this run.
        hrBuffer = []

        let run = FreeRun(
            startedAt: now,
            locationType: locationType,
            splitUnit: splitUnit,
            isPrivate: defaultPrivate
        )
        modelContext?.insert(run)
        activeRun = run
        saveContextSilently()

        // Push the initial "we're now running" snapshot to the
        // Watch IMMEDIATELY. Without this, the wrist stays on
        // its idle Ready screen until the first distance update
        // lands and triggers persistActiveRun (which pushes a
        // snapshot as a side effect). Pedometer warmup can take
        // 5-10 seconds, so the wrist felt broken — the user
        // would tap Start, wait, see nothing change. Publishing
        // here flips the wrist into the Free Run UI within ~1s
        // of the iPhone start.
        publishWatchSnapshot()

        startDistanceSource(for: locationType)
        startHeartRateObservation()
        // §11 Free Run cathedral — pair HeadphoneMotionService
        // with the run lifecycle so the live cadence chip on
        // FreeRunView publishes spm while running. Safe no-op
        // when AirPods Pro 1+ / 4 / Max aren't in the audio
        // route (or non-motion AirPods are connected).
        HeadphoneMotionService.shared.start()

        // §12C — start the Free Run Live Activity. Lock screen
        // banner + Dynamic Island timer mirror the race
        // activity pattern. Bails silently when LA isn't
        // authorized or the budget is exhausted.
        #if canImport(ActivityKit)
        if let state = currentFreeRunActivityState() {
            let attributes = FreeRunActivityAttributes(
                locationLabel: "\(locationType.displayName) Run"
            )
            LiveActivityService.shared.startFreeRun(
                attributes: attributes,
                contentState: state
            )
        }
        #endif
    }

    // Pause the active run. Engine freezes the timer; distance
    // source halts (so no late metres land while paused); HR
    // observation continues so the chip still shows current
    // value if the athlete glances at the screen.
    func pause() {
        guard let engine, engine.isRunning else { return }
        engine.pause(at: Date())
        persistActiveRun()
        pauseDistanceSource()

        #if canImport(WatchConnectivity)
        // Phase 3 — tell the Watch to pause its own session so
        // distance + HR aggregation pause in lockstep.
        // Placeholder: WatchCompanionService.shared.sendControl(.pauseFreeRun)
        #endif
    }

    func resume() {
        guard let engine, engine.isPaused else { return }
        engine.resume(at: Date())
        persistActiveRun()
        resumeDistanceSource()
    }

    // End the run cleanly — flush HK, finalize splits, kick off
    // the post-finish HR rehydrate (Phase 2 implementation), and
    // mark the FreeRun row as `.endedAt = now`.
    func end() {
        guard let engine, engine.isRunning || engine.isPaused else { return }
        let now = Date()
        engine.end(at: now)

        // §27 — flush the in-memory HR sample buffer onto the
        // FreeRun row BEFORE persistActiveRun() so the encoded
        // BLOB lands in the same SwiftData save that finalizes
        // `endedAt`. Empty buffers are still written (nil) so
        // a run with zero HR samples is unambiguous downstream.
        if let run = activeRun {
            run.setHRSeries(hrBuffer)
        }

        persistActiveRun()

        stopDistanceSource()
        stopHeartRateObservation()
        // §11 Free Run cathedral — tear down the head-motion
        // subscription alongside HR. Leaving CMHeadphoneMotionManager
        // active after the run drains AirPods battery without
        // any UI consuming the values.
        HeadphoneMotionService.shared.stop()

        // §12C — end the Live Activity with a final
        // .finished state. iOS keeps the FINISHED ribbon on
        // the lock screen for ~4h so the athlete can glance
        // at their total time + distance without unlocking
        // (matches the race finish path's .default dismissal
        // policy).
        #if canImport(ActivityKit)
        let finalState = currentFreeRunActivityState()
        LiveActivityService.shared.endFreeRun(finalState: finalState)
        #endif

        // Phase 2 hook — flush the HKWorkoutSession to HK, then
        // wait ~8s and re-query each split's HR window (same
        // rehydrate pattern that fixed race-level physiology).
        rehydrateFromHealthKit()
    }

    // Abandon — the user cancelled mid-run. Drop the FreeRun row
    // entirely so unfinished sessions don't pollute History.
    // Symmetric with RaceViewModel.abandon for races.
    func abandon() {
        engine?.end(at: Date())
        if let run = activeRun {
            modelContext?.delete(run)
            saveContextSilently()
        }
        teardown()
    }

    // Tear down post-finish or post-abandon. Clears the engine +
    // active run reference but leaves the persisted row alone
    // (it's complete — belongs in History).
    func finishSession() {
        teardown()
    }

    private func teardown() {
        engine = nil
        activeRun = nil
        currentHeartRateBPM = nil
        // §27 — drop the buffer too so an abandoned-and-then-
        // restarted session starts clean. end() has already
        // flushed it onto the FreeRun row for the happy path;
        // the abandon path drops the row entirely, so clearing
        // here is safe in both cases.
        hrBuffer = []
        stopDistanceSource()
        stopHeartRateObservation()
        // §11 Free Run cathedral — also unconditionally tear
        // down head-motion on teardown (covers abandon paths
        // that don't go through end()). HeadphoneMotionService.
        // stop() is idempotent.
        HeadphoneMotionService.shared.stop()
        // §12C — kill any stray Live Activity. Symmetric with
        // RaceViewModel.abandon's immediate end. Safe to call
        // even when no activity is running (no-op in that case).
        #if canImport(ActivityKit)
        LiveActivityService.shared.endFreeRun(finalState: nil)
        #endif
        // Clear the wrist's free-run UI — Watch returns to its
        // idle "Ready" screen, same UX a finished race produces.
        publishWatchClearSnapshot()
    }

    // MARK: - Persistence

    // Mirror engine state onto the FreeRun SwiftData row. Called
    // on every meaningful state transition (start, pause, resume,
    // split fired, end). Same write-on-every-event pattern as
    // RaceViewModel — at most a few hundred ms is lost on a
    // mid-run app kill.
    private func persistActiveRun() {
        guard let run = activeRun, let engine else { return }

        run.distanceMetres = engine.distanceMetres
        run.splits = engine.splits

        switch engine.phase {
        case .notStarted:
            // Should be unreachable from a persist call —
            // persist only fires after start(). Defensive
            // no-op.
            break
        case .inProgress(let startedAt):
            run.startedAt = startedAt
            run.endedAt = nil
            run.pausedAt = nil
        case .paused(let startedAt, let pausedAt):
            run.startedAt = startedAt
            run.endedAt = nil
            run.pausedAt = pausedAt
        case .finished(let startedAt, let endedAt):
            run.startedAt = startedAt
            run.endedAt = endedAt
            run.pausedAt = nil
        }

        saveContextSilently()
        // Mirror the state to the wrist on every persist. Same
        // write-on-every-event cadence as the iPhone summary —
        // Watch sees fresh distance + phase within ~0.5s of the
        // iPhone-side change.
        publishWatchSnapshot()
        // §12C — also push to the Live Activity. ActivityKit
        // budget caps updates per app per hour; persistActiveRun
        // is the canonical "real state change happened" hook
        // (distance milestone, pause, resume, end) so all such
        // events land on the lock screen.
        #if canImport(ActivityKit)
        pushFreeRunActivityUpdate()
        #endif
    }

    // §12C — Free Run Live Activity ContentState builder.
    // Translates the engine + active run's current state into
    // the ContentState shape the widget renders. Nil only when
    // there's no active engine / run (defensive against being
    // called outside a session).
    #if canImport(ActivityKit)
    private func currentFreeRunActivityState() -> FreeRunActivityAttributes.ContentState? {
        guard let engine, let run = activeRun else { return nil }

        let phase: FreeRunActivityAttributes.ContentState.Phase
        let timerStart: Date
        var frozenElapsed: TimeInterval? = nil

        switch engine.phase {
        case .notStarted:
            return nil
        case .inProgress(let startedAt):
            phase = .running
            timerStart = startedAt
        case .paused(let startedAt, let pausedAt):
            phase = .paused
            timerStart = startedAt
            frozenElapsed = pausedAt.timeIntervalSince(startedAt)
        case .finished(let startedAt, let endedAt):
            phase = .finished
            timerStart = startedAt
            frozenElapsed = endedAt.timeIntervalSince(startedAt)
        }

        let splitUnit = run.splitUnit
        let metres = engine.distanceMetres

        // Avg pace — total elapsed ÷ distance-in-unit. Nil
        // until distance is meaningful (>~10m) so the lock
        // screen doesn't show a nonsense pace during the
        // first few seconds.
        let avgPace: TimeInterval? = {
            guard metres > 10 else { return nil }
            let elapsed: TimeInterval = {
                switch engine.phase {
                case .notStarted: return 0
                case .inProgress(let startedAt):
                    return Date().timeIntervalSince(startedAt)
                case .paused(let startedAt, let pausedAt):
                    return pausedAt.timeIntervalSince(startedAt)
                case .finished(let startedAt, let endedAt):
                    return endedAt.timeIntervalSince(startedAt)
                }
            }()
            guard elapsed > 0 else { return nil }
            let units = metres / splitUnit.metresPerUnit
            return elapsed / units
        }()

        let hr: Int? = currentHeartRateBPM.map { Int($0.rounded()) }
        let hrZone: Int? = currentHeartRateBPM.map {
            HRZone.zone(for: $0, maxBPM: 190).rawValue
        }

        return FreeRunActivityAttributes.ContentState(
            phase: phase,
            timerStart: timerStart,
            frozenElapsed: frozenElapsed,
            distanceMeters: metres,
            splitUnitMetres: splitUnit.metresPerUnit,
            splitUnitLabel: splitUnit.shortLabel,
            avgPaceSecondsPerUnit: avgPace,
            currentHR: hr,
            currentHRZone: hrZone
        )
    }

    private func pushFreeRunActivityUpdate() {
        guard let state = currentFreeRunActivityState() else { return }
        LiveActivityService.shared.updateFreeRun(state)
    }
    #endif

    private func saveContextSilently() {
        try? modelContext?.save()
    }

    // MARK: - Watch sync

    // Build the current FreeRunStateSnapshot from engine + run
    // state. Returns nil when there's no active session — the
    // caller publishes "no run active" by sending a `.notStarted`
    // snapshot instead, so the Watch can clear its free-run UI.
    private func makeFreeRunSnapshot() -> FreeRunStateSnapshot? {
        guard let engine, let run = activeRun else { return nil }

        let phase: FreeRunStateSnapshot.Phase
        let startedAt: Date?
        let pausedAt: Date?
        let endedAt: Date?

        switch engine.phase {
        case .notStarted:
            return nil
        case .inProgress(let s):
            phase = .inProgress
            startedAt = s
            pausedAt = nil
            endedAt = nil
        case .paused(let s, let p):
            phase = .paused
            startedAt = s
            pausedAt = p
            endedAt = nil
        case .finished(let s, let e):
            phase = .finished
            startedAt = s
            pausedAt = nil
            endedAt = e
        }

        return FreeRunStateSnapshot(
            phase: phase,
            startedAt: startedAt,
            pausedAt: pausedAt,
            endedAt: endedAt,
            distanceMetres: engine.distanceMetres,
            splitUnitRaw: run.splitUnit.rawValue,
            locationTypeRaw: run.locationType.rawValue,
            currentHeartRateBPM: currentHeartRateBPM,
            completedSplitCount: engine.splits.count
        )
    }

    // Push the current state to the paired Watch. Called on every
    // meaningful event (start, pause, resume, end, distance/split
    // update). Watch's WatchRaceClient receives the dictionary and
    // routes to its free-run UI when the `kind` discriminator
    // matches FreeRunStateSnapshot.kindValue.
    private func publishWatchSnapshot() {
        #if canImport(WatchConnectivity)
        guard let snapshot = makeFreeRunSnapshot() else { return }
        WatchCompanionService.shared.publishFreeRun(snapshot)
        #endif
    }

    // Send a synthetic "no run" snapshot so the Watch returns to
    // its idle Ready screen after a free run ends or is abandoned.
    // The Watch treats `.notStarted` as "clear the free-run UI."
    private func publishWatchClearSnapshot() {
        #if canImport(WatchConnectivity)
        let synthetic = FreeRunStateSnapshot(
            phase: .notStarted,
            startedAt: nil,
            distanceMetres: 0,
            splitUnitRaw: FreeRunSplitUnit.mile.rawValue,
            locationTypeRaw: FreeRunLocationType.indoor.rawValue
        )
        WatchCompanionService.shared.publishFreeRun(synthetic)
        #endif
    }

    // MARK: - Distance source

    // Boots the iPhone's HKWorkoutSession (via FreeRunWorkoutManager)
    // configured for `.running` + the chosen indoor/outdoor location
    // type. The manager handles GPS+pedometer fusion for outdoor and
    // pedometer-only for indoor — Apple's HKLiveWorkoutBuilder
    // abstracts the two, so we just observe the cumulative-metres
    // and HR callbacks and forward into the engine.
    //
    // The manager also requests HK auth (idempotent — only prompts
    // for unseen types) and CL auth (outdoor only) on first use.
    private func startDistanceSource(for locationType: FreeRunLocationType) {
        let manager = FreeRunWorkoutManager.shared

        manager.onDistanceUpdate = { [weak self] date, metres in
            guard let self else { return }
            self.engine?.recordDistance(at: date, metres: metres)
            self.persistActiveRun()
        }
        manager.onHeartRateUpdate = { [weak self] date, bpm in
            guard let self else { return }
            // §27 — funnel HK poll samples through the same
            // ingest the Watch WCSession stream uses so the
            // buffer captures both sources. Dedupe inside
            // `ingestHeartRateBPM` keeps a fresh Watch sample
            // from being clobbered by a stale poll arriving
            // within 0.5s.
            self.ingestHeartRateBPM(bpm, at: date)
        }

        Task { @MainActor in
            await manager.requestAuthorizationIfNeeded()
            manager.start(locationType: locationType)
        }

        #if canImport(WatchConnectivity)
        // Tell the paired Watch to start its OWN HKWorkoutSession
        // for `.running`. This is what makes HR work end-to-end:
        //   • Watch's HKLiveWorkoutBuilder collects HR samples
        //     from the wrist sensor and streams them to the
        //     iPhone via WCSession (the existing onHeartRate
        //     callback the race path already uses).
        //   • Watch writes HR + distance + active calories to
        //     HKHealthStore in real time during the session, so
        //     the iPhone's `currentHeartRate()` poll finds fresh
        //     samples and the post-finish rehydrate has per-split
        //     windows to query.
        //   • Watch also writes a real HKWorkout on finish, so
        //     the run earns Activity-ring credit.
        //
        // Without this, FreeRun on iPhone would only have
        // pedometer-driven distance and zero HR (HK never gets
        // populated since no workout session is running).
        WatchCompanionService.shared.sendControl(
            .startFreeRunWorkout(
                at: Date(),
                locationTypeRaw: locationType.rawValue
            )
        )
        #endif
    }

    private func pauseDistanceSource() {
        FreeRunWorkoutManager.shared.pause()
        #if canImport(WatchConnectivity)
        // Mirror pause on the Watch — session collection halts
        // so HR / distance / calories don't accumulate during
        // the pause window. Same `pauseWorkout` control the race
        // path uses; the Watch's pause/resume operate on whatever
        // active session exists.
        WatchCompanionService.shared.sendControl(.pauseWorkout)
        #endif
    }

    private func resumeDistanceSource() {
        FreeRunWorkoutManager.shared.resume()
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.sendControl(.resumeWorkout)
        #endif
    }

    private func stopDistanceSource() {
        // `finalize: true` — saves the run as an HKWorkout to
        // Apple Health. Use `abandon()` for the cancel path,
        // which calls .end(finalize: false) via this same method
        // through teardown's stopDistanceSource — the abandon
        // path is the only caller that wants the discard
        // semantic.
        FreeRunWorkoutManager.shared.end(finalize: true)
        FreeRunWorkoutManager.shared.onDistanceUpdate = nil
        FreeRunWorkoutManager.shared.onHeartRateUpdate = nil

        #if canImport(WatchConnectivity)
        // Mirror end on the Watch — finalize the wrist's HK
        // session so HKLiveWorkoutBuilder.finishWorkout flushes
        // every buffered HR + distance sample to HKHealthStore.
        // The post-finish rehydrate (8s delayed) then queries
        // each split's window and finds real samples instead of
        // the empty windows we saw before this fix.
        WatchCompanionService.shared.sendControl(
            .endFreeRunWorkout(at: Date())
        )
        #endif
    }

    // MARK: - HR observation

    // HR is delivered through the FreeRunWorkoutManager's
    // `onHeartRateUpdate` callback (wired in startDistanceSource
    // above). The callback writes into `currentHeartRateBPM`,
    // which the live UI binds to via `@Observable`. No separate
    // poll loop needed — HKLiveWorkoutBuilder is the single source
    // of truth for the active run, and it surfaces both distance
    // and HR through the same delegate.
    //
    // When a paired Apple Watch is on the wrist, its HR samples
    // flow into HKHealthStore in real time during a workout
    // session and are consumed by the same builder. iPhone-only
    // users (no paired Watch) get sparse HR — the chip simply
    // hides until a sample lands.
    private func startHeartRateObservation() {
        // No-op for the iPhone HK poll path — wired through the
        // workout manager's callback. §20 Path A adds the
        // external BLE strap path here: register the service's
        // onHeartRate callback so Garmin / Polar / Wahoo /
        // HRM-Pro samples funnel into the same ingest as the
        // Watch + AirPods paths. Safe no-op when no BLE strap
        // is paired.
        ExternalHRService.shared.onHeartRate = { [weak self] bpm, sampledAt in
            guard let self else { return }
            self.ingestHeartRateBPM(bpm, at: sampledAt)
        }
        ExternalHRService.shared.attemptReconnectToPaired()
    }

    private func stopHeartRateObservation() {
        currentHeartRateBPM = nil
        // §20 Path A — clear the BLE callback so a stale closure
        // doesn't keep firing into a torn-down viewmodel. We
        // intentionally DON'T disconnect the peripheral — the
        // BLE connection persists across runs to avoid the
        // reconnect handshake on every start.
        ExternalHRService.shared.onHeartRate = nil
    }

    // Public ingest for HR samples — single funnel for both the
    // Watch WCSession stream (primary, ~1Hz from the wrist's
    // HKLiveWorkoutBuilder) and the HK 5s poll fallback. Same
    // contract `RaceViewModel.ingestHeartRate(_:)` provides for
    // race mode — keeps internal mutation centralized while
    // letting the view's WCSession bridge feed the value.
    //
    // §27 — appends every meaningful sample to `hrBuffer` so
    // post-run analytics have a dense series. Dedupe window is
    // 0.5s: the WCSession stream tops out at ~1Hz, so spacing
    // ≥0.5s preserves it intact, while the HK 5s poll never
    // collides with a fresh wrist sample. Out-of-order samples
    // (rare WCSession queued-delivery edge case) are dropped —
    // the buffer must stay chronological for the zone-time
    // gap calculation to behave.
    //
    // Buffer fill is gated on `engine.isRunning` so paused runs
    // don't accumulate samples (the live chip can still display
    // them — that's fine — but the persisted series excludes
    // the pause window, matching `totalDuration`'s definition).
    func ingestHeartRateBPM(_ bpm: Double, at sampledAt: Date = Date()) {
        currentHeartRateBPM = bpm

        guard engine?.isRunning == true else { return }
        guard bpm >= 30, bpm <= 230 else { return }

        if let last = hrBuffer.last {
            // Drop out-of-order arrivals AND duplicates within
            // 0.5s of the prior sample.
            guard sampledAt.timeIntervalSince(last.sampledAt) >= 0.5 else { return }
        }

        hrBuffer.append(HRSample(sampledAt: sampledAt, bpm: bpm))
    }

    // MARK: - Post-finish HK rehydrate

    // Re-query HK for per-split HR aggregates after `finishWorkout`
    // flushes the buffered samples. Same fix-pattern as
    // `RaceViewModel.rehydrateSegmentStatsAfterFinish` — without
    // it, splits captured mid-run carry no HR data because the
    // builder's samples haven't been written to the store yet.
    private func rehydrateFromHealthKit() {
        #if canImport(HealthKit)
        // Capture the run + context references BEFORE scheduling
        // the delayed Task. The view's End-button flow calls
        // `viewModel.end()` (which schedules this rehydrate) and
        // then immediately calls `viewModel.finishSession()`
        // (which sets `self.activeRun = nil` and `self.engine =
        // nil` to free the live state). If the Task captures
        // `self.activeRun` lazily, by the time the 8-second
        // sleep ends, it's already nil and the guard returns
        // silently — so the rehydrate never actually ran.
        //
        // Capturing the run reference here keeps it alive for
        // the duration of the Task regardless of teardown.
        // SwiftData @Model classes are reference types so writes
        // to `capturedRun` persist correctly.
        guard let capturedRun = activeRun else { return }
        let capturedSplits = engine?.splits ?? []
        let capturedContext = modelContext

        Task { @MainActor in
            // 8s buffer matches the race rehydrate path —
            // `finishWorkout` typically completes + propagates
            // samples to HKHealthStore within 5-8s. Bumped one
            // pass with a retry below if HK still has nothing
            // (Watch flushes can be slower in real-world use).
            try? await Task.sleep(for: .seconds(8))

            // Per-split window HR avg + max. Splits live on the
            // captured run's `.splits` array (set by the
            // engine's last `persistActiveRun` before teardown).
            // We update the persisted FreeRun's splits in-place.
            var newSplits = capturedRun.splits
            for index in newSplits.indices {
                let split = newSplits[index]
                let stats = await HealthKitService.shared.heartRateStats(
                    from: split.startedAt,
                    to: split.endedAt
                )
                if stats.avg != nil || stats.max != nil {
                    newSplits[index] = FreeRunSplit(
                        index: split.index,
                        startedAt: split.startedAt,
                        endedAt: split.endedAt,
                        cumulativeDistanceMetres: split.cumulativeDistanceMetres,
                        segmentDistanceMetres: split.segmentDistanceMetres,
                        heartRateAvgBPM: stats.avg,
                        heartRateMaxBPM: stats.max
                    )
                }
            }
            capturedRun.splits = newSplits

            // Race-level HR aggregate covering the whole run.
            // Used on the summary hero + share card.
            if let endedAt = capturedRun.endedAt {
                var stats = await HealthKitService.shared.heartRateStats(
                    from: capturedRun.startedAt,
                    to: endedAt
                )

                // Retry once after another 5 seconds if HK
                // returned nothing — the Watch's finishWorkout
                // can lag past our 8s buffer in real-world use,
                // especially on a low-battery wrist or a slow
                // BT connection. One extra pass at 13s total
                // catches most of the late-flush cases.
                if stats.avg == nil {
                    try? await Task.sleep(for: .seconds(5))
                    stats = await HealthKitService.shared.heartRateStats(
                        from: capturedRun.startedAt,
                        to: endedAt
                    )
                }

                capturedRun.heartRateAvgBPM = stats.avg
                capturedRun.heartRateMaxBPM = stats.max
                let kcal = await HealthKitService.shared.activeCalories(
                    from: capturedRun.startedAt,
                    to: endedAt
                )
                capturedRun.activeCaloriesKcal = kcal
            }

            // Save through the captured context — same path
            // persistActiveRun would use, just with the local
            // reference instead of `self.modelContext` which
            // may have already cleared.
            // Ignore — same write-on-best-effort contract as
            // the live persist path.
            _ = capturedContext
            try? capturedContext?.save()

            // Push to Supabase. Lives at the END of the rehydrate
            // task so the row we ship has the just-populated HR
            // averages + calories baked in. Pushing earlier
            // (before rehydrate) would upload a row with nil HR,
            // which the next launch's pullAndReconcile would
            // overwrite from local — wasted round-trip. Errors
            // are swallowed inside the service; offline failures
            // catch up via the next pull-and-reconcile.
            #if canImport(WatchConnectivity)
            if let userID = AuthService.shared.user?.id.uuidString {
                await FreeRunSyncService.pushFinishedRun(
                    capturedRun,
                    userID: userID
                )
            }
            #endif
        }
        #endif
    }
}

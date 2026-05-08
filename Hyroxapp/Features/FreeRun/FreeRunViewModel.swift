import Foundation
import Observation
import SwiftData

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if canImport(ActivityKit)
import ActivityKit
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
        persistActiveRun()

        stopDistanceSource()
        stopHeartRateObservation()

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
        stopDistanceSource()
        stopHeartRateObservation()
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
    }

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
        manager.onHeartRateUpdate = { [weak self] _, bpm in
            guard let self else { return }
            self.currentHeartRateBPM = bpm
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
        // No-op — wired through the workout manager's callback.
    }

    private func stopHeartRateObservation() {
        currentHeartRateBPM = nil
    }

    // Public ingest for Watch-streamed HR samples. The view
    // (`FreeRunView`) registers the WCSession HR callback and
    // forwards each update through this method so the property
    // stays `private(set)` from the rest of the world. Same
    // contract `RaceViewModel.ingestHeartRate(_:)` provides for
    // race mode — keeps internal mutation centralized while
    // letting the view's WCSession bridge feed the value.
    func ingestHeartRateBPM(_ bpm: Double) {
        currentHeartRateBPM = bpm
    }

    // MARK: - Post-finish HK rehydrate

    // Re-query HK for per-split HR aggregates after `finishWorkout`
    // flushes the buffered samples. Same fix-pattern as
    // `RaceViewModel.rehydrateSegmentStatsAfterFinish` — without
    // it, splits captured mid-run carry no HR data because the
    // builder's samples haven't been written to the store yet.
    private func rehydrateFromHealthKit() {
        #if canImport(HealthKit)
        Task { @MainActor [weak self] in
            // 8s buffer matches the race rehydrate path —
            // `finishWorkout` typically completes + propagates
            // samples to HKHealthStore within 5-8s.
            try? await Task.sleep(for: .seconds(8))
            guard let self, let engine = self.engine else { return }

            // Per-split window HR avg + max via HKStatisticsQuery.
            for index in engine.splits.indices {
                let split = engine.splits[index]
                let stats = await HealthKitService.shared.heartRateStats(
                    from: split.startedAt,
                    to: split.endedAt
                )
                if stats.avg != nil || stats.max != nil {
                    engine.setSplitHRStats(
                        atIndex: index,
                        avg: stats.avg,
                        max: stats.max
                    )
                }
            }

            // Race-level HR aggregate covering the whole run.
            // Used on the summary's hero block.
            if let run = self.activeRun, let endedAt = run.endedAt {
                let stats = await HealthKitService.shared.heartRateStats(
                    from: run.startedAt,
                    to: endedAt
                )
                run.heartRateAvgBPM = stats.avg
                run.heartRateMaxBPM = stats.max
                let kcal = await HealthKitService.shared.activeCalories(
                    from: run.startedAt,
                    to: endedAt
                )
                run.activeCaloriesKcal = kcal
            }
            self.persistActiveRun()
        }
        #endif
    }
}

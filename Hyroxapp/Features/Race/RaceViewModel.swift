import Foundation
import SwiftData

// View-model bridge between the pure `RaceEngine` and SwiftUI, now also the
// bridge into SwiftData persistence.
//
// On every state-changing action (`startRace`, `advance`, finish-on-advance),
// we mirror the engine's state onto a persisted `Race` row and `save()`. That
// way an app-kill at any point — even mid-segment — leaves a consistent row
// that we can resume from on next launch.
//
// Timer-driven UI updates still live in the view (`TimelineView(.periodic)`);
// this class stays tick-free so it's cheap to read and has no runloop state
// to tear down.
@MainActor
@Observable
final class RaceViewModel {

    // MARK: - State owned by the VM

    // Underlying state machine — single source of truth for race logic.
    private(set) var engine = RaceEngine()

    // The persisted row mirroring `engine`. `nil` between races.
    private(set) var activeRace: Race?

    // An unfinished race discovered on launch. While non-nil, the view shows
    // a Resume / Discard prompt instead of the pre-race screen.
    private(set) var pendingResume: Race?

    // Live-polled heart rate during an active race. `nil` outside of
    // an active race, when HealthKit isn't authorized, when no Watch
    // is streaming samples, or simply between poll ticks before the
    // first sample arrives. UI reads this and renders a small "165
    // bpm" chip on the race screen when present.
    //
    // Intentionally separate from the per-split `heartRateAvgBPM` /
    // `heartRateMaxBPM` statistics — this is the LATEST instantaneous
    // reading, those are historical per-segment aggregates.
    private(set) var currentHeartRateBPM: Double?

    // Handle to the background polling Task so we can cancel it when
    // the race finishes, the user abandons, or the Race view
    // disappears. Nil outside of an active race.
    private var heartRatePollTask: Task<Void, Never>?

    // How often we refresh current HR during a race. 5s is a good
    // balance — Watch publishes HR to HealthKit every 5–15s in ambient
    // mode and more frequently in workout mode, so a 5s poll usually
    // catches the latest sample shortly after it lands without
    // hammering HealthKit with redundant queries.
    private static let heartRatePollInterval: TimeInterval = 5

    // MARK: - ModelContext plumbing

    // Held as a weak reference to the injected environment context. Assigned
    // by the view on appear — before that point the VM operates in memory
    // only (fine for previews / tests).
    private var modelContext: ModelContext?

    func bindModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Derived state (same surface as before)

    var isRacing: Bool {
        if case .inProgress = engine.state { return true }
        return false
    }

    var isFinished: Bool { engine.isFinished }
    var hasStarted: Bool { isRacing || isFinished }

    var currentStation: Station?   { engine.currentStation }
    var upcomingStation: Station?  { engine.upcomingStation }
    var splits: [Split]            { engine.splits }
    var sequence: [Station]        { engine.sequence }
    var totalSegments: Int         { engine.sequence.count }
    var completedSegmentsCount: Int { engine.splits.count }

    var finalTime: TimeInterval {
        guard case .finished(let start, let end, _) = engine.state else { return 0 }
        return end.timeIntervalSince(start)
    }

    func elapsed(at date: Date) -> TimeInterval {
        engine.elapsed(at: date)
    }

    func currentSegmentElapsed(at date: Date) -> TimeInterval {
        engine.currentSegmentElapsed(at: date)
    }

    // MARK: - Launch-time resume lookup

    // Find the most recently created unfinished race, if any, so the view can
    // prompt the user to resume it. Called on view-appear.
    //
    // Skipped when we're already tracking a race — otherwise switching tabs
    // mid-race would re-find the live race and flash the resume prompt over
    // the in-progress UI.
    func checkForResumableRace() {
        guard activeRace == nil else { return }
        guard let modelContext else { return }

        // `#Predicate` is SwiftData's compile-time-checked query DSL — much
        // safer than NSPredicate string literals. Here we want races whose
        // `endedAt` is still nil (i.e. not yet finished).
        var descriptor = FetchDescriptor<Race>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let unfinished = try? modelContext.fetch(descriptor).first {
            pendingResume = unfinished
        }
    }

    // User tapped Resume on the launch prompt.
    func resumePending() {
        guard let race = pendingResume else { return }
        engine = RaceEngine(sequence: race.sequence, state: race.engineState)
        activeRace = race
        pendingResume = nil
        // If multiple unfinished races accumulated from prior force-kills
        // (we only ever offer the most recent), delete the older orphans
        // so History stays clean and future checkForResumableRace calls
        // don't fish up stale rows.
        purgeOrphanedUnfinishedRaces(excluding: race)
        // Resume the live-HR polling loop — the user's still racing,
        // they still want to see their current bpm on screen.
        startHeartRatePolling()
    }

    // User tapped Discard on the launch prompt.
    func discardPending() {
        guard let race = pendingResume else { return }
        modelContext?.delete(race)
        pendingResume = nil
        // Discard also cleans up any even older orphans — the user has
        // signaled they don't want any unfinished race to persist.
        purgeOrphanedUnfinishedRaces(excluding: nil)
        saveContextSilently()
    }

    // Delete every unfinished (`endedAt == nil`) race except optionally
    // the one being actively resumed. Called after both resume and
    // discard flows to keep storage tidy — a single athlete should never
    // have more than one unfinished race in flight at a time.
    //
    // `except` is the one race we want to keep; pass `nil` on discard to
    // wipe everything unfinished.
    private func purgeOrphanedUnfinishedRaces(excluding except: Race?) {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Race>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        guard let allUnfinished = try? modelContext.fetch(descriptor) else { return }

        for race in allUnfinished where race.id != except?.id {
            modelContext.delete(race)
        }
        saveContextSilently()
    }

    // MARK: - Actions

    // Begin a race. Defaults to the full 16-segment HYROX sequence so
    // the standard "Start Race" button keeps its zero-config behavior.
    // Pass an explicit `sequence` to run a custom workout — a shortened
    // session, a strength-focused circuit, a repeating pattern — and
    // the engine handles advance/finish naturally because it already
    // parameterizes on the segment list.
    //
    // Pass `targetDuration` to record a finish-time goal ("beat 1:30:00").
    // Engine itself is target-unaware; this value lives on the Race
    // row and views read it for display/comparison.
    //
    // Empty `sequence` is a no-op (nothing to start). Callers should
    // validate before calling; the guard here is defensive.
    func startRace(
        sequence: [Station] = Station.raceSequence,
        targetDuration: TimeInterval? = nil
    ) {
        guard !sequence.isEmpty else { return }

        let now = Date()
        engine = RaceEngine(sequence: sequence)
        engine.start(at: now)

        let race = Race(
            startedAt: now,
            currentSegmentStartedAt: now,
            sequence: engine.sequence,
            targetDuration: targetDuration
        )
        modelContext?.insert(race)
        activeRace = race
        saveContextSilently()
        // Kick off the live-HR polling loop. Runs independently of
        // the per-split HR stats — this feeds the on-screen "current
        // bpm" readout, not the historical per-station aggregates.
        startHeartRatePolling()
    }

    func advance() {
        // Detect the transition to `.finished` so we can mirror the race out
        // to HealthKit exactly once (not on every advance).
        let wasFinished = engine.isFinished
        engine.advance(at: Date())
        // Capture the index of the split that `engine.advance` just appended
        // so the async HR patch can find and update it below. Must be read
        // before `persistActiveRace` because that's a sync write; the HR
        // task is what races the user forward.
        let newSplitIndex = engine.splits.count - 1
        persistActiveRace()

        if !wasFinished, engine.isFinished {
            saveFinishedRaceToHealthKit()
        }

        // Fire-and-forget: fetch segment-window stats from HealthKit
        // (HR avg/max + active calories, in parallel) and patch them
        // onto the just-completed split. Runs in the background so
        // the UI transition to the next station is instant (no
        // 100–300ms HealthKit query latency between tap and advance).
        // If no metrics are available the split keeps its nil values
        // and the UI omits them.
        attachSegmentStats(to: newSplitIndex)
    }

    // MARK: - Segment stats capture (HR + calories)

    // Query HealthKit for HR avg/max + active calories over the
    // just-completed segment's time window, and patch the split at
    // `index` with the result. The two queries run in parallel via
    // `async let` to minimize the latency before stats appear on
    // screen. Re-persists afterwards so the Race row in SwiftData
    // carries the segment metrics through to History.
    //
    // The segment window is read from the split itself (its startedAt
    // and endedAt) rather than passed in — the engine already has the
    // authoritative timestamps by the time this runs, and reading
    // them here keeps the capture path robust to any future changes
    // in how advance is invoked.
    //
    // Guarded `#if canImport(HealthKit)` so macOS builds — which lack
    // HealthKit — compile without the query path at all.
    private func attachSegmentStats(to index: Int) {
        #if canImport(HealthKit)
        // Read the segment bounds on the current actor before hopping
        // into the async Task — avoids capturing mutable engine state
        // across a suspension point.
        guard engine.splits.indices.contains(index) else { return }
        let split = engine.splits[index]
        let segmentStart = split.startedAt
        let segmentEnd = split.endedAt

        // `@MainActor` on the Task pins the whole closure to MainActor
        // after the parallel HealthKit queries resume — safe to mutate
        // the engine directly without an extra MainActor.run hop.
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Run both HealthKit queries in parallel — HR stats and
            // calories sum are independent, so awaiting them
            // sequentially would just double the wall-clock latency.
            async let heartRate = HealthKitService.shared.heartRateStats(
                from: segmentStart,
                to: segmentEnd
            )
            async let calories = HealthKitService.shared.activeCalories(
                from: segmentStart,
                to: segmentEnd
            )
            let hr = await heartRate
            let kcal = await calories

            // Skip the persist round-trip if HealthKit had nothing
            // for this segment — common for indoor sessions without
            // a Watch streaming any of these metrics.
            guard hr.avg != nil || hr.max != nil || kcal != nil else {
                return
            }

            self.engine.setSegmentStats(
                heartRateAvg: hr.avg,
                heartRateMax: hr.max,
                activeCalories: kcal,
                atSplitIndex: index
            )
            self.persistActiveRace()
        }
        #endif
    }

    // Called from the Done button on the finished-summary screen. Keeps the
    // race row (it's complete — belongs in History), clears VM state, ready
    // for the next race.
    func finishSession() {
        engine.reset()
        activeRace = nil
        stopHeartRatePolling()
    }

    // Abandon an in-progress race, removing its persisted row. Not wired into
    // v0.1 UI yet but available for a future "cancel race" affordance.
    func abandon() {
        if let race = activeRace, !race.isFinished {
            modelContext?.delete(race)
            saveContextSilently()
        }
        engine.reset()
        activeRace = nil
        stopHeartRatePolling()
    }

    // MARK: - Persistence

    // Mirror the engine's current state onto `activeRace` and save. Called
    // after every state-changing event so the persisted row is always a
    // faithful snapshot of the live engine.
    private func persistActiveRace() {
        guard let race = activeRace else { return }

        switch engine.state {
        case .notStarted:
            break
        case .inProgress(let startedAt, let segStart, let splits):
            race.startedAt = startedAt
            race.endedAt = nil
            race.splits = splits
            race.currentSegmentStartedAt = segStart
        case .finished(let startedAt, let endedAt, let splits):
            race.startedAt = startedAt
            race.endedAt = endedAt
            race.splits = splits
            race.currentSegmentStartedAt = nil
        }

        saveContextSilently()
    }

    // The default ModelContainer autosaves periodically, but we force-save
    // after every race event so a mid-segment app-kill loses at most a few
    // hundred ms rather than whatever was buffered. `try?` is acceptable
    // because an in-memory engine still holds the true state — the next save
    // will catch up.
    private func saveContextSilently() {
        try? modelContext?.save()
    }

    // MARK: - Live HR polling

    // Start a background loop that asks HealthKit for the latest HR
    // sample every `heartRatePollInterval` seconds, publishing each
    // reading to `currentHeartRateBPM` on MainActor. Idempotent — if
    // a loop is already running (e.g. resume called after startRace),
    // the old one is cancelled first.
    //
    // Guarded by `canImport(HealthKit)` so macOS builds compile
    // without the polling path at all.
    private func startHeartRatePolling() {
        #if canImport(HealthKit)
        stopHeartRatePolling()

        heartRatePollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Loop until cancelled. Task.isCancelled trips on
            // stopHeartRatePolling() or when the task is GC'd.
            while !Task.isCancelled {
                if let bpm = await HealthKitService.shared.currentHeartRate() {
                    self.currentHeartRateBPM = bpm
                }
                // `try? await Task.sleep` — on cancellation, sleep
                // throws CancellationError which we swallow and the
                // outer while loop exits cleanly on the next check.
                try? await Task.sleep(for: .seconds(Self.heartRatePollInterval))
            }
        }
        #endif
    }

    // Stop the polling loop and clear any stale HR readout. Called on
    // race finish, abandon, and view-disappear so the task doesn't
    // outlive the race it was tracking.
    private func stopHeartRatePolling() {
        heartRatePollTask?.cancel()
        heartRatePollTask = nil
        currentHeartRateBPM = nil
    }

    // MARK: - HealthKit

    // Fire-and-forget push of the just-finished race to Apple Health. The
    // first call per install triggers the iOS authorization sheet; later
    // calls are silent. Failures (permission denied, HealthKit unavailable
    // on this device, etc.) are swallowed — the race is already saved
    // locally and shown in History, so HealthKit is additive not essential.
    //
    // Prerequisites (all in place as of the entitlements + Info.plist
    // wiring commit):
    //   - HealthKit capability on the main app target
    //     (Hyroxapp/Hyroxapp.entitlements)
    //   - NSHealthShareUsageDescription + NSHealthUpdateUsageDescription
    //     strings declared as INFOPLIST_KEY_* build settings
    // Without these, calling `requestAuthorization` crashes the app
    // unrecoverably — not an error we can catch. Keep them in sync if you
    // ever revisit the signing / Info.plist setup.
    private func saveFinishedRaceToHealthKit() {
        #if canImport(HealthKit)
        guard let race = activeRace else { return }
        Task {
            try? await HealthKitService.shared.saveRace(race)
        }
        #endif
    }
}

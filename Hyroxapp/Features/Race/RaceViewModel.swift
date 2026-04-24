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
    }

    // User tapped Discard on the launch prompt.
    func discardPending() {
        guard let race = pendingResume else { return }
        modelContext?.delete(race)
        pendingResume = nil
        saveContextSilently()
    }

    // MARK: - Actions

    func startRace() {
        let now = Date()
        engine = RaceEngine()
        engine.start(at: now)

        let race = Race(
            startedAt: now,
            currentSegmentStartedAt: now,
            sequence: engine.sequence
        )
        modelContext?.insert(race)
        activeRace = race
        saveContextSilently()
    }

    func advance() {
        // Detect the transition to `.finished` so we can mirror the race out
        // to HealthKit exactly once (not on every advance).
        let wasFinished = engine.isFinished
        engine.advance(at: Date())
        persistActiveRace()

        if !wasFinished, engine.isFinished {
            saveFinishedRaceToHealthKit()
        }
    }

    // Called from the Done button on the finished-summary screen. Keeps the
    // race row (it's complete — belongs in History), clears VM state, ready
    // for the next race.
    func finishSession() {
        engine.reset()
        activeRace = nil
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

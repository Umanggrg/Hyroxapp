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
        }
        // Fires when the user starts a new race, taps Done after finish,
        // or abandons mid-race — any transition in/out of an active-or-
        // finished race. Covers the "race began" and "race reset" cases.
        .onChange(of: viewModel.hasStarted) { _, _ in
            publishWatchState()
        }
        // Fires on every station advance (0 → 1 → ... → 16). When the
        // final advance transitions the engine to `.finished`, this still
        // fires because the count increments as part of the advance.
        .onChange(of: viewModel.completedSegmentsCount) { _, _ in
            publishWatchState()
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
        VStack(spacing: 6) {
            Text(RaceStats.format(viewModel.elapsed(at: now)))
                .font(.raceTimer)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("segment \(RaceStats.format(viewModel.currentSegmentElapsed(at: now)))")
                .font(.metadata)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
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

    // MARK: - Watch sync

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

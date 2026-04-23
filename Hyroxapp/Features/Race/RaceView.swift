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

    // Drives the "cancel race" confirmation alert. Kept in the view because
    // it's pure UI state (modal presentation) with no persistence meaning.
    @State private var showingCancelConfirm = false

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
                HStack {
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
    }

    private var stationHeadline: some View {
        VStack(spacing: 6) {
            if let station = viewModel.currentStation {
                Text(station.displayName)
                    .font(.stationTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text(station.target)
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

    private var advanceButton: some View {
        Button {
            // Fire the haptic before advancing so the buzz confirms the tap
            // was received even if the next state transition happens to lag
            // one frame. Final segment gets a distinct success pattern.
            let isFinalAdvance = viewModel.upcomingStation == nil
            if isFinalAdvance {
                Haptics.success()
            } else {
                Haptics.impact(.medium)
            }
            viewModel.advance()
        } label: {
            Text(viewModel.upcomingStation == nil ? "Finish Race" : "Next Station")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: Layout.raceButtonHeight)
                .background(Color.accent)
                .foregroundStyle(Color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        }
    }
}

#Preview("Pre-race") {
    RaceView()
        .preferredColorScheme(.dark)
}

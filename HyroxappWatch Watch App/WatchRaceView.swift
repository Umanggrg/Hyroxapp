import SwiftUI

// Static placeholder Race screen for the watchOS companion app.
//
// Today renders hardcoded values — 00:00 timer, "1km Run" station, etc.
// No state, no phone connectivity. The point of this step is to verify:
//   - the Watch target compiles cleanly against Theme.swift
//   - the watchOS simulator renders the dark Strava-style theme correctly
//   - the layout fits the tiny watch canvas without clipping
//
// Next session this becomes driven by a `WatchRaceClient` that receives
// race state from the phone via WCSession. When that lands, the View's
// shape doesn't change — it just reads its values from a `@State` or
// `@Observable` instead of hardcoded literals.
//
// Design notes for the watch canvas (much smaller than iOS):
//   - Apple Watch screens are 176×216pt (38mm) up to 224×272pt (Ultra).
//   - Horizontal padding is tight — use `.padding(.horizontal, 6)` at most.
//   - The Digital Crown can scroll, but taps land on whatever's visible.
//   - Keep type sizes smaller than iOS (36pt timer vs iOS's 72pt).
struct WatchRaceView: View {
    var body: some View {
        ZStack {
            // Full-bleed background to match the phone app's aesthetic.
            // watchOS doesn't have the same `.ignoresSafeArea` patterns
            // as iOS but `Color.background` fills the scene root anyway.
            Color.background.ignoresSafeArea()

            VStack(spacing: 8) {
                stationHeader

                Spacer(minLength: 4)

                timerDisplay

                Spacer(minLength: 4)

                advanceButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    // Small Strava-style caps label telling you which segment you're on.
    // On the phone this lives in the top header with a splits-peek chip;
    // on the watch we keep just the counter for screen real estate.
    private var stationHeader: some View {
        VStack(spacing: 2) {
            Text("STATION 1 OF 16")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.textSecondary)

            Text("1km Run")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text("1000 m")
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // The hero timer. Smaller than phone's 72pt — watchOS face is ~5x
    // narrower than an iPhone, so 36pt is the sweet spot where the digits
    // still read at arm's length without wrapping.
    private var timerDisplay: some View {
        VStack(spacing: 2) {
            Text("00:00")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("segment 00:00")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        }
    }

    // Giant primary action button — same ergonomic goal as the phone's
    // 80pt in-race button. On watchOS we use the full width and ~44pt
    // height; any less and sweaty fingers miss it. No hold-to-finish on
    // the watch today (we'll add that when we wire up the state machine
    // next session).
    private var advanceButton: some View {
        Button {
            // No-op placeholder. Will route to `WatchCompanionService.advance()`
            // in the next session's work.
        } label: {
            Text("Next Station")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WatchRaceView()
}

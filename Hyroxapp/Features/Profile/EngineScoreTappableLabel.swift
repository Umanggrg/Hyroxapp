import SwiftUI

// §36 Whoop pattern 7 — reusable wrapper that renders the
// "Engine 72 · Steady" hero-line label (the post-race + race-
// detail Engine Score readout) and makes it tap-to-explain.
// Tap presents `EngineScoreExplainSheet` with the sub-score
// breakdown + math + suggested focus.
//
// Centralizes the sheet binding so RaceSummaryView and
// RaceDetailView don't each need their own @State + .sheet
// modifier. Same visual contract as the bare `Text(...)`
// label these call sites had previously — same font, same
// tint, same monospacedDigit. Just adds the affordance.
//
// `isAthleteRollup` defaults false because the common call
// site is a per-race score; the Profile EngineScoreView has
// its own sheet wiring for the athlete rollup variant.
struct EngineScoreTappableLabel: View {

    let score: RaceStats.EngineScore
    var isAthleteRollup: Bool = false

    @State private var isSheetPresented = false

    var body: some View {
        Button {
            isSheetPresented = true
        } label: {
            HStack(spacing: 4) {
                Text("Engine \(Int(score.overall.rounded())) · \(score.tier.displayName)")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: score.tier))
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(tint(for: score.tier).opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isSheetPresented) {
            EngineScoreExplainSheet(score: score, isAthleteRollup: isAthleteRollup)
        }
    }

    private func tint(for tier: RaceStats.EngineScore.Tier) -> Color {
        switch tier {
        case .building: return Color.warning
        case .steady:   return Color.accent
        case .elite:    return Color.success
        }
    }
}

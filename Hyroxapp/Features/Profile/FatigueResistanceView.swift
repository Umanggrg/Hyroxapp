import SwiftUI

// Per-station Fatigue Resistance Score card — §17.5 "your
// engine's compromised-running fingerprint at the station level."
//
// Different from EngineImpactView which shows the same data as
// raw average slowdown %. This view scores it 0-100 and tiers it
// (Resilient / Moderate / Vulnerable) so the athlete tracks a
// number that climbs with training. The score motivates progress
// in a way "18% slowdown" doesn't — athletes have years of
// experience caring about scores climbing.
//
// Layout: one row per workout station the athlete has done. Each
// row shows:
//   • Station name (left, fixed-width column)
//   • Horizontal bar tinted by tier (vulnerable coral, moderate
//     primary, resilient success green) — bar length is the
//     score's % of 100
//   • Numeric score + tier label on the right
//
// Sorted ascending by score — lowest (most vulnerable) at the
// top so the athlete's eye lands on what they should train.
//
// Hidden when no station has compromised-running data (athlete
// has only done custom workouts without runs, or first race
// only).
struct FatigueResistanceView: View {

    let races: [Race]

    private var scores: [RaceStats.FatigueResistanceScore] {
        RaceStats.fatigueResistanceScores(across: races)
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        !RaceStats.fatigueResistanceScores(across: races).isEmpty
    }

    var body: some View {
        if !scores.isEmpty {
            card
        } else {
            EmptyView()
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(scores) { score in
                row(for: score)
                if score.id != scores.last?.id {
                    Divider()
                        .background(Color.divider)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func row(for score: RaceStats.FatigueResistanceScore) -> some View {
        HStack(spacing: 10) {
            Text(score.station.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Horizontal bar — fills proportional to score/100.
            // Tinted by tier for a glance read.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.divider.opacity(0.4))
                    let fraction = Double(score.score) / 100.0
                    Capsule()
                        .fill(tint(for: score.tier))
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 8)

            // Numeric score — primary readout. Tier label
            // beneath it as a small caption so the number
            // dominates and the tier reads as context.
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(score.score)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: score.tier))
                Text(score.tier.displayName)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 10)
    }

    private func tint(for tier: RaceStats.FatigueResistanceScore.Tier) -> Color {
        switch tier {
        case .resilient:   return .success
        case .moderate:    return .textPrimary
        case .vulnerable:  return .accent
        }
    }
}

import SwiftUI

// HYROX Score (0-1000) — the headline composite Profile metric per
// CLAUDE.md §17.3. The "credit score for HYROX fitness" — single
// number that defines the athlete's state-of-the-game.
//
// Different from the Engine Quality card (#15):
//   • Engine Quality (0-100) is a HR-derived rollup of the last
//     5 races — recent conditioning state.
//   • HYROX Score (0-1000) is an all-time composite combining
//     peak performance + engine + pillar balance + consistency.
//
// Both belong on Profile but answer different questions:
// "where is my engine right now?" vs "where am I as a HYROX
// athlete overall?"
//
// Card layout:
//   1. Hero: huge 0-1000 score + tier label (Bronze/Silver/
//      Gold/Elite) + tier coaching cue
//   2. Sub-score breakdown bars: 4 horizontal bars showing
//      Performance / Engine / Balance / Consistency
//      contributions
//   3. Provenance: "across N races" footnote so the metric's
//      basis is transparent
//
// Hidden when the athlete has zero finished races.
struct HyroxScoreView: View {

    let races: [Race]
    let division: Division
    let maxHR: Int

    var body: some View {
        if let score = RaceStats.hyroxScore(across: races, division: division, maxHR: maxHR) {
            card(score: score)
        } else {
            EmptyView()
        }
    }

    static func hasEnoughData(in races: [Race], division: Division, maxHR: Int) -> Bool {
        RaceStats.hyroxScore(across: races, division: division, maxHR: maxHR) != nil
    }

    // MARK: - Card

    private func card(score: RaceStats.HyroxScore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hero — huge 0-1000 score with tier callout. Tier
            // color drives the score tint so the eye lands on
            // both the number and its meaning at once.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(score.overall)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tierColor(for: score.tier))

                VStack(alignment: .leading, spacing: 2) {
                    Text(score.tier.displayName.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(tierColor(for: score.tier))
                    Text("/1000")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.bottom, 8)

                Spacer()
            }

            // Tier coaching cue — one line under the hero
            // framing the score as a journey, not a verdict.
            Text(score.tier.coachingCue)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.divider)
                .frame(height: 1)

            // Sub-score breakdown — four horizontal bars. Each
            // shows the component's contribution as a fill
            // proportional to its max. Lets the athlete see at
            // a glance which dimensions are pulling weight.
            VStack(alignment: .leading, spacing: 10) {
                breakdownRow(
                    label: "Performance",
                    value: score.performanceScore,
                    max: 500,
                    tint: .accent
                )
                breakdownRow(
                    label: "Engine",
                    value: score.engineScore,
                    max: 200,
                    tint: .success
                )
                breakdownRow(
                    label: "Balance",
                    value: score.balanceScore,
                    max: 150,
                    tint: Color(hex: 0x5B9BD5) // calm blue
                )
                breakdownRow(
                    label: "Consistency",
                    value: score.consistencyScore,
                    max: 150,
                    tint: .warning
                )
            }

            Text("across \(score.racesCounted) finished race\(score.racesCounted == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func breakdownRow(
        label: String,
        value: Int,
        max: Int,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.divider.opacity(0.4))
                    if max > 0 {
                        let fraction = Double(value) / Double(max)
                        let clamped = Swift.max(0, Swift.min(1, fraction))
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * clamped)
                    }
                }
            }
            .frame(height: 6)

            Text("\(value)/\(max)")
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(width: 56, alignment: .trailing)
        }
    }

    // Tier tint contract — bronze warm, silver neutral, gold
    // success green, elite accent coral. Reads as a
    // progression up the spectrum.
    private func tierColor(for tier: RaceStats.HyroxScore.Tier) -> Color {
        switch tier {
        case .bronze: return Color(hex: 0xCD7F32) // bronze
        case .silver: return Color.textPrimary
        case .gold:   return Color(hex: 0xFFD60A) // gold
        case .elite:  return Color.accent
        }
    }
}

import SwiftUI

// Engine Quality composite score — single-number rollup (0-100) of
// the athlete's HR-derived engine quality across their last 5
// finished races. The Whoop strain / Apple Activity ring equivalent
// for HYROX. Frames every HR metric the app computes (drift,
// recovery, efficiency, decoupling) into one coaching readout.
//
// Layout — three-section card:
//   1. Hero: huge 0-100 score + tier label (Building / Steady /
//      Elite) + one-line coaching cue. Reads at a glance.
//   2. Sub-score bars: four horizontal progress bars (drift,
//      recovery, efficiency, decoupling) showing what's powering
//      the overall. Lets the athlete see where the engine is
//      strong vs where it has work to do.
//   3. Provenance: "based on N races" footnote, since the score
//      is an athlete-level rollup not a per-race number.
//
// Hidden when no sub-scores can be computed (no HR data across the
// recent race window). One sub-score is enough to render the card —
// matching the helper's nil-only-on-no-data behavior.
struct EngineScoreView: View {

    let races: [Race]
    let maxHR: Int

    // §36 Whoop pattern 7 — sheet state for the tap-to-explain
    // affordance. Tapping the card anywhere opens the bottom
    // sheet with the 4 sub-score breakdown, the math, and a
    // weakest-sub-score-driven suggested focus line. Sheet is
    // scoped to this view so the binding doesn't leak into
    // ProfileView's state.
    @State private var isExplainSheetPresented = false

    var body: some View {
        if let score = RaceStats.engineScore(across: races, maxHR: maxHR) {
            card(score: score)
                .contentShape(Rectangle())
                .onTapGesture {
                    isExplainSheetPresented = true
                }
                .sheet(isPresented: $isExplainSheetPresented) {
                    EngineScoreExplainSheet(score: score, isAthleteRollup: true)
                }
        } else {
            EmptyView()
        }
    }

    static func hasEnoughData(in races: [Race], maxHR: Int) -> Bool {
        RaceStats.engineScore(across: races, maxHR: maxHR) != nil
    }

    // MARK: - Card

    private func card(score: RaceStats.EngineScore) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hero: score + tier + coaching cue. Score is the
            // visual anchor — the rest is supporting context.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Big monospaced score. Rounded design for the
                // numeric feel — matches the timer hero and
                // other large numeric displays elsewhere.
                Text("\(Int(score.overall.rounded()))")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tierColor(for: score.tier))

                VStack(alignment: .leading, spacing: 2) {
                    Text(score.tier.displayName.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(tierColor(for: score.tier))
                    Text("/100")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.bottom, 8)

                Spacer()
            }

            // Coaching-cue sentence. One line; gives the score
            // meaning without crowding the card.
            Text(score.tier.coachingCue)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Hairline divider between the hero and the sub-score
            // bars, signaling "this is what's behind the number"
            // without the visual weight of a section header.
            Rectangle()
                .fill(Color.divider)
                .frame(height: 1)

            // Sub-score breakdown. Each row is a small horizontal
            // bar with the metric label on the left and the
            // sub-score number on the right. Missing sub-scores
            // (insufficient data) render as a neutral "—" so the
            // athlete knows the metric exists but isn't
            // contributing yet.
            VStack(alignment: .leading, spacing: 10) {
                subScoreRow(label: "Drift",      value: score.driftSubScore)
                subScoreRow(label: "Recovery",   value: score.recoverySubScore)
                subScoreRow(label: "Efficiency", value: score.efficiencySubScore)
                subScoreRow(label: "Decoupling", value: score.decouplingSubScore)
            }

            // Provenance: this is an athlete-level rollup over
            // recent races, not the most-recent-race number.
            // Reading "based on 5 races" makes that explicit.
            Text("based on \(score.racesCounted) recent race\(score.racesCounted == 1 ? "" : "s")")
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

    // Single sub-score row — label, bar, number. The bar's fill
    // length reflects the sub-score's 0-100 value; missing sub-
    // scores show an empty bar with a dash on the right so the
    // metric stays visible rather than disappearing entirely.
    private func subScoreRow(label: String, value: Double?) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 78, alignment: .leading)

            // The bar — full-width, height 6pt. Background is the
            // empty track (divider color, low opacity); foreground
            // is the filled portion sized proportionally to the
            // sub-score value.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.divider.opacity(0.4))
                    if let value {
                        let fraction = max(0, min(1, value / 100))
                        Capsule()
                            .fill(barColor(for: value))
                            .frame(width: geo.size.width * fraction)
                    }
                }
            }
            .frame(height: 6)

            // Numeric readout — same color cue as the bar so the
            // number reinforces the bar's color signal.
            Group {
                if let value {
                    Text("\(Int(value.rounded()))")
                        .foregroundStyle(barColor(for: value))
                } else {
                    Text("—")
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .font(.caption.weight(.heavy))
            .monospacedDigit()
            .frame(width: 28, alignment: .trailing)
        }
    }

    // Tint contract for the hero score and the matching tier
    // label — green for elite, neutral primary for steady, amber
    // for building. Matches the trend chart family's color
    // language so the engine-score card reads coherently with the
    // recovery/drift trend dots elsewhere on Profile.
    private func tierColor(for tier: RaceStats.EngineScore.Tier) -> Color {
        switch tier {
        case .elite:    return .success
        case .steady:   return .textPrimary
        case .building: return .warning
        }
    }

    // Per-bar color reflecting the sub-score's 0-100 value with
    // the same tier thresholds the overall uses. Lets the user
    // see at a glance which sub-metric is dragging the score down
    // (amber bars are the work).
    private func barColor(for value: Double) -> Color {
        switch value {
        case ..<40:  return .warning
        case 40..<70: return .textPrimary
        default:      return .success
        }
    }
}

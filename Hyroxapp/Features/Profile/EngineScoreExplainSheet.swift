import SwiftUI

// §36 Whoop pattern 7 — "explain this score" bottom sheet.
//
// Engine Score has always been a composite of 4 sub-scores (drift,
// recovery, efficiency, decoupling), but the only place those
// sub-scores were visible was the bar chart inside EngineScoreView
// on Profile. Tapping the score number anywhere else — on
// RaceSummary, RaceDetail, or any future surface — opened nothing.
//
// This sheet fixes that. Tap the Engine Score number, sheet slides
// up showing: the number again with tier badge, the four sub-score
// bars with values, a plain-English math explanation, and a
// "suggested focus" line that names the weakest sub-score and
// proposes a training response.
//
// Whoop's "explain this" affordance is one of the most-tapped
// surfaces in their app per their public design talks — it turns
// confused users into engaged ones and builds trust by showing the
// math instead of hiding it.
//
// Two render modes:
//   • Athlete rollup (5-race window) — passes a `RaceStats.EngineScore`
//   • Per-race score — passes the same struct but representing a
//     single race; the only difference is the framing copy
//
// Suggestion logic: identifies the lowest-scored sub-metric (with
// at least one valid sub-score) and maps it to a training response
// — Z2 base work for decoupling weakness, threshold intervals for
// drift, etc. Same heuristic the Weakness-to-Workout Engine uses
// (§13.4) at a coarser per-metric level.
struct EngineScoreExplainSheet: View {

    let score: RaceStats.EngineScore
    /// True for the athlete-level Profile rollup (5-race window),
    /// false for a single-race score on RaceSummary / RaceDetail.
    /// Drives the "based on N races" provenance line at the bottom.
    var isAthleteRollup: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                subScoreSection
                howItsCalculatedSection
                if let suggestion = suggestedFocus {
                    suggestedFocusSection(text: suggestion)
                }
                provenanceFootnote
            }
            .padding(20)
        }
        .background(Color.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Text("ENGINE SCORE")
                .font(.caption2.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(Color.textSecondary)

            Text("\(Int(score.overall.rounded()))")
                .font(.system(size: 80, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tierColor(for: score.tier))
                .padding(.top, 4)

            Text(score.tier.displayName.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(tierColor(for: score.tier))
                )
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Sub-score bars

    private var subScoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BUILT FROM 4 SUB-SCORES")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.textTertiary)

            VStack(alignment: .leading, spacing: 10) {
                subScoreBar(
                    label: "Cardiac drift",
                    value: score.driftSubScore,
                    description: "HR climb across run halves"
                )
                subScoreBar(
                    label: "Recovery between stations",
                    value: score.recoverySubScore,
                    description: "HR drop in the 30s after each station"
                )
                subScoreBar(
                    label: "Efficiency",
                    value: score.efficiencySubScore,
                    description: "output relative to HR cost"
                )
                subScoreBar(
                    label: "Aerobic decoupling",
                    value: score.decouplingSubScore,
                    description: "pace-per-HR drift across the race"
                )
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func subScoreBar(label: String, value: Double?, description: String) -> some View {
        let displayed = value.map { Int($0.rounded()) }
        let tint = Self.tintForSubScore(value)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let displayed {
                    Text("\(displayed)")
                        .font(.subheadline.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Bar — width proportional to value (0-100). Nil-value
            // rows render the empty rail only so the row still
            // visually represents the dimension.
            GeometryReader { geo in
                let pct = (value ?? 0) / 100
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.surfaceElevated)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: geo.size.width * max(0, min(1, pct)), height: 4)
                }
            }
            .frame(height: 4)

            Text(description)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - How it's calculated

    private var howItsCalculatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW IT'S CALCULATED")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.textTertiary)

            Text(calculationExplanation)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private var calculationExplanation: String {
        let lowestLabel = weakestSubScoreLabel ?? "drift"
        return """
        Each sub-score normalized 0—100 against research thresholds, then averaged. Sub-scores missing HR data are dropped from the average rather than treated as zero. Tier mapping: <40 Building, 40—70 Steady, >70 Elite. Your weakest input right now: \(lowestLabel).
        """
    }

    // MARK: - Suggested focus

    private func suggestedFocusSection(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max.fill")
                .font(.title3)
                .foregroundStyle(Color.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("SUGGESTED FOCUS")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Footnote

    private var provenanceFootnote: some View {
        Text(
            isAthleteRollup
                ? "Based on your last \(score.racesCounted) finished race\(score.racesCounted == 1 ? "" : "s")."
                : "This race only."
        )
        .font(.caption)
        .foregroundStyle(Color.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func tierColor(for tier: RaceStats.EngineScore.Tier) -> Color {
        switch tier {
        case .building: return Color.warning
        case .steady:   return Color.accent
        case .elite:    return Color.success
        }
    }

    private static func tintForSubScore(_ value: Double?) -> Color {
        guard let value else { return Color.textTertiary }
        switch value {
        case ..<40:   return Color.warning
        case 40..<70: return Color.accent
        default:      return Color.success
        }
    }

    // Identify the lowest non-nil sub-score and return its display
    // label. Drives both the calculation explanation footnote AND
    // the suggested focus card's training response.
    private var weakestSubScoreLabel: String? {
        weakestSubScore?.label
    }

    private var weakestSubScore: (label: String, value: Double)? {
        let candidates: [(String, Double?)] = [
            ("drift", score.driftSubScore),
            ("recovery", score.recoverySubScore),
            ("efficiency", score.efficiencySubScore),
            ("decoupling", score.decouplingSubScore),
        ]
        let valid = candidates.compactMap { pair -> (String, Double)? in
            guard let v = pair.1 else { return nil }
            return (pair.0, v)
        }
        return valid.min { $0.1 < $1.1 }
    }

    private var suggestedFocus: String? {
        guard let weakest = weakestSubScore else { return nil }
        // Per-sub-score coaching response. Calibrated to the actual
        // physiology each metric measures:
        switch weakest.label {
        case "drift":
            return "Long Z2 base runs (45-75 min) train your aerobic ceiling. Holds HR steady across longer efforts."
        case "recovery":
            return "Interval work with active rest (e.g. 4×400m at 5K pace, jog recovery). Trains HR-drop speed."
        case "efficiency":
            return "Tempo work at threshold. Output per heartbeat improves when you race closer to your aerobic ceiling regularly."
        case "decoupling":
            return "Long Z2 base runs above 60 minutes. Same lever as drift — your engine fatigues structurally, not just metabolically."
        default:
            return nil
        }
    }
}

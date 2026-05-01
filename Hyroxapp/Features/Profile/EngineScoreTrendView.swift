import SwiftUI
import Charts

// "Where is my engine going?" — the cross-race progression of the
// per-race Engine Quality score. Closes the loop on the engine-score
// system: #15 gave the athlete-level rollup ("you're at 64 right
// now"), #16 gave the per-race readout ("today was 71"), and this
// chart connects every race's dot into a curve so the athlete can
// see whether the engine is climbing, holding, or fading.
//
// Coaching premise: this is the headline progression metric for
// HYROX athletes — every other trend chart on Profile (drift,
// recovery, time, effort) is a sub-metric. The engine-score curve
// is the rollup. A training block working as planned looks like a
// gentle climb; a peak looks like a plateau in the elite band; an
// overreaching block looks like a dip from steady back into
// building.
//
// Y-axis is per-race engine score (0-100). X-axis is race date. A
// horizontal reference rule at 70 marks the Elite threshold — the
// same boundary `EngineScore.tier(forScore:)` uses. Dots are
// colored by tier (green elite / white steady / amber building).
//
// Gated on 3+ races with any HR sub-metric data. Built on
// SwiftCharts so the chart family on Profile (drift, recovery,
// effort, time, engine score) reads as one design system.
struct EngineScoreTrendView: View {

    let races: [Race]
    let maxHR: Int

    @State private var animationsRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumRacesForTrend = 3

    private var points: [(date: Date, score: Double, tier: RaceStats.EngineScore.Tier)] {
        races
            .filter { $0.isFinished }
            .compactMap { race -> (Date, Double, RaceStats.EngineScore.Tier)? in
                guard let engine = RaceStats.engineScore(
                    forRace: race,
                    history: races,
                    maxHR: maxHR
                ) else { return nil }
                return (race.createdAt, engine.overall, engine.tier)
            }
            .sorted { $0.date < $1.date }
    }

    static func hasEnoughData(in races: [Race], maxHR: Int) -> Bool {
        races
            .filter { $0.isFinished }
            .compactMap {
                RaceStats.engineScore(forRace: $0, history: races, maxHR: maxHR)
            }
            .count >= minimumRacesForTrend
    }

    var body: some View {
        if points.count >= Self.minimumRacesForTrend {
            chart
        } else {
            EmptyView()
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // Reference rule at 70 — the Elite tier threshold from
            // RaceStats.EngineScore.tier(forScore:). Drawn first so
            // it sits behind the data line. Reading the chart at a
            // glance: dots above the line = elite-conditioned races,
            // dots below = building/steady. A training block is
            // working when the curve climbs across the rule.
            RuleMark(y: .value("Elite", 70))
                .foregroundStyle(Color.success.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("≥70 elite")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.success.opacity(0.7))
                }

            // Connecting line — coral-dim, same as the other trend
            // charts. Monotone interpolation softens the line on
            // small samples without overstating between-point
            // movement.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .opacity(animationsRevealed ? 1.0 : 0)
            }

            // Dots tinted by tier — same vocabulary the EngineScore
            // hero card uses. Color rhythm of the chart shows the
            // training-block story without needing to read numbers:
            // a healthy block reads as a band of green dots
            // climbing the right side; an overreach reads as amber
            // dots dipping back down.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(tint(for: point.tier))
                .symbolSize(animationsRevealed ? 60 : 0)
            }
        }
        .animation(
            reduceMotion ? .none : .smooth(duration: 0.8),
            value: animationsRevealed
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animationsRevealed = true
            }
        }
        // Y-axis is bounded 0-100 — the engine score's natural
        // range. Without this, SwiftCharts auto-fits to the data
        // and an athlete with all-elite races would see a chart
        // that looks like dots near a ceiling, hiding the
        // headroom. Forcing the full range makes the score's
        // position relative to the 0-100 scale legible.
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 40, 70, 100]) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text("\(Int(score.rounded()))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .frame(height: 200)
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Helpers

    // Tier tint contract — matches `EngineScoreView`'s hero score
    // tint and `RaceSummaryView`'s per-race engine line tint, so
    // every engine-score surface speaks the same color language.
    private func tint(for tier: RaceStats.EngineScore.Tier) -> Color {
        switch tier {
        case .elite:    return .success
        case .steady:   return .textPrimary
        case .building: return .warning
        }
    }
}

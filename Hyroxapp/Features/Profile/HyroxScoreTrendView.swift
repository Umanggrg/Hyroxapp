import SwiftUI
import Charts

// "Where is my HYROX Score going?" — the cross-race progression
// of the §17.3 / #52 composite headline metric.
//
// Each point is the HYROX Score computed AS OF that race —
// i.e. the score the athlete would have seen after finishing
// that race, with their then-current best time + then-current
// pillar bests + then-current race count + then-current engine
// rollup. This gives the historical climb up the
// Bronze → Silver → Gold → Elite ladder.
//
// What moves the curve:
//   • PB races → Performance component jumps (up to 500)
//   • Every finished race → Consistency +15 (capped at 150)
//   • Each race's engine state → Engine component jitter (0-200)
//   • Station PBs → Balance component shifts (0-150)
//
// So the curve typically looks like: consistent slow climb
// (Consistency stepping up), occasional jumps (PB races),
// and a steady-state plateau once Consistency caps at 150 and
// PBs become rare.
//
// Y-axis is per-race HYROX Score (0-1000). X-axis is race
// date. Three reference rules — Silver / Gold / Elite tier
// boundaries — let the athlete see at a glance which band each
// race landed in.
//
// Dots are colored by tier: bronze brown / silver primary /
// gold yellow / elite coral — same vocabulary the
// HyroxScoreView card uses.
//
// Gated on 3+ races so the chart has enough points to read as
// a trend. Lives in TrendsDetailView since it's a secondary
// trend (the Engine Score Trend on Profile is the headline
// inline curve).
struct HyroxScoreTrendView: View {

    let races: [Race]
    let division: Division
    let maxHR: Int

    @State private var animationsRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumRacesForTrend = 3

    // Per-race "score as of this race" computed by filtering
    // history to the race's date and earlier. Sorted ascending
    // by date so the chart renders left-to-right chronologically.
    private var points: [(date: Date, score: Int, tier: RaceStats.HyroxScore.Tier)] {
        let finished = races
            .filter { $0.isFinished }
            .sorted { $0.createdAt < $1.createdAt }

        return finished.compactMap { race -> (Date, Int, RaceStats.HyroxScore.Tier)? in
            // The "as-of" set: every finished race up through
            // this one. The HYROX Score helper consumes the
            // whole array, so this gives us the score the
            // athlete would have seen at the moment they
            // finished this race.
            let asOf = finished.filter { $0.createdAt <= race.createdAt }
            guard let score = RaceStats.hyroxScore(
                across: asOf,
                division: division,
                maxHR: maxHR
            ) else { return nil }
            return (race.createdAt, score.overall, score.tier)
        }
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        races.filter { $0.isFinished }.count >= minimumRacesForTrend
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
            // Three reference rules at tier boundaries — these
            // ARE the tier definitions visualized as horizontal
            // gridlines, which doubles as a reading aid: a dot
            // crossing into a higher band reads as a tier
            // promotion at a glance.
            RuleMark(y: .value("Silver", 400))
                .foregroundStyle(Color.textPrimary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Gold", 700))
                .foregroundStyle(Color(hex: 0xFFD60A).opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("≥700 gold")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xFFD60A).opacity(0.7))
                }
            RuleMark(y: .value("Elite", 900))
                .foregroundStyle(Color.accent.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("≥900 elite")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accent.opacity(0.7))
                }

            // Connecting line — same coral-dim as the rest of
            // the trend chart family. Monotone interpolation
            // softens the line on small samples without
            // overstating between-point movement.
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

            // Dots tinted by tier — bronze / silver / gold /
            // elite. Lets the athlete read the climb up the
            // tier ladder visually.
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
        // Y-axis bounded 0-1000 — the HYROX Score's natural
        // range. Forcing the full range means an athlete sitting
        // in the Silver band sees room above and below them on
        // the chart, not a chart auto-fit to their current
        // trajectory that hides the headroom.
        .chartYScale(domain: 0...1000)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 400, 700, 900, 1000]) { value in
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
        .frame(height: 220)
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Helpers

    // Tier tint contract — matches the HyroxScoreView card's
    // hero-score tint so the chart and the card speak the same
    // color language across Profile and TrendsDetailView.
    private func tint(for tier: RaceStats.HyroxScore.Tier) -> Color {
        switch tier {
        case .bronze: return Color(hex: 0xCD7F32)
        case .silver: return Color.textPrimary
        case .gold:   return Color(hex: 0xFFD60A)
        case .elite:  return Color.accent
        }
    }
}

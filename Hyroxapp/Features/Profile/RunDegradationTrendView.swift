import SwiftUI
import Charts

// "Is my run pacing fade improving?" — the cross-race progression
// of the per-race Run Degradation Score (§17.2 / #50).
//
// Coaching premise: run degradation is the §17.2 standalone metric
// that benchmarks against literature thresholds (Elite <8% / Good
// 8-15% / Needs Work >15%). A training block that's working makes
// this number drop — front-loaded pacing turns into evenly-paced
// runs as the athlete learns to control the early kilometers.
//
// Y-axis is per-race degradation %. X-axis is race date. A
// horizontal reference rule at 8% marks the Elite threshold —
// athletes who consistently sit below it have HR-driven pacing
// dialed; sitting above is the visible fade story.
//
// Dots are colored by tier: green for elite, primary white for
// good, amber for needs-work — same vocabulary the per-race
// "Run fade" line on RaceSummary uses.
//
// Gated on 3+ races with degradation data. Built on SwiftCharts
// so the chart family on Profile (engine score / time / effort /
// drift / recovery / run degradation) reads as one design
// system. iOS-only.
struct RunDegradationTrendView: View {

    let races: [Race]

    @State private var animationsRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumRacesForTrend = 3

    private var points: [(date: Date, percent: Double, tier: RaceStats.RunDegradation.Category)] {
        races
            .filter { $0.isFinished }
            .compactMap { race -> (Date, Double, RaceStats.RunDegradation.Category)? in
                guard let deg = RaceStats.runDegradation(for: race) else {
                    return nil
                }
                return (race.createdAt, deg.degradationPercent, deg.category)
            }
            .sorted { $0.date < $1.date }
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        races
            .filter { $0.isFinished }
            .compactMap { RaceStats.runDegradation(for: $0) }
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
            // Reference rule at 8% — the Elite threshold from
            // RaceStats.RunDegradation.category(forPercent:).
            // Drawn first so it sits behind the data line. Athletes
            // who consistently dot below the line have race-fit
            // pacing; sitting above it = work to do.
            RuleMark(y: .value("Elite", 8))
                .foregroundStyle(Color.success.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("≤8% elite")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.success.opacity(0.7))
                }

            // Connecting line — coral-dim, same as the rest of the
            // trend chart family. Monotone interpolation softens
            // the line on small samples without overstating
            // between-point movement.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Fade", point.percent)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .opacity(animationsRevealed ? 1.0 : 0)
            }

            // Dots tinted by tier — same vocabulary the per-race
            // "Run fade" line and the Engine Score Trend dots use.
            // Color rhythm of the chart shows the training-block
            // story: a healthy block reads as green dots dropping
            // toward the reference rule.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Fade", point.percent)
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
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel {
                    if let pct = value.as(Double.self) {
                        let signed = pct > 0
                            ? "+\(Int(pct.rounded()))%"
                            : "\(Int(pct.rounded()))%"
                        Text(signed)
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

    private func tint(for tier: RaceStats.RunDegradation.Category) -> Color {
        switch tier {
        case .elite:     return .success
        case .good:      return .textPrimary
        case .needsWork: return .accent
        }
    }
}

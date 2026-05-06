import SwiftUI
import Charts

// "Where do I characteristically fall apart?" — §18 Pillar 1.
// Different from the per-race fatigue inflection insight (which
// catches the single pivot in TODAY's race); this chart shows
// the athlete's longitudinal pattern across all races.
//
// X-axis: race date. Y-axis: fade cliff run (1-8), where the
// athlete first dropped 10%+ off Run 1 pace. Higher dot = better
// (cliff later in the race). A flat line at Run 4 across months
// = consistent mid-race fade. A rising line from Run 4 → Run 8
// over a training block = visible aerobic adaptation.
//
// Special case: races with no fade at all (rare, peak race
// state) plot at Run 9 — off the chart's natural 1-8 domain
// but visually communicates "no cliff." The Y-axis is bounded
// 1-9 so this works cleanly.
//
// Coaching read at a glance:
//   • Dots clustered at Run 1-3: vulnerable, training the
//     wrong systems
//   • Dots clustered at Run 4-6: typical amateur pattern
//   • Dots climbing toward Run 8: aerobic base is improving
//   • Dots at Run 9 (no cliff): elite-level conditioning
//
// Gated on 3+ races (same threshold as the rest of the trend
// chart family) to avoid drawing a "pattern" from 1-2 dots.
struct FatigueFingerprintView: View {

    let races: [Race]

    @State private var animationsRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumRacesForTrend = 3

    private var points: [(date: Date, cliffRun: Int, hadCliff: Bool)] {
        RaceStats.fatigueFingerprintTrend(across: races).map { p in
            // No-cliff races plot at Run 9 (off the natural 1-8
            // domain) so the chart visually rewards them.
            (p.date, p.cliffRun ?? 9, p.cliffRun != nil)
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
            // Reference rule at Run 8 — the "you finished without
            // a fade cliff" boundary. Dots at or above this line
            // = no fade detected (ideal race state).
            RuleMark(y: .value("No fade", 8.5))
                .foregroundStyle(Color.success.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Run 8 · no cliff")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.success.opacity(0.7))
                }

            // Connecting line in the trend-family coral-dim.
            // Monotone interpolation softens the line on small
            // samples without overstating between-point movement.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Cliff", point.cliffRun)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .opacity(animationsRevealed ? 1.0 : 0)
            }

            // Dots tinted by cliff position — coral for early
            // cliffs (vulnerable), warm primary for mid-race
            // cliffs (typical), success for late or no cliffs
            // (resilient).
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Cliff", point.cliffRun)
                )
                .foregroundStyle(tint(for: point.cliffRun, hadCliff: point.hadCliff))
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
        .chartYScale(domain: 1...9)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 4, 6, 8]) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel {
                    if let run = value.as(Int.self) {
                        Text("R\(run)")
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

    // Tint contract for fade cliff dots. Higher cliff = later
    // = better, so the color climbs from vulnerable coral
    // through neutral primary to resilient success green.
    private func tint(for cliffRun: Int, hadCliff: Bool) -> Color {
        guard hadCliff else { return .success }   // no cliff at all
        switch cliffRun {
        case 1...3: return .accent           // vulnerable
        case 4...6: return .textPrimary      // typical
        case 7...8: return .success          // resilient
        default:    return .success
        }
    }
}

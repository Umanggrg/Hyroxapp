import SwiftUI
import Charts

// "Am I recovering faster between stations?" — the cross-race
// conditioning story. Per-race recovery score (#5's RaceStats.recoveryScore)
// captures avg HR drop in the 30s after each station; this chart
// plots that number across the athlete's race history so the
// trajectory of between-station recovery is visible at a glance.
//
// Coaching premise: recovery between stations is the HYROX-specific
// conditioning signal. Tight transitions are about getting your HR
// back under control between efforts — and as the engine builds, the
// 30s drop should grow. Plotting it over weeks/months tells the
// athlete whether their conditioning work is paying off.
//
// Y-axis is per-race avg-30s-drop (bpm). X-axis is race date. A
// horizontal reference rule at 25 bpm marks the "excellent recovery"
// threshold — the same boundary the per-race RecoveryScore.Category
// uses. Sitting above it consistently = elite-level conditioning;
// climbing toward it across a block = engine adapting.
//
// Dots are colored by category: green for excellent (≥25 bpm),
// white for good (15-25), amber for average (10-15), coral for slow
// (<10). Same vocabulary the per-race recovery insight uses.
//
// Gated on 3+ races with recovery data. Built on SwiftCharts (used
// by the other trend charts so the whole Profile trend family reads
// as one design system). iOS-only.
struct RecoveryTrendView: View {

    let races: [Race]

    @State private var animationsRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumRacesForTrend = 3

    private var points: [(date: Date, drop: Double, category: RaceStats.RecoveryScore.Category)] {
        races
            .filter { $0.isFinished }
            .compactMap { race -> (Date, Double, RaceStats.RecoveryScore.Category)? in
                guard let recovery = RaceStats.recoveryScore(for: race) else {
                    return nil
                }
                return (race.createdAt, recovery.averageDrop30s, recovery.category)
            }
            .sorted { $0.date < $1.date }
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        races
            .filter { $0.isFinished }
            .compactMap { RaceStats.recoveryScore(for: $0) }
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
            // Reference rule at 25 bpm — the "excellent" threshold
            // straight from RaceStats.RecoveryScore.category. Drawn
            // first so it sits behind the data line. A dotted green
            // rule reads as "this is the band you're aiming for";
            // sitting above it consistently = elite-level
            // conditioning.
            RuleMark(y: .value("Target", 25))
                .foregroundStyle(Color.success.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("≥25 bpm excellent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.success.opacity(0.7))
                }

            // Connecting line — accent-dim coral, same as the
            // other trend charts. Monotone interpolation keeps
            // small-sample lines smooth without overstating
            // between-point movement.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Drop", point.drop)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .opacity(animationsRevealed ? 1.0 : 0)
            }

            // Dots colored by recovery category. Same vocabulary
            // (excellent = green, slow = coral) the per-race
            // RaceCardView and recovery insight use, so the
            // chart's color rhythm reads coherently with every
            // other recovery surface.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Drop", point.drop)
                )
                .foregroundStyle(tint(for: point.category))
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
                    if let bpm = value.as(Double.self) {
                        Text("\(Int(bpm.rounded()))")
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

    // Mirror of the recovery-category tint contract used elsewhere
    // (per-race "Recovery -N bpm" line on Summary/Detail, recovery
    // insight icon). Centralized per-view to keep each rendering
    // surface independently inspectable, matching the convention
    // EffortTrendView and HRDriftTrendView established.
    private func tint(for category: RaceStats.RecoveryScore.Category) -> Color {
        switch category {
        case .excellent: return .success
        case .good:      return .textPrimary
        case .average:   return .warning
        case .slow:      return .accent
        }
    }
}

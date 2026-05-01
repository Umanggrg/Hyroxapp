import SwiftUI
import Charts

// "Is my engine getting better?" — the cross-race cardiac-drift story.
// Per-race drift (RaceSummaryView's "HR drift +N bpm" line) tells the
// athlete what happened today; this chart tells them whether that
// number is trending the right direction over their whole training
// block.
//
// Coaching premise: cardiac drift = how much your average HR climbs
// across the run sequence at flat-or-similar pace. A well-conditioned
// HYROX athlete should see <5 bpm of drift across all 8 runs; the
// number should drop as easy-pace volume builds the aerobic base.
// So a downward-sloping drift line over weeks/months is the cleanest
// possible signal that the engine work is paying off — no other
// metric in the app shows aerobic adaptation this directly.
//
// Y-axis is per-race drift (bpm). X-axis is race date. A horizontal
// reference rule at 5 bpm marks the "minimal drift" target band so
// the athlete can see at a glance which side of the line they're on.
// Dots are colored by category: green for minimal (≤5 bpm), amber for
// moderate (5–10), coral for severe (>10) — same coral/amber/green
// language used by RaceCardView and the per-race HR drift line.
//
// Gated on 3+ races with drift data so the chart has enough points
// to read as a trend. Below that threshold the parent hides the
// section; one or two dots aren't a trend, just dots.
//
// Built on SwiftCharts (already used by EffortTrendView,
// PerformanceTrendsView, HRZonesView). iOS-only, sits alongside the
// other Profile-level analytics.
struct HRDriftTrendView: View {

    // Pre-filtered upstream to finished races. Order doesn't matter;
    // SwiftCharts orders by X-axis date.
    let races: [Race]

    // On-appear toggle that drives the chart's grow-in animation.
    // Same pattern as EffortTrendView — line fades in, dots scale
    // up from zero size after one runloop tick. Apple-grade
    // entrance, never lets the user catch a sudden state pop.
    @State private var animationsRevealed = false

    // Reduce-Motion bypass for the entrance animation. System
    // setting respected throughout the codebase.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Same minimum-points threshold as the other trend charts.
    // Two points is a line; three is the smallest set that reads
    // as a trend.
    static let minimumRacesForTrend = 3

    // Pre-built data points: (date, driftBPM, category). Computed
    // once per render. Filters to races where heartRateDrift returns
    // non-nil (need ≥6 runs with HR data) since otherwise there's
    // nothing to plot for that race.
    private var points: [(date: Date, drift: Double, category: RaceStats.HRDrift.Category)] {
        races
            .filter { $0.isFinished }
            .compactMap { race -> (Date, Double, RaceStats.HRDrift.Category)? in
                guard let drift = RaceStats.heartRateDrift(for: race) else {
                    return nil
                }
                return (race.createdAt, drift.driftBPM, drift.category)
            }
            .sorted { $0.date < $1.date }
    }

    // Whether the parent should render this section at all.
    // Centralized here so ProfileView can hide the section header +
    // chart together without leaking the data-availability logic.
    static func hasEnoughData(in races: [Race]) -> Bool {
        races
            .filter { $0.isFinished }
            .compactMap { RaceStats.heartRateDrift(for: $0) }
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
            // Reference rule at 5 bpm — the minimal-drift target.
            // Drawn first so it sits behind the data line. A dotted
            // green rule reads as "this is the band you're aiming
            // for"; falling under it on most points = engine
            // dialed, sitting above = work to do.
            RuleMark(y: .value("Target", 5))
                .foregroundStyle(Color.success.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("≤5 bpm target")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.success.opacity(0.7))
                }

            // Connecting line — same coral-dim used by EffortTrend
            // + PerformanceTrend so the three charts read as a
            // family. Monotone interpolation softens the line on
            // small samples without misrepresenting the data.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Drift", point.drift)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .opacity(animationsRevealed ? 1.0 : 0)
            }

            // Dots colored by category — separate ForEach so each
            // dot tints independently. Read the chart at a glance
            // and the rhythm of green/amber/coral shows whether
            // recent races are clustering at minimal drift or
            // tipping toward severe.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Drift", point.drift)
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
            // One runloop tick delay so SwiftCharts gets its
            // initial zero-state layout before the animation fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animationsRevealed = true
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel {
                    if let bpm = value.as(Double.self) {
                        // Show + sign for positive values (drift)
                        // since negative drift (cooling-off-with-pace)
                        // is rare but possible and reads weirdly
                        // without the sign convention. Matches the
                        // signed rendering on RaceSummaryView's
                        // drift line.
                        let signed = bpm > 0
                            ? "+\(Int(bpm.rounded()))"
                            : "\(Int(bpm.rounded()))"
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

    // Mirror of the per-race "HR drift +N bpm · Category" line's
    // tint contract used on RaceSummaryView + RaceDetailView.
    // Centralizing the mapping per-view feels redundant, but keeps
    // each surface independently inspectable — same trade-off the
    // EffortTrendView made.
    private func tint(for category: RaceStats.HRDrift.Category) -> Color {
        switch category {
        case .minimal:  return .success
        case .moderate: return .warning
        case .severe:   return .accent
        }
    }
}

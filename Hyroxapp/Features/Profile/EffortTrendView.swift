import SwiftUI
import Charts

// "Am I training harder?" — the cross-race intensity story. While
// `PerformanceTrendsView` answers "am I getting faster?", this one
// answers "is my training load building, holding, or backing off?"
// They're complementary — fast races at low effort are rare, fast
// races at high effort are the goal, and easy days at low effort
// are recovery. Plotting the rhythm tells the story.
//
// Y-axis is the per-race effort score (intensity-weighted minutes
// from `RaceStats.effortScore`). X-axis is race date. Each dot is
// colored by its `EffortCategory` — green for recovery races, white
// for moderate, amber for high, coral for very high — so a glance
// at the chart shows whether recent races have been clustering high
// or oscillating into recovery.
//
// Gated on 3+ races with HR data so the chart has enough points to
// read as a trend. Below that threshold the parent hides the section
// — one or two dots aren't a trend, just dots.
//
// Like every other effort surface in the app, hidden cleanly when
// no HR data exists across the history. Athletes who race without
// a watch still see all the time-based trends (PerformanceTrendsView,
// PerformanceOverloadView) but skip this one.
//
// Built on SwiftCharts (already used by HR + fatigue + performance
// trend charts elsewhere). iOS-only; sits alongside the other
// profile-level analytics in Features/Profile/.
struct EffortTrendView: View {

    // Pre-filtered upstream to finished races only. Order doesn't
    // matter — SwiftCharts orders by X-axis date.
    let races: [Race]

    // Athlete's max HR drives the per-race effort calculation. Pass
    // through from UserProfile; falls back to 190 if the caller
    // doesn't have a profile (matches the rest of the codebase).
    let maxHR: Int

    // On-appear toggle that drives the chart's grow-in animation.
    // Initially false so the line draws from zero on the right side
    // and points fade in. Flipped to true 0.05s after onAppear
    // (one runloop tick) so SwiftCharts has its initial layout
    // before the animation kicks. Apple-grade entrance — never
    // lets the user catch a sudden state pop.
    @State private var animationsRevealed = false

    // Reduce-Motion bypass — when the system setting is on, skip
    // the entrance animation entirely. Same pattern used by
    // HeroBackdrop and the post-finish summary.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Minimum races with HR data needed for a trendline. Same
    // threshold PerformanceTrendsView uses — two points is a line,
    // three is the smallest set that reads as a trend.
    static let minimumRacesForTrend = 3

    // Pre-built data points: (date, score, category). Computed once
    // per render. Filters to races that have any HR data (otherwise
    // the effort score is nil and there's nothing to plot).
    private var points: [(date: Date, score: Double, category: RaceStats.EffortCategory)] {
        races
            .filter { $0.isFinished }
            .compactMap { race -> (Date, Double, RaceStats.EffortCategory)? in
                guard let score = RaceStats.effortScore(for: race, maxHR: maxHR) else {
                    return nil
                }
                // Use the same average-HR-fraction-to-category mapping
                // as the per-station chip + RaceCardView badge, so the
                // colors are coherent across every effort surface in
                // the app. Compute it from the race's duration-weighted
                // average HR.
                let category = raceCategory(for: race) ?? .moderate
                return (race.createdAt, score, category)
            }
            .sorted { $0.date < $1.date }
    }

    // Whether the parent should render this section at all. Centralized
    // here so ProfileView can hide the section header + chart together
    // without leaking any of the data-availability logic.
    static func hasEnoughData(in races: [Race], maxHR: Int) -> Bool {
        races
            .filter { $0.isFinished }
            .compactMap { RaceStats.effortScore(for: $0, maxHR: maxHR) }
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
            // The connecting line — same coral-dim used by
            // PerformanceTrendsView so the two charts read as a
            // family. Monotone interpolation softens the line on
            // small samples without misrepresenting the data.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Effort", point.score)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                // Opacity-driven line draw — line fades in across
                // 0.7s as a subtle entrance. SwiftCharts handles
                // the geometric layout; the opacity reveal is what
                // makes the chart feel alive on first paint.
                .opacity(animationsRevealed ? 1.0 : 0)
            }

            // Dots colored by category — separate ForEach so each
            // dot's tint can vary. The unified tint contract from
            // EffortCategory means recovery dots are green, very-
            // high are coral, etc. Read the chart at a glance and
            // the rhythm of intensity tells itself.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Effort", point.score)
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
            // One runloop tick delay so SwiftCharts gets its initial
            // zero-state layout before the animation fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animationsRevealed = true
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
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

    // Mirror of the EffortCategory tint contract used elsewhere
    // (StationDetailView chip, RaceCardView badge, split-row dot).
    // Centralizing the mapping per-view feels redundant but keeps
    // each effort-rendering surface independently inspectable.
    private func tint(for category: RaceStats.EffortCategory) -> Color {
        switch category {
        case .recovery: return .success
        case .moderate: return .textPrimary
        case .high:     return .warning
        case .veryHigh: return .accent
        }
    }

    // Race-level category: duration-weighted average HR fraction
    // bucketed into the same boundaries the per-split helper uses.
    // Same shape as RaceCardView's effortCategory computed property
    // — duplicated rather than extracted because RaceCardView lives
    // in Shared/Components/ (used by share-card render) while this
    // file is iOS-only Profile UI; an extraction would force a
    // cross-folder dependency for a 12-line helper.
    private func raceCategory(for race: Race) -> RaceStats.EffortCategory? {
        let hrSplits = race.splits.compactMap { split -> (avg: Double, duration: TimeInterval)? in
            guard let avg = split.heartRateAvgBPM, avg > 0, split.duration > 0 else {
                return nil
            }
            return (avg, split.duration)
        }
        guard !hrSplits.isEmpty else { return nil }

        let totalDuration = hrSplits.reduce(0) { $0 + $1.duration }
        guard totalDuration > 0 else { return nil }
        let weightedAvg = hrSplits.reduce(0) { $0 + ($1.avg * $1.duration) } / totalDuration
        let fraction = weightedAvg / Double(maxHR)

        switch fraction {
        case ..<0.65:
            return .recovery
        case ..<0.75:
            return .moderate
        case ..<0.85:
            return .high
        default:
            return .veryHigh
        }
    }
}

import SwiftUI
import Charts

// "Am I getting faster?" — the headline question every endurance
// athlete asks about themselves. Renders the athlete's full HYROX
// race history as a line chart, total finish time on the Y axis,
// race date on the X axis. A trendline that drops left-to-right is
// the visual signature of improvement.
//
// Gated on 3+ finished races so the chart has enough points to read
// as a trend rather than a single dot. Below that threshold the
// caller hides the section entirely (one or two dots aren't a trend).
//
// SwiftCharts (Apple, iOS 16+) — already in the project from the HR
// + fatigue charts on race detail. iOS-only; lives alongside other
// Profile charts in Features/Profile/.
struct PerformanceTrendsView: View {

    // Pre-filtered to finished races only. Order doesn't matter for
    // the chart (Charts orders by X-axis date), but the caller
    // typically passes them ascending by createdAt for readability.
    let races: [Race]

    // Minimum races needed for a trendline to be meaningful. Two
    // points is a line, not a trend; three is the smallest set
    // where you can see "is the slope flat or trending."
    static let minimumRacesForTrend = 3

    static func hasEnoughData(in races: [Race]) -> Bool {
        races.filter { $0.isFinished && $0.totalDuration != nil }.count
            >= minimumRacesForTrend
    }

    // Pre-compute the (date, duration) pairs once per render so the
    // chart's body doesn't repeatedly walk the races array.
    private var points: [(date: Date, seconds: TimeInterval)] {
        races
            .filter { $0.isFinished }
            .compactMap { race in
                guard let total = race.totalDuration else { return nil }
                return (race.createdAt, total)
            }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        if points.count >= Self.minimumRacesForTrend {
            chart
        } else {
            EmptyView()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                // Line connecting all races chronologically. Monotone
                // interpolation rounds the corners between points so
                // the chart reads as a smooth progression rather than
                // a jagged sawtooth on small samples.
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Time", point.seconds)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

                // Dot at each race so the athlete can pick out
                // individual races on the line — useful when the
                // points are sparse over a long time window.
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Time", point.seconds)
                )
                .foregroundStyle(Color.accent)
                .symbolSize(40)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(RaceStats.format(seconds))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            // Compact date labels — full year is overkill; "Jan 5"
            // / "Mar 12" reads well on a small phone-width chart.
            AxisMarks(preset: .automatic, position: .bottom) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.textTertiary)
                    .font(.caption2)
            }
        }
        .frame(height: 180)
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}

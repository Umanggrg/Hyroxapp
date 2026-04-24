import SwiftUI
import Charts

// "Did I slow down?" visualization for a single race.
//
// Plots the 8 (or however many completed) 1km-run splits as a line chart
// — x-axis is the run's position in the race (R1 → R8), y-axis is its
// duration. A trendline going up from left to right is the visual
// signature of fatigue: later runs are slower than earlier ones.
//
// Why runs specifically and not all 16 stations: run durations are
// directly comparable to each other (all are 1km), so the y-axis is
// meaningful. A line chart mixing 1km runs with a 40-second sled push
// would be noise — the runs would dominate and the workouts would be
// invisible on the same scale.
//
// Uses existing split data (startedAt, endedAt) — no HealthKit, no
// Watch, no extra capture. Always available once the race has at least
// a couple of run splits logged.
//
// Framework: Apple's built-in `Charts`. iOS-only (watchOS Charts is
// limited); lives in Features/History/ alongside HeartRateChartView.
struct RunFatigueChartView: View {

    let splits: [Split]

    // Only 1km runs — filter by station kind, preserve original order
    // (the splits array is already in race order, so the first run is
    // R1, etc.).
    private var runSplits: [Split] {
        splits.filter { $0.station.kind == .run }
    }

    // Expose to callers so they can gate the section on whether there's
    // enough data to chart. Needs at least 2 runs for a "trend" to even
    // exist — a single point isn't a fatigue curve.
    static func hasFatigueData(in splits: [Split]) -> Bool {
        splits.filter { $0.station.kind == .run }.count >= 2
    }

    var body: some View {
        if runSplits.count >= 2 {
            chart
        } else {
            EmptyView()
        }
    }

    private var chart: some View {
        // Map each run to (position, duration). Position is 1-indexed so
        // the axis reads "R1, R2, R3..." matching how athletes name them.
        let points = runSplits.enumerated().map { index, split in
            (position: index + 1, seconds: split.duration)
        }

        return Chart {
            ForEach(points, id: \.position) { point in
                // LineMark draws the connecting line. PointMark on the
                // same x-category adds the dots — Charts will layer them
                // so the line passes through each dot.
                LineMark(
                    x: .value("Run", "R\(point.position)"),
                    y: .value("Duration", point.seconds)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Run", "R\(point.position)"),
                    y: .value("Duration", point.seconds)
                )
                .foregroundStyle(Color.accent)
                .symbolSize(40)
            }
        }
        .chartYAxis {
            // Format Y-axis ticks as MM:SS so athletes see "5:00" not
            // "300 seconds". Integer-cast into our shared RaceStats
            // formatter so the style matches every other time display
            // in the app.
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
            AxisMarks(preset: .automatic, position: .bottom) { _ in
                AxisValueLabel()
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

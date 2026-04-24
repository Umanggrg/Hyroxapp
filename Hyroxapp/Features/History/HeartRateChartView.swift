import SwiftUI
import Charts

// Per-race heart-rate visualization shown on RaceDetailView.
//
// Renders one BarMark per split: the bar's height is the segment's
// average HR, and a trailing PointMark marks the segment's max HR on
// the same axis. Empty splits (HR never recorded, e.g. old races from
// before HealthKit capture shipped, or a race where the athlete wasn't
// wearing their Watch) are filtered out so the chart only shows the
// bars that have something to say.
//
// Framework: Apple's built-in `Charts` (iOS 16+). Our min deployment is
// iOS 17 (per CLAUDE.md §3), so no availability check needed. Charts on
// watchOS is a reduced subset — this component is iOS-only and lives in
// Features/History/ so target membership stays on the phone target.
//
// X-axis labeling is deliberately minimal: 16 full station names
// ("Burpee Broad Jumps", "Farmers Carry") won't fit. We use a short
// abbreviation map and let the auto-axis space them out. The caller
// can still see the full name in the splits table above the chart.
struct HeartRateChartView: View {

    let splits: [Split]

    // Derived: only splits that actually have HR data. If this is empty
    // the whole view renders nothing (caller should gate on
    // `hasAnyHeartRateData`).
    private var splitsWithHR: [Split] {
        splits.filter { $0.heartRateAvgBPM != nil }
    }

    // Expose to the caller for gating the section visibility without
    // having to rebuild the filter.
    static func hasAnyHeartRateData(in splits: [Split]) -> Bool {
        splits.contains { $0.heartRateAvgBPM != nil }
    }

    var body: some View {
        // Defensive: return nothing if called despite no HR data. Caller
        // should gate, but this keeps the view robust.
        if splitsWithHR.isEmpty {
            EmptyView()
        } else {
            chart
        }
    }

    private var chart: some View {
        // Enumerate so each split gets a unique positional id — required
        // for custom workouts with repeated stations (3× Sled Push etc.)
        // where Split.id (station.rawValue) would collide.
        let indexed = Array(splitsWithHR.enumerated())

        return Chart {
            ForEach(indexed, id: \.offset) { _, split in
                // Avg HR as a filled bar — the headline metric for this
                // segment's intensity.
                BarMark(
                    x: .value("Station", Self.shortLabel(for: split.station)),
                    y: .value("Avg bpm", split.heartRateAvgBPM ?? 0)
                )
                .foregroundStyle(Color.accentDim)
                .cornerRadius(4)

                // Max HR as a small circle at the peak, layered on the
                // same x-category. Gives a visual hint of the segment's
                // peak strain without cluttering with a second bar series.
                if let maxBPM = split.heartRateMaxBPM {
                    PointMark(
                        x: .value("Station", Self.shortLabel(for: split.station)),
                        y: .value("Max bpm", maxBPM)
                    )
                    .foregroundStyle(Color.accent)
                    .symbolSize(32)
                }
            }
        }
        .chartYAxis {
            // Custom Y axis styling — muted labels, no gridline for the
            // zero baseline (HR of 0 isn't meaningful, it's just noise).
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.divider)
                AxisValueLabel() {
                    if let bpm = value.as(Double.self) {
                        Text("\(Int(bpm))")
                            .font(.caption2)
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

    // Short labels that fit on the x axis. Full names like "Burpee
    // Broad Jumps" don't fit next to each other for 16 categories;
    // these abbreviations keep the chart readable.
    private static func shortLabel(for station: Station) -> String {
        switch station {
        case .run1: return "R1"
        case .skiErg: return "Ski"
        case .run2: return "R2"
        case .sledPush: return "Push"
        case .run3: return "R3"
        case .sledPull: return "Pull"
        case .run4: return "R4"
        case .burpeeBroadJumps: return "Burp"
        case .run5: return "R5"
        case .rowing: return "Row"
        case .run6: return "R6"
        case .farmersCarry: return "Carry"
        case .run7: return "R7"
        case .sandbagLunges: return "Lunge"
        case .run8: return "R8"
        case .wallBalls: return "Wall"
        }
    }
}

import SwiftUI
import Charts

// Per-race scatter visualizing each of the 8 runs as a dot in
// pace × HR space, with a line connecting them in race order
// (R1 → R8). The trajectory pattern tells the back-half story
// instantly:
//
//   • Tight cluster — held pace and HR consistently. Elite.
//   • Up-and-right trail — classic fade (slowing AND climbing
//     HR). The aerobic-base gap.
//   • Up-only trail — HR drift at flat pace. Engine fading
//     while you held output.
//   • Right-only trail — slowing at flat HR. You eased up
//     deliberately or pacing collapsed.
//
// Different visualization angle from the run-fatigue line
// chart and the cardiac-drift bar — this one puts pace and HR
// on the SAME chart so the relationship between them is
// visible at a glance. The line drift across the chart says
// more in two seconds than any single line+number readout
// can.
//
// X-axis: pace (sec/km). Lower-numerically = faster, so the
// chart inverts the X domain to read "left = faster" — same
// convention runners use when looking at pace charts on
// Strava / Garmin.
//
// Y-axis: avg HR (bpm), which reads "higher = more cost"
// without needing inversion.
//
// Dots are tinted by HR zone (Z3 white, Z4 amber, Z5 coral) so
// the color picks up the zone story alongside the position.
// Each dot is annotated with its run number (R1...R8) so the
// trajectory sequence is unambiguous even if the line
// crisscrosses.
//
// Hidden when fewer than 4 runs have both pace and HR data —
// below that the trajectory has no real shape to read.
struct PaceHeartRateScatterView: View {

    let race: Race
    let maxHR: Int

    @State private var animationsRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let minimumRunsForScatter = 4

    // Per-run data points. Sorted chronologically so the line
    // mark renders R1 → R8 left-to-right (in chart-time order,
    // not pace-order).
    private var points: [(runNumber: Int, paceSecPerKm: Double, hr: Double, zone: HRZone)] {
        let runSplits = race.splits
            .filter { $0.station.kind == .run }
            .sorted { $0.startedAt < $1.startedAt }

        return runSplits.enumerated().compactMap { index, split in
            guard let avg = split.heartRateAvgBPM, avg > 0,
                  split.duration > 0 else { return nil }
            let zone = HRZone.zone(for: avg, maxBPM: maxHR)
            return (
                runNumber: index + 1,
                paceSecPerKm: split.duration,
                hr: avg,
                zone: zone
            )
        }
    }

    static func hasEnoughData(for race: Race) -> Bool {
        let count = race.splits
            .filter { $0.station.kind == .run }
            .compactMap { split -> Bool? in
                guard let avg = split.heartRateAvgBPM, avg > 0,
                      split.duration > 0 else { return nil }
                return true
            }
            .count
        return count >= minimumRunsForScatter
    }

    var body: some View {
        if points.count >= Self.minimumRunsForScatter {
            chart
        } else {
            EmptyView()
        }
    }

    // MARK: - Chart

    private var chart: some View {
        // Compute axis bounds with a little padding so dots
        // don't touch the chart edges. SwiftCharts auto-fits
        // by default, but we want explicit padding so the
        // labels above each dot don't get clipped.
        let paces = points.map(\.paceSecPerKm)
        let hrs = points.map(\.hr)
        guard let minPace = paces.min(),
              let maxPace = paces.max(),
              let minHR = hrs.min(),
              let maxHR = hrs.max()
        else { return AnyView(EmptyView()) }

        let pacePadding = max(5.0, (maxPace - minPace) * 0.15)
        let hrPadding = max(3.0, (maxHR - minHR) * 0.15)

        return AnyView(
            Chart {
                // Connecting line — shows the trajectory R1 → R8
                // in race order. Coral-dim like the rest of the
                // app's chart family, with a slight stroke so
                // the path stays visible underneath the dots.
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Pace", point.paceSecPerKm),
                        y: .value("HR", point.hr)
                    )
                    .foregroundStyle(Color.accentDim.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .interpolationMethod(.linear)
                    .opacity(animationsRevealed ? 1.0 : 0)
                }

                // Dots — tinted by HR zone so the color picks
                // up the zone story alongside position. Each
                // annotated with the run number (R1...R8) so
                // the trajectory sequence is unambiguous.
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    PointMark(
                        x: .value("Pace", point.paceSecPerKm),
                        y: .value("HR", point.hr)
                    )
                    .foregroundStyle(point.zone.color)
                    .symbolSize(animationsRevealed ? 110 : 0)
                    .annotation(position: .top, spacing: 2) {
                        Text("R\(point.runNumber)")
                            .font(.caption2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(point.zone.color)
                    }
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
            // X-axis inverted so faster pace reads left — same
            // convention runners expect (Strava / Garmin).
            .chartXScale(
                domain: (maxPace + pacePadding)...(minPace - pacePadding),
                range: .plotDimension(startPadding: 8, endPadding: 8)
            )
            .chartYScale(
                domain: (minHR - hrPadding)...(maxHR + hrPadding)
            )
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.divider)
                    AxisValueLabel {
                        if let pace = value.as(Double.self) {
                            Text(formatPace(pace))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.divider)
                    AxisValueLabel {
                        if let hr = value.as(Double.self) {
                            Text("\(Int(hr.rounded()))")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
            .chartXAxisLabel(alignment: .center) {
                Text("Pace · faster ←")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .chartYAxisLabel(position: .leading, alignment: .center) {
                Text("HR")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(height: 240)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        )
    }

    // Format sec/km as "M:SS" — same convention used elsewhere
    // for pace display. 312 seconds → "5:12".
    private func formatPace(_ secPerKm: Double) -> String {
        let totalSec = Int(secPerKm.rounded())
        let mins = totalSec / 60
        let secs = totalSec % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

import SwiftUI
import Charts

// Wireframe §04.1 trends mode — finish-time line chart over the
// last N races + per-station deep-dive list showing the delta
// between most-recent and prior-best for each station type.
//
// Takes the full finished-race array; this view does its own
// filtering (last 6 only for the chart, group-by-station for
// the deep dive). No tap interactions on the chart for v1 —
// the chart is informational.
struct HistoryTrendsMode: View {

    let races: [Race]

    // Chart shows the last 6 races worth of finish times. Filters
    // out anything without a totalDuration (in-progress / nil).
    // Ordered oldest → newest so the line reads left-to-right as
    // a time series.
    private var chartRaces: [Race] {
        races
            .filter { $0.isFinished && $0.totalDuration != nil }
            .sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
            .suffix(6)
            .map { $0 }
    }

    // Station deep-dive entries — one per workout station type.
    // For each, computes the most recent finish time and the
    // delta vs the athlete's prior best for that station.
    private var stationDeepDive: [StationTrendRow] {
        let workoutStations: [Station] = [
            .skiErg, .sledPush, .sledPull, .burpeeBroadJumps,
            .rowing, .farmersCarry, .sandbagLunges, .wallBalls
        ]

        return workoutStations.compactMap { station -> StationTrendRow? in
            let priorSplits = races
                .filter { $0.isFinished }
                .flatMap(\.splits)
                .filter { $0.station == station }

            guard !priorSplits.isEmpty else { return nil }

            // Most recent split for this station (by parent
            // race's endedAt).
            let sortedSplits = priorSplits.sorted { ($0.startedAt) > ($1.startedAt) }
            guard let mostRecent = sortedSplits.first else { return nil }
            let mostRecentDuration = mostRecent.duration

            // Prior best = min duration across ALL splits for
            // this station, excluding the most recent. If only
            // one exists, delta is nil (no baseline to compare).
            let others = sortedSplits.dropFirst()
            let priorBest = others.map(\.duration).min()
            let delta: TimeInterval? = priorBest.map { mostRecentDuration - $0 }

            return StationTrendRow(
                station: station,
                mostRecentDuration: mostRecentDuration,
                delta: delta
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if chartRaces.isEmpty {
                emptyState
            } else {
                finishTimeChartSection
                stationDeepDiveSection
            }
        }
    }

    // MARK: - Finish time chart section

    private var finishTimeChartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FINISH TIME · LAST \(chartRaces.count) RACES")
                .capsLabelStyle()

            finishTimeChart
                .frame(height: 120)
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.surfaceElevated)
                )
                .overlay(alignment: .topTrailing) {
                    chartRangeLabel
                        .padding(8)
                }

            if let observation = trendObservation {
                Text(observation)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 2)
            }
        }
    }

    @ChartContentBuilder
    private var finishTimeChartContent: some ChartContent {
        ForEach(Array(chartRaces.enumerated()), id: \.offset) { idx, race in
            if let total = race.totalDuration {
                LineMark(
                    x: .value("Race", idx),
                    y: .value("Finish time", total)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Race", idx),
                    y: .value("Finish time", total)
                )
                .foregroundStyle(Color.accent)
                .symbolSize(idx == chartRaces.count - 1 ? 80 : 40)
            }
        }
    }

    private var finishTimeChart: some View {
        Chart {
            finishTimeChartContent
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    // "1:24 → 1:18" tiny mono label top-right showing the range.
    @ViewBuilder
    private var chartRangeLabel: some View {
        let times = chartRaces.compactMap(\.totalDuration)
        if let oldest = times.first, let newest = times.last {
            Text("\(RaceStats.format(oldest)) → \(RaceStats.format(newest))")
                .font(.system(size: 9, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textTertiary)
        }
    }

    // Hand-written observation about the trend direction. Picks
    // one of three sentences based on whether the line slopes
    // down (improving), up (regressing), or flat. Mimics the
    // wireframe's italicized note beneath the chart.
    private var trendObservation: String? {
        let times = chartRaces.compactMap(\.totalDuration)
        guard times.count >= 2,
              let first = times.first,
              let last = times.last
        else { return nil }

        let delta = last - first
        let percent = abs(delta) / first

        if delta < 0 && percent >= 0.02 {
            return "\(chartRaces.count) races, \(chartRaces.count) gains. Trending down nicely."
        } else if delta > 0 && percent >= 0.02 {
            return "Finish time creeping up. Worth a recovery week."
        } else {
            return "Steady ground. Look for the next push."
        }
    }

    // MARK: - Station deep dive section

    private var stationDeepDiveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATION DEEP DIVE")
                .capsLabelStyle()

            VStack(spacing: 4) {
                ForEach(stationDeepDive) { row in
                    stationRow(row)
                }
            }
        }
    }

    private func stationRow(_ row: StationTrendRow) -> some View {
        let isRegressing = (row.delta ?? 0) > 0
        let tint: Color = isRegressing ? Color.accent : Color.onPace

        return HStack {
            Text(row.station.displayName)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let delta = row.delta {
                Text(deltaLabel(delta))
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            Text(RaceStats.format(row.mostRecentDuration))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRegressing ? Color.accent.opacity(0.08) : Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRegressing ? Color.accent : Color.clear, lineWidth: 1)
        )
    }

    private func deltaLabel(_ delta: TimeInterval) -> String {
        let sign = delta < 0 ? "−" : "+"
        return "\(sign)\(RaceStats.format(abs(delta)))"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("Run two races to see trends.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Trends compare your last finish to the one before it — they need at least two completed races.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.screenMargin)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

struct StationTrendRow: Identifiable {
    let station: Station
    let mostRecentDuration: TimeInterval
    let delta: TimeInterval?

    var id: Int { station.rawValue }
}

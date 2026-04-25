import SwiftUI
import SwiftData
import Charts

// Roxfit-style per-station deep dive — pushed from a tap on any
// split row in `RaceDetailView`. Answers the questions a HYROX
// athlete asks about an individual station after the dust settles:
//
//   • how fast was THIS attempt?
//   • how does it compare to my all-time best on this station?
//   • where does this rank in my recent history?
//   • what was happening physiologically — HR avg / max, calories?
//
// Navigation contract: the nav value is a `Split` (Hashable). The
// view re-queries all finished races internally so the trend chart
// stays live to the rest of the app — no manual passing of the
// races list through the navigation graph.
//
// Run-station semantics: when the tapped split is a 1km run case
// (run1…run8), the trend collapses ALL run splits across history
// into a single series. From the athlete's POV they have one
// "1km Run" stat, not eight. Workout stations (Sled Push, Wall
// Balls, etc.) are 1:1 with their case.
//
// Guarded `#if !os(watchOS)` because Race + Charts aren't
// available on watchOS.
#if !os(watchOS)
struct StationDetailView: View {

    // The specific split the athlete tapped — drives the hero
    // duration, HR, calories. Its `station` field is the type used
    // for trend/PB queries.
    let split: Split

    // Re-query finished races at view scope. Same pattern used on
    // RaceDetailView and ProfileView; keeps the trend live without
    // threading a races array through navigation.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .forward)]
    ) private var allFinishedRaces: [Race]

    // Best ever on this station type (collapsing run cases together).
    private var personalBest: Split? {
        RaceStats.allTimeBest(for: split.station, among: allFinishedRaces)
    }

    // Time-series of every attempt at this station type, oldest
    // first. One dot per attempt (8 per race for runs, 1 per race
    // for workouts). Each tuple carries its source Split so the
    // chart can highlight the current attempt's dot exactly without
    // a per-dot lookup back to the parent race.
    private var trend: [(date: Date, duration: TimeInterval, split: Split)] {
        RaceStats.stationTrend(for: split.station, among: allFinishedRaces)
    }

    // True when this attempt is the fastest in the trend series.
    // Used for the "PB" pill above the hero number. `Split`
    // conforms to Equatable, so the identity check is exact —
    // station + start/end times + HR/cals all match.
    private var isPersonalBest: Bool {
        personalBest == split
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    if !trend.isEmpty {
                        trendCard
                    }
                    physiologyCard
                }
                .padding(Layout.screenMargin)
            }
        }
        .navigationTitle(split.station.displayName)
        .hyroxDarkNavigationBar(inline: true)
    }

    // MARK: - Hero (this attempt's duration + PB context)

    private var heroCard: some View {
        VStack(spacing: 8) {
            if isPersonalBest {
                HStack(spacing: 6) {
                    Image(systemName: "rosette")
                        .font(.caption.weight(.bold))
                    Text("Personal Best")
                        .font(.caption.weight(.bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                }
                .foregroundStyle(Color(hex: 0xFFD60A))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex: 0xFFD60A).opacity(0.15))
                )
            }

            Text(RaceStats.format(split.duration))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("This attempt")
                .capsLabelStyle()

            // Comparison line — only renders when there's a PB to
            // compare against (i.e. another attempt exists). For a
            // first-ever attempt this stays blank.
            if let pb = personalBest, !isPersonalBest {
                let delta = split.duration - pb.duration
                HStack(spacing: 6) {
                    Image(systemName: delta < 0 ? "arrow.down" : "arrow.up")
                        .font(.caption.weight(.bold))
                    Text(deltaText(absDelta: abs(delta), isFaster: delta < 0))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    Text("vs your best (\(RaceStats.format(pb.duration)))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
                .foregroundStyle(delta < 0 ? Color.success : Color.warning)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func deltaText(absDelta: TimeInterval, isFaster: Bool) -> String {
        "\(RaceStats.format(absDelta)) \(isFaster ? "faster" : "slower")"
    }

    // MARK: - Trend chart (all attempts at this station type)

    // SwiftCharts line + point chart of every attempt over time.
    // The current split's dot is highlighted in coral so the athlete
    // can see "where this attempt sits in my history at a glance."
    // Y-axis is duration in seconds — lower = faster, so the line
    // dropping over time visually reads as "getting fitter." Same
    // convention Strava uses for PR trend charts.
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trend").capsLabelStyle()
                Spacer()
                Text("\(trend.count) attempt\(trend.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            Chart(Array(trend.enumerated()), id: \.offset) { index, point in
                // Connecting line — gives the chart its trend shape.
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Duration", point.duration)
                )
                .foregroundStyle(Color.accentDim)
                .interpolationMethod(.monotone)

                // Dots on every attempt. Current split's dot is
                // larger + coral, others are smaller + dim — same
                // pattern Strava uses to highlight "this activity"
                // in a PR history view. Identity check is exact —
                // we compare the trend tuple's source Split to the
                // viewed split via Equatable.
                let isCurrent = point.split == split
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Duration", point.duration)
                )
                .foregroundStyle(isCurrent ? Color.accent : Color.textSecondary)
                .symbolSize(isCurrent ? 120 : 40)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let seconds = value.as(TimeInterval.self) {
                            Text(RaceStats.format(seconds))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    AxisGridLine()
                        .foregroundStyle(Color.divider)
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: 180)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // Dynamic y-axis domain — ±10% padding around the data range so
    // the line doesn't kiss the edges. Falls back to a sane window
    // when there's only one point so the chart renders.
    private var yDomain: ClosedRange<TimeInterval> {
        let values = trend.map(\.duration)
        guard let minV = values.min(), let maxV = values.max() else {
            return 0...60
        }
        let span = max(maxV - minV, 1)
        let pad = span * 0.1
        return max(minV - pad, 0)...(maxV + pad)
    }

    // MARK: - Physiology (HR + calories for this segment)

    // Three-tile row: avg HR, max HR, calories. Each tile shows a
    // dash placeholder when the underlying HealthKit data isn't
    // available rather than hiding the row entirely — empty tiles
    // are a lighter cue ("we don't have that") than a missing
    // section ("there's nothing to say").
    private var physiologyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Physiology").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                physiologyTile(
                    value: split.heartRateAvgBPM.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    label: "AVG HR"
                )
                physiologyTile(
                    value: split.heartRateMaxBPM.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    label: "MAX HR"
                )
                physiologyTile(
                    value: split.activeCaloriesKcal.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "kcal",
                    label: "CALORIES"
                )
            }
        }
    }

    private func physiologyTile(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}
#endif

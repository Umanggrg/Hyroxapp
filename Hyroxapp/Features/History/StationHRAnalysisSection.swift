import SwiftUI
import SwiftData
import Charts

// §43 — universal HR deep-dive section for StationDetailView.
//
// Sits between the Trend chart and the Physiology card. Pulls
// from `race.hrSeries` (Phase 28 — the dense ~1Hz HR timeline
// persisted on every Phase-28+ race) filtered to the station's
// time window, then surfaces three layers the existing
// physiology card doesn't:
//
//   1. HR curve chart — actual bpm over the station's duration,
//      with zone-band tinting behind so the athlete sees not
//      just "avg 162" but "where the spikes and valleys were."
//   2. Time-in-zone breakdown specific to THIS station — not
//      race-wide. Was this sled push 8 seconds in Z4 and 12 in
//      Z5? Different shape than a steady-state row.
//   3. vs Last 3 Attempts comparison grid — Whoop-style "how
//      did this rep at this station stack against your recent
//      memory?" Duration / avg HR / max HR / calories with
//      signed deltas + green/amber tinting.
//
// Hides silently when there's no hrSeries data (pre-Phase-28
// race) or the slice within the station's window is too sparse
// to draw a meaningful chart (< 4 samples). The physiology
// card beneath still renders, so the athlete never sees a "data
// missing" placeholder — just a slimmer detail view.
//
// Universal across all 8 workout stations + the 8 run cases.
// The curve + zones + vs-last-3 grid all derive from the same
// data shape regardless of station type. Future station-aware
// sections (§13.12 — stroke counts for rowing, strategy
// detection for wall balls) layer on top of this without
// replacing it.
#if !os(watchOS)
struct StationHRAnalysisSection: View {

    // The split this section is analyzing — same source as the
    // parent StationDetailView's hero.
    let split: Split

    // The full HR series for the parent race, passed down from
    // StationDetailView. Empty for pre-Phase-28 races; section
    // hides itself in that case via `hasSignal`.
    let raceHRSeries: [HRSample]

    // All finished races, used for the vs-last-3 comparison
    // grid. Passed in (not @Query'd here) so the section can
    // be unit-previewed against fixture data.
    let allFinishedRaces: [Race]

    // Athlete's max HR — drives zone classification + zone band
    // overlay on the chart.
    let maxHeartRate: Int

    // MARK: - Derived

    // HR samples that fell inside this station's [startedAt,
    // endedAt] window. The chart, zone breakdown, and climb
    // metrics all read from this. Sorted ascending — required
    // for chart line continuity and for the zone-time gap math
    // in HRZone.timeInZones to behave.
    private var stationSamples: [HRSample] {
        raceHRSeries
            .filter { $0.sampledAt >= split.startedAt && $0.sampledAt <= split.endedAt }
            .sorted { $0.sampledAt < $1.sampledAt }
    }

    // True when we have enough signal to render meaningfully.
    // Fewer than 4 samples in a 30-second sled push isn't a
    // curve — it's three dots. The whole-section hide is more
    // honest than a degenerate chart.
    private var hasSignal: Bool {
        stationSamples.count >= 4
    }

    // Bound the y-axis to a reasonable window around the
    // observed samples + the redline threshold so the curve
    // shape reads clearly without being overwhelmed by the
    // full 0-220 range.
    private var yDomain: ClosedRange<Double> {
        let bpms = stationSamples.map(\.bpm)
        guard let minV = bpms.min(), let maxV = bpms.max() else {
            return 60...190
        }
        let span = max(maxV - minV, 20)
        let pad = span * 0.15
        return max(minV - pad, 40)...(maxV + pad)
    }

    // Per-zone time totals across this station's samples. The
    // bar's segments scale from these.
    private var timeInZones: [HRZone: TimeInterval] {
        HRZone.timeInZones(
            samples: stationSamples,
            maxBPM: maxHeartRate,
            end: split.endedAt
        )
    }

    // Total time accounted for across zones — usually within a
    // second or two of the split's duration but can differ
    // slightly if there are gaps. Used as the denominator for
    // per-zone percentages.
    private var totalZonedTime: TimeInterval {
        timeInZones.values.reduce(0, +)
    }

    // The last N attempts at this station type (oldest of the
    // N first, so the most-recent attempt is the LAST element).
    // Includes the current split — it's the right-most cell of
    // the comparison so the athlete sees "this vs the three
    // before it." If fewer than 4 attempts exist, the grid
    // adapts down (1, 2, or 3 cells).
    private var recentAttempts: [Split] {
        let trend = RaceStats.stationTrend(
            for: split.station,
            among: allFinishedRaces
        )
        return Array(trend.suffix(4)).map(\.split)
    }

    // MARK: - Body

    var body: some View {
        if hasSignal {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Heart Rate",
                    icon: "heart.fill"
                )

                VStack(spacing: 16) {
                    curveCard
                    zonesCard
                    if recentAttempts.count >= 2 {
                        comparisonCard
                    }
                }
            }
        }
    }

    // MARK: - HR curve

    // Line chart of the HR samples within the station window.
    // Zone-band shading behind the curve so the athlete reads
    // "spent most of this in Z4" without needing the zone bar
    // below. Y axis bounded to the observed range + 15% pad.
    private var curveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HR Curve").capsLabelStyle()
                Spacer()
                if let climb = climbDeltaBPM {
                    Text(climbCopy(climb))
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(climbTint(climb))
                }
            }
            .padding(.horizontal, 4)

            Chart {
                // Zone bands — render BEHIND the curve so each
                // shade reads through the line. Cap the band
                // tops/bottoms to the y-domain so they don't
                // visually leak past the visible range.
                ForEach(HRZone.allCases, id: \.self) { zone in
                    let lo = Double(maxHeartRate) * zone.lowerFraction
                    let hi = zone == .z5
                        ? yDomain.upperBound
                        : Double(maxHeartRate) * zone.upperFraction
                    if hi > yDomain.lowerBound && lo < yDomain.upperBound {
                        RectangleMark(
                            xStart: .value("Start", split.startedAt),
                            xEnd: .value("End", split.endedAt),
                            yStart: .value("Lo", max(lo, yDomain.lowerBound)),
                            yEnd: .value("Hi", min(hi, yDomain.upperBound))
                        )
                        .foregroundStyle(zone.color.opacity(0.10))
                    }
                }

                // The HR curve itself.
                ForEach(stationSamples, id: \.sampledAt) { sample in
                    LineMark(
                        x: .value("Time", sample.sampledAt),
                        y: .value("HR", sample.bpm)
                    )
                    .foregroundStyle(Color.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm))")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    AxisGridLine().foregroundStyle(Color.divider.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.minute().second())
                        .foregroundStyle(Color.textTertiary)
                    AxisGridLine().foregroundStyle(Color.divider.opacity(0.5))
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: 140)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // Net climb across the station — last sample minus first.
    // Positive = HR climbed (typical for sustained efforts);
    // close to zero = held flat (efficient pacing); negative =
    // HR dropped during the work (recovery between bouts).
    private var climbDeltaBPM: Int? {
        guard let first = stationSamples.first?.bpm,
              let last = stationSamples.last?.bpm else { return nil }
        return Int((last - first).rounded())
    }

    private func climbCopy(_ delta: Int) -> String {
        if delta > 0 { return "Climbed +\(delta) bpm" }
        if delta < 0 { return "Dropped \(delta) bpm" }
        return "Held flat"
    }

    // Tier coloring for the climb chip. Big climbs on sustained
    // stations (sled push, wall balls) are normal — Z3-Z5
    // territory, expected. Climbs on runs are the engine signal
    // we care about, but the chip itself stays neutral; the
    // race-wide drift chart is the proper home for that
    // interpretation. Keep this informational not judgmental.
    private func climbTint(_ delta: Int) -> Color {
        if delta >= 20 { return Color.warning }
        if delta <= -10 { return Color.success }
        return Color.textSecondary
    }

    // MARK: - Time in zones

    // Horizontal stacked bar of per-zone time, with caps label
    // legend below. Same pattern HRZonesView uses race-wide,
    // scoped here to one station's window.
    private var zonesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Time in Zone").capsLabelStyle()
                Spacer()
                Text(stationZoneSummary)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 4)

            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(HRZone.allCases, id: \.self) { zone in
                        let secs = timeInZones[zone] ?? 0
                        let width = totalZonedTime > 0
                            ? CGFloat(secs / totalZonedTime) * proxy.size.width
                            : 0
                        Rectangle()
                            .fill(zone.color)
                            .frame(width: max(width, 0))
                    }
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 10) {
                ForEach(HRZone.allCases, id: \.self) { zone in
                    let secs = timeInZones[zone] ?? 0
                    if secs > 0 {
                        zoneLegendEntry(zone: zone, seconds: secs)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Dominant-zone one-liner — "Mostly Z3 · Race Pace" or
    // "Mostly Z5 · Redline" — answers the same question as the
    // bar itself but in words for the at-a-glance read.
    private var stationZoneSummary: String {
        guard let dominant = timeInZones.max(by: { $0.value < $1.value })?.key else {
            return ""
        }
        return "Mostly \(dominant.hyroxLabel)"
    }

    private func zoneLegendEntry(zone: HRZone, seconds: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(zone.color)
                .frame(width: 6, height: 6)
            Text("\(zone.hyroxLabel) \(Int(seconds.rounded()))s")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - vs Last 3 Attempts

    // Compact 4-column grid: most-recent on the right. Each
    // column carries the date / duration / HR avg / HR max /
    // kcal stacked. The current split's column has a Volt
    // border so the athlete sees "this vs the three before it"
    // at a glance.
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("vs Recent Attempts").capsLabelStyle()
                Spacer()
                Text("\(recentAttempts.count) attempts")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 6) {
                // ForEach keys on `startedAt` for stable identity
                // across data shifts — a new race landing while
                // the view is visible would otherwise re-key by
                // array position and animate the wrong columns.
                // Split conforms to Identifiable but its `id` is
                // the station rawValue (unique within ONE race,
                // not across attempts), so we can't use \.self
                // or \.id here.
                ForEach(recentAttempts, id: \.startedAt) { attempt in
                    attemptColumn(attempt: attempt, isCurrent: attempt == split)
                }
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func attemptColumn(attempt: Split, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(attemptDateLabel(attempt))
                .font(.caption2.weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(isCurrent ? Color.accent : Color.textTertiary)

            Text(RaceStats.format(attempt.duration))
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            attemptStatRow(
                label: "avg",
                value: attempt.heartRateAvgBPM.map { "\(Int($0.rounded()))" } ?? "—"
            )
            attemptStatRow(
                label: "max",
                value: attempt.heartRateMaxBPM.map { "\(Int($0.rounded()))" } ?? "—"
            )
            attemptStatRow(
                label: "kcal",
                value: attempt.activeCaloriesKcal.map { "\(Int($0.rounded()))" } ?? "—"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isCurrent ? Color.accent : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private func attemptStatRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: 0)
            Text(value)
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func attemptDateLabel(_ attempt: Split) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: attempt.startedAt).uppercased()
    }
}
#endif

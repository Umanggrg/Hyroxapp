import SwiftUI
import Charts

// HYROX-specific "compromised running" analysis. The thing every
// other fitness app misses about HYROX: your run pace doesn't
// stay constant. Each workout station blows up your engine for
// the next run, and athletes obsess over WHICH stations cost
// them the most pace. This view answers exactly that.
//
// What's shown:
//   • Line chart of run durations across R1 → R8
//   • Each run point colored by slowdown severity (green at
//     baseline, warming through orange, full red at the slowest)
//   • The single worst run is highlighted with a coral ring
//   • Beneath the chart: a row of station icons under each run
//     point showing the workout that just preceded it
//   • Below the chart: a callout card naming the biggest
//     slowdown and the station that caused it ("Run 6 was 22%
//     slower than Run 1 after Sandbag Lunges")
//
// vs the older RunFatigueChartView (kept for backward compat,
// but this one is a strict superset): adds station attribution
// and the most-compromised-run callout. The narrative beat —
// "Sandbag Lunges compromised your engine" — is the killer
// HYROX-specific framing.
//
// Gated on having at least 2 runs in the splits — single-run
// custom workouts have no slowdown to plot.
//
// Guarded `#if !os(watchOS)` because Charts on watchOS is
// limited and the layout is iPhone-sized.
#if !os(watchOS)
struct CompromisedRunningView: View {

    let race: Race

    private var data: [RaceStats.CompromisedRunData] {
        RaceStats.compromisedRunData(for: race)
    }

    private var biggest: RaceStats.CompromisedRunData? {
        RaceStats.biggestCompromisedRun(for: race)
    }

    // Visibility helper — at least 2 runs needed for slowdown to
    // mean anything (R1 is the baseline; we need R2+ for the
    // "compromised" delta).
    static func hasData(in race: Race) -> Bool {
        RaceStats.compromisedRunData(for: race).count >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chart
            stationRow
            if let biggest, biggest.percentSlower > 0 {
                attributionCallout(biggest)
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Chart

    // Same line+point layout as the older RunFatigueChartView,
    // but each PointMark is colored by its slowdown severity:
    // green at baseline, warming through gold to red at the
    // slowest. The slowest point also gets a halo ring so it
    // visually pops.
    private var chart: some View {
        let maxSlowdown = data.dropFirst().map(\.percentSlower).max() ?? 0
        let worstIndex = biggest?.runIndex

        return Chart {
            ForEach(data, id: \.runIndex) { item in
                LineMark(
                    x: .value("Run", "R\(item.runIndex)"),
                    y: .value("Duration", item.split.duration)
                )
                .foregroundStyle(Color.accentDim)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Run", "R\(item.runIndex)"),
                    y: .value("Duration", item.split.duration)
                )
                .foregroundStyle(slowdownColor(item.percentSlower, max: maxSlowdown))
                .symbolSize(item.runIndex == worstIndex ? 180 : 60)
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
            AxisMarks(preset: .automatic, position: .bottom) { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.textTertiary)
                    .font(.caption2)
            }
        }
        .frame(height: 160)
    }

    // Color ramp: at 0% slowdown (baseline) → success green, max
    // slowdown → accent coral, midpoint → warning orange. Linear
    // interpolation by % position. Returns success for the
    // baseline (Run 1, percentSlower = 0).
    private func slowdownColor(_ percent: Double, max: Double) -> Color {
        guard max > 0 else { return Color.success }
        let t = min(percent / max, 1.0)
        if t < 0.5 {
            return Color.success  // < halfway → call it green
        } else if t < 0.85 {
            return Color.warning  // mostly slowed
        } else {
            return Color.accent   // worst tier
        }
    }

    // MARK: - Station attribution row (under chart)

    // Below the chart: a row aligned to the chart's x-axis
    // showing which station preceded each run. Run 1 has no
    // preceding station (it's the first segment) so its slot
    // shows a tiny "—" placeholder. Later runs show a small SF
    // Symbol + caption with the station kind.
    //
    // Kept text-light: just an icon + 2-letter abbreviation per
    // station because anything fuller would crowd at 8 columns.
    private var stationRow: some View {
        HStack(spacing: 0) {
            ForEach(data, id: \.runIndex) { item in
                VStack(spacing: 3) {
                    Image(systemName: item.precedingStation?.glyph ?? "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(stationAbbreviation(item.precedingStation))
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        // Match the chart's plot inset so labels align under
        // their corresponding x-axis tick. SwiftCharts adds a
        // ~10pt left margin for the leading y-axis labels.
        .padding(.leading, 24)
        .padding(.trailing, 4)
    }

    // SF Symbol per station kind. Bodyweight stations (ergs, burpees)
    // and the runs themselves get distinct glyphs so the row reads
    // at a glance.
    // `stationIcon` was hoisted onto the Station model as
    // `Station.glyph` so every consumer reads from one source.
    // Local helper kept removed; call sites read
    // `station?.glyph ?? "minus"`.

    // Two-letter abbreviation for the station, used under the
    // glyph. Keeps the row tight at 8-column width.
    private func stationAbbreviation(_ station: Station?) -> String {
        guard let station else { return "—" }
        switch station {
        case .skiErg:           return "SKI"
        case .sledPush:         return "PSH"
        case .sledPull:         return "PUL"
        case .burpeeBroadJumps: return "BRP"
        case .rowing:           return "ROW"
        case .farmersCarry:     return "FRM"
        case .sandbagLunges:    return "LUN"
        case .wallBalls:        return "WB"
        default:                return ""
        }
    }

    // MARK: - Attribution callout

    // Below the chart + station row: the headline insight in
    // sentence form. Reads as a coach's diagnosis, not a stat
    // table. "Most compromised: Run 6 (+22%) after Sandbag
    // Lunges" — actionable: the athlete now knows where to
    // focus engine recovery training.
    private func attributionCallout(_ biggest: RaceStats.CompromisedRunData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("MOST COMPROMISED")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.warning)

                Text(headline(biggest))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let preceding = biggest.precedingStation {
                    Text("After \(preceding.displayName) — your engine took the biggest hit here.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.warning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.warning.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func headline(_ item: RaceStats.CompromisedRunData) -> String {
        let pct = Int(item.percentSlower.rounded())
        return "Run \(item.runIndex) was \(pct)% slower than Run 1"
    }
}
#endif

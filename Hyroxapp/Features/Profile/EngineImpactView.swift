import SwiftUI

// "Engine Impact" — cross-race aggregation of which workout
// stations consistently compromise the athlete's run pace the
// most. The Profile-level companion to per-race CompromisedRunningView:
//
//   • Per-race view says "today, Sandbag Lunges hurt your
//     engine the most"
//   • This view says "across all your races, Sandbag Lunges is
//     your worst engine-recovery weakness"
//
// That second statement is actionable training intelligence no
// other HYROX-adjacent app surfaces. Athletes use this to
// prioritize lunge-to-run brick sessions, sled-pull conditioning,
// etc.
//
// Visual: a horizontal bar list. Each row is a station; bar
// length is the avg % slowdown the station causes on its
// following run. Sorted biggest impact at top. The single
// biggest-impact bar is coral-tinted (your weakness); the single
// lowest-impact bar is success-green (your strongest recovery).
//
// Each bar has a sample-count badge ("4 races") so the athlete
// can see how confident the average is. <3 samples doesn't render
// here — too noisy. The visibility helper enforces 3+ races as
// the parent gate.
//
// Guarded `#if !os(watchOS)`.
#if !os(watchOS)
struct EngineImpactView: View {

    let races: [Race]

    private var impacts: [RaceStats.StationImpact] {
        // Filter to entries with at least 2 samples — single-race
        // averages on a per-station basis are essentially raw
        // observations, not aggregates. The parent should already
        // gate on overall race count (3+), but this is the
        // per-station floor.
        RaceStats.crossRaceCompromisedAnalysis(among: races)
            .filter { $0.sampleCount >= 2 }
    }

    private var weakest: RaceStats.StationImpact? {
        impacts.first  // sorted desc
    }

    private var strongest: RaceStats.StationImpact? {
        impacts.last
    }

    // Visibility helper for the parent. Requires 3+ finished
    // races so the cross-race aggregate has any meaning at all.
    static func shouldShow(in races: [Race]) -> Bool {
        let finished = races.filter(\.isFinished).count
        guard finished >= 3 else { return false }
        return !RaceStats.crossRaceCompromisedAnalysis(among: races)
            .filter { $0.sampleCount >= 2 }
            .isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            if !impacts.isEmpty {
                bars
                summaryFootnote
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Bars

    // Each station's row: station label on the left, bar in the
    // middle, percentage + sample count on the right. Bar length
    // proportional to the row's avg % vs the LARGEST avg in the
    // set so the biggest impact always hits full width — gives
    // the visual a clear "your worst is here" signal even when
    // absolute slowdowns are small.
    private var bars: some View {
        let maxImpact = impacts.first?.avgPercentSlower ?? 1
        return VStack(spacing: 10) {
            ForEach(impacts, id: \.station) { impact in
                row(for: impact, maxImpact: maxImpact)
            }
        }
    }

    private func row(
        for impact: RaceStats.StationImpact,
        maxImpact: Double
    ) -> some View {
        let color = barColor(for: impact)
        let fraction = maxImpact > 0
            ? CGFloat(impact.avgPercentSlower / maxImpact)
            : 0

        return HStack(spacing: 10) {
            Text(impact.station.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Bar track + filled bar. Track gives a visual scale
            // even when the bar itself is short.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfaceElevated)
                        .frame(height: 10)

                    Capsule()
                        .fill(color)
                        .frame(
                            width: max(geo.size.width * fraction, 4),
                            height: 10
                        )
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(impact.avgPercentSlower.rounded()))%")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text("\(impact.sampleCount) race\(impact.sampleCount == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 56, alignment: .trailing)
        }
    }

    // Color rule: the worst impact is coral (athlete's weakness),
    // the best is success green (their strongest recovery), the
    // middle band is warning orange (notable but not critical).
    // Ties on either end resolve to the warning color — defensive
    // against single-row results where weakest == strongest.
    private func barColor(for impact: RaceStats.StationImpact) -> Color {
        guard let weakest, let strongest, weakest != strongest else {
            return Color.warning
        }
        if impact == weakest { return Color.accent }
        if impact == strongest { return Color.success }
        return Color.warning
    }

    // MARK: - Summary footnote

    // Two-line caption below the bars naming the headline finding.
    // Coaching-diagnosis voice consistent with InsightGenerator
    // and the per-race CompromisedRunningView callout.
    private var summaryFootnote: some View {
        VStack(spacing: 4) {
            if let weakest, weakest.avgPercentSlower > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accent)
                    Text("Weakest recovery: ")
                        .foregroundStyle(Color.textSecondary)
                    + Text(weakest.station.displayName)
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.semibold)
                    + Text(" · prioritize bricks from here.")
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let strongest, strongest != weakest {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.success)
                    Text("Strongest recovery: ")
                        .foregroundStyle(Color.textSecondary)
                    + Text(strongest.station.displayName)
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.semibold)
                    + Text(" · your engine bounces back fastest.")
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif

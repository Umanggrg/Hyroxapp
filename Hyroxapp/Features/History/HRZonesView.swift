import SwiftUI

// Time-in-zone visualization for a race. A horizontal stacked bar
// where each segment's width is proportional to the time spent in
// that HR zone, plus a legend below pairing zone labels with their
// MM:SS time totals.
//
// Why a stacked bar (not a pie or donut): a single bar gives an
// immediate left-to-right read of "where did most of my race happen,
// HR-wise?" Pies hide proportions when zones are unevenly weighted;
// the stacked bar always shows magnitude even when one zone is tiny.
//
// Splits without HR data are skipped (see HRZone.timeInZones). If
// every split lacks HR data, the view returns an empty bar and
// `hasAnyZoneData(in:maxBPM:)` returns false so the caller can hide
// the section entirely.
struct HRZonesView: View {

    let splits: [Split]
    let maxBPM: Int

    // Drives the entrance animation — bar segments grow from 0 width
    // to their final share. Same pattern as EffortDistributionView's
    // stacked bar so the two zone-style charts feel like a coordinated
    // family.
    @State private var animationsRevealed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Pre-compute the totals once per render. SwiftUI re-evaluates
    // the body on every state change; if this were inside `body`
    // we'd be re-iterating splits on every redraw.
    private var totals: [HRZone: TimeInterval] {
        HRZone.timeInZones(splits: splits, maxBPM: maxBPM)
    }

    private var totalSeconds: TimeInterval {
        totals.values.reduce(0, +)
    }

    static func hasAnyZoneData(in splits: [Split], maxBPM: Int) -> Bool {
        !HRZone.timeInZones(splits: splits, maxBPM: maxBPM).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stackedBar
            legend
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .animation(
            reduceMotion ? .none : .smooth(duration: 0.7),
            value: animationsRevealed
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animationsRevealed = true
            }
        }
    }

    // MARK: - Stacked bar

    // Single horizontal bar split into 1–5 colored segments
    // proportional to time-in-zone. We render each zone with width
    // = (zoneSeconds / totalSeconds) * containerWidth via
    // GeometryReader so the bar fills whatever horizontal space the
    // parent gives us.
    private var stackedBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                // Iterate zones in numeric order so the bar reads
                // Z1 → Z5 left to right (cool → hot).
                ForEach(HRZone.allCases, id: \.rawValue) { zone in
                    if let seconds = totals[zone], seconds > 0 {
                        Rectangle()
                            .fill(zone.color)
                            .frame(
                                width: animationsRevealed
                                    ? width(for: seconds, in: proxy.size.width)
                                    : 0
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 14)
    }

    private func width(for seconds: TimeInterval, in totalWidth: CGFloat) -> CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return totalWidth * CGFloat(seconds / totalSeconds)
    }

    // MARK: - Legend

    // Two-column legend: zone color dot + label on the left, time
    // value on the right. Only rows with >0 time render — skipping
    // empty zones keeps the legend tight (a typical HYROX race only
    // touches 2–3 zones, not all 5).
    private var legend: some View {
        VStack(spacing: 6) {
            ForEach(HRZone.allCases, id: \.rawValue) { zone in
                if let seconds = totals[zone], seconds > 0 {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(zone.color)
                            .frame(width: 8, height: 8)
                        Text(zone.displayName)
                            .font(.caption)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(RaceStats.format(seconds))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }
}

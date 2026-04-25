import SwiftUI

// "Progressive overload" callouts on Profile — auto-generated
// sentence-style insights about which stations are trending up or
// down across recent races. Strava's "fitness summary" equivalent
// for HYROX. Reads like a coach's recap:
//
//   • "Your Sled Pull is trending 12% faster over the last 5 races"
//     (improving — green up arrow)
//   • "Your Wall Balls have slowed 8% over the last 6 races"
//     (declining — orange down arrow)
//
// Plateaued stations are intentionally omitted. The callout is
// signal-only — empty space when nothing's moving says "you're
// holding steady" without being said.
//
// Hidden entirely when no station has a meaningful trend yet —
// either because there aren't enough attempts or every station is
// plateaued. Same `shouldShow` pattern used elsewhere.
//
// Guarded `#if !os(watchOS)` because RaceStats helpers are
// iOS-only.
#if !os(watchOS)
struct PerformanceOverloadView: View {

    let races: [Race]

    // Stations + their detected trends. Computed once per render.
    // Filters to only the meaningful ones (improving / declining)
    // so the view reads as a curated list, not a wall of "no
    // change" rows.
    private var meaningfulTrends: [(station: Station, direction: RaceStats.TrendDirection)] {
        Station.canonicalPickerOptions.compactMap { station in
            let direction = RaceStats.stationTrendDirection(
                for: station,
                among: races
            )
            return direction.isMeaningful ? (station, direction) : nil
        }
        // Sort biggest movers first so the most exciting changes
        // (whether positive or negative) lead. Athletes care more
        // about the standout stations than tiny shifts.
        .sorted { lhs, rhs in
            magnitude(of: lhs.1) > magnitude(of: rhs.1)
        }
    }

    // Visibility helper for the parent — hide the section when
    // there's nothing meaningful to say.
    static func hasMeaningfulTrends(in races: [Race]) -> Bool {
        Station.canonicalPickerOptions.contains { station in
            RaceStats.stationTrendDirection(for: station, among: races).isMeaningful
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(meaningfulTrends.enumerated()), id: \.offset) { index, item in
                row(for: item.station, direction: item.direction)
                if index < meaningfulTrends.count - 1 {
                    Divider().background(Color.divider)
                }
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Single row: arrow icon + station name + trend sentence. Color-
    // coded green for improving, warning orange for declining. Same
    // visual idiom as the per-split delta on RaceDetailView so the
    // two surfaces feel related.
    private func row(for station: Station, direction: RaceStats.TrendDirection) -> some View {
        let isImproving = isImproving(direction)
        let percentText = percentText(direction)

        return HStack(spacing: 12) {
            Image(systemName: isImproving ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isImproving ? Color.success : Color.warning)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(isImproving
                     ? "Trending \(percentText) faster"
                     : "Slowing \(percentText) recently")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Text(percentText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isImproving ? Color.success : Color.warning)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Trend helpers

    // Pull the unsigned magnitude of a direction so we can sort by
    // "biggest mover first" regardless of sign.
    private func magnitude(of direction: RaceStats.TrendDirection) -> Double {
        switch direction {
        case .improving(let pct), .declining(let pct):
            return pct
        case .plateau:
            return 0
        }
    }

    private func isImproving(_ direction: RaceStats.TrendDirection) -> Bool {
        if case .improving = direction { return true }
        return false
    }

    private func percentText(_ direction: RaceStats.TrendDirection) -> String {
        switch direction {
        case .improving(let pct), .declining(let pct):
            // Round to whole percentage points — fractional changes
            // (4.7% vs 5%) read as noise, integers read as facts.
            return "\(Int(pct.rounded()))%"
        case .plateau:
            return ""
        }
    }
}
#endif

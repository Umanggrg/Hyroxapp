import SwiftUI

// HYROX Performance Score panel on Profile — three pillar tiles
// (Strength / Endurance / Engine) showing the athlete's theoretical-
// best total time per pillar. The headline read is "across my best
// performances at every station, what does each part of my game
// actually look like?"
//
// Self-relative metric: needs no benchmarks, no community data, no
// backend. Updates automatically as the athlete sets new station
// PBs (because pillar totals are derived from all-time bests).
//
// Hidden when no pillar has any data. Partial coverage (e.g. you've
// done sled push but never wall balls) renders the pillar with a
// "2 of 4 stations" subtitle so the time isn't read as authoritative.
struct HyroxPerformanceScoreView: View {

    let races: [Race]

    var body: some View {
        if hasAnyData {
            grid
        } else {
            EmptyView()
        }
    }

    // True when at least one pillar has at least one station
    // covered. False on a brand-new install with no finished races.
    static func hasAnyData(in races: [Race]) -> Bool {
        HyroxPillar.allCases.contains { pillar in
            RaceStats.pillarTheoreticalBest(pillar, among: races) != nil
        }
    }

    private var hasAnyData: Bool {
        Self.hasAnyData(in: races)
    }

    // 3-up horizontal grid of pillar tiles. Equal-width columns
    // via `LazyVGrid` flexible items so the tile widths adjust to
    // screen width automatically.
    private var grid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 0),
                count: HyroxPillar.allCases.count
            ),
            spacing: 0
        ) {
            ForEach(HyroxPillar.allCases) { pillar in
                tile(for: pillar)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Single pillar tile: hero time on top, caps-style label
    // below, and a small "X of Y" coverage subtitle when not all
    // stations in the pillar have data yet.
    private func tile(for pillar: HyroxPillar) -> some View {
        let best = RaceStats.pillarTheoreticalBest(pillar, among: races)
        let coverage = RaceStats.pillarStationsCovered(pillar, among: races)
        let isPartial = coverage.covered < coverage.total

        return VStack(spacing: 6) {
            Text(best.map(RaceStats.format) ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pillar.color)

            Text(pillar.displayName)
                .capsLabelStyle()

            // Coverage subtitle is only useful when partial — when
            // all stations are covered it'd just be visual noise.
            if isPartial && best != nil {
                Text("\(coverage.covered) of \(coverage.total)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            } else if best == nil {
                // Empty pillar — show a quiet "no data yet" cue
                // so the tile isn't blank.
                Text("no data")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

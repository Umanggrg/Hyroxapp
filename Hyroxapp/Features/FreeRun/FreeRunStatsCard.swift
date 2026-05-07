import SwiftUI

#if canImport(UIKit)

// Aggregate Free Run stats card for Profile.
//
// Three-up tile layout — total runs, total distance, longest run.
// Same `StatsGridView`-style anatomy as the existing race aggregate
// cards, just bound to FreeRun rows instead of Race rows.
//
// Renders nothing (returns EmptyView) when the user has zero free
// runs — saves Profile-screen real estate for the HYROX-shaped
// content that always exists. Once the first free run lands, the
// card slides into the Profile feed.
struct FreeRunStatsCard: View {

    let runs: [FreeRun]

    // Whether the card has anything to show. Bound to the
    // existence check at the call site so the parent's layout
    // can hide the section header along with the card.
    static func hasData(_ runs: [FreeRun]) -> Bool {
        runs.contains { $0.isFinished }
    }

    var body: some View {
        let finishedRuns = runs.filter { $0.isFinished }

        if finishedRuns.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Running",
                    icon: "figure.run"
                )

                HStack(spacing: 8) {
                    statTile(
                        label: "RUNS",
                        value: "\(finishedRuns.count)",
                        unit: ""
                    )
                    statTile(
                        label: "TOTAL",
                        value: totalDistanceString(for: finishedRuns),
                        unit: dominantUnit(for: finishedRuns).shortLabel
                    )
                    statTile(
                        label: "LONGEST",
                        value: longestDistanceString(for: finishedRuns),
                        unit: dominantUnit(for: finishedRuns).shortLabel
                    )
                }
            }
        }
    }

    // MARK: - Tiles

    private func statTile(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Aggregations

    // Pick the unit that more of the user's runs were logged in.
    // Free Run lets the athlete pick mile or km on each start, so
    // a mixed history is plausible. Surfacing the dominant unit
    // means the card doesn't flip between mi/km depending on
    // which run was last edited. Tie-breaks to mile (US default).
    private func dominantUnit(for runs: [FreeRun]) -> FreeRunSplitUnit {
        let mileCount = runs.filter { $0.splitUnit == .mile }.count
        let kmCount = runs.count - mileCount
        return mileCount >= kmCount ? .mile : .km
    }

    private func totalDistanceString(for runs: [FreeRun]) -> String {
        let totalMetres = runs.reduce(0.0) { $0 + $1.distanceMetres }
        let units = totalMetres / dominantUnit(for: runs).metresPerUnit
        return String(format: "%.1f", units)
    }

    private func longestDistanceString(for runs: [FreeRun]) -> String {
        let longest = runs.map(\.distanceMetres).max() ?? 0
        let units = longest / dominantUnit(for: runs).metresPerUnit
        return String(format: "%.1f", units)
    }
}

#endif

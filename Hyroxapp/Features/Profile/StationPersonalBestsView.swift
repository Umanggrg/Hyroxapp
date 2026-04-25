import SwiftUI

// Personal Bests panel — one card on Profile listing every canonical
// HYROX station type with the athlete's all-time best split duration
// for that station. Equivalent to Strava's "PR Times" but per HYROX
// station instead of per running distance.
//
// Data shape: receives the full list of finished races and computes
// the best split per station type at render time. Computation is
// O(splits × 9) which is trivial at any reasonable history size and
// keeps the view stateless / easy to reason about.
//
// The eight run cases collapse into one "1km Run" row — see
// `RaceStats.allTimeBest(for:among:)` for the kind-aware aggregation.
struct StationPersonalBestsView: View {

    let races: [Race]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Personal Bests").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let stations = Station.canonicalPickerOptions
                ForEach(Array(stations.enumerated()), id: \.offset) { index, station in
                    pbRow(for: station)
                    if index < stations.count - 1 {
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
    }

    // One row per station type. Left column = display name; right
    // column = best duration in MM:SS via shared formatter, or an
    // em-dash placeholder when the athlete hasn't completed that
    // station in any finished race yet.
    private func pbRow(for station: Station) -> some View {
        HStack {
            Text(station.displayName)
                .font(.body)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let best = RaceStats.allTimeBest(for: station, among: races) {
                Text(RaceStats.format(best.duration))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            } else {
                Text("—")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 8)
    }
}

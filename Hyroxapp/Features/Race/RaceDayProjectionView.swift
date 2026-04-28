import SwiftUI

// Race-level "if you'd been at race weight today" projection.
// Sums actual durations for stations already at race weight and
// projected durations (via linear scaling) for stations logged
// under race weight. The single coaching number that answers
// "what's my fitness level at the official setup?"
//
// Shipped on top of the per-station projection that already lives
// on StationDetailView. The per-station view tells the athlete
// where they're losing time at sub-weight; this rollup tells
// them what the race would total if every station carried full
// race weight.
//
// Hidden when:
//   • Race isn't finished (projection requires complete data)
//   • No stations had a sub-race-weight projection — every station
//     was already at race weight, in which case the actual total
//     IS the projection and showing it would be redundant noise
//
// Visual sibling of TargetOutcomeView and RecoveryEstimateView —
// caps "Projection" header, hero coral number, subtitle anchoring
// the data ("based on N stations under race weight"). Sits in the
// summary scroll alongside the other coaching readouts so the
// post-race story reads as a coherent set of cards.
//
// Guarded `#if !os(watchOS)` because Race / Division aren't on the
// watch target.
#if !os(watchOS)
struct RaceDayProjectionView: View {

    let race: Race
    let division: Division

    private var projection: TimeInterval? {
        RaceStats.raceDayProjectedTotal(for: race, division: division)
    }

    private var stationCount: Int {
        RaceStats.raceDayProjectionStationCount(for: race, division: division)
    }

    // Difference between projected and actual. Positive = projected
    // is longer than actual (athlete was under-weight, race-day
    // would've been slower). Always positive in practice because
    // we never project downward (over-weight athletes get nil).
    private var delta: TimeInterval? {
        guard let projection, let actual = race.totalDuration else { return nil }
        return projection - actual
    }

    var body: some View {
        if let projection {
            content(projection: projection)
        } else {
            EmptyView()
        }
    }

    private func content(projection: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Race-day projection").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accent.opacity(0.16))
                            .frame(width: 44, height: 44)
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(RaceStats.format(projection))
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(Color.textPrimary)

                        if let delta, delta > 0 {
                            Text("+\(RaceStats.format(delta)) at race weight")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.warning)
                        }
                    }

                    Spacer()
                }

                Text(stationCount == 1
                    ? "Based on 1 station logged under race weight."
                    : "Based on \(stationCount) stations logged under race weight."
                )
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(Color.accent.opacity(0.20), lineWidth: 1)
            )
        }
    }
}
#endif

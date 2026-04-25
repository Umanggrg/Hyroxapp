import SwiftUI

// "Race-ready" check on Profile — for each weighted HYROX station,
// shows whether the athlete has logged at least one finished split
// AT race-day weight for their division. The killer HYROX-specific
// feature: a 4:32 sled push at 80kg and a 4:32 at 152kg are
// different universes, and other HYROX-adjacent apps don't surface
// the gap. This view does.
//
// Anatomy:
//   • Header: "X of 6 stations race-ready" (counter)
//   • Grid: 6 station tiles, each green-tinted when ready, dim
//     when not. Tap a tile to see what weight to log.
//
// Six weighted stations: Sled Push, Sled Pull, Farmers Carry,
// Sandbag Lunges, Wall Balls, plus one more for layout? Actually
// HYROX has 5 weighted workout stations (the 8 workouts include
// 3 bodyweight: Ski Erg, Burpees, Rowing — 8 minus 3 = 5). So 5
// tiles, not 6. Let the layout flow with the data.
//
// Hidden by the parent until the user has at least 1 finished
// race — no point showing 5 grey tiles on a fresh install.
//
// Guarded `#if !os(watchOS)`.
#if !os(watchOS)
struct RaceReadyView: View {

    let races: [Race]
    let division: Division

    // Weighted-workout stations only — runs and ergs (Ski / Row
    // / Burpees) have no race weight. Order matches HYROX race
    // sequence so the tiles read intuitively.
    private static let weightedStations: [Station] = [
        .sledPush,
        .sledPull,
        .farmersCarry,
        .sandbagLunges,
        .wallBalls
    ]

    // Visibility helper for parent.
    static func shouldShow(in races: [Race]) -> Bool {
        races.contains(where: { $0.isFinished })
    }

    private var readyCount: Int {
        Self.weightedStations.filter { isReady($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Race-Ready")
                    .capsLabelStyle()
                Spacer()
                Text("\(readyCount) of \(Self.weightedStations.count)")
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(
                        readyCount == Self.weightedStations.count
                            ? Color.success
                            : Color.textTertiary
                    )
            }
            .padding(.horizontal, 4)

            grid
        }
    }

    // 5-tile flexible grid. On phone widths the tiles end up
    // ~roughly 2 columns × 3 rows (with one row of 1 to fill
    // out). LazyVGrid with 2 columns gives the cleanest layout
    // for 5 items.
    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(Self.weightedStations, id: \.self) { station in
                tile(for: station)
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Single tile: station name, race weight requirement, ready/
    // not-ready visual state.
    private func tile(for station: Station) -> some View {
        let ready = isReady(station)
        let raceWeight = division.raceWeight(for: station)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(station.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ready ? Color.success : Color.textTertiary)
            }

            if let weight = raceWeight {
                Text(format(weight: weight) + perHandSuffix(for: station))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ready ? Color.success : Color.textPrimary)
            }

            // Best logged weight at this station — reassures the
            // athlete that progress is being measured even when
            // they haven't hit race weight yet. "Best: 100kg"
            // means they've gotten that far. Hidden when no
            // finished splits at this station yet.
            if let bestLogged = bestLoggedWeight(for: station) {
                Text("Best logged: \(format(weight: bestLogged))")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Not logged yet")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ready ? Color.success.opacity(0.10) : Color.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            ready ? Color.success.opacity(0.4) : Color.divider,
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Logic

    // True when the athlete has at least one finished split for
    // this station type with `weightKg` matching the division
    // race weight (within ±0.5kg tolerance for floating-point
    // safety).
    private func isReady(_ station: Station) -> Bool {
        guard let raceWeight = division.raceWeight(for: station) else {
            return true  // no weight required → trivially ready
        }
        return races
            .filter(\.isFinished)
            .flatMap(\.splits)
            .contains { split in
                guard split.station == station,
                      let logged = split.weightKg
                else { return false }
                return abs(logged - raceWeight) < 0.5
            }
    }

    // Heaviest weight ever logged at this station type across
    // all finished races. Drives the "Best logged: 100kg" line.
    // Returns nil when nothing's been logged yet.
    private func bestLoggedWeight(for station: Station) -> Double? {
        races
            .filter(\.isFinished)
            .flatMap(\.splits)
            .compactMap { split -> Double? in
                guard split.station == station else { return nil }
                return split.weightKg
            }
            .max()
    }

    private func format(weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight)) kg"
        }
        return String(format: "%.1f kg", weight)
    }

    private func perHandSuffix(for station: Station) -> String {
        Division.isPerHandStation(station) ? "/hand" : ""
    }
}
#endif

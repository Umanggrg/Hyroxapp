import SwiftUI

// §43 Phase 2 — station-aware "Work Output" card on
// StationDetailView.
//
// Answers the question that's adjacent to but distinct from
// the HR layer: "what did I actually DO at this station?"
//
// HR card answers physiology (how hard did it feel?). This
// card answers mechanics (cadence / pace / output / load).
// Together they bracket the post-station story.
//
// Renders different metrics depending on the station type
// because the relevant work-output number differs:
//
//   • Run                       Pace (min/km) + AirPods running
//                               economy (vertical osc + ground
//                               contact when available)
//   • Ergs (Ski / Row, 1000m)   Pace (m/s) + canonical 500m split
//   • Distance workouts         Pace (m/s) — sled push 50m,
//                               sled pull 50m, burpee BJ 80m,
//                               farmers carry 200m, lunges 100m
//   • Wall Balls                Cadence (rpm) when reps logged
//   • Manual fields (any)       Weight, Reps, RPE if entered
//
// Self-hides when nothing renders — e.g. a sled push split
// with no manual log and no run-style sensor data would only
// show pace. Pace alone is meaningful enough to keep the card
// visible (it's the station's primary derived metric), so the
// hide threshold is "no station-relevant signal at all," which
// in practice means we always render for shipped stations.
//
// Layout: caps section header, then a horizontal scroll of
// uniform tiles. Each tile is `StationOutputTile` — value,
// unit, label. Same visual register as the existing
// physiology card's tile row.
#if !os(watchOS)
struct StationWorkOutputCard: View {

    let split: Split

    // MARK: - Body

    var body: some View {
        let tiles = derivedTiles()
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Work Output",
                    icon: "bolt.fill"
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(outputCaption)
                            .capsLabelStyle()
                        Spacer()
                        Text(split.station.target)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, 4)

                    // Tiles wrap to 2 rows if needed via a 3-up
                    // grid — uniform column widths so the visual
                    // rhythm matches the physiology card row.
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(tiles, id: \.label) { tile in
                            outputTile(tile)
                        }
                    }
                }
            }
        }
    }

    // Caps label that describes the dominant output metric for
    // this station kind. Reads more naturally than the generic
    // "Work Output" header above ("Pace" / "Cadence" / "Running
    // Economy") and disambiguates when multiple tiles render.
    private var outputCaption: String {
        switch split.station {
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            return "Running Economy"
        case .skiErg, .rowing:
            return "Erg Output"
        case .wallBalls:
            return "Rep Cadence"
        default:
            return "Work Pace"
        }
    }

    // MARK: - Derived data

    // Lightweight value type holding one row of tile content.
    // Existence-of-tile gates on whether the underlying field
    // is non-nil so we don't render "—" placeholders for data
    // that wasn't captured.
    private struct OutputTile {
        let label: String
        let value: String
        let unit: String?
    }

    private func derivedTiles() -> [OutputTile] {
        var tiles: [OutputTile] = []

        // Pace / cadence tier — the primary mechanical metric
        // for this station type. Always renders.
        if let primary = primaryOutputTile() {
            tiles.append(primary)
        }

        // Secondary mechanical tiers — station-specific.
        tiles.append(contentsOf: secondaryOutputTiles())

        // Manual-entry tier — weight / reps / RPE if the
        // athlete bothered to log them. These ride along on
        // EVERY station card when set, since they're useful
        // independently of the auto-derived metrics.
        tiles.append(contentsOf: manualEntryTiles())

        return tiles
    }

    // Primary output: pace m/s, pace min/km, or cadence rpm.
    private func primaryOutputTile() -> OutputTile? {
        switch split.station.kind {
        case .run:
            return paceMinPerKMTile()
        case .workout:
            // Wall balls — primary is cadence when reps logged,
            // pace otherwise.
            if split.station == .wallBalls, let reps = split.repsCompleted, reps > 0 {
                return cadenceTile(reps: reps)
            }
            return paceMpsTile()
        }
    }

    // Secondary metrics — split-per-500m for ergs, vertical
    // osc + ground contact for runs.
    private func secondaryOutputTiles() -> [OutputTile] {
        var tiles: [OutputTile] = []

        switch split.station {
        case .skiErg, .rowing:
            if let split500 = split500mTile() {
                tiles.append(split500)
            }
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            // AirPods running economy — already captured on
            // Split when AirPods Pro 1+ / 4 / Max were in the
            // route. Renders prominently here so the run cards
            // have a real "running economy" story instead of
            // burying these in a footnote.
            if let osc = split.verticalOscCmAvg {
                tiles.append(OutputTile(
                    label: "VERTICAL OSC",
                    value: String(format: "%.1f", osc),
                    unit: "cm"
                ))
            }
            if let gct = split.groundContactTimeMsAvg {
                tiles.append(OutputTile(
                    label: "GND CONTACT",
                    value: "\(Int(gct.rounded()))",
                    unit: "ms"
                ))
            }
        case .sandbagLunges:
            // Lunge cadence (lunges/min) when reps logged.
            if let reps = split.repsCompleted, reps > 0, split.duration > 0 {
                let rate = Double(reps) / (split.duration / 60)
                tiles.append(OutputTile(
                    label: "LUNGE RATE",
                    value: String(format: "%.0f", rate),
                    unit: "/min"
                ))
            }
        default:
            break
        }

        return tiles
    }

    // Manual-entry tier. Renders only the fields that were
    // actually logged — no "—" placeholders.
    private func manualEntryTiles() -> [OutputTile] {
        var tiles: [OutputTile] = []

        if let weight = split.weightKg, weight > 0 {
            tiles.append(OutputTile(
                label: "WEIGHT",
                value: "\(Int(weight.rounded()))",
                unit: "kg"
            ))
        }
        // Reps tile — only for stations where the rep count is
        // the primary work unit, AND only when it wasn't
        // already encoded in the cadence tile (Wall Balls).
        // Showing both "Reps 100" and "Cadence 23 rpm" on Wall
        // Balls is redundant.
        if split.station != .wallBalls,
           let reps = split.repsCompleted, reps > 0 {
            tiles.append(OutputTile(
                label: "REPS",
                value: "\(reps)",
                unit: nil
            ))
        }
        if let rpe = split.rpe, rpe > 0 {
            tiles.append(OutputTile(
                label: "RPE",
                value: "\(rpe)",
                unit: "/10"
            ))
        }

        return tiles
    }

    // MARK: - Specific tile builders

    // Pace in min:ss / km for runs. Run station is always 1000m
    // so the math is duration directly.
    private func paceMinPerKMTile() -> OutputTile? {
        guard split.duration > 0 else { return nil }
        let totalSeconds = Int(split.duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return OutputTile(
            label: "PACE",
            value: String(format: "%d:%02d", minutes, seconds),
            unit: "/km"
        )
    }

    // Pace in m/s for workout stations with known distances.
    // Useful coaching read because the m/s number doesn't mean
    // much in isolation but normalises across station types so
    // an athlete can compare "I moved at 1.6 m/s on sled push
    // but 2.1 m/s on farmers carry."
    private func paceMpsTile() -> OutputTile? {
        guard let metres = stationDistanceMetres,
              split.duration > 0 else { return nil }
        let mps = metres / split.duration
        return OutputTile(
            label: "PACE",
            value: String(format: "%.2f", mps),
            unit: "m/s"
        )
    }

    // Canonical erg metric — duration of one 500m chunk. The
    // 1000m row / ski erg has TWO 500m chunks, so split500 is
    // half the duration. This is the number rowers /
    // ergometers see everywhere — "I pulled 1:51/500m."
    private func split500mTile() -> OutputTile? {
        guard split.station == .skiErg || split.station == .rowing,
              split.duration > 0 else { return nil }
        let split500 = split.duration / 2
        let mins = Int(split500) / 60
        let secs = Int(split500) % 60
        return OutputTile(
            label: "SPLIT /500",
            value: String(format: "%d:%02d", mins, secs),
            unit: nil
        )
    }

    // Wall ball cadence — reps per minute. Calling out as
    // "RPM" matches CrossFit / HYROX coaching lingo.
    private func cadenceTile(reps: Int) -> OutputTile {
        let rpm = Double(reps) / (split.duration / 60)
        return OutputTile(
            label: "CADENCE",
            value: String(format: "%.0f", rpm),
            unit: "rpm"
        )
    }

    // Canonical HYROX station distances. Runs are 1km. Ergs are
    // 1000m. Workout stations carry their distance on the
    // station's `target` string — but for math we need the
    // numeric value.
    private var stationDistanceMetres: Double? {
        switch split.station {
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            return 1000
        case .skiErg, .rowing:
            return 1000
        case .sledPush, .sledPull:
            return 50
        case .burpeeBroadJumps:
            return 80
        case .farmersCarry:
            return 200
        case .sandbagLunges:
            return 100
        case .wallBalls:
            return nil // rep-based, not distance
        }
    }

    // MARK: - Tile renderer

    private func outputTile(_ tile: OutputTile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(tile.value)
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = tile.unit {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text(tile.label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceElevated)
        )
    }
}
#endif

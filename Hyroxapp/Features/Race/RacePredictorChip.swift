import SwiftUI

// Compact pre-race finish predictor chip per §17.5. Renders
// above the Start button on RaceStartView when the athlete has
// at least one prior finished race; hidden silently for
// first-race users.
//
// Reads:
//
//   ┌──────────────────────────────────────┐
//   │  PREDICTED FINISH                    │
//   │  1:27:32  ± 3:00                     │
//   │  Engine 78 · Steady · Trend Stable   │
//   └──────────────────────────────────────┘
//
// The number is the prediction; the ± band is the σ window
// from the recent baseline. The driver line under it surfaces
// the model's reasoning so the prediction doesn't read as
// magic — the athlete sees what's pulling the number up or
// down from their raw average.
//
// Tappable in v1.5 to push a sheet with deeper breakdown;
// for now the chip is read-only.
struct RacePredictorChip: View {

    let races: [Race]
    let division: Division
    let maxHR: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var prediction: RaceStats.PredictedFinish? {
        RaceStats.predictedFinish(
            across: races,
            division: division,
            maxHR: maxHR
        )
    }

    static func hasEnoughData(in races: [Race], division: Division, maxHR: Int) -> Bool {
        RaceStats.predictedFinish(
            across: races,
            division: division,
            maxHR: maxHR
        ) != nil
    }

    var body: some View {
        if let prediction {
            chip(for: prediction)
        } else {
            EmptyView()
        }
    }

    private func chip(for prediction: RaceStats.PredictedFinish) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Caps strap header — same caps-label vocabulary
            // used elsewhere on the app for section headers.
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.caption2.weight(.heavy))
                Text("PREDICTED FINISH")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.accent)

            // Predicted time + ± band. Time is monospaced rounded
            // so it reads like the timer hero on the race screen.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(RaceStats.format(prediction.predicted))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                Text("± \(formatBand(prediction))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }

            // Driver chips — small inline list of what's
            // pulling the prediction up/down. Hidden when no
            // drivers are available (first-race-with-data
            // case).
            if !prediction.drivers.isEmpty {
                FlowingDriversRow(drivers: prediction.drivers)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func formatBand(_ prediction: RaceStats.PredictedFinish) -> String {
        let band = prediction.upperBound - prediction.predicted
        let total = Int(band.rounded())
        let mins = total / 60
        let secs = total % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(secs)s"
    }
}

// Wrapping row of driver chips. Each driver renders as a small
// pill with a directional glyph (down arrow = accelerating /
// up arrow = braking / equal = neutral) + label.
private struct FlowingDriversRow: View {
    let drivers: [RaceStats.PredictedFinish.Driver]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(drivers.enumerated()), id: \.offset) { _, driver in
                driverPill(driver)
            }
        }
    }

    private func driverPill(_ driver: RaceStats.PredictedFinish.Driver) -> some View {
        let (glyph, color): (String, Color) = {
            switch driver.modifier {
            case .accelerating: return ("arrow.down", .success)
            case .braking:      return ("arrow.up", .warning)
            case .neutral:      return ("equal", .textTertiary)
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 8, weight: .heavy))
            Text(driver.detail)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

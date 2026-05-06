import SwiftUI

// "Who you are as a racer at the station level."
//
// Each row is one station (or all 8 runs pooled). Reads:
//
//   ┌─────────────────────────────────────────┐
//   │  Sled Push    ▇▇▇▇▇░░  178 bpm   +6 ↑  │
//   │  Wall Balls   ▇▇▇░░░░  152 bpm   -3 ↓  │
//   │  Runs         ▇▇▇▇░░░  165 bpm    0    │
//   └─────────────────────────────────────────┘
//
// Median HR is the "your usual" anchor; recent delta is the
// recent-N-races average minus the median. Tendency tints the
// delta — cool (green, running below usual), typical (neutral),
// hot (amber/coral, running above usual).
//
// The bar is a visual band showing where the recent average
// sits inside the historical IQR — a quick-glance "is this in
// the typical band or out at the edges?" affordance.
//
// Coaching value: athletes can spot patterns at a glance —
// "sled push always runs hot for me" / "rowing always cools me
// down" — that the per-race chip on StationDetailView can't
// surface. Surfaces the §18 Pillar 1 (Fatigue Fingerprint)
// flavor at the station level, paired with the broader
// Engine Score rollup nearby.
//
// Hidden when fewer than 3 historical samples exist for any
// station (matches the underlying StationHRSignature minimum).
struct StationFingerprintView: View {

    let races: [Race]
    let maxHR: Int

    private var tendencies: [RaceStats.StationHRTendency] {
        RaceStats.stationHRTendencies(across: races)
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        !RaceStats.stationHRTendencies(across: races).isEmpty
    }

    var body: some View {
        if !tendencies.isEmpty {
            card
        } else {
            EmptyView()
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(tendencies) { tendency in
                row(for: tendency)
                if tendency.id != tendencies.last?.id {
                    Divider()
                        .background(Color.divider)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func row(for tendency: RaceStats.StationHRTendency) -> some View {
        HStack(spacing: 10) {
            // Station label — left-aligned, fixed width so the
            // bars + numbers below line up across rows.
            Text(tendency.stationKey.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Tendency bar — IQR band + recent-average tick.
            // Reads quickly: tick inside the band = typical,
            // tick at the edges = running cool/hot.
            tendencyBar(for: tendency)
                .frame(maxWidth: .infinity)
                .frame(height: 14)

            // Median HR — the "your usual" anchor.
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(tendency.medianHR.rounded()))")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("bpm")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 42, alignment: .trailing)

            // Delta with directional glyph. Tinted by tendency
            // so a glance reads the color first ("this row is
            // hot/cool/typical") before the number.
            HStack(spacing: 2) {
                Image(systemName: deltaGlyph(tendency.tendency))
                    .font(.system(size: 9, weight: .heavy))
                Text(formattedDelta(tendency.recentDelta))
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(deltaTint(tendency.tendency))
            .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 10)
    }

    // The IQR band with a recent-average tick. The bar's
    // visible area represents the IQR (Q1 to Q3) of historical
    // HR for that station — anything in this range reads as
    // "typical." A single tick inside the bar shows where the
    // recent N races' average HR sits relative to that band.
    private func tendencyBar(for tendency: RaceStats.StationHRTendency) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track — full-width rounded line that
                // visually represents the typical IQR.
                Capsule()
                    .fill(Color.divider.opacity(0.4))

                // Filled portion — the IQR band itself in the
                // tendency tint at low opacity. Reads as the
                // "typical zone" the athlete usually lives in.
                Capsule()
                    .fill(deltaTint(tendency.tendency).opacity(0.35))

                // Recent-average tick — the diamond marker
                // showing where the athlete's recent races
                // sit inside (or outside) the band.
                let xPos = tickPosition(for: tendency, width: geo.size.width)
                Circle()
                    .fill(deltaTint(tendency.tendency))
                    .frame(width: 8, height: 8)
                    .offset(x: xPos - 4)
            }
        }
    }

    // Map the recent-average HR to an x-position inside the
    // bar. The IQR (Q1 to Q3) maps to the central 60% of the
    // bar's width — values inside that range slot proportionally;
    // values outside extend toward the bar edges (clamped). This
    // gives the tick a clear "typical zone" to live inside while
    // letting "running hot" or "running cool" reach the edges
    // visually.
    private func tickPosition(
        for tendency: RaceStats.StationHRTendency,
        width: CGFloat
    ) -> CGFloat {
        let bandStart = width * 0.20
        let bandEnd = width * 0.80
        let bandWidth = bandEnd - bandStart

        let q1 = tendency.lowerQuartile
        let q3 = tendency.upperQuartile
        let range = q3 - q1

        guard range > 0 else { return width / 2 }

        // Linearly map [Q1...Q3] into the central band, then
        // extrapolate gently outside. Clamp to bar edges so the
        // tick never escapes the visible track.
        let normalized = (tendency.recentAverageHR - q1) / range
        let raw = bandStart + bandWidth * CGFloat(normalized)
        return min(max(raw, 4), width - 4)
    }

    private func formattedDelta(_ delta: Double) -> String {
        let rounded = Int(delta.rounded())
        if rounded > 0 { return "+\(rounded)" }
        if rounded < 0 { return "\(rounded)" }
        return "0"
    }

    private func deltaGlyph(_ tendency: RaceStats.StationHRTendency.Tendency) -> String {
        switch tendency {
        case .hot:     return "arrow.up"
        case .cool:    return "arrow.down"
        case .typical: return "equal"
        }
    }

    private func deltaTint(_ tendency: RaceStats.StationHRTendency.Tendency) -> Color {
        switch tendency {
        case .hot:     return .accent
        case .cool:    return .success
        case .typical: return .textSecondary
        }
    }
}

import SwiftUI
import Charts

// §50 — Station-specific deep dive for Sandbag Lunges.
//
// The novel surface in the app: L/R asymmetry detection
// derived purely from rep-time alternation. No gyro pattern
// matching, no sensor calibration — just the per-rep
// timestamps that §47a + §49 already capture.
//
// The logic: lunge segments alternate L/R by design (you can't
// take two lunges with the same leg). So consecutive reps in
// the timestamp series alternate sides. Bucket odd-indexed reps
// vs even-indexed reps and compute the per-bucket average cycle
// time. The DIFFERENCE between the two averages is the asymmetry
// signal — "your group-A leg is X.Xs faster than your group-B
// leg," surfaced as a coaching insight when the gap exceeds a
// meaningful threshold (~0.15s/rep).
//
// We don't claim to know which group is "left" and which is
// "right" — that requires gyro calibration we don't have today.
// Phase 51 could layer the labeling on if real-device testing
// shows the asymmetry signal is robust. For now the framing is
// "first-lead leg vs alternate leg" which is technically
// accurate and useful.
//
// Sections:
//   1. LUNGES (count) — auto-counted by §49 Z-axis latch.
//   2. CADENCE (lunges/min) — total / segment duration.
//   3. ASYMMETRY (signed Δ s/rep + tier classification:
//      symmetric / minor / significant).
//   4. Cadence-per-10m curve over the 100m segment.
//   5. First-lead vs alternate row — avg cycle time per group
//      with the signed delta and a coaching one-liner.
//
// Self-hides on every non-lunge station, and on lunge splits
// without per-rep timestamps (pre-§49 race, no Watch, detector
// didn't fire).
#if !os(watchOS)
struct StationLungeDetailSection: View {

    let split: Split

    // MARK: - Body

    var body: some View {
        if split.station == .sandbagLunges,
           let offsets = split.repTimestampOffsets,
           offsets.count >= 4 {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Lunge Output",
                    icon: "figure.cooldown"
                )
                VStack(spacing: 12) {
                    headlineRow(offsets: offsets)
                    cadenceCurveCard(offsets: offsets)
                    asymmetryRow(offsets: offsets)
                    asymmetryInsight(offsets: offsets)
                }
            }
        }
    }

    // MARK: - Headline row

    private func headlineRow(offsets: [TimeInterval]) -> some View {
        let asym = asymmetry(offsets: offsets)
        return HStack(spacing: 8) {
            tile(label: "LUNGES", value: "\(offsets.count)", unit: nil)
            tile(
                label: "CADENCE",
                value: String(format: "%.0f", meanCadence(offsets: offsets)),
                unit: "/min"
            )
            tile(
                label: "ASYMMETRY",
                value: String(format: "%.2f", abs(asym.deltaSec)),
                unit: "s/rep"
            )
        }
    }

    private func tile(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text(label)
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

    // MARK: - Cadence curve

    private func cadenceCurveCard(offsets: [TimeInterval]) -> some View {
        let buckets = cadenceBuckets(offsets: offsets)
        let mean = meanCadence(offsets: offsets)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CADENCE over the 100m")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            Chart {
                RuleMark(y: .value("Mean", mean))
                    .foregroundStyle(Color.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(buckets, id: \.bucketIndex) { bucket in
                    LineMark(
                        x: .value("Distance", bucket.midpointMetres),
                        y: .value("Rate", bucket.cadenceRpm)
                    )
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Distance", bucket.midpointMetres),
                        y: .value("Rate", bucket.cadenceRpm)
                    )
                    .foregroundStyle(Color.accent)
                    .symbolSize(28)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                    AxisValueLabel(format: Decimal.FormatStyle.number)
                        .foregroundStyle(Color.textTertiary)
                    AxisGridLine().foregroundStyle(Color.divider.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.textTertiary)
                    AxisGridLine().foregroundStyle(Color.divider.opacity(0.5))
                }
            }
            .chartXScale(domain: 0...100)
            .frame(height: 140)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // MARK: - Asymmetry row (first-lead vs alternate leg)

    private func asymmetryRow(offsets: [TimeInterval]) -> some View {
        let asym = asymmetry(offsets: offsets)
        return HStack(spacing: 8) {
            tile(
                label: "FIRST LEAD",
                value: String(format: "%.2f", asym.groupACycleSec),
                unit: "s/rep"
            )
            tile(
                label: "ALTERNATE",
                value: String(format: "%.2f", asym.groupBCycleSec),
                unit: "s/rep"
            )
            tile(
                label: "Δ",
                value: String(format: "%+.2f", asym.deltaSec),
                unit: "s/rep"
            )
        }
    }

    // MARK: - Asymmetry insight

    @ViewBuilder
    private func asymmetryInsight(offsets: [TimeInterval]) -> some View {
        let asym = asymmetry(offsets: offsets)
        let tier = asymmetryTier(absDeltaSec: abs(asym.deltaSec))
        if tier.shouldRender {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tier.symbol)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(tier.tint)
                    .padding(.top, 2)
                Text(tier.copy)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tier.tint.opacity(0.12))
            )
        }
    }

    // MARK: - Derivation helpers

    private func meanCadence(offsets: [TimeInterval]) -> Double {
        guard split.duration > 0 else { return 0 }
        return Double(offsets.count) / (split.duration / 60)
    }

    /// Bucket the reps into ten 10m chunks for the cadence curve.
    /// Time-based bucketing (assumes constant pace within 100m).
    private struct CadenceBucket: Equatable {
        let bucketIndex: Int
        let midpointMetres: Int  // 5, 15, 25 ... 95
        let cadenceRpm: Double
    }

    private func cadenceBuckets(offsets: [TimeInterval]) -> [CadenceBucket] {
        guard !offsets.isEmpty, split.duration > 0 else { return [] }
        let bucketCount = 10
        let bucketDurationSec = split.duration / Double(bucketCount)
        var counts = [Int](repeating: 0, count: bucketCount)
        for offset in offsets {
            let index = min(Int(offset / bucketDurationSec), bucketCount - 1)
            counts[index] += 1
        }
        return counts.enumerated().compactMap { idx, count in
            guard count > 0 else { return nil }
            let cadence = Double(count) / (bucketDurationSec / 60)
            return CadenceBucket(
                bucketIndex: idx,
                midpointMetres: 5 + idx * 10,
                cadenceRpm: cadence
            )
        }
    }

    /// Cycle time per rep for the two alternating groups. Group A
    /// = first rep + every other rep; Group B = second rep +
    /// every other rep. Cycle time within a group is the average
    /// time between two consecutive reps OF THAT GROUP — so
    /// group-A cycle time covers two physical lunges (the one
    /// from this side AND the one from the other side that
    /// happened in between).
    ///
    /// To make the numbers comparable to "time spent per rep,"
    /// halve them — that's the per-lunge cycle time on that
    /// side. The delta is reported AT that halved scale.
    private struct AsymmetryReport {
        let groupACycleSec: Double  // per-lunge time, first-lead group
        let groupBCycleSec: Double  // per-lunge time, alternate group
        let deltaSec: Double        // groupA - groupB (signed)
    }

    private func asymmetry(offsets: [TimeInterval]) -> AsymmetryReport {
        guard offsets.count >= 4 else {
            return AsymmetryReport(groupACycleSec: 0, groupBCycleSec: 0, deltaSec: 0)
        }
        let groupA = offsets.enumerated()
            .filter { $0.offset % 2 == 0 }
            .map(\.element)
        let groupB = offsets.enumerated()
            .filter { $0.offset % 2 == 1 }
            .map(\.element)

        // Per-group consecutive deltas — time between two reps
        // OF THAT GROUP. Halve to get per-lunge time on that side.
        let aDeltas = zip(groupA.dropFirst(), groupA).map { $0 - $1 }
        let bDeltas = zip(groupB.dropFirst(), groupB).map { $0 - $1 }
        let aCycle = aDeltas.isEmpty ? 0 : (aDeltas.reduce(0, +) / Double(aDeltas.count)) / 2
        let bCycle = bDeltas.isEmpty ? 0 : (bDeltas.reduce(0, +) / Double(bDeltas.count)) / 2

        return AsymmetryReport(
            groupACycleSec: aCycle,
            groupBCycleSec: bCycle,
            deltaSec: aCycle - bCycle
        )
    }

    /// Three-tier classification of the asymmetry magnitude.
    /// Thresholds calibrated against typical sandbag-lunge cycle
    /// times (~1.0-1.5s/rep at race pace):
    ///   <0.10s/rep → symmetric (no insight rendered)
    ///   0.10-0.20  → minor (informational, neutral tone)
    ///   >0.20      → significant (warning tint, coaching call)
    private struct AsymmetryTier {
        let shouldRender: Bool
        let symbol: String
        let tint: Color
        let copy: String
    }

    private func asymmetryTier(absDeltaSec: Double) -> AsymmetryTier {
        if absDeltaSec < 0.10 {
            return AsymmetryTier(
                shouldRender: false,
                symbol: "checkmark.circle",
                tint: .success,
                copy: ""
            )
        }
        if absDeltaSec < 0.20 {
            return AsymmetryTier(
                shouldRender: true,
                symbol: "info.circle",
                tint: .textSecondary,
                copy: "Minor lead-leg asymmetry. Likely natural — most athletes favor one side slightly. Worth watching if it persists across races."
            )
        }
        return AsymmetryTier(
            shouldRender: true,
            symbol: "exclamationmark.triangle.fill",
            tint: .warning,
            copy: "Significant lead-leg asymmetry. Could indicate fatigue compensation, an old injury favoring one side, or technique drift. Worth checking your form on the slower side."
        )
    }
}
#endif

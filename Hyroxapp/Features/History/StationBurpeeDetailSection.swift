import SwiftUI
import Charts

// §50 — Station-specific deep dive for Burpee Broad Jumps.
//
// Sits on StationDetailView between the Work Output card and
// the HR Analysis section, renders ONLY for the .burpeeBroadJumps
// station case with per-rep timestamps from §47a + §49. Self-
// hides when timestamps are absent (pre-§49 races, no Watch, or
// the burpee detector didn't fire).
//
// Mirrors StationErgDetailSection's shape — same chart format,
// same headline triplet, same first-half / second-half row —
// but tailored to burpee metrics:
//
//   1. REPS (count) — auto-counted by §49 Z-axis latch detector.
//   2. CADENCE (reps/min) — total reps / segment duration.
//   3. AVG LEAP (m/rep) — 80m / count. The HYROX-specific
//      coaching number; elite athletes average ~5m/leap, weaker
//      reps drop into the 3-4m range under fatigue.
//   4. Cadence-per-10m curve — bucket reps by 10m chunks of the
//      80m segment (assumes constant pace within the segment).
//      Line + points chart with a mean reference line.
//   5. First half / second half cycle time + signed delta —
//      the decay-slope signal. Climbing = athlete blew up early;
//      flat = paced; negative = sprinted home (uncommon).
//
// All metrics derived from Split.repTimestampOffsets — no new
// sensor work beyond what §47a + §49 already capture.
#if !os(watchOS)
struct StationBurpeeDetailSection: View {

    let split: Split

    // MARK: - Body

    var body: some View {
        if split.station == .burpeeBroadJumps,
           let offsets = split.repTimestampOffsets,
           !offsets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Burpee Output",
                    icon: "figure.jumprope"
                )
                VStack(spacing: 12) {
                    headlineRow(offsets: offsets)
                    if offsets.count >= 4 {
                        cadenceCurveCard(offsets: offsets)
                        pacingRow(offsets: offsets)
                    }
                }
            }
        }
    }

    // MARK: - Headline row

    private func headlineRow(offsets: [TimeInterval]) -> some View {
        HStack(spacing: 8) {
            tile(label: "REPS", value: "\(offsets.count)", unit: nil)
            tile(
                label: "CADENCE",
                value: String(format: "%.0f", meanCadence(offsets: offsets)),
                unit: "/min"
            )
            tile(
                label: "AVG LEAP",
                value: String(format: "%.1f", avgLeapMetres(offsets: offsets)),
                unit: "m"
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
        let decay = decayClassification(buckets: buckets)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CADENCE over the 80m")
                    .capsLabelStyle()
                Spacer()
                Text(decay.copy)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(decay.tint)
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
                AxisMarks(values: [0, 20, 40, 60, 80]) { _ in
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
            .chartXScale(domain: 0...80)
            .frame(height: 140)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // MARK: - Pacing row (first vs second half decay)

    private func pacingRow(offsets: [TimeInterval]) -> some View {
        let pacing = secondHalfDelta(offsets: offsets)

        return HStack(spacing: 8) {
            tile(
                label: "FIRST HALF",
                value: String(format: "%.1f", pacing.firstHalfCycleSec),
                unit: "s/rep"
            )
            tile(
                label: "SECOND HALF",
                value: String(format: "%.1f", pacing.secondHalfCycleSec),
                unit: "s/rep"
            )
            tile(
                label: "CYCLE Δ",
                value: pacing.deltaCopy,
                unit: "s/rep"
            )
        }
    }

    // MARK: - Derivation helpers

    private func meanCadence(offsets: [TimeInterval]) -> Double {
        guard split.duration > 0 else { return 0 }
        return Double(offsets.count) / (split.duration / 60)
    }

    /// Average broad-jump distance — 80m divided by rep count.
    /// Real coaching read because the rep count alone doesn't
    /// say HOW FAR each jump went; if an athlete did 20 reps to
    /// cover 80m, that's 4m/leap, well below elite ~5m.
    private func avgLeapMetres(offsets: [TimeInterval]) -> Double {
        guard !offsets.isEmpty else { return 0 }
        return 80.0 / Double(offsets.count)
    }

    /// Bucket the reps into eight 10m chunks for the cadence
    /// curve. Time-based bucketing inside the segment (assumes
    /// constant pace across the 80m) — same simplification the
    /// erg section uses. Each bucket's cadence = reps in that
    /// chunk / time spent in chunk × 60.
    private struct CadenceBucket: Equatable {
        let bucketIndex: Int       // 0..7
        let midpointMetres: Int    // 5, 15, ..., 75
        let cadenceRpm: Double
    }

    private func cadenceBuckets(offsets: [TimeInterval]) -> [CadenceBucket] {
        guard !offsets.isEmpty, split.duration > 0 else { return [] }
        let bucketCount = 8
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

    /// First-half / second-half cycle-time delta. Cycle time =
    /// duration / reps for each half. Positive delta = slowed
    /// (athlete blew up early); negative = sprint finish
    /// (uncommon, usually intentional).
    private struct PacingSplit {
        let firstHalfCycleSec: Double
        let secondHalfCycleSec: Double
        let deltaCopy: String
    }

    private func secondHalfDelta(offsets: [TimeInterval]) -> PacingSplit {
        let halfDuration = split.duration / 2
        let first = offsets.filter { $0 < halfDuration }
        let second = offsets.filter { $0 >= halfDuration }
        let firstCycle = first.isEmpty ? 0 : halfDuration / Double(first.count)
        let secondCycle = second.isEmpty ? 0 : halfDuration / Double(second.count)
        let delta = secondCycle - firstCycle
        let prefix = delta > 0 ? "+" : ""
        return PacingSplit(
            firstHalfCycleSec: firstCycle,
            secondHalfCycleSec: secondCycle,
            deltaCopy: String(format: "\(prefix)%.1f", delta)
        )
    }

    /// Decay classification from the bucket spread. CV of bucket
    /// cadences against the mean — same thresholds the erg
    /// section uses for "pacing quality" but framed for burpees:
    ///   <5% rock-solid pacing
    ///   5-12% variable pacing (typical race load)
    ///   >12% blew up early — large cadence drop late in segment
    private func decayClassification(buckets: [CadenceBucket]) -> (copy: String, tint: Color) {
        let mean = meanCadence(offsets: split.repTimestampOffsets ?? [])
        guard mean > 0, buckets.count >= 4 else {
            return ("", .textSecondary)
        }
        let variances = buckets.map { ($0.cadenceRpm - mean) * ($0.cadenceRpm - mean) }
        let variance = variances.reduce(0, +) / Double(buckets.count)
        let cv = sqrt(variance) / mean
        if cv < 0.05 { return ("Rock-solid pacing", .success) }
        if cv < 0.12 { return ("Variable pacing", .textSecondary) }
        return ("Blew up early", .warning)
    }
}
#endif

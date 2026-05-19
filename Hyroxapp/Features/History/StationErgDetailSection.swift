import SwiftUI
import Charts

// §47b — Station-specific deep dive for Rowing + SkiErg.
//
// Sits on StationDetailView between the Work Output card and
// the HR Analysis section, and renders ONLY for .rowing /
// .skiErg splits that carry per-stroke timestamps from the
// Watch's IMU detector (Phase 46 + 47a). Self-hides when
// timestamps are absent (pre-Phase-47 races, no Watch, or the
// detector didn't fire) so old data degrades silently.
//
// Surfaces four insights the generic StationDetailView can't:
//
//   1. DPS — distance per stroke. Gold-standard rowing
//      efficiency metric (DPS = 1000m / strokes). 8m+ = good,
//      9m+ = elite, 10m+ = top 1%. Headline tile.
//   2. Stroke rate (spm) — mean across the segment. Sits
//      alongside the count + DPS as the canonical erg triplet.
//   3. Stroke-rate curve — spm computed per 100m chunk,
//      rendered as a line chart. Tells the "did you hold
//      cadence?" story: flat line = paced, dropping = blew up
//      early, climbing = sprinted home.
//   4. First-half vs second-half delta + consistency score.
//      Pacing-quality signal — derived from the same per-100m
//      curve. CV (coefficient of variation) under 5% reads
//      'rock-solid'; over 10% reads 'erratic'.
//
// Vocabulary adapts to station — labels say STROKES on rowing,
// PULLS on SkiErg. Same vocabulary contract the live race
// screen + Watch chip honor.
#if !os(watchOS)
struct StationErgDetailSection: View {

    let split: Split

    // MARK: - Body

    var body: some View {
        // Section is rowing/ski-only AND requires per-stroke
        // timestamps. Both gates fail silently — the surrounding
        // StationDetailView keeps rendering the other sections.
        if isErg, let offsets = split.repTimestampOffsets, !offsets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: sectionTitle,
                    icon: sectionIcon
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

    // MARK: - Headline row (count + rate + DPS)

    private func headlineRow(offsets: [TimeInterval]) -> some View {
        HStack(spacing: 8) {
            ergTile(
                label: countLabel,
                value: "\(offsets.count)",
                unit: nil
            )
            ergTile(
                label: rateLabel,
                value: String(format: "%.0f", meanCadence(offsets: offsets)),
                unit: rateUnit
            )
            ergTile(
                label: "DPS",
                value: String(format: "%.1f", dps(offsets: offsets)),
                unit: "m"
            )
        }
    }

    private func ergTile(label: String, value: String, unit: String?) -> some View {
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
                Text("\(rateLabel) over the \(distanceLabel)")
                    .capsLabelStyle()
                Spacer()
                Text(consistencySummary(buckets: buckets, mean: mean))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(consistencyTint(buckets: buckets, mean: mean))
            }
            .padding(.horizontal, 4)

            Chart {
                // Mean reference line — a horizontal dashed
                // marker so the curve's rises and falls read
                // against the segment average.
                RuleMark(y: .value("Mean", mean))
                    .foregroundStyle(Color.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(buckets, id: \.bucketIndex) { bucket in
                    LineMark(
                        x: .value("Distance", bucket.midpointMetres),
                        y: .value("Rate", bucket.cadenceSpm)
                    )
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Distance", bucket.midpointMetres),
                        y: .value("Rate", bucket.cadenceSpm)
                    )
                    .foregroundStyle(Color.accent)
                    .symbolSize(28)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 250, 500, 750, 1000]) { _ in
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
            .chartXScale(domain: 0...1000)
            .frame(height: 140)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // MARK: - Pacing row (first vs second half)

    private func pacingRow(offsets: [TimeInterval]) -> some View {
        let split500 = secondHalfDelta(offsets: offsets)

        return HStack(spacing: 8) {
            ergTile(
                label: "FIRST 500",
                value: String(format: "%.0f", split500.firstHalfRate),
                unit: rateUnit
            )
            ergTile(
                label: "SECOND 500",
                value: String(format: "%.0f", split500.secondHalfRate),
                unit: rateUnit
            )
            ergTile(
                label: "\(rateLabel) Δ",
                value: split500.deltaCopy,
                unit: rateUnit
            )
        }
    }

    // MARK: - Vocabulary

    private var isErg: Bool {
        split.station == .rowing || split.station == .skiErg
    }

    private var sectionTitle: String {
        split.station == .rowing ? "Rowing Output" : "SkiErg Output"
    }

    private var sectionIcon: String {
        split.station == .rowing
            ? "figure.rower"
            : "figure.skiing.crosscountry"
    }

    private var countLabel: String {
        split.station == .rowing ? "STROKES" : "PULLS"
    }

    private var rateLabel: String {
        split.station == .rowing ? "SPM" : "PPM"
    }

    private var rateUnit: String {
        split.station == .rowing ? "/min" : "/min"
    }

    private var distanceLabel: String {
        "1000m"
    }

    // MARK: - Derivation helpers

    /// Mean cadence in strokes/pulls per minute across the whole
    /// segment. duration / strokes = seconds-per-stroke → invert
    /// + scale to per-minute.
    private func meanCadence(offsets: [TimeInterval]) -> Double {
        let strokes = Double(offsets.count)
        guard split.duration > 0, strokes > 0 else { return 0 }
        return strokes / (split.duration / 60)
    }

    /// Distance per stroke / pull. Erg distance is 1000m
    /// (fixed for both rowing and SkiErg stations).
    private func dps(offsets: [TimeInterval]) -> Double {
        let strokes = Double(offsets.count)
        guard strokes > 0 else { return 0 }
        return 1000.0 / strokes
    }

    /// Bucket the strokes into ten 100m chunks for the curve.
    /// Each bucket's cadence is computed as (strokes in this
    /// 100m) / (time spent in this 100m) × 60. Time spent in a
    /// 100m is approximated by linear interpolation from the
    /// split duration — i.e. assumes constant pace within the
    /// 1000m, which is the right call without sub-stroke
    /// distance telemetry.
    ///
    /// Returns at most 10 buckets; fewer if the early-bucket
    /// strokes haven't landed yet (which happens for short
    /// stations relative to stroke cycle — never realistic for
    /// 1000m ergs but defensive).
    private struct CadenceBucket: Equatable {
        let bucketIndex: Int       // 0..9
        let midpointMetres: Int    // 50, 150, ..., 950
        let cadenceSpm: Double
    }

    private func cadenceBuckets(offsets: [TimeInterval]) -> [CadenceBucket] {
        guard !offsets.isEmpty, split.duration > 0 else { return [] }
        let bucketCount = 10
        let bucketDurationSec = split.duration / Double(bucketCount)
        var counts = [Int](repeating: 0, count: bucketCount)
        for offset in offsets {
            let index = min(
                Int(offset / bucketDurationSec),
                bucketCount - 1
            )
            counts[index] += 1
        }
        return counts.enumerated().compactMap { idx, count in
            guard count > 0 else { return nil }
            let cadence = Double(count) / (bucketDurationSec / 60)
            return CadenceBucket(
                bucketIndex: idx,
                midpointMetres: 50 + idx * 100,
                cadenceSpm: cadence
            )
        }
    }

    /// First-half / second-half cadence + delta — the classic
    /// erg pacing tell. Each half is the cadence over its 500m
    /// window, derived the same way as the bucket cadences but
    /// at coarser resolution.
    private struct PacingSplit {
        let firstHalfRate: Double
        let secondHalfRate: Double
        let deltaCopy: String
    }

    private func secondHalfDelta(offsets: [TimeInterval]) -> PacingSplit {
        let halfDuration = split.duration / 2
        let first = offsets.filter { $0 < halfDuration }
        let second = offsets.filter { $0 >= halfDuration }
        let firstRate = Double(first.count) / (halfDuration / 60)
        let secondRate = Double(second.count) / (halfDuration / 60)
        let delta = secondRate - firstRate
        let prefix = delta > 0 ? "+" : ""
        let copy = String(format: "\(prefix)%.0f", delta)
        return PacingSplit(
            firstHalfRate: firstRate,
            secondHalfRate: secondRate,
            deltaCopy: copy
        )
    }

    /// Coefficient of variation across the per-100m buckets.
    /// Lower = more consistent pacing. Thresholds:
    ///   <5%  rock-solid
    ///   5-10%  variable
    ///   >10%  erratic
    private func consistencySummary(buckets: [CadenceBucket], mean: Double) -> String {
        guard mean > 0, buckets.count >= 4 else { return "" }
        let cv = coefficientOfVariation(buckets: buckets, mean: mean)
        if cv < 0.05 { return "Rock-solid pacing" }
        if cv < 0.10 { return "Variable pacing" }
        return "Erratic pacing"
    }

    private func consistencyTint(buckets: [CadenceBucket], mean: Double) -> Color {
        guard mean > 0, buckets.count >= 4 else { return .textSecondary }
        let cv = coefficientOfVariation(buckets: buckets, mean: mean)
        if cv < 0.05 { return .success }
        if cv < 0.10 { return .textSecondary }
        return .warning
    }

    private func coefficientOfVariation(
        buckets: [CadenceBucket],
        mean: Double
    ) -> Double {
        guard mean > 0 else { return 0 }
        let variances = buckets.map { ($0.cadenceSpm - mean) * ($0.cadenceSpm - mean) }
        let variance = variances.reduce(0, +) / Double(buckets.count)
        let stddev = sqrt(variance)
        return stddev / mean
    }
}
#endif

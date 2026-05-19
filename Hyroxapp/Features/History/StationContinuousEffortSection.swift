import SwiftUI

// §51 — Station-specific deep dive for the three continuous-
// effort stations: Sled Push, Sled Pull, and Farmers Carry.
//
// Renders only for those three station cases with non-empty
// step timestamps (Phase 51 ships the step detector that
// populates `Split.repTimestampOffsets` for these stations —
// the field is named for reps historically but the §51 pipeline
// reuses it as a step-timestamp store).
//
// Surfaces metrics the rep-based detail sections can't:
//
//   1. STEPS (count) + CADENCE (steps/min) + PACE (m/s) —
//      the mechanical triplet for any walking/driving effort.
//   2. Stuck-phase analysis — every gap between consecutive
//      steps larger than the 2-second threshold counts as a
//      stuck phase (athlete paused, lost grip, walked the
//      rope back, set the sandbag down). Reports: count,
//      total stuck time, longest stuck phase.
//   3. Stuck timeline — a horizontal strip showing the segment
//      length with red marks where each stuck phase occurred.
//      Lets the athlete see at a glance "I stuck twice, both
//      near the start" vs "I had one long stuck phase
//      mid-segment."
//
// Self-hides on every non-continuous-effort station and on
// continuous-effort splits without step timestamps (pre-§51
// race, no Watch, or the step detector didn't fire).
#if !os(watchOS)
struct StationContinuousEffortSection: View {

    let split: Split

    // MARK: - Body

    var body: some View {
        // ≥8 steps required before rendering — fewer than that
        // on a sled push (50m, walking under load) is more
        // likely to be a noise-triggered detection than a real
        // step sequence. FC + Sled Pull will routinely produce
        // 20+ steps so this gate is rarely binding for them.
        // §51 follow-up after review flagged the false-positive
        // risk on sled push specifically.
        if isContinuousEffort,
           let offsets = split.repTimestampOffsets,
           offsets.count >= 8 {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: sectionTitle,
                    icon: "figure.walk"
                )
                VStack(spacing: 12) {
                    headlineRow(offsets: offsets)
                    stuckPhaseRow(offsets: offsets)
                    let phases = stuckPhases(offsets: offsets)
                    if !phases.isEmpty {
                        timelineCard(phases: phases)
                    }
                }
            }
        }
    }

    // MARK: - Headline row (steps + cadence + pace)

    private func headlineRow(offsets: [TimeInterval]) -> some View {
        HStack(spacing: 8) {
            tile(label: "STEPS", value: "\(offsets.count)", unit: nil)
            tile(
                label: "CADENCE",
                value: String(format: "%.0f", meanCadence(offsets: offsets)),
                unit: "/min"
            )
            tile(
                label: "PACE",
                value: String(format: "%.2f", meanPaceMps()),
                unit: "m/s"
            )
        }
    }

    // MARK: - Stuck phase row

    private func stuckPhaseRow(offsets: [TimeInterval]) -> some View {
        let phases = stuckPhases(offsets: offsets)
        let totalStuck = phases.reduce(0.0) { $0 + $1.durationSec }
        let longest = phases.map(\.durationSec).max() ?? 0

        return HStack(spacing: 8) {
            tile(label: "STUCK COUNT", value: "\(phases.count)", unit: nil)
            tile(
                label: "TIME STUCK",
                value: String(format: "%.1f", totalStuck),
                unit: "s"
            )
            tile(
                label: "LONGEST",
                value: String(format: "%.1f", longest),
                unit: "s"
            )
        }
    }

    // MARK: - Timeline strip

    private func timelineCard(phases: [StuckPhase]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STUCK TIMELINE")
                    .capsLabelStyle()
                Spacer()
                Text("0–\(Int(stationDistanceMetres))m")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 4)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // Track — full-width grey baseline.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surfaceElevated)
                        .frame(height: 14)

                    // Stuck-phase marks — width proportional
                    // to the phase's duration as a fraction of
                    // segment total, offset by the phase's
                    // start-time fraction. Warning tint so the
                    // bar reads as "this is where you lost time."
                    ForEach(phases.indices, id: \.self) { index in
                        let phase = phases[index]
                        let startFraction = phase.startOffsetSec / split.duration
                        let widthFraction = phase.durationSec / split.duration
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.warning)
                            .frame(
                                width: max(CGFloat(widthFraction) * proxy.size.width, 3),
                                height: 14
                            )
                            .offset(x: CGFloat(startFraction) * proxy.size.width)
                    }
                }
            }
            .frame(height: 14)

            Text(timelineCaption(phases: phases))
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Tile renderer

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

    // MARK: - Derivation helpers

    private var isContinuousEffort: Bool {
        switch split.station {
        case .sledPush, .sledPull, .farmersCarry:
            return true
        default:
            return false
        }
    }

    private var sectionTitle: String {
        switch split.station {
        case .sledPush:     return "Sled Push Output"
        case .sledPull:     return "Sled Pull Output"
        case .farmersCarry: return "Farmers Carry Output"
        default:            return "Effort Output"
        }
    }

    private var stationDistanceMetres: Double {
        switch split.station {
        case .sledPush, .sledPull: return 50
        case .farmersCarry:        return 200
        default:                   return 0
        }
    }

    private func meanCadence(offsets: [TimeInterval]) -> Double {
        guard split.duration > 0 else { return 0 }
        return Double(offsets.count) / (split.duration / 60)
    }

    private func meanPaceMps() -> Double {
        // split.duration is the station window ONLY — roxzone
        // (transition) time lives on a sibling field
        // (roxzoneSeconds) and is excluded from this calc.
        // Future edits to roxzone bookkeeping must preserve
        // that invariant or this pace number will silently
        // shift.
        guard split.duration > 0, stationDistanceMetres > 0 else { return 0 }
        return stationDistanceMetres / split.duration
    }

    /// A stuck phase — a continuous stretch of segment time
    /// during which the step detector saw no steps. Includes:
    ///   • Start-of-segment to first step (athlete setting up)
    ///   • Between any two consecutive steps where the gap
    ///     exceeds the 2s threshold
    ///   • Last step to end-of-segment (post-work pause before
    ///     advancing)
    private struct StuckPhase: Equatable {
        let startOffsetSec: TimeInterval
        let durationSec: TimeInterval
    }

    /// Gap threshold defining a stuck phase. 2s catches obvious
    /// pauses (set down sandbag, walk rope back, reset feet)
    /// without flagging the natural between-steps recovery of
    /// gait (~0.5-1.5s typically).
    private static let stuckGapThreshold: TimeInterval = 2.0

    private func stuckPhases(offsets: [TimeInterval]) -> [StuckPhase] {
        guard !offsets.isEmpty, split.duration > 0 else { return [] }
        var phases: [StuckPhase] = []

        // Pre-first-step gap.
        if let first = offsets.first, first > Self.stuckGapThreshold {
            phases.append(StuckPhase(startOffsetSec: 0, durationSec: first))
        }
        // Between-steps gaps.
        for i in 0..<(offsets.count - 1) {
            let gap = offsets[i + 1] - offsets[i]
            if gap > Self.stuckGapThreshold {
                phases.append(StuckPhase(
                    startOffsetSec: offsets[i],
                    durationSec: gap
                ))
            }
        }
        // Post-last-step gap.
        if let last = offsets.last {
            let tailGap = split.duration - last
            if tailGap > Self.stuckGapThreshold {
                phases.append(StuckPhase(
                    startOffsetSec: last,
                    durationSec: tailGap
                ))
            }
        }
        return phases
    }

    /// One-line coaching descriptor based on where the stuck
    /// phases landed. Late stucks suggest grip / fatigue
    /// failure; early stucks suggest setup difficulty.
    private func timelineCaption(phases: [StuckPhase]) -> String {
        guard !phases.isEmpty else { return "" }
        let halfDuration = split.duration / 2
        let lateStucks = phases.filter { $0.startOffsetSec >= halfDuration }
        let earlyStucks = phases.filter { $0.startOffsetSec < halfDuration }
        if lateStucks.count > earlyStucks.count {
            return "Stuck more in the second half — likely grip or leg fatigue."
        }
        if earlyStucks.count > lateStucks.count {
            return "Stuck more in the first half — likely setup or pacing."
        }
        return "Stuck phases distributed across the segment."
    }
}
#endif

import SwiftUI

// §19.4 Phase 10I — post-race Running Economy section.
//
// Per-run vertical oscillation (cm/step) from AirPods Pro 1+ /
// 4 / Max head motion, captured at segment-end by
// RaceViewModel and persisted on Split.verticalOscCmAvg.
// Shows each run with its osc reading + a coaching-tier
// chip (Elite / Good / Needs work) anchored to research-
// grounded thresholds.
//
// Why head-positioned > wrist-positioned: vertical bounce
// is a whole-body center-of-mass property best read at the
// head. Wrist-mounted IMUs pick up arm swing noise that
// confounds the metric. Stryd / Garmin Forerunner sell this
// on $400 dedicated chest pods; we ship it on AirPods Pro 1+
// that the athlete already owns.
//
// Self-hides when no run split carries a verticalOscCmAvg —
// typical for Watch-only or iPhone-only races. Sits on the
// Race Detail Runs tab alongside CompromisedRunningView so
// the "8 runs deep" tab earns its name with more than just
// degradation analysis.
//
// v1 caveat (matches HeadphoneMotionService's amplitude
// heuristic): values are a proxy via 8x scaling of step
// peak-to-trough Z acceleration, clamped 3-20cm. Trend +
// tier are more meaningful than absolute values until the
// proper ground-contact-time integration (10K) lands.
struct RunningEconomySection: View {

    let race: Race

    // Pulled per-render — cheap; only renders 8 numbers.
    private var runSplits: [(index: Int, split: Split)] {
        race.splits
            .enumerated()
            .filter { $0.element.station.kind == .run }
            .map { (index: $0.offset, split: $0.element) }
    }

    // §19.4 Phase 10K — a row is meaningful if it carries
    // AT LEAST ONE of vertical osc or ground contact time.
    // Athletes with older builds (osc only) keep rendering;
    // newer races with both metrics show the richer view.
    private var runsWithEconomy: [(runNumber: Int, osc: Double?, gct: Double?)] {
        var runNumber = 0
        return runSplits.compactMap { item -> (Int, Double?, Double?)? in
            runNumber += 1
            let osc = item.split.verticalOscCmAvg
            let gct = item.split.groundContactTimeMsAvg
            // Filter out rows where both are nil — those add
            // no information.
            guard osc != nil || gct != nil else { return nil }
            return (runNumber, osc, gct)
        }
    }

    static func hasData(in race: Race) -> Bool {
        race.splits.contains { split in
            split.station.kind == .run &&
            (split.verticalOscCmAvg != nil || split.groundContactTimeMsAvg != nil)
        }
    }

    var body: some View {
        if !runsWithEconomy.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header

                VStack(spacing: 4) {
                    ForEach(runsWithEconomy, id: \.runNumber) { entry in
                        row(runNumber: entry.runNumber, osc: entry.osc, gct: entry.gct)
                    }
                }

                footnote
            }
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "airpodspro")
                .font(.caption.weight(.heavy))
            Text("RUNNING ECONOMY")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
        }
        .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Per-run row

    private func row(runNumber: Int, osc: Double?, gct: Double?) -> some View {
        // Tier chip prioritizes vertical osc when available
        // (the longer-standing metric); falls back to GCT
        // tiering when only GCT is present. Both null is
        // already filtered out at the runsWithEconomy stage.
        //
        // Locals are suffixed `Value` because `gctTier` would
        // otherwise shadow the `gctTier(for:)` instance method
        // (Swift resolves the identifier to the local at the
        // closure call site, breaking the `.map { gctTier(for:) }`).
        let oscTierValue = osc.map { tier(for: $0) }
        let gctTierValue = gct.map { gctTier(for: $0) }
        let primaryTier = oscTierValue ?? gctTierValue

        return HStack(alignment: .top, spacing: 10) {
            Text("RUN \(runNumber)")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 2)

            // Stacked value column — vertical osc on top, GCT
            // below. Each renders only when its source value
            // is non-nil; older races (osc only) compress
            // back to a single line because the GCT branch
            // is empty.
            VStack(alignment: .leading, spacing: 2) {
                if let osc {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", osc))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.textPrimary)
                        Text("cm")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                        Text("OSC")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(Color.textTertiary.opacity(0.7))
                    }
                }
                if let gct {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(gct.rounded()))")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                        Text("ms")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                        Text("GCT")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(Color.textTertiary.opacity(0.7))
                    }
                }
            }

            Spacer()

            // Tier chip — coaching-grade indicator at a glance.
            if let primaryTier {
                Text(primaryTier.label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(primaryTier.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(primaryTier.color.opacity(0.12))
                    )
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surfaceElevated)
        )
    }

    // MARK: - Tier classification

    private struct Tier {
        let label: String
        let color: Color
    }

    // Research-grounded bands: elite distance runners exhibit
    // 6-8 cm vertical oscillation; recreational runners
    // 10-14 cm. Lower = more efficient = less wasted vertical
    // motion = better running economy.
    private func tier(for osc: Double) -> Tier {
        switch osc {
        case ..<8:    return Tier(label: "Elite",      color: Color.success)
        case 8..<12:  return Tier(label: "Good",       color: Color.accent)
        default:      return Tier(label: "Improve",    color: Color.warning)
        }
    }

    // §19.4 Phase 10K — research-grounded GCT bands: elite
    // distance runners 180-220ms; sub-elite 220-260ms;
    // recreational 260-300+ms. Lower = more efficient.
    // Tier labels match the vertical-osc tier vocabulary so
    // the chip reads consistently when GCT-only rows render
    // (older races where vertical-osc fired but no GCT, or
    // future races where the inverse).
    private func gctTier(for gct: Double) -> Tier {
        switch gct {
        case ..<220:  return Tier(label: "Elite",      color: Color.success)
        case 220..<260: return Tier(label: "Good",     color: Color.accent)
        default:      return Tier(label: "Improve",    color: Color.warning)
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text("OSC: lower = less wasted vertical motion (elite 6-8 cm, recreational 10-14 cm). GCT: shorter ground contact = more elastic-recoil return (elite 180-220 ms, recreational 260+ ms). Both from AirPods Pro head motion.")
            .font(.system(size: 10))
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

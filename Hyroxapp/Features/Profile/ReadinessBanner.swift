import SwiftUI

// Today's readiness signal — the at-a-glance "should I push hard
// today?" answer. Sits at the top of Profile so the athlete sees
// it immediately on app open.
//
// Pulls from RaceStats.currentReadiness which combines the most
// recent race's recovery demand with hours-elapsed. Three states
// (Fresh / Partial / Recovering) each carry their own coaching
// guidance, severity-tinted icon, and the context line ("18h
// since last hard session") so the athlete can sanity-check the
// signal against their own felt sense.
//
// Visual language is the same coaching-card pattern used by the
// RecoveryEstimateView post-race — severity tint cascade
// (success → warning → accent), icon halo, hero label, subtitle
// line. Reads as a sibling of the post-race recovery card; the
// difference is *what* it answers (post-race: when can you train
// hard again. profile: should you train hard today).
//
// Hidden when:
//   • No finished races
//   • Most recent race lacks HR data — without it we'd be
//     guessing readiness from incomplete signal, and a
//     fabricated readout misleads worse than silence
//
// Sits ABOVE the existing Race-Event countdown banner on Profile
// so it's the very first thing visible after the hero header.
struct ReadinessBanner: View {

    let races: [Race]
    let maxHR: Int

    // Drives the gentle halo pulse when state is .fresh — a 1.5s
    // ease-in-out scale loop on the icon background so the "ready
    // to go" signal feels alive without nagging. Off for non-fresh
    // states because pulsing a "Recovering" warning would be
    // anxiety-inducing motion.
    @State private var pulseHalo = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readout: RaceStats.ReadinessReadout? {
        RaceStats.currentReadiness(in: races, maxHR: maxHR)
    }

    // Visibility helper for ProfileView — keeps the conditional
    // logic at the call site clean. Same shape as
    // StreakBannerView.shouldShow.
    static func shouldShow(in races: [Race], maxHR: Int) -> Bool {
        RaceStats.currentReadiness(in: races, maxHR: maxHR) != nil
    }

    var body: some View {
        if let readout {
            content(readout: readout)
        } else {
            EmptyView()
        }
    }

    // Severity tint contract:
    //   • fresh      — success green ("you're good")
    //   • partial    — warning amber ("ease into it")
    //   • recovering — accent coral ("don't push")
    //
    // Inverted from RecoveryDemand's tint mapping because the
    // semantic axis is different — recovery demand asks "how
    // hard was the session" (more = worse), readiness asks
    // "are you ready" (more = better).
    private func tint(for state: RaceStats.ReadinessState) -> Color {
        switch state {
        case .fresh:      return .success
        case .partial:    return .warning
        case .recovering: return .accent
        }
    }

    // Engine context line — explains the engine's contribution
    // to today's readiness. Three flavors:
    //
    //   • Unmodulated: "Engine 64 · Steady" — neutral, shows
    //     what the rollup is without claiming it changed the
    //     state.
    //   • bumpedUp: "↑ Engine 78 · Elite breakthrough" — the
    //     engine bumped readiness up a tier.
    //   • bumpedDown: "↓ Engine 51 · Off-day, taking it easy" —
    //     the engine bumped readiness down a tier.
    //
    // Color tracks the modulation: bumped-up is success green
    // (positive signal), bumped-down is warning amber (caution
    // signal), unmodulated is neutral text-tertiary.
    @ViewBuilder
    private func engineContextLine(
        score: Double,
        tier: RaceStats.EngineScore.Tier,
        modulation: RaceStats.ReadinessReadout.EngineModulation
    ) -> some View {
        // Compute label / color / symbol via an immediately-
        // invoked closure so the @ViewBuilder body sees a single
        // expression series. A switch statement that assigns to
        // local lets isn't allowed in @ViewBuilder context — the
        // builder treats it as a Void statement and complains
        // "Type '()' cannot conform to 'View'." The closure
        // returns a tuple instead.
        let scoreInt = Int(score.rounded())
        let (label, color, symbol): (String, Color, String?) = {
            switch modulation {
            case .bumpedUp:
                return ("Engine \(scoreInt) · \(tier.displayName) breakthrough", .success, "arrow.up")
            case .bumpedDown:
                return ("Engine \(scoreInt) · Off-day, taking it easy", .warning, "arrow.down")
            case .unmodulated:
                return ("Engine \(scoreInt) · \(tier.displayName)", .textTertiary, nil)
            }
        }()

        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.heavy))
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.top, 2)
    }

    private func content(readout: RaceStats.ReadinessReadout) -> some View {
        let color = tint(for: readout.state)
        let hoursLabel: String = {
            // Compact "18h ago" / "2d ago" style. We use whole-hour
            // precision under 48h and switch to days afterward —
            // "57 hours ago" reads worse than "2 days ago" once
            // you cross that threshold.
            let hours = readout.hoursSinceLastRace
            if hours < 1 {
                let mins = Int(hours * 60)
                return "\(mins)m ago"
            } else if hours < 48 {
                return "\(Int(hours))h ago"
            } else {
                let days = Int(hours / 24)
                return "\(days)d ago"
            }
        }()

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 48, height: 48)
                    // Gentle 1.5s pulse on .fresh state — scales
                    // the halo between 0.95 and 1.05 with an
                    // ease-in-out loop. Subtle enough to read as
                    // "alive," not as a notification badge demanding
                    // attention. Other states stay still — pulsing
                    // a "Recovering" coral halo would feel like
                    // a warning rather than information.
                    .scaleEffect(
                        readout.state == .fresh && pulseHalo ? 1.05 : 0.95
                    )
                    .animation(
                        reduceMotion || readout.state != .fresh
                            ? .none
                            : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: pulseHalo
                    )
                Image(systemName: readout.state.symbol)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(color)
            }
            .onAppear {
                if readout.state == .fresh && !reduceMotion {
                    pulseHalo = true
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(readout.state.displayName)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)

                    Text("· \(hoursLabel)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }

                Text(readout.state.guidance)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Engine context — small line surfacing why the
                // state landed where it did. Only renders when the
                // engine rollup is computable (1+ HR-tracked
                // races); first-race users see the time-based
                // state without the engine context, same as before.
                //
                // When engine modulation actually moved the
                // state (bumpedUp / bumpedDown), prefix with an
                // explainer arrow so the athlete can see how the
                // engine influenced the read. Unmodulated states
                // get a neutral "Engine N · Tier" line.
                if let score = readout.engineRollupScore,
                   let tier = readout.engineRollupTier {
                    engineContextLine(
                        score: score,
                        tier: tier,
                        modulation: readout.engineModulation
                    )
                }
            }

            Spacer()
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

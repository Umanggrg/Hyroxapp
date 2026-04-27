import SwiftUI

// Post-race recovery readout. Surfaces RaceStats.RecoveryDemand
// as a card with the bucket name, typical hour range, and a
// one-line coaching guidance. The athlete walks away from the
// summary knowing not just what they did but when to schedule
// their next intense session.
//
// Visual language matches the EffortCategory chips: SF Symbol +
// text, color tinted to severity (success → warning → accent as
// load increases). Reads as a sibling of the effort + roxzone
// callouts already on the summary hero.
//
// Hidden when no HR data — the underlying recoveryDemand helper
// returns nil and we render EmptyView. Every effort surface in
// the app shares this silence-on-no-data pattern.
//
// Used on RaceSummaryView (post-race, immediate) and
// RaceDetailView (retrospective, when reviewing past races).
// Both pass the same race + maxHR.
struct RecoveryEstimateView: View {

    let race: Race
    let maxHR: Int

    private var demand: RaceStats.RecoveryDemand? {
        RaceStats.recoveryDemand(for: race, maxHR: maxHR)
    }

    var body: some View {
        if let demand {
            content(demand: demand)
        } else {
            EmptyView()
        }
    }

    // Tint contract — light = success, moderate = textPrimary,
    // hard = warning, veryHard = accent. Mirrors EffortCategory's
    // tint pattern so the visual hierarchy is consistent: green
    // for "easy day," coral for "you absolutely sent it."
    private func tint(for demand: RaceStats.RecoveryDemand) -> Color {
        switch demand {
        case .light:    return .success
        case .moderate: return .textPrimary
        case .hard:     return .warning
        case .veryHard: return .accent
        }
    }

    // Card body. Three-tier hierarchy:
    //   • Hero: bucket name + symbol — the headline diagnosis
    //   • Subtitle: typical hour range — "30-48 hours"
    //   • Footer: coaching guidance — what to do tomorrow
    private func content(demand: RaceStats.RecoveryDemand) -> some View {
        let color = tint(for: demand)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recovery").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.16))
                            .frame(width: 44, height: 44)
                        Image(systemName: demand.symbol)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(demand.displayName)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.textPrimary)

                        Text("~\(demand.typicalRecovery)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()
                }

                Text(demand.guidance)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
}

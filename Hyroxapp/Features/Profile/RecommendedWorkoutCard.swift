import SwiftUI

// "Recommended for you" card per §17.3 Weakness-to-Workout
// Engine. Renders the targeted compromised-running prescription
// derived from the athlete's lowest-FRS station.
//
// Different from a generic workout library: this card's
// recommendation comes from the athlete's OWN data — their
// measured weakest station drives the prescription. Each user
// sees a different recommendation; the recommendation pivots as
// their FRS map evolves race-by-race.
//
// Layout:
//
//   ┌────────────────────────────────────────┐
//   │  ✦ RECOMMENDED FOR YOU                 │  ← caps strap
//   │                                        │
//   │  Train Sled Push Recovery              │  ← title
//   │                                        │
//   │  4 rounds: 25m sled push at 80% race   │  ← prescription
//   │  weight → 400m run holding Z3.         │
//   │                                        │
//   │  Heavy legs + sustained tension is...  │  ← coaching note
//   │                                        │
//   │  Sled Push · 32 · Vulnerable           │  ← what's driving it
//   └────────────────────────────────────────┘
//
// Hidden when no recommendation exists (no compromised-running
// data yet, or athlete is already resilient on every station).
struct RecommendedWorkoutCard: View {

    let races: [Race]

    private var recommendation: RaceStats.WeaknessRecommendation? {
        RaceStats.topWeaknessRecommendation(across: races)
    }

    static func hasRecommendation(in races: [Race]) -> Bool {
        RaceStats.topWeaknessRecommendation(across: races) != nil
    }

    var body: some View {
        if let recommendation {
            card(for: recommendation)
        } else {
            EmptyView()
        }
    }

    private func card(for rec: RaceStats.WeaknessRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Caps strap header — sparkles glyph hints "this is
            // generated for you" without going full-AI.
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.heavy))
                Text("RECOMMENDED FOR YOU")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.accent)

            // Title — the workout name. Headline weight so it
            // dominates the card.
            Text(rec.title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Prescription — the actual workout. Body text,
            // multi-line wrap. This is the sentence the athlete
            // takes to the gym.
            Text(rec.prescription)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Coaching note — the "why this works" sentence.
            // Smaller + dimmer so it reads as supporting context
            // for the prescription above.
            Text(rec.coachingNote)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.divider)
                .frame(height: 1)

            // Driver line — what's pulling this recommendation.
            // Gives the card transparency about WHY the engine
            // chose this station.
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption2.weight(.semibold))
                Text("\(rec.station.displayName) · \(rec.currentScore) · \(rec.tier.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(tierColor(rec.tier))
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
                .overlay(
                    // Hairline left border in coral — same
                    // tone-tinted callout pattern Race Story
                    // and the readiness banner use, signaling
                    // "this is targeted advice."
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accent)
                            .frame(width: 3)
                        Spacer()
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    )
                )
        )
    }

    private func tierColor(_ tier: RaceStats.FatigueResistanceScore.Tier) -> Color {
        switch tier {
        case .resilient:   return .success
        case .moderate:    return .textPrimary
        case .vulnerable:  return .accent
        }
    }
}

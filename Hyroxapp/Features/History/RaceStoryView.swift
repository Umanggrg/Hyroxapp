import SwiftUI

// "What Went Wrong?" narrative card — Pillar 5 from CLAUDE.md §18.
//
// Renders the rule-based story produced by `RaceStoryGenerator` as
// a single tinted card with a headline + the multi-sentence
// paragraph. Different from the bullet-list `RaceInsightsView`:
// the insights pane lists 5+ separate observations; this card
// consolidates them into ONE narrative arc that reads like a
// coach summarizing the race.
//
// Tone-driven color treatment:
//   • celebration → success green (PB / breakthrough engine score)
//   • steady      → textPrimary  (normal-range race)
//   • diagnostic  → warning amber (off-day, regression race)
//
// Hidden via `EmptyView` when the generator returns nil
// (race not finished, no anchor data). The thin-narrative path
// (no engine context yet) renders a short fallback story
// rather than nothing — the card always speaks when it appears.
struct RaceStoryView: View {

    let race: Race
    let history: [Race]
    let maxHR: Int

    private var story: RaceStory? {
        RaceStoryGenerator.generate(for: race, history: history, maxHR: maxHR)
    }

    var body: some View {
        if let story {
            card(story: story)
        } else {
            EmptyView()
        }
    }

    static func hasContent(for race: Race, history: [Race], maxHR: Int) -> Bool {
        RaceStoryGenerator.generate(for: race, history: history, maxHR: maxHR) != nil
    }

    private func card(story: RaceStory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header strap — tone-tinted icon + caps headline.
            // Icon picks up the same color contract every other
            // tone-driven surface uses (recovery insight, engine
            // breakthrough callout, etc.) so the visual language
            // is consistent across the post-race screens.
            HStack(spacing: 8) {
                Image(systemName: glyph(for: story.tone))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(tint(for: story.tone))

                Text(story.headline.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.0)
                    .foregroundStyle(tint(for: story.tone))

                Spacer()
            }

            // The paragraph itself — body weight, primary-color
            // text, generous line spacing because the athlete
            // reads this slowly post-race. fixedSize forces
            // multi-line wrap rather than truncation.
            Text(story.paragraph)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(tint(for: story.tone).opacity(0.10))
                .overlay(
                    // Hairline left border in the tone color so
                    // the card reads as a "callout" — same
                    // pattern used by every tone-driven insight
                    // strip elsewhere in the app.
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(tint(for: story.tone))
                            .frame(width: 3)
                        Spacer()
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    )
                )
        )
    }

    private func tint(for tone: RaceStory.Tone) -> Color {
        switch tone {
        case .celebration: return .success
        case .steady:      return .textPrimary
        case .diagnostic:  return .warning
        }
    }

    private func glyph(for tone: RaceStory.Tone) -> String {
        switch tone {
        case .celebration: return "sparkles"
        case .steady:      return "text.alignleft"
        case .diagnostic:  return "stethoscope"
        }
    }
}

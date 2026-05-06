import SwiftUI

// §16 Layer 2 — horizontal scroll strip of post-race insights.
// Replaces the previous bullet-list `RaceInsightsView` with a
// compact card-based UX that:
//
//   • Shows up to N insights at once (capped to keep the strip
//     glanceable — when the InsightGenerator surfaces 6+, we
//     pick the top N most actionable)
//   • Reads horizontally so it doesn't push the splits / story /
//     deeper sections further down the long-scroll
//   • Each card has a tinted left border + glyph + body text
//     in the insight's tone color (success / warning / accent),
//     same vocabulary the bullet rows used
//
// The card content is intentionally identical to the bullet
// version — same `RaceInsight.text` sentence, same `symbol`, same
// `color`. Just a different rendering surface. When we later
// extend `RaceInsight` with structured headline + value fields
// (§16 spec calls for headlines like "Run Degradation" + value
// "18%"), the cards will get richer; for now they show the
// existing one-sentence narrative in a compact format.
//
// Empty array → renders nothing. Same null-state contract as
// `RaceInsightsView`.
struct RaceInsightStrip: View {
    let insights: [RaceInsight]

    /// Max cards rendered. The InsightGenerator can produce 6+
    /// callouts on a feature-rich race; capping at 5 keeps the
    /// strip readable without horizontal hunting. The order
    /// passed in is preserved (caller decides priority).
    let maxCount: Int

    init(insights: [RaceInsight], maxCount: Int = 5) {
        self.insights = insights
        self.maxCount = maxCount
    }

    private var displayedInsights: [RaceInsight] {
        Array(insights.prefix(maxCount))
    }

    var body: some View {
        if displayedInsights.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayedInsights) { insight in
                        card(insight)
                    }
                }
                // Same horizontal padding as the surrounding
                // page content so the first card starts at the
                // correct margin and the last card breathes off
                // the right edge.
                .padding(.horizontal, Layout.screenMargin)
            }
            // Override the parent's horizontal padding — the
            // strip itself bleeds full-width so card chrome
            // doesn't get clipped on either edge during a flick.
            .padding(.horizontal, -Layout.screenMargin)
        }
    }

    // Single insight card. ~220pt wide so 1.5 cards visible at
    // once on a 6.1" iPhone, signaling "scroll for more." Tinted
    // left border in the insight's tone color (success / warning /
    // accent) so a glance reads the severity before the words.
    private func card(_ insight: RaceInsight) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Hairline left border — 3pt tinted strip. Same
            // pattern the Race Story card uses for tone-tinted
            // callouts elsewhere in the app.
            Rectangle()
                .fill(insight.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                // Glyph at top — same icon the bullet-list
                // version showed, scaled up for the card.
                Image(systemName: insight.symbol)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(insight.color)

                // Body text — multi-line wrap, fixed-size
                // forces the card to grow to fit content rather
                // than truncating mid-sentence.
                Text(insight.text)
                    .font(.footnote)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 220, height: 130, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}

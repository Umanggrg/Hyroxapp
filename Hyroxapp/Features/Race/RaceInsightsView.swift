import SwiftUI

// Card listing auto-generated narrative insights for a race —
// "you slowed down 18% on the back-half runs," "HR peaked at
// 184 bpm during Wall Balls," etc. Used on both RaceSummaryView
// (post-finish) and RaceDetailView (retrospective).
//
// The view itself is dumb — it just renders whatever insights the
// caller passes in. The interesting logic lives in
// `InsightGenerator.generate(for:allRaces:)` so summary and detail
// produce identical insights for the same race.
//
// Empty insights array → renders nothing. Caller decides whether
// to also hide the section header above this view, since `nil` /
// `EmptyView` won't trigger a wrapper VStack section header to
// disappear on its own.
struct RaceInsightsView: View {
    let insights: [RaceInsight]

    // Drives the staggered reveal. False on mount; flipped to true
    // on appear so each insight slides+fades in with a per-row
    // delay. Reads as a sequential reveal — coach reading off
    // observations one at a time — rather than a wall of insights
    // appearing at once.
    @State private var revealedCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    insightRow(insight)
                        .opacity(index < revealedCount ? 1.0 : 0)
                        .offset(y: index < revealedCount ? 0 : 6)
                    if insight.id != insights.last?.id {
                        Divider()
                            .background(Color.divider)
                            .opacity(index < revealedCount ? 1.0 : 0)
                    }
                }
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
            .onAppear {
                if reduceMotion {
                    revealedCount = insights.count
                } else {
                    // Stagger: 80ms between each row's reveal,
                    // first row fires 100ms after onAppear so the
                    // layout pass has time to settle. With 3-5
                    // insights, the whole reveal completes inside
                    // 500ms — feels purposeful, not slow.
                    for index in insights.indices {
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 0.1 + Double(index) * 0.08
                        ) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                revealedCount = index + 1
                            }
                        }
                    }
                }
            }
        }
    }

    private func insightRow(_ insight: RaceInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(insight.color)
                .frame(width: 24, alignment: .leading)
            Text(insight.text)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

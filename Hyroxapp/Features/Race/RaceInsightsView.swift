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

    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(insights) { insight in
                    insightRow(insight)
                    if insight.id != insights.last?.id {
                        Divider().background(Color.divider)
                    }
                }
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
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

import SwiftUI

// "Is my training balanced?" — the distribution counterpart to
// EffortTrendView's timeline. Where the trend chart shows intensity
// over time, this shows the *mix* of intensity across recent races:
// across your last N races, what fraction landed in each category?
//
// Visual: a stacked horizontal bar where each segment's width matches
// its share of the window. Below the bar, a small legend lists each
// category with its count + percentage. The bar reads at a glance —
// a healthy training block has visible green (recovery) interleaved
// with amber + coral (high + very high effort), not a wall of one
// color.
//
// Race-mix coaching question this answers: "Am I always pegged?"
// Strava + Whoop both flag chronic high-strain training as a red
// flag — too much volume at intensity, not enough recovery, leads
// to plateau or injury. Seeing a bar that's 90% coral signals the
// athlete to schedule a recovery week. Seeing a bar that's 60%
// green tells the opposite story (build up).
//
// Window: last 10 races by default. Long enough to be statistically
// meaningful, short enough that the breakdown reflects current
// training rather than ancient history.
//
// Gated on 3+ races with HR data — same threshold as the trend
// chart for consistency.
struct EffortDistributionView: View {

    let races: [Race]
    let maxHR: Int

    // Drives the entrance animation — segments grow from 0 width
    // to their final share when the view first appears. False on
    // mount, flipped to true 0.05s after onAppear so the layout
    // pass settles before the spring fires.
    @State private var animationsRevealed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Number of most-recent races to include. 10 is the same window
    // EffortScoreInsight uses for its "above your recent average"
    // comparison, so the two surfaces stay coherent.
    static let windowSize = 10

    static let minimumRacesForChart = 3

    // Visibility helper for the parent. Returns true when the recent
    // window has at least 3 categorizable races.
    static func hasEnoughData(in races: [Race], maxHR: Int) -> Bool {
        recentCategorizedRaces(in: races, maxHR: maxHR).count >= minimumRacesForChart
    }

    var body: some View {
        let categorized = Self.recentCategorizedRaces(in: races, maxHR: maxHR)
        if categorized.count >= Self.minimumRacesForChart {
            content(categorized: categorized)
        } else {
            EmptyView()
        }
    }

    // MARK: - Content

    private func content(categorized: [RaceStats.EffortCategory]) -> some View {
        let counts = Self.counts(in: categorized)
        let total = categorized.count

        return VStack(alignment: .leading, spacing: 14) {
            // Stacked horizontal bar — each segment's width is the
            // category's share of the window. GeometryReader so the
            // segment widths add up to exactly the available width
            // regardless of the parent's frame.
            //
            // Entrance animation: segments grow from 0 → full width
            // on first appear. The width multiplier (animationsRevealed
            // ? 1 : 0) drives the bar to spring open from the leading
            // edge. Cleaner than fading in because the user can
            // visually parse the proportions as they're drawn.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(RaceStats.EffortCategory.allCases, id: \.self) { category in
                        let count = counts[category] ?? 0
                        if count > 0 {
                            let fraction = Double(count) / Double(total)
                            let fullWidth = geo.size.width * CGFloat(fraction)
                                - CGFloat(visibleSegmentCount(in: counts) - 1) * 2 / CGFloat(visibleSegmentCount(in: counts))
                            Rectangle()
                                .fill(tint(for: category))
                                .frame(
                                    width: animationsRevealed ? fullWidth : 0
                                )
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 14)

            // Legend rows — one per category that's actually
            // present in the window. Hides categories with 0
            // count to keep the layout tight; an athlete who's
            // never had a Recovery race in the last 10 doesn't
            // need a "Recovery: 0" row taking visual weight.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(RaceStats.EffortCategory.allCases, id: \.self) { category in
                    if let count = counts[category], count > 0 {
                        legendRow(
                            category: category,
                            count: count,
                            total: total
                        )
                    }
                }
            }

            // Subtitle anchors the data — "based on your last 10
            // races" prevents the user from misreading the
            // breakdown as their lifetime mix. Singular when only
            // 3 races have HR data, plural otherwise.
            Text("Across your last \(total) HR-tracked race\(total == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .animation(
            reduceMotion ? .none : .smooth(duration: 0.7),
            value: animationsRevealed
        )
        .onAppear {
            // One runloop tick before the animation kicks so the
            // initial zero-width state has a chance to render.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animationsRevealed = true
            }
        }
    }

    // Count of categories with non-zero entries. Used to compute
    // gap allowance so the stacked bar segments still fit inside
    // the geometry width with the inter-segment 2pt spacing.
    private func visibleSegmentCount(in counts: [RaceStats.EffortCategory: Int]) -> Int {
        max(1, counts.values.filter { $0 > 0 }.count)
    }

    // Legend row: small color swatch + category name + count
    // + percentage. Same tint contract as everywhere else so the
    // colors carry meaning without re-explaining at this surface.
    private func legendRow(
        category: RaceStats.EffortCategory,
        count: Int,
        total: Int
    ) -> some View {
        let percent = Int(((Double(count) / Double(total)) * 100).rounded())

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint(for: category))
                .frame(width: 12, height: 12)

            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text("\(count) · \(percent)%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Static helpers

    // Walks the most-recent N races (by createdAt descending),
    // categorizes any with HR data, and returns the categorized
    // sequence. Skips races without HR — they can't be categorized
    // and would either pollute the bar with a "missing" segment
    // or skew the percentages if forced into a default bucket.
    static func recentCategorizedRaces(
        in races: [Race],
        maxHR: Int
    ) -> [RaceStats.EffortCategory] {
        races
            .filter { $0.isFinished }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(windowSize * 2)  // pull more in case some lack HR
            .compactMap { categorize($0, maxHR: maxHR) }
            .prefix(windowSize)
            .map { $0 }
    }

    // Group categorized races by category for the count map.
    private static func counts(
        in categories: [RaceStats.EffortCategory]
    ) -> [RaceStats.EffortCategory: Int] {
        var dict: [RaceStats.EffortCategory: Int] = [:]
        for category in categories {
            dict[category, default: 0] += 1
        }
        return dict
    }

    // Race-level categorization — same duration-weighted-average-HR
    // logic used by RaceCardView's effort badge and EffortTrendView's
    // dot color, so all three surfaces agree on a race's category.
    // Duplicated rather than extracted to keep each effort-rendering
    // surface independently inspectable; the upstream helper would be
    // a nice refactor target if a fourth surface is ever added.
    private static func categorize(
        _ race: Race,
        maxHR: Int
    ) -> RaceStats.EffortCategory? {
        let hrSplits = race.splits.compactMap { split -> (avg: Double, duration: TimeInterval)? in
            guard let avg = split.heartRateAvgBPM, avg > 0, split.duration > 0 else {
                return nil
            }
            return (avg, split.duration)
        }
        guard !hrSplits.isEmpty else { return nil }

        let totalDuration = hrSplits.reduce(0) { $0 + $1.duration }
        guard totalDuration > 0 else { return nil }
        let weightedAvg = hrSplits.reduce(0) { $0 + ($1.avg * $1.duration) } / totalDuration
        let fraction = weightedAvg / Double(maxHR)

        switch fraction {
        case ..<0.65:
            return .recovery
        case ..<0.75:
            return .moderate
        case ..<0.85:
            return .high
        default:
            return .veryHigh
        }
    }

    // Tint contract — same as every other effort surface in the app.
    private func tint(for category: RaceStats.EffortCategory) -> Color {
        switch category {
        case .recovery: return .success
        case .moderate: return .textPrimary
        case .high:     return .warning
        case .veryHigh: return .accent
        }
    }
}

import SwiftUI

// The canonical race card. Strava-inspired anatomy described in CLAUDE.md §5:
// header (title + relative time) → hero stat (total time) → supporting stats
// (3-up grid) → optional badges (e.g. PB). Lives in Shared/Components/ so it
// can appear anywhere we need to render a race row:
//   - History feed (primary consumer today)
//   - Profile "Recent races" section
//   - Future v1 social feed — a flag for social actions (like/comment/share)
//     will slot in at the bottom without changing the rest of the card.
//
// The PB badge is derived from `allRaces`, not a property on the race model
// itself, because "was this a PB at the time it was set?" depends on every
// earlier race. Passing the slice at render time keeps the model clean and
// lets callers decide what pool of races to evaluate against (all races,
// this month, just this user's, etc. when social lands).
struct RaceCardView: View {

    let race: Race
    let allRaces: [Race]

    private var isPB: Bool {
        RaceStats.wasPBWhenSet(race, among: allRaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero
            supportingStats
            if isPB {
                pbBadge
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("HYROX Race")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(race.startedAt.formatted(.relative(presentation: .named)))
                .font(.metadata)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RaceStats.totalTime(race))
                .font(.heroStat)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text("Total Time")
                .capsLabelStyle()
        }
    }

    private var supportingStats: some View {
        HStack(spacing: 0) {
            statTile(value: RaceStats.bestRun(race), label: "Best Run")
            statDivider
            statTile(value: RaceStats.avgRun(race), label: "Avg Run")
            statDivider
            statTile(value: RaceStats.wallBalls(race), label: "Wall Balls")
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 32)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var pbBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption)
            Text("New PB")
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.success)
    }
}

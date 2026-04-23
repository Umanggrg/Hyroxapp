import SwiftUI
import SwiftData

// Feed-style list of completed races, newest first.
//
// Built deliberately to foreshadow the v1+ social feed: every row is a card
// with the same anatomy (hero stat, supporting stats, metadata header). When
// social ships, cards gain a kudos / comment row at the bottom — the rest
// shouldn't need to change. Per CLAUDE-2.md §5 the card layout itself will
// eventually move to `Shared/Components/RaceCardView.swift`; for v0.1 it
// lives alongside its only consumer.
struct HistoryView: View {

    // `@Query` lets SwiftData drive the view reactively — inserts, edits,
    // and deletes to the store trigger re-renders automatically. Filter to
    // finished races only (unfinished ones are resumable state, not history).
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var races: [Race]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                if races.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(races) { race in
                                NavigationLink(value: race) {
                                    RaceCard(race: race, allRaces: races)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Layout.screenMargin)
                    }
                }
            }
            .navigationTitle("History")
            .hyroxDarkNavigationBar()
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No races yet")
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Text("Finish a race and it will show up here.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Layout.screenMargin)
    }
}

// MARK: - Race Card

// Strava-inspired race card. Same anatomy described in CLAUDE-2.md §5:
// header (title + relative time) → hero stat (total time) → supporting
// stats (3-up grid). Social actions row is absent in v0.1 and slots in
// at the bottom when v1 ships the feed.
private struct RaceCard: View {
    let race: Race
    // Needed to tell whether this race was a PB when it was set. Passing
    // the whole list is fine at v0.1 scale; v1 can precompute if needed.
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
}

// RaceStats (formatting + per-race/aggregate helpers) lives in
// Shared/RaceStats.swift — used by Race, History, and Profile.

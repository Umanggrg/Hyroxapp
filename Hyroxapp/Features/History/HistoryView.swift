import SwiftUI
import SwiftData

// Feed-style list of completed races, newest first.
//
// Built deliberately to foreshadow the v1+ social feed: every row is a
// `RaceCardView` (Shared/Components/) with the same anatomy it will use in
// the future feed. When social ships, the card gains a kudos / comment row
// at the bottom — this view doesn't change.
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
                                    RaceCardView(race: race, allRaces: races)
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

// RaceStats (formatting + per-race/aggregate helpers) lives in
// Shared/RaceStats.swift — used by Race, History, and Profile.
// RaceCardView lives in Shared/Components/ — shared with Profile and
// the future social feed.

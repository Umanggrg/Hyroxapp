import SwiftUI
import SwiftData

// The Profile tab. Composes the reusable `ProfileHeaderView` with a stats
// grid computed from all finished races in storage. Empty state shows up
// when there are no races yet so the screen still feels intentional.
struct ProfileView: View {

    // Only finished races contribute to Profile aggregates. In-progress rows
    // are resume-state, not history.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var races: [Race]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        ProfileHeaderView()
                            .padding(.top, 8)

                        if races.isEmpty {
                            emptyStats
                        } else {
                            StatsGridView(items: aggregates)
                        }
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.bottom, Layout.screenMargin)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // The four stats called out in CLAUDE-2.md §4.1: race count, PB, avg
    // time, total stations completed. All computed from the same @Query
    // so the tab stays live as new races are added.
    private var aggregates: [StatsGridView.Item] {
        let pb = RaceStats.personalBest(races).map(RaceStats.format) ?? "—"
        let avg = RaceStats.averageTotal(races).map(RaceStats.format) ?? "—"
        let stations = RaceStats.totalStationsCompleted(races)

        return [
            .init(label: "Races", value: "\(races.count)"),
            .init(label: "PB", value: pb),
            .init(label: "Avg Time", value: avg),
            .init(label: "Stations", value: "\(stations)")
        ]
    }

    private var emptyStats: some View {
        VStack(spacing: 8) {
            Text("No stats yet")
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Text("Finish a race to see your PB, average time, and more.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

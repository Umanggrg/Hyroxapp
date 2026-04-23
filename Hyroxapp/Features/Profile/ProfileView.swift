import SwiftUI
import SwiftData

// The Profile tab. Composes a `ProfileHeaderView` reading from the live
// `UserProfile` model with a stats grid computed from all finished races.
// Bootstraps a default `UserProfile` on first launch so the header always
// has something to render; an Edit button in the toolbar presents the
// `EditProfileView` sheet for changes.
struct ProfileView: View {

    @Environment(\.modelContext) private var modelContext

    // There is exactly one `UserProfile` row in v1 — `@Query` returns the
    // whole list sorted; we use `.first` to fetch the single record.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Only finished races contribute to Profile aggregates. In-progress
    // rows are resume-state, not history.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var races: [Race]

    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        if let profile = profiles.first {
                            ProfileHeaderView(profile: profile)
                                .padding(.top, 8)
                        }

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
            .hyroxDarkNavigationBar()
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                        .disabled(profiles.first == nil)
                }
                #endif
            }
            .onAppear(perform: bootstrapIfNeeded)
            #if canImport(UIKit)
            .sheet(isPresented: $isEditing) {
                if let profile = profiles.first {
                    EditProfileView(profile: profile)
                        .preferredColorScheme(.dark)
                }
            }
            #endif
        }
    }

    // First-launch seeding. Runs every time ProfileView appears, but the
    // guard keeps it cheap — insert + save only happens once.
    private func bootstrapIfNeeded() {
        guard profiles.isEmpty else { return }
        let profile = UserProfile.makeDefault()
        modelContext.insert(profile)
        try? modelContext.save()
    }

    // The four stats called out in CLAUDE-2.md §4.1: race count, PB, avg
    // time, total stations completed. Computed from the same @Query so the
    // tab stays live as new races are added.
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

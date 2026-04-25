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
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        if let profile = profiles.first {
                            ProfileHeaderView(profile: profile, raceCount: races.count)
                                .padding(.top, 8)
                        }

                        if races.isEmpty {
                            emptyStats
                        } else {
                            StatsGridView(items: aggregates)
                            // All-time PBs per station type sit between
                            // the aggregate stats grid and the recent
                            // races feed — answers "what's my best Sled
                            // Push / 1km Run / Wall Balls?" at a glance,
                            // adjacent to the high-level metrics.
                            StationPersonalBestsView(races: races)
                            // Performance trends chart only shows up
                            // once there's enough data for a real
                            // trendline (3+ finished races). Without
                            // this gate, the section would render an
                            // awkward 1- or 2-dot chart that doesn't
                            // tell the athlete anything.
                            if PerformanceTrendsView.hasEnoughData(in: races) {
                                trendsSection
                            }
                            recentRacesSection
                        }
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.bottom, Layout.screenMargin)
                }
            }
            .navigationTitle("Profile")
            .hyroxDarkNavigationBar()
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            .toolbar {
                #if !os(macOS)
                // Settings gear goes on the leading edge, Edit on the
                // trailing edge — mirrors the conventional iOS pattern
                // (Back/Cancel on left, confirm/action on right).
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .disabled(profiles.first == nil)
                    .accessibilityLabel("Settings")
                }
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
            .sheet(isPresented: $isShowingSettings) {
                if let profile = profiles.first {
                    SettingsView(profile: profile)
                }
            }
            #endif
        }
    }

    // Most-recent finished races. Capped at 3 for a tight Strava-style
    // profile layout — if the user wants more, they use the History tab.
    private var recentRaces: [Race] {
        Array(races.prefix(3))
    }

    // Performance trends section — caps-label header + chart, sandwiched
    // between Personal Bests and Recent Races. The chart itself is
    // gated on race count via PerformanceTrendsView.hasEnoughData; this
    // wrapper only adds the section header so the layout reads
    // consistently with the other Profile sections.
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trends")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            PerformanceTrendsView(races: races)
        }
    }

    // Section displayed below the stats grid. Hidden entirely when no
    // finished races (the empty state above already covers that case).
    private var recentRacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Races")
                    .capsLabelStyle()
                Spacer()
            }

            ForEach(recentRaces) { race in
                NavigationLink(value: race) {
                    // Use the full list for PB evaluation — not just the 3
                    // we're showing — so the badge is accurate.
                    RaceCardView(race: race, allRaces: races)
                }
                .buttonStyle(.plain)
            }
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

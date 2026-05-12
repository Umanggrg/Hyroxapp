import SwiftUI
import SwiftData

// Feed-style list of completed races, newest first.
//
// Built deliberately to foreshadow the v1+ social feed: every row is a
// `RaceCardView` (Shared/Components/) with the same anatomy it will use in
// the future feed. When social ships, the card gains a kudos / comment row
// at the bottom — this view doesn't change.
//
// Searchable + filterable as of the search/filter slice — the feed reads
// well at 5 races, but past 20+ a way to slice it becomes essential.
// Search matches race names (case-insensitive, blank query → no filter).
// Filter chips narrow the feed to a category (this month, PBs only, custom
// workouts, races with photos). Search and filter compose — a query for
// "morning" with the "PBs Only" chip selected returns only morning-named
// PB races.
struct HistoryView: View {

    // `@Query` lets SwiftData drive the view reactively — inserts, edits,
    // and deletes to the store trigger re-renders automatically. Filter to
    // finished races only (unfinished ones are resumable state, not history).
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var races: [Race]

    // FreeRun rows — surfaced alongside races as part of the
    // unified History feed. Filter to finished runs (endedAt != nil)
    // for the same reason as Race: in-progress rows are resumable
    // state, not history. Newest first.
    @Query(
        filter: #Predicate<FreeRun> { $0.endedAt != nil },
        sort: [SortDescriptor(\FreeRun.createdAt, order: .reverse)]
    ) private var freeRuns: [FreeRun]

    // User profile for max HR — drives the effort-category chip on
    // each RaceCardView. Singleton-via-Query pattern matches every
    // other surface that reads UserProfile; when no profile exists
    // yet (pre-onboarding) the cards fall back to the 190 default.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    @State private var searchText = ""
    @State private var selectedFilter: HistoryFilter = .all

    // Activity-kind filter — top-level segmented control that
    // determines which row types render. `all` mixes races + free
    // runs chronologically; `races` shows only HYROX races (with
    // the existing chip filters); `runs` shows only Free Runs.
    @State private var selectedActivity: HistoryActivityKind = .all

    // Wireframe §04.1 primary mode switcher — List / Calendar /
    // Trends. The wireframe positions this as the top-level
    // navigation; activity-kind + filter chips live below it
    // and only apply in List mode.
    @State private var selectedMode: HistoryMode = .list

    // State-driven navigation for the new modes. List/Calendar
    // rows use button callbacks (cleaner than passing a
    // NavigationLink destination into reusable mode views), so
    // we surface the destination via these @State bindings and
    // a pair of navigationDestination(item:) modifiers on the
    // NavigationStack below.
    @State private var raceDestination: Race?
    @State private var runDestination: FreeRun?

    // Selected tag (nil = no tag filter). Composes with selectedFilter
    // — both apply in series, so the user can do "PBs Only" + tag
    // "zone2" to see PB races that were also zone-2 sessions.
    @State private var selectedTag: String? = nil

    // All tags ever used across the athlete's race history, sorted
    // by usage frequency descending so the most-used tags surface
    // first. Drives the TagFilterRow below the preset filters.
    private var availableTags: [String] {
        var counts: [String: Int] = [:]
        for race in races {
            for tag in race.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .map(\.key)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                if races.isEmpty && freeRuns.isEmpty {
                    emptyState
                } else {
                    historyScrollBody
                }
            }
            .navigationTitle("History")
            .hyroxDarkNavigationBar()
            // Standard iOS search bar in the nav area. Bound to
            // searchText; an empty string disables the search
            // filter at the data layer.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search races"
            )
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            .navigationDestination(for: FreeRun.self) { run in
                // No onClose — the summary's Done button falls
                // through to its own `dismiss` env value, which
                // pops the nav stack and lands the user back on
                // the History feed.
                FreeRunSummaryView(run: run)
            }
            // State-driven nav destinations for the wireframe §04.1
            // List/Calendar modes — those modes use button-callback
            // navigation rather than NavigationLink wrappers. When
            // a row taps, its mode flips the corresponding @State
            // optional to non-nil and these modifiers push the
            // destination automatically.
            .navigationDestination(item: $raceDestination) { race in
                RaceDetailView(race: race)
            }
            .navigationDestination(item: $runDestination) { run in
                FreeRunSummaryView(run: run)
            }
            .navigationDestination(for: HistoryDestination.self) { destination in
                switch destination {
                case .compare:
                    RaceComparisonView()
                case .gallery:
                    #if canImport(UIKit) && !os(watchOS)
                    RaceGalleryView()
                    #else
                    EmptyView()
                    #endif
                }
            }
            .toolbar {
                #if !os(macOS)
                // Photos gallery button — only meaningful when at
                // least one race has a photo. Hidden otherwise so
                // the toolbar doesn't show controls that lead to
                // empty screens.
                if hasAnyPhoto {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: HistoryDestination.gallery) {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        .accessibilityLabel("Race photos gallery")
                    }
                }
                // Compare button — only meaningful with 2+ finished
                // races to compare. Hidden when there's nothing to do.
                if races.count >= 2 {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: HistoryDestination.compare) {
                            Image(systemName: "rectangle.split.2x1")
                        }
                        .accessibilityLabel("Compare two races")
                    }
                }
                #endif
            }
        }
    }

    // True when any finished race has a photo attached. Drives
    // toolbar visibility — keeps the gallery icon hidden until
    // the gallery would actually have something to show. A race
    // counts as "has a photo" if EITHER the local bytes are
    // present OR the cloud URL is set, since cross-device sync
    // can leave a row with only the URL until the bytes are
    // fetched lazily on render.
    private var hasAnyPhoto: Bool {
        races.contains { $0.photoData != nil || $0.photoURL != nil }
    }

    // Wireframe §04.1 mode-aware body. Hero stats persist at the
    // top regardless of mode (athletes want the at-a-glance count
    // + PB even when they're scrubbing through the calendar).
    // Mode chip row sits beneath the hero; below that, each mode
    // renders its own content.
    private var historyScrollBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HistoryHero(races: races)
                    .padding(.bottom, 2)

                modeChipRow

                switch selectedMode {
                case .list:
                    listModeContent
                case .calendar:
                    HistoryCalendarMode(
                        races: races,
                        freeRuns: freeRuns,
                        onRaceTap: { race in raceDestination = race },
                        onRunTap: { run in runDestination = run }
                    )
                case .trends:
                    HistoryTrendsMode(races: races)
                }
            }
            .padding(.horizontal, Layout.screenMargin)
            .padding(.vertical, Layout.screenMargin)
        }
    }

    // Wireframe §04.1 primary mode switcher. Three pills: List
    // (default) / Calendar / Trends. Coral active, neutral
    // outline inactive — same shape as the feed's filter chips.
    private var modeChipRow: some View {
        HStack(spacing: 6) {
            ForEach(HistoryMode.allCases) { mode in
                modeChip(mode)
            }
            Spacer()
        }
    }

    private func modeChip(_ mode: HistoryMode) -> some View {
        let isActive = (selectedMode == mode)
        return Button {
            Haptics.impact(.light)
            withAnimation(.smooth(duration: 0.2)) {
                selectedMode = mode
            }
        } label: {
            Text(mode.displayName)
                .font(.caption.weight(.heavy))
                .foregroundStyle(isActive ? Color.accent : Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isActive ? Color.accent.opacity(0.12) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.accent : Color.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // List-mode body. When the search field is active, swaps
    // the standard grouped list for the wireframe §04.1
    // dedicated search-results layout (HistorySearchResults).
    // Otherwise renders the existing activity-kind / filter /
    // tag chip chain + weekly-grouped HistoryListMode.
    @ViewBuilder
    private var listModeContent: some View {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedQuery.isEmpty {
            // Search active → dedicated results view with
            // station-summary card when query matches a station
            // name. No filter chips here — search results stand
            // alone per wireframe.
            HistorySearchResults(
                query: trimmedQuery,
                races: races,
                onRaceTap: { race in raceDestination = race }
            )
        } else {
            FilterChipRow(
                filters: HistoryActivityKind.allCases,
                selection: $selectedActivity,
                label: \.displayName
            )
            .padding(.horizontal, -Layout.screenMargin)

            if selectedActivity != .runs {
                FilterChipRow(
                    filters: HistoryFilter.allCases,
                    selection: $selectedFilter,
                    label: \.displayName
                )
                .padding(.horizontal, -Layout.screenMargin)

                TagFilterRow(
                    tags: availableTags,
                    selection: $selectedTag
                )
                .padding(.horizontal, -Layout.screenMargin)
            }

            if filteredItems.isEmpty {
                noResultsState
                    .padding(.top, 40)
            } else {
                HistoryListMode(
                    items: filteredItems,
                    allRaces: races,
                    onRaceTap: { race in raceDestination = race },
                    onRunTap: { run in runDestination = run }
                )
            }
        }
    }

    // Render a history row for a unified `HistoryItem` —
    // dispatches to the appropriate card view (RaceCardView or
    // FreeRunCardView). Each card pushes via NavigationLink to
    // the right destination. Same pressableCard styling on both
    // so the feed feels homogeneous.
    @ViewBuilder
    private func historyRow(for item: HistoryItem) -> some View {
        switch item {
        case .race(let race):
            NavigationLink(value: race) {
                RaceCardView(race: race, allRaces: races, maxHR: maxHeartRate)
            }
            .buttonStyle(.pressableCard)
        case .run(let run):
            NavigationLink(value: run) {
                FreeRunCardView(run: run)
            }
            .buttonStyle(.pressableCard)
        }
    }

    // Unified, filtered, sorted feed of races + free runs. Honors
    // the activity-kind filter (top-level), the race-specific
    // chip filter (when the user hasn't switched to runs-only),
    // the tag filter (race-only), and the search query.
    //
    // Mixed-type sorting uses createdAt descending so the most
    // recent activity is on top regardless of whether it's a
    // race or a run.
    private var filteredItems: [HistoryItem] {
        var items: [HistoryItem] = []

        // Race side — only included when the activity filter is
        // .all or .races. Runs through the existing chip filter
        // chain (preset + tag + search).
        if selectedActivity != .runs {
            let raceMatches = filteredRaces
            items.append(contentsOf: raceMatches.map { HistoryItem.race($0) })
        }

        // Run side — included when activity filter is .all or
        // .runs. The race chip filters don't apply (PBs /
        // customWorkouts are race concepts), but the search
        // query DOES — matches against run.name.
        if selectedActivity != .races {
            var runs = freeRuns
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                runs = runs.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                }
            }
            items.append(contentsOf: runs.map { HistoryItem.run($0) })
        }

        // Sort the mixed feed by createdAt descending. Both
        // models share the same sort key so this is straightforward.
        items.sort { $0.createdAt > $1.createdAt }
        return items
    }

    // Apply the active chip + the search query in series. Order
    // doesn't change the result (both are conjunctive filters) —
    // we filter by chip first because chip-matching is cheaper
    // than string compare, so on a long history the search query
    // runs against a smaller set.
    private var filteredRaces: [Race] {
        var result = races.filter { selectedFilter.matches($0, allRaces: races) }

        // Tag filter — composes on top of the preset filter. A
        // race must contain the selected tag to survive (case
        // already-canonical via the model's setter, so equality
        // comparison is safe).
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { race in
                race.name.localizedCaseInsensitiveContains(query)
            }
        }

        return result
    }

    // Hashable navigation value used for non-Race destinations from
    // History. Currently single-purpose (Compare); having a real
    // enum makes it trivial to add more destinations later (export,
    // bulk delete, etc.) without each becoming its own boolean
    // sheet flag.
    enum HistoryDestination: Hashable {
        case compare
        case gallery
    }

    // MARK: - Empty states

    private var emptyState: some View {
        ZStack {
            // Recurring brand-fingerprint watermark, anchored
            // bottom-center at very low opacity so it reads as
            // texture, not a chart. Same visual signature used
            // on the share cards + app icon — gives even an
            // empty page a coherent identity.
            VStack {
                Spacer()
                FingerprintWatermark()
                    .frame(height: 110)
                    .opacity(0.05)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 100)
            }

            VStack(spacing: 14) {
                Spacer()

                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.bottom, 4)

                Text("Your race history")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text("Finish your first HYROX and it lands here as a card. Every race becomes a personal best to chase.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Start in the Race tab")
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.accent)
                    .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, Layout.screenMargin)
        }
    }

    // Distinct from the "no races at all" empty state — fires
    // when the user has races but the active search/filter
    // combo excludes everything. Different copy because the
    // remediation is "change your filter," not "go race."
    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("No matches")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Try a different search or filter.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// Wrapper enum that lets the unified History feed render either
// a Race row or a Free Run row in the same scroll. Identifiable
// via the wrapped model's id (both Race and FreeRun have stable
// UUIDs), Hashable so SwiftUI's diffing identifies rows on
// updates.
//
// `createdAt` is the unified sort key — both models share the
// same field so a chronological mixed feed Just Works.
enum HistoryItem: Identifiable, Hashable {
    case race(Race)
    case run(FreeRun)

    var id: UUID {
        switch self {
        case .race(let r): return r.id
        case .run(let r): return r.id
        }
    }

    var createdAt: Date {
        switch self {
        case .race(let r): return r.createdAt
        case .run(let r): return r.createdAt
        }
    }
}

// Wireframe §04.1 primary mode. The athlete picks one of three
// views into their history archive:
//   • List     — reverse-chronological logbook, weekly grouped
//   • Calendar — month heatmap with race-day indicators
//   • Trends   — finish-time chart + station deep dive
// Search is reachable across all three via the .searchable
// nav-bar field; race detail is the universal tap-into.
enum HistoryMode: Int, CaseIterable, Identifiable, Hashable {
    case list
    case calendar
    case trends

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .list:     return "List"
        case .calendar: return "Calendar"
        case .trends:   return "Trends"
        }
    }
}

// Top-level activity-type filter. Sits ABOVE the existing race
// chips and gates which model types render. .runs short-circuits
// the race chips (which don't apply to free runs).
enum HistoryActivityKind: Int, CaseIterable, Identifiable, Hashable {
    case all
    case races
    case runs

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .all:   return "All"
        case .races: return "Races"
        case .runs:  return "Runs"
        }
    }
}

// Filter options shown as chips above the feed. CaseIterable +
// Identifiable so FilterChipRow can iterate them.
//
// `matches(_:allRaces:)` is the predicate each chip applies. PBs
// uses `RaceStats.wasPBWhenSet` against the cumulative history so
// the chip shows races that were PRs at the moment they were saved
// — same semantic as the trophy badge on the card itself.
enum HistoryFilter: Int, CaseIterable, Identifiable, Hashable {
    case all
    case thisMonth
    case pbsOnly
    case customWorkouts
    case withPhoto
    // Filter races by mode. Solo and duo are conceptually separate
    // — the athlete may want to see only their solo PBs (without
    // duo races inflating / contaminating the picture) or only
    // their duo races (to see partner history at a glance).
    case soloOnly
    case duoOnly

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .all:             return "All"
        case .thisMonth:       return "This Month"
        case .pbsOnly:         return "PBs Only"
        case .customWorkouts:  return "Custom"
        case .withPhoto:       return "With Photo"
        case .soloOnly:        return "Solo"
        case .duoOnly:         return "Duo"
        }
    }

    func matches(_ race: Race, allRaces: [Race]) -> Bool {
        switch self {
        case .all:
            return true
        case .thisMonth:
            // Race endedAt falling within the current calendar
            // month. Uses the user's local calendar so the same
            // race appears in the same month consistently.
            guard let end = race.endedAt else { return false }
            let cal = Calendar.current
            return cal.isDate(end, equalTo: Date(), toGranularity: .month)
        case .pbsOnly:
            return RaceStats.wasPBWhenSet(race, among: allRaces)
        case .customWorkouts:
            // A "custom workout" is any race whose station sequence
            // doesn't match the canonical 16-segment HYROX format.
            // Length difference is the cheap discriminator; if the
            // length matches we compare element-by-element.
            return race.sequenceRaw != Station.raceSequence.map(\.rawValue)
        case .withPhoto:
            return race.photoData != nil || race.photoURL != nil
        case .soloOnly:
            return race.mode == .solo
        case .duoOnly:
            return race.mode == .duo
        }
    }
}

// RaceStats (formatting + per-race/aggregate helpers) lives in
// Shared/RaceStats.swift — used by Race, History, and Profile.
// RaceCardView lives in Shared/Components/ — shared with Profile and
// the future social feed.

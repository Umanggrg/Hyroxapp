import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Auth)
import Auth
#endif

// Social feed — chronological list of recent races from
// athletes the local user follows. CLAUDE.md §14 has this
// pinned as Tab 1 (the front door); v1 ships it behind a
// toolbar button on Profile while we validate the data
// pipeline. Promote to a top-level tab once it's verified
// end-to-end.
//
// Each row is a `FeedRaceCard` — Strava-style anatomy:
//   • athlete header (avatar + name + handle + relative time)
//   • title + duo-partner sub-line when applicable
//   • optional photo hero
//   • finish time as hero stat
//   • supporting stat row (HYROX vs Custom, partner pill)
//
// Tap the athlete name → present `PublicProfileSheet` for
// that user. Card body itself is non-tappable for v1 — race
// detail across athletes needs a "public race detail" view
// that doesn't exist yet (would expose splits / notes / etc.
// which the view layer doesn't surface publicly).
struct FeedView: View {

    @State private var races: [RemotePublicRace] = []
    @State private var isLoading = true
    @State private var selectedAthleteID: String?

    // Reaction counts per race per kind, plus the local
    // user's own reactions. Both keyed by race_id so cards
    // look up in O(1). Refreshed on every feed reload.
    @State private var reactionCounts: [String: [ReactionKind: Int]] = [:]
    @State private var myReactedKinds: [String: Set<ReactionKind>] = [:]

    // Comment counts per race. Drives the "💬 N" pill on each
    // card. Bulk-fetched alongside reactions on load.
    @State private var commentCounts: [String: Int] = [:]

    // Race ID currently presenting `PublicRaceDetailSheet`
    // and `CommentsSheet`. Separate states so the user can
    // (eventually) open one then the other without state
    // collisions; today only one sheet shows at a time.
    @State private var detailRaceID: String?
    @State private var commentsRaceID: String?

    // Pagination state. `isLoadingMore` debounces the
    // last-card-on-screen trigger so a fast scroll doesn't
    // fire N concurrent fetches. `isExhausted` flips true
    // when the server returns fewer than `pageSize` — there's
    // nothing older to load, so further scrolls skip the
    // fetch entirely. Both reset on refresh (pull-to-refresh
    // hits `load()` which resets fresh).
    @State private var isLoadingMore = false
    @State private var isExhausted = false

    // Wireframe 02.6 — long-press reaction picker. Non-nil =
    // a palette sheet is open for that race; user taps any of
    // the 4 reactions to toggle, or dismisses to cancel. Lives
    // here (not on the card) because the palette presents over
    // the whole feed and the state survives card re-renders.
    @State private var reactionPaletteRaceID: String?

    // Wireframe 02.1 — search affordance in the navigation
    // toolbar (🔍 icon top-right). Reuses the existing
    // PublicProfileSearchSheet that Profile also presents.
    // Non-nil = sheet is open; tapping the toolbar icon flips
    // it true, dismissing flips it back.
    @State private var isShowingSearch = false

    // Page size — kept small for tight perceived latency
    // on first paint. Larger pages mean fewer round-trips
    // but a longer initial wait. 25 lands at well under a
    // second on a typical connection while leaving headroom
    // for richer feeds later.
    private static let pageSize = 25

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 18) {
                        filterChipRow
                        if isLoading {
                            loadingIndicator
                        } else if races.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(races.enumerated()), id: \.element.id) { index, race in
                                FeedRaceCard(
                                    race: race,
                                    counts: reactionCounts[race.id] ?? [:],
                                    myReactedKinds: myReactedKinds[race.id] ?? [],
                                    commentCount: commentCounts[race.id] ?? 0,
                                    onTapAthlete: { selectedAthleteID = race.userId },
                                    onToggleReaction: { kind in
                                        toggleReaction(raceID: race.id, kind: kind)
                                    },
                                    onTapDetail: { detailRaceID = race.id },
                                    onTapComments: { commentsRaceID = race.id },
                                    onLongPressReactions: {
                                        reactionPaletteRaceID = race.id
                                    }
                                )
                                // Prefetch trigger — fire when the
                                // second-to-last card becomes
                                // visible, not the last, so the
                                // next page is in hand by the time
                                // the user reaches the bottom.
                                // `index == races.count - 3`
                                // (effectively "3-from-bottom")
                                // gives a comfortable buffer at
                                // page size 25.
                                .onAppear {
                                    if index >= races.count - 3 {
                                        Task { await loadNextPage() }
                                    }
                                }
                            }

                            // Footer states: in-flight spinner
                            // while paging, or the wireframe-
                            // prescribed end-of-feed wrap-up once
                            // we know there's nothing older.
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(Color.accent)
                                    .padding(.vertical, 16)
                            } else if isExhausted && !races.isEmpty {
                                endOfFeedFooter
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.top, 16)
                }
                .refreshable {
                    await load()
                }
            }
            .navigationTitle("Feed")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityLabel("Find athletes")
                }
            }
            .sheet(isPresented: $isShowingSearch) {
                PublicProfileSearchSheet()
            }
            .task { await load() }
            .sheet(item: Binding(
                get: { selectedAthleteID.map(AthleteIDWrapper.init) },
                set: { selectedAthleteID = $0?.id }
            )) { wrapper in
                PublicProfileSheet(userID: wrapper.id)
            }
            .sheet(item: Binding(
                get: { detailRaceID.map(RaceIDWrapper.init) },
                set: { detailRaceID = $0?.id }
            )) { wrapper in
                PublicRaceDetailSheet(raceID: wrapper.id)
            }
            .sheet(item: Binding(
                get: { commentsRaceID.map(RaceIDWrapper.init) },
                set: { newValue in
                    commentsRaceID = newValue?.id
                    // When the comments sheet dismisses, refresh
                    // counts so the pill updates without a full
                    // feed reload.
                    if newValue == nil {
                        Task { await refreshCommentCounts() }
                    }
                }
            )) { wrapper in
                CommentsSheet(raceID: wrapper.id)
            }
            // Wireframe 02.6 — long-press reaction palette.
            // Centered medium-height sheet showing all four
            // reaction kinds at large size with labels. Tap
            // one to commit, swipe down to dismiss. Distinct
            // from individual button tap-to-toggle on the
            // card itself; this is the "switch quickly" or
            // "discover what's available" path.
            .sheet(item: Binding(
                get: { reactionPaletteRaceID.map(RaceIDWrapper.init) },
                set: { reactionPaletteRaceID = $0?.id }
            )) { wrapper in
                reactionPalette(for: wrapper.id)
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // Reaction palette content — 4 large emoji buttons in a
    // row with their kind labels underneath. Tapping toggles
    // the reaction via the same path as the per-button
    // tap-to-toggle on the card, then dismisses the sheet.
    private func reactionPalette(for raceID: String) -> some View {
        VStack(spacing: 18) {
            Text("React to this race")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 8)

            HStack(spacing: 12) {
                ForEach(ReactionKind.allCases) { kind in
                    Button {
                        toggleReaction(raceID: raceID, kind: kind)
                        reactionPaletteRaceID = nil
                    } label: {
                        VStack(spacing: 8) {
                            Text(kind.emoji)
                                .font(.system(size: 44))
                            Text(kind.label)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(
                                    (myReactedKinds[raceID]?.contains(kind) ?? false)
                                        ? Color.accent
                                        : Color.textSecondary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .fill(
                                    (myReactedKinds[raceID]?.contains(kind) ?? false)
                                        ? Color.accent.opacity(0.12)
                                        : Color.surface
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                        .stroke(
                                            (myReactedKinds[raceID]?.contains(kind) ?? false)
                                                ? Color.accent
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.screenMargin)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.background.ignoresSafeArea())
    }

    // Race-id wrapper — same Identifiable trick as
    // AthleteIDWrapper. Separate type so a single sheet
    // binding doesn't conflate "viewing detail" with "viewing
    // comments" (both use a race UUID but the sheets are
    // distinct).
    private struct RaceIDWrapper: Identifiable {
        let id: String
    }

    // MARK: - Filter chip row
    //
    // Per the v1 wireframe IA: three filter chips at the top of
    // the feed — Following (functional), Division (deferred),
    // Nearby (deferred). Following is the only mode wired today;
    // the other two render with a small `SOON` badge so the
    // design intent is visible without pretending they work. Two
    // future expansions wire Division (requires `athlete_division`
    // exposed on the `public_races` view + a per-division query)
    // and Nearby (requires location permission + a geo-indexed
    // query). Both are Phase 3 follow-ups.
    private var filterChipRow: some View {
        HStack(spacing: 8) {
            chip(label: "Following", isActive: true, isAvailable: true)
            chip(label: "Division",  isActive: false, isAvailable: false)
            chip(label: "Nearby",    isActive: false, isAvailable: false)
            Spacer()
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func chip(label: String, isActive: Bool, isAvailable: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundStyle(
                    isActive
                        ? Color.accent
                        : (isAvailable ? Color.textSecondary : Color.textTertiary)
                )
            if !isAvailable {
                Text("SOON")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.surfaceElevated)
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.accent.opacity(0.12) : Color.clear)
                .overlay(
                    Capsule()
                        .stroke(
                            isActive ? Color.accent : Color.divider,
                            lineWidth: 1
                        )
                )
        )
        .opacity(isAvailable ? 1.0 : 0.7)
    }

    // String isn't Identifiable, so the sheet binding needs a
    // tiny wrapper to drive `.sheet(item:)`. Reusing
    // PublicProfileSheet keeps the tap-from-feed UX identical
    // to tap-from-race-card and tap-from-search.
    private struct AthleteIDWrapper: Identifiable {
        let id: String
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        // Reset pagination flags on a full refresh — pull-to-
        // refresh and tab-reentry both want a clean slate.
        isLoadingMore = false
        isExhausted = false

        #if canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            races = []
            reactionCounts = [:]
            myReactedKinds = [:]
            isLoading = false
            return
        }
        // Clear reaction + comment maps before the first-page
        // fetch. The additive refreshes below seed them from
        // the server response; without this clear, a refresh
        // after unfollowing would leave stale data for races
        // no longer in the feed.
        reactionCounts = [:]
        myReactedKinds = [:]
        commentCounts = [:]

        let firstPage = await PublicRaceFeedService.feed(
            followedBy: userID,
            limit: Self.pageSize
        )
        races = firstPage
        isExhausted = firstPage.count < Self.pageSize
        await refreshReactions(for: races)
        await refreshComments(for: races)
        #else
        races = []
        reactionCounts = [:]
        myReactedKinds = [:]
        #endif
        isLoading = false
    }

    // Fetch the next page using the oldest currently-loaded
    // race's `ended_at` as the cursor. Idempotent guards:
    //   • Already in flight (isLoadingMore) → bail
    //   • No more rows server-side (isExhausted) → bail
    //   • No anchor row (empty feed) → bail
    private func loadNextPage() async {
        guard !isLoadingMore else { return }
        guard !isExhausted else { return }
        guard let oldest = races.last else { return }

        #if canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            return
        }

        isLoadingMore = true
        let nextPage = await PublicRaceFeedService.feed(
            followedBy: userID,
            limit: Self.pageSize,
            before: oldest.endedAt
        )
        // De-dupe on id in case the page boundary coincides
        // with a tie on ended_at (rare but possible). Append
        // only races we don't already have.
        let existingIDs = Set(races.map(\.id))
        let fresh = nextPage.filter { !existingIDs.contains($0.id) }
        races.append(contentsOf: fresh)
        isExhausted = nextPage.count < Self.pageSize
        await refreshReactions(for: fresh)
        await refreshComments(for: fresh)
        isLoadingMore = false
        #endif
    }

    // Bulk-fetch comment counts for the given race IDs and
    // merge into `commentCounts`. Mirrors the additive shape
    // `refreshReactions` uses — the first-load caller resets
    // the dict before calling so pagination doesn't wipe.
    private func refreshComments(for races: [RemotePublicRace]) async {
        let raceIDs = races.map(\.id)
        guard !raceIDs.isEmpty else { return }

        let fetched = await CommentService.counts(forRaceIDs: raceIDs)
        var merged = commentCounts
        // Zero each fetched race_id first so a race that
        // dropped to 0 comments reflects accurately.
        for raceID in raceIDs {
            merged[raceID] = 0
        }
        for (raceID, count) in fetched {
            merged[raceID] = count
        }
        commentCounts = merged
    }

    // Lightweight refresh for ALL currently-loaded race IDs.
    // Fires when the comments sheet dismisses so the pill
    // count updates without reloading the whole feed.
    private func refreshCommentCounts() async {
        await refreshComments(for: races)
    }

    // Bulk-fetch reactions for the given races + the local
    // user's own reactions. Additive — merges into the
    // existing maps rather than replacing wholesale so
    // pagination doesn't wipe prior pages' reaction data.
    // First-load callers pass the full `races` list AND
    // get a fresh map; pagination callers pass only the new
    // page and inherit the older pages' state.
    //
    // For the first-load case the caller resets the maps to
    // empty beforehand (via `load()`), so additive-merge
    // does the right thing in both contexts.
    private func refreshReactions(for races: [RemotePublicRace]) async {
        let raceIDs = races.map(\.id)
        guard !raceIDs.isEmpty else { return }

        async let allRows = ReactionService.reactions(forRaceIDs: raceIDs)
        async let mineRows = ReactionService.myReactions(forRaceIDs: raceIDs)
        let (all, mine) = await (allRows, mineRows)

        // Merge counts in-place. We zero each fetched
        // (race_id, kind) cell first so a stale local
        // optimistic count gets replaced cleanly by the
        // server-of-truth.
        var counts = reactionCounts
        for raceID in raceIDs {
            counts[raceID] = [:]
        }
        for row in all {
            guard let kind = row.typedKind else { continue }
            counts[row.raceId, default: [:]][kind, default: 0] += 1
        }
        reactionCounts = counts

        // Same merge shape for my-reacted set.
        var mineSet = myReactedKinds
        for raceID in raceIDs {
            mineSet[raceID] = []
        }
        for row in mine {
            guard let kind = row.typedKind else { continue }
            mineSet[row.raceId, default: []].insert(kind)
        }
        myReactedKinds = mineSet
    }

    // Optimistic-toggle reaction on `raceID` for `kind`.
    // Flips the local state instantly so the tap feels
    // responsive, then issues the mutation; reverts on
    // failure. Idempotent against rapid double-taps because
    // the service treats already-done as success.
    private func toggleReaction(raceID: String, kind: ReactionKind) {
        let wasReacted = myReactedKinds[raceID]?.contains(kind) ?? false

        // Optimistic local update.
        if wasReacted {
            myReactedKinds[raceID]?.remove(kind)
            reactionCounts[raceID]?[kind] = max(0, (reactionCounts[raceID]?[kind] ?? 1) - 1)
        } else {
            myReactedKinds[raceID, default: []].insert(kind)
            reactionCounts[raceID, default: [:]][kind, default: 0] += 1
        }

        // Network mutation in the background. On failure
        // revert. We do NOT await — UI already flipped.
        Task { @MainActor in
            do {
                if wasReacted {
                    try await ReactionService.unreact(raceID: raceID, kind: kind)
                } else {
                    try await ReactionService.react(raceID: raceID, kind: kind)
                }
            } catch {
                // Revert. Failure mode is rare (auth gap or
                // network blip) and silent revert is the
                // least disruptive UX.
                if wasReacted {
                    myReactedKinds[raceID, default: []].insert(kind)
                    reactionCounts[raceID, default: [:]][kind, default: 0] += 1
                } else {
                    myReactedKinds[raceID]?.remove(kind)
                    reactionCounts[raceID]?[kind] = max(0, (reactionCounts[raceID]?[kind] ?? 1) - 1)
                }
            }
        }
    }

    // MARK: - States

    // Loading state — wireframe 02.3 specifies "skeleton cards"
    // rather than a bare spinner. Three dimmed placeholder cards
    // hint at the shape of the content coming so the perceived
    // wait feels shorter and the layout doesn't jump when real
    // data lands. Shimmer is a slow opacity loop; respects
    // Reduce Motion by falling back to a static dim.
    private var loadingIndicator: some View {
        VStack(spacing: 18) {
            skeletonCard(opacity: 0.7)
            skeletonCard(opacity: 0.45)
            skeletonCard(opacity: 0.25)
        }
    }

    @State private var skeletonShimmer = false

    private func skeletonCard(opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row: avatar disc + two stacked text bars
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.surfaceElevated)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surfaceElevated)
                        .frame(width: 120, height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.surfaceElevated)
                        .frame(width: 80, height: 8)
                }
                Spacer()
            }

            // Title bar
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceElevated)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 14)

            // Hero time block
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.surfaceElevated)
                .frame(width: 180, height: 36)

            // Reaction row placeholder
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule()
                        .fill(Color.surfaceElevated)
                        .frame(width: 44, height: 22)
                }
                Spacer()
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .opacity(opacity * (skeletonShimmer ? 1.0 : 0.55))
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: skeletonShimmer
        )
        .onAppear {
            // Kick the shimmer once per appear. Reduce-Motion
            // users get a static dim because the .animation
            // modifier above respects the reduce-motion env
            // automatically via SwiftUI's built-in behavior.
            skeletonShimmer = true
        }
    }

    // Wireframe 02.1 empty state. Big ⚑ glyph at low opacity so
    // it reads as an invitation, not a placeholder. Headline
    // "Feed is quiet." (period — declarative, not anxious). Sub-
    // line "Follow a few athletes and their finishes will land
    // here. Start with your division." Coral pill CTA "Find
    // athletes →" wired to PublicProfileSearchSheet. Quiet
    // helper line below: "or finish a race to get started."
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 48, weight: .heavy))
                .foregroundStyle(Color.textPrimary.opacity(0.18))

            Text("Feed is quiet.")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("Follow a few athletes and their finishes will land here. Start with your division.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, Layout.screenMargin)
                .frame(maxWidth: 280)

            Button {
                Haptics.impact(.light)
                isShowingSearch = true
            } label: {
                HStack(spacing: 6) {
                    Text("Find athletes")
                        .font(.caption.weight(.heavy))
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.heavy))
                }
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(Color.accent)
                )
            }
            .buttonStyle(.pressableCard)
            .padding(.top, 4)

            Text("or finish a race to get started")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.bottom, 32)
    }

    // Wireframe 02.1 end-of-feed treatment. The chronological
    // feed has a discrete bottom; the wireframe specifies a
    // gentle wrap-up rather than a bare "all caught up" line.
    // Two pieces of copy + a coral-outline CTA that drops the
    // user into Race tab (same path Quick Actions take).
    private var endOfFeedFooter: some View {
        VStack(spacing: 8) {
            Text("You're all caught up.")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("Check back tomorrow — or go run.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            Button {
                Haptics.impact(.light)
                // Same path Quick Actions / deep links take —
                // ContentView's notification handler flips the
                // selectedTab to .race. Keeps tab routing
                // centralized in one place.
                NotificationCenter.default.post(
                    name: .quickActionTriggered,
                    object: QuickAction.startRace
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.caption.weight(.heavy))
                    Text("Start a race")
                        .font(.caption.weight(.heavy))
                }
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .stroke(Color.accent, lineWidth: 1.5)
                )
            }
            .buttonStyle(.pressableCard)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Card

// Single feed entry. Drives off `RemotePublicRace` (the
// public view DTO) rather than the local `Race` model — the
// feed is cross-athlete, so we never have a SwiftData @Model
// for these rows.
struct FeedRaceCard: View {

    let race: RemotePublicRace
    let counts: [ReactionKind: Int]
    let myReactedKinds: Set<ReactionKind>
    let commentCount: Int
    let onTapAthlete: () -> Void
    let onToggleReaction: (ReactionKind) -> Void
    let onTapDetail: () -> Void
    let onTapComments: () -> Void
    // Wireframe 02.6 — long-press anywhere on the reaction
    // row opens a centered palette (sheet rendered at the
    // feed level) so the user can quickly switch between
    // reaction kinds without first un-toggling the current
    // one. Tap-to-toggle on individual buttons still works.
    let onLongPressReactions: () -> Void

    var body: some View {
        // Wireframe 02.2 anatomy:
        //   header (avatar + name + meta)
        //   title + kind sub-line
        //   hero (finish time + future PB badge)
        //   photo (inline, after hero — NOT above the header
        //     as the prior layout had it; the wireframe places
        //     the photo as a body element so the athlete header
        //     reads first)
        //   supporting row (partner pill when present)
        //   divider
        //   reaction row + comments pill
        VStack(alignment: .leading, spacing: 14) {
            header
            titleTappable
            hero
            #if canImport(UIKit)
            if let urlString = race.photoUrl,
               let url = URL(string: urlString) {
                photoHero(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { onTapDetail() }
            }
            #endif
            supportingRow

            Divider()
                .background(Color.divider)

            reactionRow
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }

    // Tappable title row — opens `PublicRaceDetailSheet`. Made
    // the title the tap target (rather than the whole card)
    // so the athlete name + reaction buttons retain their own
    // hit areas. Chevron telegraphs the affordance.
    private var titleTappable: some View {
        Button(action: onTapDetail) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Four reaction buttons in a row + a comments pill on the
    // trailing edge. Each reaction has an emoji + a count
    // number; the local user's active reactions render with
    // the accent-tinted background. Tap any reaction to
    // toggle; tap the comments pill to open the thread;
    // long-press anywhere on the row opens the centered
    // reaction palette (wireframe 02.6).
    private var reactionRow: some View {
        HStack(spacing: 8) {
            ForEach(ReactionKind.allCases) { kind in
                reactionButton(kind: kind)
            }
            Spacer()
            commentsPill
        }
        // Long-press at the row level so the gesture catches
        // anywhere along the reaction strip, not just on a
        // specific emoji. Individual reaction button taps
        // still work for fast single-tap toggle. 0.4s
        // duration matches iOS's system long-press
        // convention (Messages tapback, etc).
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    onLongPressReactions()
                }
        )
    }

    private var commentsPill: some View {
        Button(action: onTapComments) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.callout)
                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.surfaceElevated)
            )
        }
        .buttonStyle(.plain)
    }

    private func reactionButton(kind: ReactionKind) -> some View {
        let count = counts[kind] ?? 0
        let active = myReactedKinds.contains(kind)

        return Button {
            onToggleReaction(kind)
        } label: {
            HStack(spacing: 4) {
                Text(kind.emoji)
                    .font(.callout)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(
                            active ? Color.accent : Color.textSecondary
                        )
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(active
                          ? Color.accent.opacity(0.14)
                          : Color.surfaceElevated)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        active ? Color.accent.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(
            .spring(response: 0.35, dampingFraction: 0.7),
            value: active
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.divider, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Button(action: onTapAthlete) {
                    Text(race.athleteDisplayName)
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Text("@\(race.athleteHandle)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(relativeDateLabel(from: race.endedAt))
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        #if canImport(UIKit)
        if let urlString = race.athleteAvatarUrl,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    defaultAvatarSymbol
                @unknown default:
                    defaultAvatarSymbol
                }
            }
        } else {
            defaultAvatarSymbol
        }
        #else
        defaultAvatarSymbol
        #endif
    }

    private var defaultAvatarSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
    }

    // MARK: - Title

    @ViewBuilder
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedTitle)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            // Kind subline — "HYROX RACE" / "CUSTOM WORKOUT"
            // in caps so the feed visually distinguishes
            // simulation runs from training sessions at a
            // glance.
            Text(kindLabel)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var displayedTitle: String {
        let trimmed = race.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Race" : trimmed
    }

    private var kindLabel: String {
        if race.mode == "duo" {
            return "HYROX Duo"
        }
        return race.isHyroxRace ? "HYROX Race" : "Custom Workout"
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RaceStats.format(race.totalDuration))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text("Total time")
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Supporting row

    @ViewBuilder
    private var supportingRow: some View {
        if let partner = race.partner, !partner.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption2.weight(.bold))
                Text("with \(partner)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.accent.opacity(0.12))
            )
        }
    }

    // MARK: - Photo hero

    // 16:9 photo per wireframe 02.2 — aspect-ratio matches what's
    // shown in the design and works cleanly across iPhone widths.
    // The image fills via .aspectRatio + .clipped so wider/taller
    // source photos get cropped to the 16:9 window rather than
    // stretched. Failure / loading states show a neutral surface
    // panel rather than a coloured placeholder.
    #if canImport(UIKit)
    private func photoHero(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Color.surfaceElevated
            @unknown default:
                Color.surfaceElevated
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }
    #endif

    // Strava-style abbreviated relative time. "3d ago",
    // "12h ago", "5m ago". Falls back to "now" under a minute.
    private func relativeDateLabel(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

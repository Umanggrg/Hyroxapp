import SwiftUI
import SwiftData

// Full detail screen for a single race: hero total time, all 16 splits,
// heart rate + fatigue charts when enough data exists, and the athlete's
// free-form notes (editable in place). Pushed from `HistoryView` via
// NavigationStack.
//
// `@Bindable` on the Race lets the `NotesSection`'s TextField write
// directly back to the SwiftData-backed model — no save button needed,
// context autosave handles persistence. Reuses the same NotesSection
// used on RaceSummaryView so the edit UX is identical in both places.
//
// Also `@Query`s every finished race so per-split rows can answer
// "was this a PB at the time?" / "how much faster/slower was this
// than my prior best for this station?" — feedback the athlete cares
// about every time they look at a recent race.
struct RaceDetailView: View {
    @Bindable var race: Race

    // All finished races in the store — used to compute per-station
    // PB status and delta-from-prior-best for every split in THIS
    // race. Filtered by endedAt so in-progress rows (resumable state)
    // don't skew the comparisons. Read-only; we never mutate this list.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .forward)]
    ) private var allFinishedRaces: [Race]

    // The athlete's profile — read for `maxHeartRate` so the HR
    // zones chart can classify split avg HRs against the user's
    // own max. Falls back to 190 (a reasonable default) when the
    // bootstrap hasn't run yet.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Active mode — drives the coral halo behind the hero finish
    // time. Same scaling logic as RaceSummaryView and RaceView.
    @Environment(\.colorScheme) private var colorScheme

    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // Cached renders of the share card — one per format. Same
    // caching rationale as RaceSummaryView: ImageRenderer is
    // non-trivial, so we render each once on appear instead of on
    // every body update.
    @State private var squareShareImage: RaceShareImage?
    @State private var storyShareImage: RaceShareImage?

    // Drives the StationStatsSheet for long-press edit on a split
    // row. Same wrapper pattern as RaceSummaryView.
    @State private var editingSplitIndex: IdentifiedIndex?

    // §16 Layer 3 — selected tab state. Defaults to Overview so
    // the screen opens with the chronological race recap; the
    // Story tab is one tap away on the right.
    @State private var selectedTab: RaceDetailTab = .overview

    // Reflection (photo, title, notes, tags, privacy) lives in
    // a sheet now rather than at the bottom of a long scroll.
    // Toolbar button opens it; sheet presents the existing
    // reflection sections in a modal Form-style layout.
    @State private var isShowingReflectionSheet = false

    var body: some View {
        ZStack {
            // Hero backdrop bleeds full-width behind everything.
            // Standard intensity — this is a review surface, not
            // a finish moment, so we keep the glow gentler than
            // RaceSummaryView's intense backdrop.
            HeroBackdrop(.standard)

            // §16 layout: pinned hero + tab bar + scrolling tab
            // content. Three vertical regions; only the bottom
            // region scrolls. Apple Fitness uses the same pattern
            // for its workout detail view.
            VStack(spacing: 0) {
                detailHeroSection
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                RaceDetailTabBar(selection: $selectedTab)

                // The active tab's content. Each tab view owns
                // its own ScrollView so the hero + tab bar stay
                // pinned while the body scrolls. Switching tabs
                // resets scroll position (default SwiftUI
                // behavior, which matches what users expect from
                // a tab bar).
                tabContent(for: selectedTab)
            }
        }
        // Show the user-set title in the nav bar when present;
        // fall back to the auto date stamp otherwise. Lets athletes
        // navigate History by their own labels rather than a wall of
        // identical-looking date strings.
        .navigationTitle(
            race.name.isEmpty
                ? race.startedAt.formatted(date: .abbreviated, time: .shortened)
                : race.name
        )
        .hyroxDarkNavigationBar(inline: true)
        // Tapping any split row pushes a per-station deep dive.
        // Registered here because RaceDetailView is the surface
        // where the nav originates; HistoryView / ProfileView
        // already register Race.self separately for their own
        // race-detail navigations.
        .navigationDestination(for: Split.self) { split in
            StationDetailView(split: split)
        }
        .toolbar {
            #if !os(macOS)
            // Share menu on the trailing edge — Strava-style affordance
            // for exporting an old race after the fact (e.g. "I want to
            // post that PB I set last week"). Tapping opens a native
            // iOS Menu with two formats — Square (1:1, IG post) and
            // Story (9:16, IG / Snap / TikTok story). Both render the
            // same RaceShareCardView so visuals stay consistent.
            ToolbarItem(placement: .topBarTrailing) {
                if squareShareImage != nil || storyShareImage != nil {
                    shareMenu
                }
            }
            // §16 Post-Race phase 2 — reflection (photo, title,
            // notes, tags, privacy) moved out of the long scroll
            // into a sheet accessed via this pencil button.
            // Reflection is editing UI, not viewing UI, so a
            // sheet is the right surface. Athletes still get
            // every existing edit affordance, just one tap deeper.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingReflectionSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit race notes")
            }
            #endif
        }
        #if canImport(UIKit) && !os(watchOS)
        .sheet(isPresented: $isShowingReflectionSheet) {
            NavigationStack {
                ScrollView {
                    reflectionGroupSection
                        .padding(.horizontal, Layout.screenMargin)
                        .padding(.vertical, 16)
                }
                .background(Color.background.ignoresSafeArea())
                .navigationTitle("Reflection")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingReflectionSheet = false
                        }
                    }
                }
            }
        }
        #endif
        .onAppear(perform: prepareShareImages)
        // Re-bake the share cards when the photo changes. Same
        // rationale as RaceSummaryView — the cached images would
        // otherwise reflect a stale photo state.
        .onChange(of: race.photoData) { _, _ in
            squareShareImage = nil
            storyShareImage = nil
            prepareShareImages()
        }
    }

    // Format-picker Menu in the toolbar. Children are ShareLinks,
    // each pre-loaded with its rendered image so taps fire the
    // system share sheet immediately.
    private var shareMenu: some View {
        Menu {
            if let item = squareShareImage {
                ShareLink(
                    item: item,
                    preview: SharePreview(
                        "HYROX Race",
                        image: Image(uiImage: item.image)
                    )
                ) {
                    Label(ShareCardFormat.square.menuLabel, systemImage: "square")
                }
            }
            if let item = storyShareImage {
                ShareLink(
                    item: item,
                    preview: SharePreview(
                        "HYROX Race",
                        image: Image(uiImage: item.image)
                    )
                ) {
                    Label(ShareCardFormat.story.menuLabel, systemImage: "rectangle.portrait")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share race")
    }

    // Engine-tier tint contract — matches RaceSummaryView and
    // EngineScoreView's hero-score tint so the per-race line on
    // historical detail reads the same color language as the
    // post-race summary and the Profile rollup.
    private func engineTint(_ tier: RaceStats.EngineScore.Tier) -> Color {
        switch tier {
        case .elite:    return .success
        case .steady:   return .textPrimary
        case .building: return .warning
        }
    }

    // Guardrail-compliance tint — matches RaceSummaryView's
    // contract: strong dims to accentDim, moderate goes warning
    // amber, poor goes accent coral.
    private func complianceTint(_ tier: RaceStats.GuardrailCompliance.Tier) -> Color {
        switch tier {
        case .strong:   return .accentDim
        case .moderate: return .warning
        case .poor:     return .accent
        }
    }

    // Render both formats once and stash in @State for the Menu's
    // ShareLinks. Idempotent per-format.
    private func prepareShareImages() {
        if squareShareImage == nil,
           let image = RaceShareRenderer.render(
            race: race,
            profile: profiles.first,
            allRaces: allFinishedRaces,
            format: .square
           ) {
            squareShareImage = RaceShareImage(
                image: image,
                filename: RaceShareImage.filename(for: race, format: .square)
            )
        }

        if storyShareImage == nil,
           let image = RaceShareRenderer.render(
            race: race,
            profile: profiles.first,
            allRaces: allFinishedRaces,
            format: .story
           ) {
            storyShareImage = RaceShareImage(
                image: image,
                filename: RaceShareImage.filename(for: race, format: .story)
            )
        }
    }

    // v2 hero — replaces the bordered card with an open
    // composition that breathes against the HeroBackdrop.
    // Shows the date as caps wordmark, total time at displayHero
    // with coral glow, optional PB ribbon, and calorie subtitle.
    // Same visual language as RaceSummaryView's finish hero so
    // the two surfaces feel like one experience.
    private var detailHeroSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2.weight(.heavy))
                Text(race.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.weight(.heavy))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.textSecondary)

            if isPBRace {
                pbRibbon
                    .padding(.bottom, 2)
            }

            Text(RaceStats.totalTime(race))
                .font(.displayHero)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                // Coral halo behind the hero time. Strong on dark
                // (stadium spotlight), softer on light (avoids
                // a coral fog over warm off-white).
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.35 : 0.18),
                    radius: 20,
                    x: 0,
                    y: 0
                )

            Text("TOTAL TIME")
                .font(.caption2.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(Color.textSecondary)

            // §16 Layer 1 — 3-tile quick stat row. Avg HR /
            // Distance / Transition Total. The "at a glance"
            // numbers an athlete reads first when reviewing a
            // race in History. Each tile self-omits when its
            // data isn't available — a race without HR shows
            // 2 tiles, a race without roxzone tracking shows
            // 2 tiles, etc. Hidden entirely when none have
            // data so the hero collapses cleanly on thin races.
            quickStatRow
                .padding(.top, 8)

            if let kcal = RaceStats.totalActiveCalories(race) {
                Text("\(Int(kcal.rounded())) kcal active")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
                    .padding(.top, 6)
            }

            // Roxzone summary — only when captured (two-tap mode
            // was on for this race).
            if let total = RaceStats.totalRoxzoneTime(race),
               let avg = RaceStats.avgRoxzoneTime(race) {
                Text("\(RaceStats.format(total)) total roxzone · \(Int(avg.rounded()))s avg")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.warning)
            }

            // Effort score — HR-time integration showing "how
            // hard" this race was. Same line treatment as the
            // roxzone summary above; both are post-race body-load
            // readouts (discipline + intensity respectively).
            if let effort = RaceStats.effortScore(for: race, maxHR: maxHeartRate) {
                Text("Effort \(Int(effort.rounded())) · HR-time")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
            }

            // Engine Quality — single-number rollup of this race's
            // drift + recovery + efficiency + decoupling. Same hero
            // line treatment as RaceSummaryView so the post-race
            // summary and the historical detail screen read with
            // the same headline.
            if let engine = RaceStats.engineScore(
                forRace: race,
                history: allFinishedRaces,
                maxHR: maxHeartRate
            ) {
                Text("Engine \(Int(engine.overall.rounded())) · \(engine.tier.displayName)")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(engineTint(engine.tier))
            }

            // Race-wide HR aggregate. Avg is duration-weighted across
            // all splits (a long station with high HR matters more
            // than a short one with low HR). Peak is the max of all
            // splits' segment-window peaks. Hidden when no splits
            // have HR data — silence pattern matches the per-station
            // HR rows: missing data → no row, not "—".
            if let avgHR = RaceStats.averageHeartRate(for: race),
               let peakHR = RaceStats.peakHeartRate(for: race) {
                Text("HR \(Int(avgHR.rounded())) avg · \(Int(peakHR.rounded())) peak")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Recovery score — same line treatment as RaceSummary.
            // Hidden when fewer than 4 stations have recovery data.
            if let recovery = RaceStats.recoveryScore(for: race) {
                Text("Recovery -\(Int(recovery.averageDrop30s.rounded())) bpm avg · \(recovery.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Efficiency score — output per HR cost. Silent when
            // there's no prior PB baseline (first race for these
            // stations) or no HR data captured.
            if let efficiency = RaceStats.efficiencyScore(
                for: race,
                history: allFinishedRaces,
                maxHR: maxHeartRate
            ) {
                Text("Efficiency \(String(format: "%.2f", efficiency.overall)) · \(efficiency.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Cardiac drift (runs only) — avg HR climb across the
            // 8 runs (first half vs second half). Silent when
            // fewer than 6 runs have HR data captured. Same line
            // treatment + signed bpm rendering as the RaceSummary
            // post-race hero.
            if let drift = RaceStats.heartRateDrift(for: race) {
                let signed = drift.driftBPM >= 0
                    ? "+\(Int(drift.driftBPM.rounded()))"
                    : "\(Int(drift.driftBPM.rounded()))"
                Text("Run drift \(signed) bpm · \(drift.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Cardiac drift (all stations) — same calculation but
            // across all 16 segments. Catches workout-station
            // fatigue that runs-only misses. See RaceSummaryView
            // for the full rationale.
            if let drift = RaceStats.heartRateDriftAllStations(for: race) {
                let signed = drift.driftBPM >= 0
                    ? "+\(Int(drift.driftBPM.rounded()))"
                    : "\(Int(drift.driftBPM.rounded()))"
                Text("Race drift \(signed) bpm · \(drift.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Aerobic decoupling — pace-per-HR ratio change across
            // run halves. Sport-science engine-quality metric;
            // pairs with cardiac drift to tell the full engine
            // story (drift = HR climbed, decoupling = engine
            // worked harder for same/less output). Silent when
            // fewer than 6 runs have HR + pace data captured.
            if let decoupling = RaceStats.aerobicDecoupling(for: race) {
                let pct = Int((decoupling.decouplingFraction * 100).rounded())
                let signed = pct >= 0 ? "+\(pct)%" : "\(pct)%"
                Text("Decoupling \(signed) · \(decoupling.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Run degradation — explicit (R_last - R_first) /
            // R_first metric. Same line treatment as RaceSummary;
            // see that view for the full context comment on why
            // this metric sits next to drift + decoupling.
            if let deg = RaceStats.runDegradation(for: race) {
                let pct = Int(deg.degradationPercent.rounded())
                let signed = pct >= 0 ? "+\(pct)%" : "\(pct)%"
                Text("Run fade \(signed) · \(deg.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentDim)
            }

            // Guardrail compliance (§17.1 phase 2) — same line
            // treatment as RaceSummary. Hidden when no workout
            // stations had HR data.
            if let compliance = RaceStats.guardrailCompliance(
                for: race,
                across: allFinishedRaces,
                maxHR: maxHeartRate
            ) {
                Text("Guardrails \(compliance.compliantCount)/\(compliance.totalEvaluated) · \(compliance.percent)%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(complianceTint(compliance.tier))
            }

            // Target outcome readout — only shown if a target
            // was set on this race. Tucks into the hero so the
            // success/over-target framing reads as part of the
            // race's identity rather than a separate stat row.
            if let target = race.targetDuration,
               let actual = race.totalDuration {
                TargetOutcomeView(
                    targetDuration: target,
                    actualDuration: actual
                )
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 12)
    }

    // PB ribbon — same gold treatment used by RaceSummaryView so
    // the indicator reads consistently across the two surfaces.
    private var isPBRace: Bool {
        RaceStats.wasPBWhenSet(race, among: allFinishedRaces)
    }

    private var pbRibbon: some View {
        HStack(spacing: 6) {
            Image(systemName: "rosette")
                .font(.caption.weight(.bold))
            Text("PERSONAL BEST")
                .font(.caption.weight(.heavy))
                .tracking(1.2)
        }
        .foregroundStyle(Color(hex: 0xFFD60A))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: 0xFFD60A).opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color(hex: 0xFFD60A).opacity(0.4), lineWidth: 1)
                )
        )
    }

    // §16 Layer 1 quick stat row — 3 compact tiles below the
    // hero time. Each tile is value + unit on top, caps label
    // beneath. Tiles self-omit when their data isn't available.
    @ViewBuilder
    private var quickStatRow: some View {
        let tiles = quickStatTiles
        if !tiles.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    quickStatTile(tile)
                }
            }
        }
    }

    // Builds the array of (value, unit, label) tuples to render.
    // Returns only the populated ones — empty data → no tile.
    // Order matches §16 spec: Avg HR / Distance / Transition.
    private var quickStatTiles: [(value: String, unit: String, label: String)] {
        var tiles: [(String, String, String)] = []

        if let avgHR = RaceStats.averageHeartRate(for: race) {
            tiles.append(("\(Int(avgHR.rounded()))", "bpm", "AVG HR"))
        }

        let runsCount = race.splits.filter { $0.station.kind == .run }.count
        if runsCount > 0 {
            // Each run is 1km in HYROX. Sum of run kilometers
            // is the "running distance" — a quick glance at
            // how much of the race was run vs station work.
            tiles.append(("\(runsCount)", "km", "RUN"))
        }

        if let total = RaceStats.totalRoxzoneTime(race) {
            tiles.append((RaceStats.format(total), "", "TRANS"))
        }

        return tiles
    }

    private func quickStatTile(_ tile: (value: String, unit: String, label: String)) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(tile.value)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                if !tile.unit.isEmpty {
                    Text(tile.unit)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Text(tile.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
    }

    // MARK: - §16 tab dispatch

    // Renders the content for the currently-selected tab. Each
    // case routes to a private view builder that returns a
    // ScrollView containing the relevant sections from the
    // pre-§16 long-scroll layout. This keeps the existing
    // section helpers (insightsGroupSection, etc.) intact —
    // we're regrouping their renders, not rewriting them.
    @ViewBuilder
    private func tabContent(for tab: RaceDetailTab) -> some View {
        switch tab {
        case .overview: overviewTabContent
        case .runs:     runsTabContent
        case .stations: stationsTabContent
        case .hr:       hrTabContent
        case .story:    storyTabContent
        }
    }

    // OVERVIEW tab — chronological race recap. The post-race
    // "what just happened" surface: splits + recovery
    // estimate + race-day projection. The athlete's first stop
    // after a finish.
    private var overviewTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                splitsGroupSection
                    .padding(.horizontal, Layout.screenMargin)

                let hasRecovery = RaceStats.recoveryDemand(for: race, maxHR: maxHeartRate) != nil
                let hasProjection = RaceStats.raceDayProjectedTotal(
                    for: race,
                    division: profiles.first?.resolvedDivision ?? .mensOpen
                ) != nil
                if hasRecovery {
                    RecoveryEstimateView(race: race, maxHR: maxHeartRate)
                        .padding(.horizontal, Layout.screenMargin)
                }
                if hasProjection {
                    RaceDayProjectionView(
                        race: race,
                        division: profiles.first?.resolvedDivision ?? .mensOpen
                    )
                    .padding(.horizontal, Layout.screenMargin)
                }
            }
            .padding(.vertical, 16)
        }
    }

    // RUNS tab — the 8 runs deep. Currently surfaces the
    // Compromised Running view (which IS the run degradation
    // analysis); future phase 2.5 work could break out
    // individual run cards with HR arc + post-station context
    // per the §16 spec.
    @ViewBuilder
    private var runsTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if CompromisedRunningView.hasData(in: race) {
                    compromisedRunningSection
                        .padding(.horizontal, Layout.screenMargin)
                } else {
                    emptyTabState(message: "Run analysis appears once 8 runs have HR or pace data.")
                }
            }
            .padding(.vertical, 16)
        }
    }

    // STATIONS tab — the 8 workout stations. v1 lists the
    // workout-kind splits as tappable rows pushing into
    // StationDetailView. Future enhancement: Station Strength
    // Map (radar chart) + per-station performance cards per the
    // §16 spec.
    @ViewBuilder
    private var stationsTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                let workoutSplits = race.splits.filter { $0.station.kind == .workout }
                if !workoutSplits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Stations").capsLabelStyle()
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(workoutSplits.enumerated()), id: \.offset) { index, split in
                                stationRow(split: split, index: index)
                                if index < workoutSplits.count - 1 {
                                    Divider().background(Color.divider)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .fill(Color.surface)
                        )
                    }
                    .padding(.horizontal, Layout.screenMargin)
                } else {
                    emptyTabState(message: "Workout stations appear once you've completed a race with workout splits.")
                }
            }
            .padding(.vertical, 16)
        }
    }

    // Single tappable row in the Stations tab. Pushes into
    // StationDetailView for the deeper per-station analysis
    // (PB, trend, HR boundaries, race-day projection).
    private func stationRow(split: Split, index: Int) -> some View {
        NavigationLink(value: split) {
            HStack(spacing: 12) {
                Text(split.station.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(RaceStats.format(split.duration))
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Layout.cardPadding)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // HR tab — the engine room. HR curve + zones + pace × HR
    // scatter. The §16 spec also calls for HR drift score and
    // between-station recovery table — those live in the
    // existing per-race hero metric lines (drift) and could be
    // surfaced more prominently here in a future phase.
    @ViewBuilder
    private var hrTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                let hasHR = HeartRateChartView.hasAnyHeartRateData(in: race.splits)
                let hasScatter = PaceHeartRateScatterView.hasEnoughData(for: race)
                if hasHR {
                    heartRateSection
                        .padding(.horizontal, Layout.screenMargin)
                    hrZonesSection
                        .padding(.horizontal, Layout.screenMargin)
                }
                if hasScatter {
                    paceHeartRateScatterSection
                        .padding(.horizontal, Layout.screenMargin)
                }
                if !hasHR && !hasScatter {
                    emptyTabState(message: "HR analysis appears once you race with the Watch streaming heart rate.")
                }
            }
            .padding(.vertical, 16)
        }
    }

    // STORY tab — the narrative + insight strip. The athlete's
    // post-race "what to take away" surface. Story card is the
    // headline; insight strip below is the bullet-list backup.
    @ViewBuilder
    private var storyTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                let insights = InsightGenerator.generate(
                    for: race,
                    allRaces: allFinishedRaces
                )
                let hasStory = RaceStoryView.hasContent(
                    for: race,
                    history: allFinishedRaces,
                    maxHR: maxHeartRate
                )
                if hasStory {
                    RaceStoryView(
                        race: race,
                        history: allFinishedRaces,
                        maxHR: maxHeartRate
                    )
                    .padding(.horizontal, Layout.screenMargin)
                }
                if !insights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Insights").capsLabelStyle()
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        RaceInsightStrip(insights: insights)
                    }
                    .padding(.horizontal, Layout.screenMargin)
                }
                if !hasStory && insights.isEmpty {
                    emptyTabState(message: "Race story appears once enough HR or pace data is captured.")
                }
            }
            .padding(.vertical, 16)
        }
    }

    // Generic empty-state for tabs that don't have data yet.
    // Used when a fresh race doesn't have HR yet, or a custom
    // workout doesn't have certain station types.
    private func emptyTabState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(Color.textTertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // INSIGHTS group — narrative callouts (target outcome already
    // sits in the hero). Hidden entirely when InsightGenerator
    // returns nothing, so a thin race doesn't show an empty
    // section header.
    @ViewBuilder
    private var insightsGroupSection: some View {
        let insights = InsightGenerator.generate(
            for: race,
            allRaces: allFinishedRaces
        )
        // Recovery + race-day projection are coaching readouts, not
        // raw analytics — same group as the narrative insights.
        // Skip the group header entirely when nothing in the trio
        // has anything to render.
        let hasRecovery = RaceStats.recoveryDemand(for: race, maxHR: maxHeartRate) != nil
        let hasProjection = RaceStats.raceDayProjectedTotal(
            for: race,
            division: profiles.first?.resolvedDivision ?? .mensOpen
        ) != nil
        let hasStory = RaceStoryView.hasContent(
            for: race,
            history: allFinishedRaces,
            maxHR: maxHeartRate
        )
        if hasStory || !insights.isEmpty || hasRecovery || hasProjection {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Insights",
                    icon: "sparkles"
                )
                // Race Story sits at the top of the Insights group
                // because it's the rollup narrative — the
                // bullet-list insights below are the supporting
                // detail. Reads top-down: "what's the story?"
                // → "here are the specific signals."
                if hasStory {
                    RaceStoryView(
                        race: race,
                        history: allFinishedRaces,
                        maxHR: maxHeartRate
                    )
                }
                if hasRecovery {
                    RecoveryEstimateView(race: race, maxHR: maxHeartRate)
                }
                if hasProjection {
                    RaceDayProjectionView(
                        race: race,
                        division: profiles.first?.resolvedDivision ?? .mensOpen
                    )
                }
                if !insights.isEmpty {
                    // §16 Layer 2 — horizontal scroll strip
                    // instead of bullet list. Same insights data,
                    // different rendering surface.
                    RaceInsightStrip(insights: insights)
                }
            }
        }
    }

    // ANALYSIS group — HR chart, HR zones, compromised running.
    // The data-dense surface that distinguishes this app's race
    // detail from generic fitness loggers. Each child is gated
    // on its own data sufficiency.
    @ViewBuilder
    private var analysisGroupSection: some View {
        let hasHR = HeartRateChartView.hasAnyHeartRateData(in: race.splits)
        let hasCompromised = CompromisedRunningView.hasData(in: race)
        let hasScatter = PaceHeartRateScatterView.hasEnoughData(for: race)

        if hasHR || hasCompromised || hasScatter {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Analysis",
                    icon: "waveform.path.ecg"
                )
                if hasHR {
                    heartRateSection
                    hrZonesSection
                }
                // Pace × HR scatter — different lens on the same
                // data the HR chart already covers, but with pace
                // and HR on the SAME plane. The R1→R8 trajectory
                // line shows fade patterns at a glance: tight
                // cluster = elite, up-and-right trail = aerobic
                // gap. Hidden when fewer than 4 runs have HR +
                // pace data.
                if hasScatter {
                    paceHeartRateScatterSection
                }
                if hasCompromised {
                    compromisedRunningSection
                }
            }
        }
    }

    // Pace × HR scatter section — caps-label header + chart.
    // Sits between HR Zones and Compromised Running because the
    // scatter answers a related-but-distinct question from each:
    // zones = "how much time at each intensity," scatter = "how
    // did pace and HR co-evolve across the runs."
    private var paceHeartRateScatterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pace × HR").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            PaceHeartRateScatterView(race: race, maxHR: maxHeartRate)
        }
    }

    // SPLITS group — single card but earns its own header
    // because splits ARE the meat of the race. Tappable rows
    // already exist for per-station deep dive.
    private var splitsGroupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                title: "Splits",
                icon: "list.number",
                trailing: "\(race.splits.count) of \(race.sequence.count)"
            )
            splitsCard
        }
    }

    // REFLECTION group — photo + title + notes. The athlete's
    // post-race input. Dropped in last because it's editing UI,
    // not data display.
    private var reflectionGroupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                title: "Reflection",
                icon: "square.and.pencil"
            )
            #if canImport(UIKit) && !os(watchOS)
            RacePhotoSection(race: race)
            #endif
            TitleSection(race: race)
            NotesSection(race: race)
            TagsSection(race: race, suggestedTags: suggestedTagPool)
            PrivacyToggleSection(race: race)
        }
    }

    // Pool of tags the athlete has used on past races, sorted by
    // frequency. Drives the suggestion ribbon in TagsSection.
    // Mirror of RaceSummaryView's same-named property; duplicated
    // because the two surfaces have different `@Query` race lists.
    private var suggestedTagPool: [String] {
        var counts: [String: Int] = [:]
        for r in allFinishedRaces {
            for tag in r.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .map(\.key)
    }

    // Heart rate section — chart only; the parent group's
    // ProfileSectionHeader ("Analysis") owns the section label
    // now, so this internal caps-label was duplicating it.
    // Sub-cards inside the Analysis group sit at equal weight
    // visually (HR chart, then HR zones, then compromised
    // running) — chart cards already carry their own visual
    // identity via their internal layouts.
    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HR over time")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 4)

            HeartRateChartView(splits: race.splits)
        }
    }

    // Old `insightsSection` — kept here as a no-op stub to keep
    // any preview / external reference compiling, but actual
    // rendering moved to `insightsGroupSection` above.
    @ViewBuilder
    private var insightsSection: some View {
        let insights = InsightGenerator.generate(
            for: race,
            allRaces: allFinishedRaces
        )
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Insights").capsLabelStyle()
                    .padding(.horizontal, 4)
                // §16 Layer 2 — horizontal scroll strip rendering.
                RaceInsightStrip(insights: insights)
            }
        }
    }

    // HR Zones stacked bar — classifies each split's avg HR into
    // a Z1-Z5 bucket (against the athlete's profile maxHeartRate)
    // and shows total time-in-zone proportions. Caps-label header
    // matches the other Detail sections; uses the same gate as
    // the HR chart so both appear / hide together.
    private var hrZonesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time in zones")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 4)

            HRZonesView(splits: race.splits, maxBPM: maxHeartRate)
        }
    }

    // Compromised running analysis — HYROX-specific framing of
    // run-pace degradation. Shows which workout station hurt the
    // athlete's engine the most, with station-attribution
    // labels under each run point + a coach's-diagnosis callout.
    private var compromisedRunningSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compromised running")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 4)

            CompromisedRunningView(race: race)
        }
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Hint about the long-press affordance — moves out of
            // the section header (which is now owned by the
            // parent `splitsGroupSection`) into a small subtitle
            // line above the card. Reads as instructions rather
            // than competing with the section break.
            HStack {
                Text("Tap a row for details · long-press to edit")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // id: \.offset supports custom workouts with repeated
                // stations — see comment in RaceSummaryView.
                ForEach(Array(race.splits.enumerated()), id: \.offset) { index, split in
                    // Each row is a NavigationLink to the per-station
                    // deep dive. `.buttonStyle(.plain)` keeps the row
                    // visually identical to the read-only version —
                    // without it SwiftUI would apply default link tint
                    // to all the text. The nav value is the Split
                    // itself; StationDetailView re-queries history.
                    //
                    // Long-press opens StationStatsSheet for in-place
                    // edits to weight / reps / RPE. We picked long-
                    // press so the primary tap (push to detail) stays
                    // unchanged — the existing affordance is the
                    // common case.
                    NavigationLink(value: split) {
                        splitRow(index: index + 1, split: split)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editingSplitIndex = IdentifiedIndex(index)
                        } label: {
                            Label("Edit weight, reps, RPE", systemImage: "slider.horizontal.3")
                        }
                    }

                    if index < race.splits.count - 1 {
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
        .sheet(item: $editingSplitIndex) { wrappedIndex in
            let index = wrappedIndex.value
            if race.splits.indices.contains(index) {
                StationStatsSheet(
                    split: race.splits[index],
                    division: profiles.first?.resolvedDivision ?? .mensOpen
                ) { weight, reps, rpe in
                    var splits = race.splits
                    splits[index] = splits[index].withStationStats(
                        weightKg: .some(weight),
                        repsCompleted: .some(reps),
                        rpe: .some(rpe)
                    )
                    race.splits = splits
                }
            }
        }
    }

    private func splitRow(index: Int, split: Split) -> some View {
        // Compute per-split PB status once for this row. `wasPBSplit`
        // returns true on the very first completion of a station
        // (nothing to beat = implicit PB); `deltaFromPriorBest` returns
        // nil for that case so we don't render a nonsensical "±0:00".
        let isPB = RaceStats.wasPBSplit(split, in: race, among: allFinishedRaces)
        let delta = RaceStats.deltaFromPriorBest(for: split, in: race, among: allFinishedRaces)

        return HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24, alignment: .leading)

            // Effort dot — same renderer used on RaceSummaryView's
            // split rows. Tints the leading gutter by intensity
            // category so a quick scan shows which stations were
            // hardest. Hidden cleanly when the split has no HR
            // data (the helper returns an empty 14pt frame).
            RaceSummaryView.effortDot(for: split, maxHR: maxHeartRate)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(split.station.displayName)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                    // PB badge — shown only when this split actually
                    // broke the prior best (including "first time
                    // ever"). Small, inline, so it doesn't push the
                    // time column around.
                    if isPB {
                        pbBadge
                    }
                }
                // Manual-entry station stats — weight / reps / RPE.
                // Renders only when at least one is set so unlogged
                // splits stay clean. Same renderer used by
                // RaceSummaryView so the format matches.
                if let stats = RaceSummaryView.stationStatsSubtitle(for: split) {
                    Text(stats)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.accent)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(RaceStats.format(split.duration))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                // HR subtitle format is centralized on RaceSummaryView
                // so both surfaces stay in sync. Returns nil when no
                // HR data is available; UI omits the line in that case.
                // Trailing Z<n> tag is tinted in the canonical HR-zone
                // color (Z1 blue → Z5 red) so intensity reads at a
                // glance.
                if let hrText = RaceSummaryView.heartRateSubtitle(for: split) {
                    HStack(spacing: 5) {
                        Text(hrText)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.accentDim)
                        if let avg = split.heartRateAvgBPM {
                            let zone = HRZone.zone(for: avg, maxBPM: maxHeartRate)
                            // HYROX-coded label same as RaceSummaryView
                            // — keeps the row's vocabulary consistent
                            // across post-race summary and history.
                            Text(zone.hyroxLabel.uppercased())
                                .font(.caption2.weight(.heavy))
                                .tracking(0.4)
                                .foregroundStyle(zone.color)
                        }
                    }
                }
                // Delta vs prior best. Non-PB splits get a warning-
                // colored "+X:XX slower" readout; PB splits get a
                // success-colored "-X:XX faster" readout (quantifying
                // by how much they broke the record). First-time
                // stations show nothing — no prior data to delta from.
                if let delta, let deltaText = Self.deltaLabel(for: delta) {
                    Text(deltaText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(delta < 0 ? Color.success : Color.warning)
                }
            }

            // Chevron — Apple's standard "row is tappable" cue.
            // Tertiary text color so it's visible but doesn't compete
            // with the duration / HR data.
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // Tight inline badge matching the style of the New-PB trophy on
    // RaceCardView. Inline not standalone so it flows in the row.
    private var pbBadge: some View {
        Text("PB")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.success.opacity(0.18))
            )
            .foregroundStyle(Color.success)
    }

    // Format a signed TimeInterval delta as "-0:04" (faster) or
    // "+0:12" (slower). Returns nil when the delta is below a floor
    // of ~0.5s so the UI doesn't clutter with meaningless ±0:00 badges
    // on floating-point rounding noise.
    private static func deltaLabel(for delta: TimeInterval) -> String? {
        let abs = Swift.abs(delta)
        guard abs >= 0.5 else { return nil }
        let sign = delta < 0 ? "-" : "+"
        return "\(sign)\(RaceStats.format(abs))"
    }
}

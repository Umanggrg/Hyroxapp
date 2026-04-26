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

    var body: some View {
        ZStack {
            // Hero backdrop bleeds full-width behind the scroll
            // content. Standard intensity — this is a review
            // surface, not a finish moment, so we keep the glow
            // gentler than RaceSummaryView's intense backdrop.
            HeroBackdrop(.standard)

            ScrollView {
                VStack(spacing: 24) {
                    detailHeroSection
                    insightsGroupSection
                    analysisGroupSection
                    splitsGroupSection
                    reflectionGroupSection
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, Layout.screenMargin)
                .padding(.top, 8)
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
            #endif
        }
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
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Insights",
                    icon: "sparkles"
                )
                RaceInsightsView(insights: insights)
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

        if hasHR || hasCompromised {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Analysis",
                    icon: "waveform.path.ecg"
                )
                if hasHR {
                    heartRateSection
                    hrZonesSection
                }
                if hasCompromised {
                    compromisedRunningSection
                }
            }
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
        }
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
                RaceInsightsView(insights: insights)
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
                if let hrText = RaceSummaryView.heartRateSubtitle(for: split) {
                    Text(hrText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.accentDim)
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

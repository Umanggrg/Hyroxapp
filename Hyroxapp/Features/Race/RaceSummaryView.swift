import SwiftUI
import SwiftData

// Post-race screen: total time hero, all 16 splits, a free-form notes
// field for "how did this feel?", and a Done button that returns the VM
// to its resting state (the race itself is already persisted and will
// appear in History).
//
// Notes are bound directly to the active `Race` via `@Bindable` so edits
// persist without a Save button — SwiftData autosaves on model dealloc
// and debounces context writes. The same binding is re-used on
// `RaceDetailView` so athletes can reflect and edit after the fact too.
struct RaceSummaryView: View {
    let viewModel: RaceViewModel

    // All finished races — used to compute the "set N station PBs"
    // insight, which only makes sense relative to the athlete's
    // history. Filtered by endedAt so unfinished resumable rows
    // don't skew the count. Same pattern as RaceDetailView.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .forward)]
    ) private var allFinishedRaces: [Race]

    // Single-row UserProfile drives the athlete footer on the
    // shareable race card (avatar, display name, handle, division).
    // Same `@Query` pattern as ProfileView.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Active mode — drives the coral halo behind the hero finish
    // time. Same scaling logic as the in-race CTAs.
    @Environment(\.colorScheme) private var colorScheme

    // Athlete's configured max HR. Drives the effort-score
    // computation surfaced under the time hero. Defaults to 190
    // if no profile bootstrapped yet (defensive).
    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // Cached renders of the share card — one per format. ImageRenderer
    // is non-trivial (lays out + rasterizes a SwiftUI view), so we
    // generate each once in `.onAppear` and reuse them for the
    // lifetime of the summary view. Story renders 1080×1920, square
    // renders 1080×1080.
    @State private var squareShareImage: RaceShareImage?
    @State private var storyShareImage: RaceShareImage?

    // Drives the StationStatsSheet for the row the user tapped.
    // Wrapped in `IdentifiedIndex` because raw Int doesn't
    // conform to Identifiable, which `.sheet(item:)` requires.
    @State private var editingSplitIndex: IdentifiedIndex?

    // Drives the on-appear count-up animation for the hero
    // total-time number. Starts at false; flips to true 0.1s
    // after appear so the spring transition fires after the view
    // has settled. The count-up itself is implemented as a
    // smooth interpolation between `0` and `viewModel.finalTime`
    // using the .contentTransition(.numericText) modifier.
    @State private var heroCountUpComplete = false

    // Drives the slide-in cascade of the supporting sections.
    // Each section's index drives a per-section delay so the
    // post-finish content reveals in a satisfying staircase
    // rather than all at once.
    @State private var sectionsRevealed = false

    var body: some View {
        // ZStack layers the hero backdrop behind the existing
        // scroll content. The backdrop bleeds full-width via
        // .ignoresSafeArea(), while the inner padding keeps
        // content readable.
        ZStack {
            HeroBackdrop(.intense)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 24)

                        finishHero

                        // Total active calories from HealthKit across all
                        // splits. Hidden when no segment had calorie data.
                        if let race = viewModel.activeRace,
                           let kcal = RaceStats.totalActiveCalories(race) {
                            Text("\(Int(kcal.rounded())) kcal burned")
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accent)
                        }

                        // Roxzone summary — total transition time +
                        // avg per transition. Only renders when
                        // roxzone data was captured (two-tap mode
                        // was on for this race).
                        if let race = viewModel.activeRace,
                           let total = RaceStats.totalRoxzoneTime(race),
                           let avg = RaceStats.avgRoxzoneTime(race) {
                            Text("\(RaceStats.format(total)) total roxzone · \(Int(avg.rounded()))s avg")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.warning)
                        }

                        // Effort score — HR-time integration
                        // showing "how hard" this race was as an
                        // interpretable single number. Sits next
                        // to the roxzone line because both are
                        // post-race body-load summaries: roxzone
                        // is "discipline," effort is "intensity."
                        if let race = viewModel.activeRace,
                           let effort = RaceStats.effortScore(for: race, maxHR: maxHeartRate) {
                            Text("Effort \(Int(effort.rounded())) · HR-time")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accent)
                        }

                    // Target outcome — only shown if the athlete set a
                    // goal. "Goal met" + green delta when beaten,
                    // warning delta when missed. Centralized in
                    // TargetOutcomeView so RaceDetailView uses the
                    // same format when reviewing past races.
                    if let race = viewModel.activeRace, let target = race.targetDuration {
                        TargetOutcomeView(
                            targetDuration: target,
                            actualDuration: viewModel.finalTime
                        )
                        .padding(.top, 4)
                    }

                    // Auto-generated narrative insights — PBs, HR
                    // peak, run fatigue. The view skips itself when
                    // no insights apply (e.g. first race ever, no
                    // HR data, even pacing). Section header only
                    // renders when the underlying view has content.
                    if let race = viewModel.activeRace {
                        let insights = InsightGenerator.generate(
                            for: race,
                            allRaces: allFinishedRaces
                        )
                        if !insights.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Insights").capsLabelStyle()
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                                RaceInsightsView(insights: insights)
                            }
                            .padding(.top, 8)
                        }
                    }

                    splitsCard
                        .padding(.top, 16)

                    // Title + notes live right under splits so the
                    // athlete's reflection ("call this race something,
                    // how did it feel") is adjacent to the data they're
                    // looking at. Only rendered when there's an active
                    // race — defensive, shouldn't happen in practice
                    // since summary only shows when a race has finished.
                    if let race = viewModel.activeRace {
                        // Photo first — most visually impactful piece
                        // of the reflection block. Empty by default,
                        // tap-to-add. When set, becomes the hero of
                        // the race card AND the shareable image.
                        #if canImport(UIKit) && !os(watchOS)
                        RacePhotoSection(race: race)
                            .padding(.top, 8)
                        #endif
                        TitleSection(race: race)
                            .padding(.top, 8)
                        NotesSection(race: race)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Layout.screenMargin)
            }

                // Bottom action bar: Share + Done side by side. Share
                // takes the secondary slot (icon + label, accent-tinted
                // outline) and Done stays the primary call-to-action so
                // there's still one obvious "I'm finished here" tap.
                // Stays out of the scroll view so both buttons remain
                // reachable no matter how long the splits / notes get.
                HStack(spacing: 12) {
                    if squareShareImage != nil || storyShareImage != nil {
                        shareMenu
                    }

                    Button(action: viewModel.finishSession) {
                        Text("Done")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: Layout.raceButtonHeight)
                            .background(Color.surfaceElevated)
                            .foregroundStyle(Color.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, Layout.screenMargin)
            }
        }
        // Render both share cards once when the summary appears.
        // Doing it here (vs. lazily on tap) means the Share menu is
        // ready to fire instantly with no spinner — Strava-style.
        .onAppear {
            prepareShareImages()
            // Trigger the hero count-up + section reveal cascade
            // on a small delay so the user feels the moment, not
            // a snap.
            withAnimation(Motion.heroSpring.delay(0.15)) {
                heroCountUpComplete = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                sectionsRevealed = true
            }
        }
        // Re-bake the share cards when the user adds / changes /
        // removes the race photo. Without this the cached images
        // would still show the no-photo background even after the
        // photo lands on the race row.
        .onChange(of: viewModel.activeRace?.photoData) { _, _ in
            squareShareImage = nil
            storyShareImage = nil
            prepareShareImages()
        }
    }

    // MARK: - Finish hero (v2 redesign)

    // The post-race moment. "FINISHED" caps wordmark in success
    // green, total time displayed at displayHero (88pt heavy
    // rounded), spring-animated fade-in. Coral glow sits behind
    // the time text so the moment reads as significant. Optional
    // PB ribbon when applicable lands above the time.
    private var finishHero: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.caption.weight(.heavy))
                Text("FINISHED")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
            }
            .foregroundStyle(Color.success)

            if isPBRace {
                pbRibbon
                    .padding(.bottom, 2)
            }

            Text(RaceStats.format(viewModel.finalTime))
                .font(.displayHero)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                // Coral halo behind the finish time. Stronger on
                // dark (reads as a stadium-finish spotlight),
                // softer on light (the hero already has plenty of
                // weight from the displayHero typography against
                // warm off-white).
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.20),
                    radius: 24,
                    x: 0,
                    y: 0
                )
                .scaleEffect(heroCountUpComplete ? 1.0 : 0.85)
                .opacity(heroCountUpComplete ? 1.0 : 0)

            Text("TOTAL TIME")
                .font(.caption2.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // PB ribbon — only shown when this race set a new PB at the
    // moment it was saved. Same wasPBWhenSet predicate the per-
    // card trophy uses, so the indicator aligns with the History
    // feed's own labelling.
    private var isPBRace: Bool {
        guard let race = viewModel.activeRace else { return false }
        return RaceStats.wasPBWhenSet(race, among: allFinishedRaces)
    }

    private var pbRibbon: some View {
        HStack(spacing: 6) {
            Image(systemName: "rosette")
                .font(.caption.weight(.bold))
            Text("NEW PERSONAL BEST")
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

    // Format-picker menu. Tapping "Share" opens a native iOS Menu
    // with two ShareLink children — Square (1:1) for IG posts,
    // Story (9:16) for IG / Snapchat / TikTok stories. Each child
    // hands its own pre-rendered image to the system share sheet.
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
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share")
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: Layout.raceButtonHeight)
            .foregroundStyle(Color.accent)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(Color.accent, lineWidth: 1.5)
            )
        }
    }

    // Bake the active race into both share-card formats and stash
    // them in @State for the Menu's ShareLinks. Idempotent — bails
    // per-format if the cached image already exists.
    private func prepareShareImages() {
        guard let race = viewModel.activeRace else { return }

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

    private var splitsCard: some View {
        VStack(spacing: 0) {
            // id: \.offset (not \.element.id) so custom workouts with
            // repeated stations (e.g. 3× Sled Push) render distinct rows.
            // Station.rawValue isn't unique across an array that allows
            // duplicates; position always is.
            ForEach(Array(viewModel.splits.enumerated()), id: \.offset) { index, split in
                Button {
                    editingSplitIndex = IdentifiedIndex(index)
                } label: {
                    splitRow(for: split)
                }
                .buttonStyle(.plain)

                if index < viewModel.splits.count - 1 {
                    Divider().background(Color.divider)
                }
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .sheet(item: $editingSplitIndex) { wrappedIndex in
            let index = wrappedIndex.value
            if viewModel.splits.indices.contains(index) {
                StationStatsSheet(
                    split: viewModel.splits[index],
                    division: profiles.first?.resolvedDivision ?? .mensOpen
                ) { weight, reps, rpe in
                    viewModel.updateStationStats(
                        splitIndex: index,
                        weightKg: weight,
                        repsCompleted: reps,
                        rpe: rpe
                    )
                }
            }
        }
    }

    private func splitRow(for split: Split) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(split.station.displayName)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                // HYROX-specific stats subtitle when set. "152kg ·
                // 100 reps · RPE 8" — only the present fields
                // render so a half-logged station doesn't show
                // dashes for what was skipped.
                if let stats = Self.stationStatsSubtitle(for: split) {
                    Text(stats)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.accent)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RaceStats.format(split.duration))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                // HR subtitle appears only when HealthKit had samples
                // in the segment window. Three shapes:
                //   both avg + max  →  "168 / 184 bpm"
                //   only avg        →  "168 bpm"
                //   neither         →  row has just the time, no subtitle
                if let hrText = Self.heartRateSubtitle(for: split) {
                    Text(hrText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.accentDim)
                }
            }
            // Edit chevron — small visual cue that the row is
            // tappable. Same pattern as the History detail rows.
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 6)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // Compact subtitle string built from the optional manual-
    // entry fields. Returns nil when none are set so the row
    // collapses cleanly. Centralized here so RaceDetailView
    // can use the same renderer for consistency.
    static func stationStatsSubtitle(for split: Split) -> String? {
        var parts: [String] = []
        if let weight = split.weightKg {
            // Drop the decimal when weight is a whole number to
            // keep the line tight.
            if weight.truncatingRemainder(dividingBy: 1) == 0 {
                parts.append("\(Int(weight)) kg")
            } else {
                parts.append(String(format: "%.1f kg", weight))
            }
        }
        if let reps = split.repsCompleted {
            parts.append("\(reps) reps")
        }
        if let rpe = split.rpe {
            parts.append("RPE \(rpe)")
        }
        if let roxzone = split.roxzoneSeconds, roxzone > 0 {
            // Roxzone is the transition INTO this segment.
            // Render with an arrow glyph so the meaning reads
            // visually ("→ 12s" = "12s transitioning in").
            parts.append("→ \(Int(roxzone.rounded()))s rox")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // Shared formatting between summary and detail views. Centralizing
    // the choice of "show avg / max / both" in one place keeps the two
    // surfaces consistent if the format changes (e.g. adding "(184 peak)"
    // phrasing later).
    static func heartRateSubtitle(for split: Split) -> String? {
        switch (split.heartRateAvgBPM, split.heartRateMaxBPM) {
        case (let avg?, let max?):
            return "\(Int(avg.rounded())) / \(Int(max.rounded())) bpm"
        case (let avg?, nil):
            return "\(Int(avg.rounded())) bpm"
        case (nil, let max?):
            // Edge case: max present but avg missing shouldn't happen
            // from a healthy `HKStatisticsQuery`, but handle it just in
            // case — labeled explicitly so it doesn't look like avg.
            return "\(Int(max.rounded())) bpm peak"
        case (nil, nil):
            return nil
        }
    }
}

// MARK: - Target outcome

// Post-race readout comparing actual finish time against the goal the
// athlete set at start. "Goal met · 1:15 ahead" (success green) or
// "Over target · 5:23 slower" (warning). Lives alongside the summary
// hero time and is reused on RaceDetailView for the same display on
// historical races.
//
// Exposed as a top-level struct (not private) so RaceDetailView can
// import it without duplicating format logic.
struct TargetOutcomeView: View {
    let targetDuration: TimeInterval
    let actualDuration: TimeInterval

    var body: some View {
        let delta = actualDuration - targetDuration
        let isMet = delta <= 0
        let absDelta = Swift.abs(delta)

        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMet ? "Goal met" : "Over target")
                    .font(.caption.weight(.semibold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                // Qualifier reads "1:15 ahead" when met, "5:23 slower"
                // when missed — describes *how* the actual differed
                // from the goal in plain language.
                Text("Target \(RaceStats.format(targetDuration)) · \(RaceStats.format(absDelta)) \(isMet ? "ahead" : "slower")")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isMet ? Color.success : Color.warning)
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}

// MARK: - Notes section

// Extracted into its own view so `@Bindable var race` has a stable
// declaration site — `@Bindable` can't be declared inline inside an
// if-let branch of the parent view's body.
//
// Reused as-is on `RaceDetailView` (shared component in intent;
// lives here alongside its primary caller until it earns promotion
// to Shared/Components/).
// Editable title field for a Race. Single-line TextField with
// placeholder "Name this race" — same affordance pattern as
// NotesSection so the two stack visually. Bound directly to the
// model via @Bindable; SwiftData autosaves on context flush so
// there's no Save button.
//
// Reused on RaceDetailView so titles can be edited / added
// retroactively (e.g. "I named this 'PR attempt' three weeks ago,
// updating to 'first sub-1:30'").
struct TitleSection: View {
    @Bindable var race: Race

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            TextField(
                "Name this race",
                text: $race.name
            )
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }
}

struct NotesSection: View {
    @Bindable var race: Race

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            // `axis: .vertical` with `lineLimit(3...8)` gives a TextField
            // that grows as the user types up to 8 visible lines before
            // internally scrolling. Matches Apple's standard notes field
            // look (Reminders, Notes app inline notes).
            TextField(
                "How did this feel?",
                text: $race.notes,
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }
}

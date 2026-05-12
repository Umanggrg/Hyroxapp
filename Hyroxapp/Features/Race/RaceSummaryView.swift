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

    // Pool of tags the athlete has used on previous races. Surfaced
    // in TagsSection's suggestion ribbon so common tags ("zone2",
    // "race-sim", "morning") become one-tap repeats. Sorted by
    // frequency descending — most-used tags surface first.
    private var suggestedTagPool: [String] {
        var counts: [String: Int] = [:]
        for race in allFinishedRaces {
            for tag in race.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .map(\.key)
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

    // Wireframe §03.5 — Post / Save sheet presentation state. Only
    // one can be active at a time. Tapping the corresponding
    // bottom-row CTA flips its flag; the sheet's own dismiss
    // route (× / Done / Share later) flips it back and routes
    // through viewModel.finishSession to return to the app's
    // resting state.
    @State private var isShowingPostComposer = false
    @State private var isShowingSaveOnlyConfirm = false

    var body: some View {
        // ZStack layers the hero backdrop behind the existing
        // scroll content. The backdrop bleeds full-width via
        // .ignoresSafeArea(), while the inner padding keeps
        // content readable.
        ZStack {
            HeroBackdrop(.intense)

            VStack(spacing: 0) {
                // v1 pinned-hero treatment — `finishHero` lifted
                // out of the ScrollView so the total time stays
                // anchored as the user scrolls through insights,
                // splits, photo, notes, etc. Wireframe §16 calls
                // for this pinned moment so the headline number
                // (total time + vs PB + vs target) doesn't slip
                // out of view while the athlete is reading the
                // breakdown.
                //
                // Animation is purely state-driven via
                // `.onAppear`'s `heroCountUpComplete` toggle —
                // pulling the hero out of the scroll doesn't
                // affect the entrance scaleEffect / opacity
                // springs.
                finishHero
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        // Small top breather inside the scroll
                        // region so the first content item
                        // (calories / engine / HR lines)
                        // doesn't crash into the pinned hero
                        // above. Was `Spacer(height: 24)` +
                        // `finishHero` pre-pinning; replaced
                        // with a smaller fixed spacer since
                        // the hero now lives outside.
                        Spacer().frame(height: 8)

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

                        // Engine Quality — single-number rollup of
                        // this race's drift + recovery +
                        // efficiency + decoupling. Sits at the top
                        // of the HR-derived hero block because it
                        // frames every metric below it ("Engine 72
                        // · Steady" tells the story; the lines
                        // beneath are the breakdown). Tinted
                        // semibold + monospaced score to read like
                        // a performance number, not a stat row.
                        if let race = viewModel.activeRace,
                           let engine = RaceStats.engineScore(
                               forRace: race,
                               history: allFinishedRaces,
                               maxHR: maxHeartRate
                           ) {
                            Text("Engine \(Int(engine.overall.rounded())) · \(engine.tier.displayName)")
                                .font(.caption.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(engineTint(engine.tier))
                        }

                        // Race-wide HR aggregate — duration-weighted
                        // avg + peak across the whole race. Silent
                        // when no HR data was captured (matches the
                        // per-station HR rows' missing-data
                        // treatment).
                        if let race = viewModel.activeRace,
                           let avgHR = RaceStats.averageHeartRate(for: race),
                           let peakHR = RaceStats.peakHeartRate(for: race) {
                            Text("HR \(Int(avgHR.rounded())) avg · \(Int(peakHR.rounded())) peak")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Recovery score — 30s post-segment HR drop
                        // averaged across all stations with capture.
                        // The HYROX-specific conditioning signal:
                        // tight transitions are about getting your
                        // HR back under control between efforts.
                        // Silent when fewer than 4 stations have
                        // recovery data captured.
                        if let race = viewModel.activeRace,
                           let recovery = RaceStats.recoveryScore(for: race) {
                            Text("Recovery -\(Int(recovery.averageDrop30s.rounded())) bpm avg · \(recovery.category.displayName)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Efficiency score — output (relative pace
                        // vs your PB) per unit of HR cost. Silent
                        // when the athlete has no prior PB to
                        // compare against (first race ever for
                        // these stations) or no HR data.
                        if let race = viewModel.activeRace,
                           let efficiency = RaceStats.efficiencyScore(
                               for: race,
                               history: allFinishedRaces,
                               maxHR: maxHeartRate
                           ) {
                            Text("Efficiency \(String(format: "%.2f", efficiency.overall)) · \(efficiency.category.displayName)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Cardiac drift (runs only) — avg HR climb
                        // across the 8 runs (first half vs second
                        // half). The clean prescribed-work signal:
                        // every run is the same 1km, so HR climb
                        // is unambiguously engine fade. Sign is
                        // intentionally rendered with explicit "+"
                        // so a climb reads as a climb, not as a
                        // neutral number. Silent when fewer than 6
                        // runs have HR data captured.
                        if let race = viewModel.activeRace,
                           let drift = RaceStats.heartRateDrift(for: race) {
                            let signed = drift.driftBPM >= 0
                                ? "+\(Int(drift.driftBPM.rounded()))"
                                : "\(Int(drift.driftBPM.rounded()))"
                            Text("Run drift \(signed) bpm · \(drift.category.displayName)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Cardiac drift (all stations) — same
                        // calculation but across all 16 segments.
                        // Catches cumulative fatigue from the
                        // workout stations that runs-only drift
                        // misses (sled push spike + lunges burn +
                        // wall balls grind all show up here).
                        // Renders as a separate line right under
                        // run drift so the athlete can compare
                        // the two — a big gap between them is
                        // diagnostic ("the workouts are beating
                        // me up more than the runs reveal").
                        if let race = viewModel.activeRace,
                           let drift = RaceStats.heartRateDriftAllStations(for: race) {
                            let signed = drift.driftBPM >= 0
                                ? "+\(Int(drift.driftBPM.rounded()))"
                                : "\(Int(drift.driftBPM.rounded()))"
                            Text("Race drift \(signed) bpm · \(drift.category.displayName)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Aerobic decoupling — pace-per-HR ratio
                        // change across run halves. Sport-science
                        // gold standard for engine quality. The
                        // percentage is signed so an athlete who
                        // somehow improves in the back half (rare,
                        // possible) sees a negative value. Silent
                        // when fewer than 6 runs have HR + pace
                        // data captured.
                        if let race = viewModel.activeRace,
                           let decoupling = RaceStats.aerobicDecoupling(for: race) {
                            let pct = Int((decoupling.decouplingFraction * 100).rounded())
                            let signed = pct >= 0 ? "+\(pct)%" : "\(pct)%"
                            Text("Decoupling \(signed) · \(decoupling.category.displayName)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Run degradation score — explicit
                        // (R_last - R_first) / R_first metric from
                        // §17.2. Tiered Elite <8% / Good <15% /
                        // Needs Work >15%. Sits next to drift +
                        // decoupling so the three "how-did-the-
                        // engine-fade?" signals cluster: drift is
                        // HR-only, decoupling is HR/pace ratio,
                        // degradation is pace-only. Together
                        // they triangulate the fade story.
                        if let race = viewModel.activeRace,
                           let deg = RaceStats.runDegradation(for: race) {
                            let pct = Int(deg.degradationPercent.rounded())
                            let signed = pct >= 0 ? "+\(pct)%" : "\(pct)%"
                            Text("Run fade \(signed) · \(deg.category.displayName)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentDim)
                        }

                        // Guardrail compliance (§17.1 phase 2) —
                        // post-race evaluation of the per-
                        // station HR ceiling system. Reads as
                        // "Guardrails 14/16 · 88%" with hero-
                        // dim tint when strong, warning amber
                        // when moderate, accent coral when
                        // poor. Silent when no workout
                        // stations had HR data.
                        if let race = viewModel.activeRace,
                           let compliance = RaceStats.guardrailCompliance(
                               for: race,
                               across: allFinishedRaces,
                               maxHR: maxHeartRate
                           ) {
                            Text("Guardrails \(compliance.compliantCount)/\(compliance.totalEvaluated) · \(compliance.percent)%")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(complianceTint(compliance.tier))
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

                    // Recovery estimate — bucketed coaching readout
                    // ("Hard · ~30-48 hours · Take tomorrow easy").
                    // Sits between the target outcome and the
                    // narrative insights so the post-race scroll
                    // reads: did you hit your goal → how hard was it
                    // → what to do next. Hidden cleanly when no HR
                    // data was captured for this race.
                    if let race = viewModel.activeRace {
                        RecoveryEstimateView(race: race, maxHR: maxHeartRate)
                            .padding(.top, 8)
                    }

                    // Race-day weight projection — when the athlete
                    // logged sub-race-weight on at least one station,
                    // surface what the race would total at official
                    // setup. Coaching honesty signal: "your fitness
                    // is here, race-day would be there." Hidden when
                    // every station was already at race weight.
                    if let race = viewModel.activeRace {
                        let division = profiles.first?.resolvedDivision ?? .mensOpen
                        RaceDayProjectionView(race: race, division: division)
                            .padding(.top, 8)
                    }

                    // Race Story — single-paragraph narrative
                    // summary of the race, drawn from the engine
                    // score context's dominant sub-metric driver.
                    // Sits above the bullet-list insights because
                    // it's the rollup story; the insights below
                    // are the supporting detail (drift line +
                    // recovery line + decoupling line + etc).
                    // Hidden when generator returns nil (race
                    // not finished, no anchor data).
                    if let race = viewModel.activeRace {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Story").capsLabelStyle()
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            RaceStoryView(
                                race: race,
                                history: allFinishedRaces,
                                maxHR: maxHeartRate
                            )
                        }
                        .padding(.top, 8)
                    }

                    // Auto-generated narrative insights as a §16
                    // Layer 2 horizontal scroll strip. Replaces
                    // the previous bullet-list rendering. The
                    // view skips itself when no insights apply
                    // (e.g. first race ever, no HR data, even
                    // pacing). Section header only renders when
                    // the underlying strip has content.
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
                                RaceInsightStrip(insights: insights)
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
                        TagsSection(
                            race: race,
                            suggestedTags: suggestedTagPool
                        )
                            .padding(.top, 8)
                        PrivacyToggleSection(race: race)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Layout.screenMargin)
            }

                // Wireframe §03.5 bottom action row — Post to feed
                // (coral primary) + Save only (outline secondary).
                // The Done CTA is replaced by these two: the athlete
                // commits to a posting choice, both paths end in
                // finishSession via their respective sheets. Share
                // menu still surfaces above as a tertiary chip.
                postOrSaveRow
                    .padding(.vertical, 16)
                    .padding(.horizontal, Layout.screenMargin)
            }
        }
        // Wireframe §03.5 post composer sheet. Presented when
        // the athlete taps "Post to feed" — captures caption,
        // photo, and feed-card toggles before the race lands in
        // the cross-athlete feed.
        .sheet(isPresented: $isShowingPostComposer) {
            if let race = viewModel.activeRace {
                RacePostComposerView(
                    race: race,
                    onPost: handlePostCommit,
                    onCancel: { isShowingPostComposer = false }
                )
                .presentationDragIndicator(.visible)
            }
        }
        // Wireframe §03.5 save-only confirmation. Presented when
        // the athlete taps "Save only" — confirms the private
        // save with a quiet green check + race recap + Done/Share
        // later options.
        .sheet(isPresented: $isShowingSaveOnlyConfirm) {
            if let race = viewModel.activeRace {
                RaceSaveOnlyConfirmView(
                    race: race,
                    onShareLater: handleSaveOnlyShareLater,
                    onDone: handleSaveOnlyDone
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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

    // MARK: - Wireframe §03.5 post / save bottom action row

    // Wireframe-spec bottom CTA pair: Post to feed (coral filled,
    // primary) + Save only (outline neutral, secondary). Tapping
    // Post opens the composer sheet; tapping Save opens the
    // private-save confirmation sheet. Both paths ultimately end
    // in viewModel.finishSession to return the app to its
    // resting state, but they take very different routes through
    // the sheets first.
    private var postOrSaveRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.impact(.light)
                isShowingPostComposer = true
            } label: {
                Text("Post to feed")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .fill(Color.accent)
                    )
            }
            .buttonStyle(.pressableCard)

            Button {
                Haptics.impact(.light)
                isShowingSaveOnlyConfirm = true
            } label: {
                Text("Save only")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.divider, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.pressableCard)
        }
    }

    // Called from RacePostComposerView when the athlete taps
    // Post. The composer has already committed caption / photo /
    // privacy onto the race row; we just close the sheet and
    // route the app back to its resting state.
    private func handlePostCommit() {
        isShowingPostComposer = false
        viewModel.finishSession()
    }

    // Called from RaceSaveOnlyConfirmView when the athlete taps
    // Share later — drops them onto the existing share-card flow
    // (Strava-style image export). The race is already privately
    // saved; sharing is opt-in afterthought.
    private func handleSaveOnlyShareLater() {
        isShowingSaveOnlyConfirm = false
        // The existing share menu is bound to the rendered images.
        // For v1 we just dismiss the confirmation and let the
        // athlete tap the Share chip on the summary screen if
        // they want — finishSession isn't called so they're
        // still on the summary view. Future: directly open the
        // share sheet from here.
    }

    // Called from RaceSaveOnlyConfirmView when the athlete taps
    // Done. Closes the confirmation + returns to the app's
    // resting state.
    private func handleSaveOnlyDone() {
        isShowingSaveOnlyConfirm = false
        viewModel.finishSession()
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

    // Engine-tier tint contract — green for elite, primary for
    // steady, amber for building. Mirrors the tint used on
    // `EngineScoreView`'s hero score so the per-race line and
    // the Profile rollup card speak the same color language.
    private func engineTint(_ tier: RaceStats.EngineScore.Tier) -> Color {
        switch tier {
        case .elite:    return .success
        case .steady:   return .textPrimary
        case .building: return .warning
        }
    }

    // Guardrail-compliance tint contract — strong reads as the
    // dim hero tint (consistent with other compliance lines),
    // moderate reads as warning amber, poor reads as coral.
    // Reading at a glance: dim = good, amber = caution, coral
    // = action required.
    private func complianceTint(_ tier: RaceStats.GuardrailCompliance.Tier) -> Color {
        switch tier {
        case .strong:   return .accentDim
        case .moderate: return .warning
        case .poor:     return .accent
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
            // Effort dot — small colored marker in the leading
            // gutter showing this split's intensity category. Reads
            // at-a-glance when scanning the splits list ("Sled
            // Push hit me hardest"). Hidden when no HR data was
            // captured so unmeasured rows don't show a misleading
            // "Recovery" green for any-old-station.
            //
            // Tint mirrors the per-station chip on
            // StationDetailView and the badge on RaceCardView so
            // the same color language reads consistently across
            // every effort surface in the app.
            Self.effortDot(for: split, maxHR: maxHeartRate)

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
                //   both avg + max  →  "168 / 184 bpm"  + "Z3" tag
                //   only avg        →  "168 bpm"        + "Z3" tag
                //   neither         →  row has just the time, no subtitle
                //
                // The trailing Z<n> tag is tinted in the canonical
                // HR-zone color (Z1 blue → Z5 red) so the athlete
                // can read intensity at a glance, not just BPM number.
                // Same palette as HRZonesView + the live HR chip on
                // RaceView, so the same zone reads the same color
                // across surfaces.
                if let hrText = Self.heartRateSubtitle(for: split) {
                    HStack(spacing: 5) {
                        Text(hrText)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.accentDim)
                        if let avg = split.heartRateAvgBPM {
                            let zone = HRZone.zone(for: avg, maxBPM: maxHeartRate)
                            // HYROX-coded label ("Race" / "Hard" /
                            // "Redline") instead of the generic Zn —
                            // reads as coaching guidance, not a
                            // training-plan abstraction. Same zone
                            // color so visual continuity is preserved.
                            Text(zone.hyroxLabel.uppercased())
                                .font(.caption2.weight(.heavy))
                                .tracking(0.4)
                                .foregroundStyle(zone.color)
                        }
                    }
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

    // Effort dot for the leading gutter of split rows. Small (6pt)
    // colored circle that matches the EffortCategory tint contract
    // used everywhere else — green for recovery, white for moderate,
    // amber for high, coral for very high. Returns a fixed-width
    // 14pt frame regardless of whether the dot renders, so rows
    // align cleanly whether the data is present or not.
    //
    // Static so RaceDetailView can call the same helper without
    // duplicating the rendering logic.
    @ViewBuilder
    static func effortDot(for split: Split, maxHR: Int) -> some View {
        let tint: Color? = {
            guard let category = RaceStats.effortCategory(forSplit: split, maxHR: maxHR) else {
                return nil
            }
            switch category {
            case .recovery: return .success
            case .moderate: return .textPrimary
            case .high:     return .warning
            case .veryHigh: return .accent
            }
        }()

        ZStack {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 14, alignment: .center)
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

// Privacy toggle — hides this race from any future-public surfaces
// (v1 social feed, leaderboards, public profile). Local History +
// Profile stats are unaffected; this controls EXTERNAL visibility
// only.
//
// Shipping the toggle now means existing races flagged private
// stay private when the social feed lights up — no retroactive
// "everything I logged in 2026 is suddenly public" surprise. The
// `Race.isPrivate` field defaults to false, matching the
// public-by-default Strava model.
struct PrivacyToggleSection: View {
    @Bindable var race: Race

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Privacy").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            Toggle(isOn: $race.isPrivate) {
                HStack(spacing: 12) {
                    Image(systemName: race.isPrivate ? "lock.fill" : "globe")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(race.isPrivate ? Color.warning : Color.textSecondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.isPrivate ? "Private race" : "Public race")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        Text(race.isPrivate
                            ? "Hidden from feed and leaderboards."
                            : "Will appear in feed and leaderboards.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .tint(Color.accent)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }
}

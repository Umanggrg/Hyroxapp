import SwiftUI
import SwiftData

// Navigation destinations for the Profile depth-behind-nav
// pushed views. Hashable enum so SwiftUI's
// `.navigationDestination(for:)` can dispatch on it. New
// destinations append cases here; the dispatch happens in
// ProfileView's body.
enum ProfileDestination: Hashable {
    case performanceDetail
    case trendsDetail
}

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

    // Templates power the `customCrafter` badge criterion ("save
    // three or more custom workouts"). Sort isn't important here —
    // the badge check is just a count.
    @Query(sort: [SortDescriptor(\WorkoutTemplate.createdAt, order: .forward)])
    private var templates: [WorkoutTemplate]

    // All race events, sorted by date ascending. SwiftData's
    // #Predicate macro doesn't allow global function calls like
    // Date() inside the filter body — it expands at compile time
    // and can only reference captured constants. So we fetch all
    // events here and filter to "upcoming" in the computed
    // property below using a runtime Date().
    @Query(sort: [SortDescriptor(\RaceEvent.date, order: .forward)])
    private var allRaceEvents: [RaceEvent]

    // All challenges — active, completed, abandoned. The
    // mostRecentActiveChallenge computed below filters down to
    // the single one we surface on Profile. Sorted descending by
    // createdAt so the freshest active one wins when multiple
    // happen to be active simultaneously (rare; the setup sheet
    // replaces existing).
    @Query(sort: [SortDescriptor(\Challenge.createdAt, order: .reverse)])
    private var challenges: [Challenge]

    // Future-dated race events. The Profile banner pulls
    // `upcomingEvents.first` for the headline countdown — we
    // surface only one event at a time in v1 even when multiple
    // exist, so the user has a single anchor to train against.
    // Boundary is startOfDay so the day-of-event still counts as
    // "upcoming" until midnight, not just until the saved hour.
    private var upcomingEvents: [RaceEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        return allRaceEvents.filter { $0.date >= today }
    }

    @State private var isEditing = false
    @State private var isShowingSettings = false

    // Drives the challenge setup sheet from the Next Up section.
    // Triggered by the empty-state CTA or the "Replace Challenge"
    // context menu on an existing active challenge.
    @State private var isShowingChallengeSheet = false

    // Drives the RaceEventEditSheet — non-nil with an event to
    // edit (or .create for the new-event path). Wrapped in an
    // optional with two cases via the small enum below so the
    // same sheet supports both create and edit paths from the
    // banner without needing two separate boolean flags.
    @State private var eventEditingMode: EventEditMode?

    private enum EventEditMode: Identifiable {
        case create
        case edit(RaceEvent)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let event): return event.id.uuidString
            }
        }
    }

    // Cached render of the profile share card. Same `.onAppear`
    // bake pattern used elsewhere — ImageRenderer is non-trivial,
    // so we generate the image once and reuse for the lifetime of
    // the view. Re-rendered when the underlying race count changes
    // (most common reason the card content shifts).
    @State private var profileShareImage: RaceShareImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    // v2 redesign: 6 grouped sections with strong
                    // visual breaks instead of the v1 flat 12-card
                    // stack. Each group's gating predicates are
                    // unchanged — empty groups skip their header
                    // entirely so a fresh user doesn't see a wall
                    // of empty section labels.
                    //
                    // .scrollTransition fades + slightly scales each
                    // child as it enters the visible viewport. The
                    // effect is most visible on first appearance
                    // (sections reveal sequentially as the scroll
                    // settles) and during pull-to-scroll (sections
                    // re-fade as they leave/enter the edges). Apple-
                    // grade entrance, no manual state plumbing.
                    LazyVStack(spacing: 28, pinnedViews: []) {
                        if let profile = profiles.first {
                            ProfileHero(
                                profile: profile,
                                raceCount: races.count,
                                pbDisplay: heroPBDisplay,
                                avgDisplay: heroAvgDisplay,
                                streakDays: heroStreakDays
                            )
                            .applyScrollAppearTransition()
                        }

                        if races.isEmpty {
                            // Fresh install: just race-event banner
                            // (so the user can pin their goal) plus
                            // the empty-stats inviter. No section
                            // headers needed yet.
                            VStack(spacing: 16) {
                                raceEventBanner
                                emptyStats
                            }
                            .padding(.horizontal, Layout.screenMargin)
                            .applyScrollAppearTransition()
                        } else {
                            nextUpSection.applyScrollAppearTransition()
                            summarySection.applyScrollAppearTransition()
                            performanceSection.applyScrollAppearTransition()
                            trainingSection.applyScrollAppearTransition()
                            personalBestsSection.applyScrollAppearTransition()
                            achievementsGroupSection.applyScrollAppearTransition()
                            recentSection.applyScrollAppearTransition()
                        }
                    }
                    .padding(.bottom, Layout.screenMargin)
                }
            }
            .navigationTitle("Profile")
            .hyroxDarkNavigationBar()
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            // MonthlyRecap is a value-type Hashable struct, so it
            // works directly as a navigation value. The destination
            // pushes the full recap screen + share button.
            .navigationDestination(for: MonthlyRecap.self) { recap in
                MonthlyRecapView(recap: recap)
            }
            // Yearly companion — same Hashable struct pattern.
            .navigationDestination(for: YearlyRecap.self) { recap in
                YearlyRecapView(recap: recap)
            }
            // Profile cleanup — Performance + Trends sections push
            // their secondary cards behind navigation taps so the
            // Profile overview stays focused on the headline
            // metrics. PerformanceDetailView houses the deep
            // Performance cards (HYROX Performance pillars, Race
            // Ready, HR Baseline, Station Fingerprint, Performance
            // Overload, Engine Impact); TrendsDetailView houses
            // the secondary trend charts (Time, Effort, HR Drift,
            // Run Fade, Recovery, Intensity Mix). Engine Score +
            // Engine Score Trend stay above-the-fold as the
            // headlines for each domain.
            .navigationDestination(for: ProfileDestination.self) { destination in
                let maxHR = profiles.first?.maxHeartRate ?? 190
                let division = profiles.first?.resolvedDivision ?? .mensOpen
                switch destination {
                case .performanceDetail:
                    PerformanceDetailView(
                        races: races,
                        division: division,
                        maxHR: maxHR
                    )
                case .trendsDetail:
                    TrendsDetailView(
                        races: races,
                        division: division,
                        maxHR: maxHR
                    )
                }
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
                // Share button — story-aspect athlete card export.
                // Hidden until the cached image is ready (renderer
                // is async on appear). Sits to the LEFT of Edit
                // because in iOS toolbars trailing items render
                // right-to-left in declaration order, and we want
                // Edit closest to the right edge as the primary
                // text action.
                if let item = profileShareImage {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: item,
                            preview: SharePreview(
                                "HYROX Athlete",
                                image: Image(uiImage: item.image)
                            )
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share profile")
                    }
                }
                #endif
            }
            .onAppear {
                bootstrapIfNeeded()
                prepareProfileShareImage()
            }
            // Re-bake the card when the race count changes — that's
            // the most common reason the card content shifts. We
            // could also key on profile fields (name, division)
            // but those rarely change at runtime; an over-eager
            // re-render here is cheap (one ImageRenderer pass) so
            // the slight redundancy isn't a problem.
            .onChange(of: races.count) { _, _ in
                profileShareImage = nil
                prepareProfileShareImage()
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isEditing) {
                if let profile = profiles.first {
                    EditProfileView(profile: profile)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                if let profile = profiles.first {
                    SettingsView(profile: profile)
                }
            }
            // RaceEventEditSheet — single sheet handles both
            // create and edit paths via the EventEditMode case.
            .sheet(item: $eventEditingMode) { mode in
                switch mode {
                case .create:
                    RaceEventEditSheet(existing: nil)
                case .edit(let event):
                    RaceEventEditSheet(existing: event)
                }
            }
            // ChallengeSetupSheet — picker for a new active
            // challenge. Replaces any existing active challenge
            // on commit (single-active invariant).
            .sheet(isPresented: $isShowingChallengeSheet) {
                ChallengeSetupSheet(existingChallenge: mostRecentActiveChallenge)
            }
            #endif
        }
    }

    // MARK: - v2 grouped sections

    // Each group below wraps related content under a single
    // ProfileSectionHeader so the page reads as 6 distinct
    // domains (NEXT UP / SUMMARY / PERFORMANCE / TRAINING /
    // PERSONAL BESTS / RECENT) rather than a flat 12-card list.
    // Inner cards keep their existing components — the
    // restructure is composition only, not new UI per card.

    // NEXT UP — future-facing race anchor PLUS today's readiness
    // signal. Both answer questions about TODAY's training context:
    //   • Race event banner — "what are you training for?"
    //   • Readiness banner — "should you train hard today?"
    // Together they're the forward-looking pair, separate from the
    // backward-looking summary/performance/training sections below.
    //
    // Readiness sits ABOVE the race event banner so the most
    // immediately-actionable signal (today's body state) reads
    // first. Race event countdown is a multi-week anchor; readiness
    // is the answer the athlete usually opened the app to find.
    private var nextUpSection: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190

        return VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                title: "Next Up",
                icon: "flag.checkered",
                accent: true
            )
            if ReadinessBanner.shouldShow(in: races, maxHR: maxHR) {
                ReadinessBanner(races: races, maxHR: maxHR)
            }
            // §17.3 Weakness-to-Workout — recommended workout
            // card driven by the athlete's lowest-FRS station.
            // Sits BELOW the readiness banner because readiness
            // answers "should I push today?" first; once that's
            // affirmative, this card answers "what should I
            // push?". Hidden when no compromised-running data
            // exists or athlete is already resilient on every
            // station.
            if RecommendedWorkoutCard.hasRecommendation(in: races) {
                RecommendedWorkoutCard(races: races)
            }
            raceEventBanner
            challengeBannerOrCTA
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // Active challenge — either the most recent active one or, when
    // none exist, a "Start a challenge" CTA that opens the setup
    // sheet. Renders below the readiness/event signals so the
    // forward-looking trio reads top to bottom: how you feel today
    // → what race you're training for → what goal you committed to.
    @ViewBuilder
    private var challengeBannerOrCTA: some View {
        if let active = mostRecentActiveChallenge {
            NavigationLink {
                EmptyView()  // placeholder for ChallengeDetailView (v2)
            } label: {
                ActiveChallengeBanner(challenge: active, races: races)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    isShowingChallengeSheet = true
                } label: {
                    Label("Replace Challenge", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    abandonChallenge(active)
                } label: {
                    Label("Abandon", systemImage: "trash")
                }
            }
        } else {
            Button {
                Haptics.impact(.light)
                isShowingChallengeSheet = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accent.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "target")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a Challenge")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color.textPrimary)
                        Text("Pick a goal — race count, sub-time, or streak.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .stroke(Color.accent.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.pressableCard)
        }
    }

    // Most recently created challenge that's still active (not
    // expired AND not completed). The Profile only ever surfaces
    // one — the single-active-challenge invariant from §1 of the
    // Challenge model.
    private var mostRecentActiveChallenge: Challenge? {
        challenges
            .filter { $0.isActive }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    // Hard delete — abandon = "I'm not pursuing this anymore."
    // Different from completion which sets completedAt.
    private func abandonChallenge(_ challenge: Challenge) {
        Haptics.warning()
        modelContext.delete(challenge)
        try? modelContext.save()
    }

    // SUMMARY — the recap trio + streak. Backwards-looking
    // synthesis of where the athlete has been recently.
    @ViewBuilder
    private var summarySection: some View {
        let hasYearly = (YearlyRecapBuilder.mostRecent(from: races) != nil)
        let hasMonthly = (MonthlyRecap.mostRecent(from: races) != nil)
        let hasStreak = StreakBannerView.shouldShow(in: races)
        let hasAtRiskBanner = StreakAtRiskBanner.shouldShow(in: races)

        if hasYearly || hasMonthly || hasStreak {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Summary",
                    icon: "calendar",
                    trailing: nil
                )
                // At-risk banner sits ABOVE the regular streak
                // banner — when both render together (streak alive
                // but no race yet today), the urgent CTA leads and
                // the standard counter follows. The at-risk banner
                // has its own warning treatment so the visual
                // hierarchy reads correctly.
                if hasAtRiskBanner {
                    StreakAtRiskBanner(races: races)
                }
                if let recap = YearlyRecapBuilder.mostRecent(from: races) {
                    yearlyRecapBanner(recap)
                }
                if let recap = MonthlyRecap.mostRecent(from: races) {
                    monthlyRecapBanner(recap)
                }
                if hasStreak {
                    StreakBannerView(races: races)
                }
            }
            .padding(.horizontal, Layout.screenMargin)
        }
    }

    // PERFORMANCE — the headline analytics. HYROX Performance
    // Score (3 pillars), Race-Ready check (5 stations),
    // Progressive Overload (sentence-style insights), Engine
    // Impact (cross-race weakness analysis). All gated on data
    // sufficiency at the component level.
    @ViewBuilder
    private var performanceSection: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        let division = profiles.first?.resolvedDivision ?? .mensOpen
        let hasPerf = HyroxPerformanceScoreView.hasAnyData(in: races)
        let hasReady = RaceReadyView.shouldShow(in: races)
        let hasOverload = PerformanceOverloadView.hasMeaningfulTrends(in: races)
        let hasEngine = EngineImpactView.shouldShow(in: races)
        let hasHRBaseline = PersonalHRBaselineView.hasEnoughData(in: races)
        let hasEngineScore = EngineScoreView.hasEnoughData(in: races, maxHR: maxHR)
        let hasStationFingerprint = StationFingerprintView.hasEnoughData(in: races)
        let hasHyroxScore = HyroxScoreView.hasEnoughData(in: races, division: division, maxHR: maxHR)

        // Profile cleanup: keep the two headline rollup metrics
        // inline (HYROX Score + Engine Quality), push the rest of
        // the Performance cards behind a "View Detail →" tap to
        // PerformanceDetailView. Same depth-behind-nav approach
        // the Race Start screen uses for Custom Workout.
        //
        // The "has more detail" gate is anything that lives in
        // PerformanceDetailView — when none of those cards have
        // data, the nav row hides too so a fresh-install athlete
        // doesn't see a teaser link to an empty page.
        let hasMoreDetail = hasPerf || hasReady || hasHRBaseline
            || hasStationFingerprint || hasOverload || hasEngine

        if hasHyroxScore || hasEngineScore || hasMoreDetail {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Performance",
                    icon: "bolt.fill"
                )
                // HYROX Score — §17.3 "credit score for HYROX
                // fitness" headline. All-time positioning
                // (Bronze → Elite). The single number to
                // screenshot.
                if hasHyroxScore {
                    hyroxScoreSection
                }

                // Engine Quality — recent-form HR rollup
                // (Building / Steady / Elite). Recent
                // conditioning state, complementary to HYROX
                // Score's all-time positioning.
                if hasEngineScore {
                    engineScoreSection
                }

                // Detail navigation — pushes PerformanceDetailView
                // with the deeper Performance cards. Mirrors the
                // "View All →" pattern Apple Fitness uses.
                if hasMoreDetail {
                    NavigationLink(value: ProfileDestination.performanceDetail) {
                        viewDetailRow(label: "View Performance Detail")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.screenMargin)
        }
    }

    // Reusable "View Detail →" row used by both the Performance
    // and Trends sections. Surface treatment matches the
    // existing card vocabulary on Profile (rounded surface,
    // subtle border) so the nav row reads as a sibling of the
    // cards above it, not an unrelated control.
    private func viewDetailRow(label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, Layout.cardPadding)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .stroke(Color.divider, lineWidth: 1)
                )
        )
    }

    // Station HR Fingerprint — per-station tendency map
    // (Runs + 7 workout stations). Sits between HR Baseline
    // (athlete-wide Z3 band) and Performance Overload because
    // it's the "who am I" signal at the station level — natural
    // bridge between the global baseline above and the specific
    // station signals (Engine Impact) below.
    private var stationFingerprintSection: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Station Fingerprint")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            StationFingerprintView(races: races, maxHR: maxHR)
        }
    }

    // Engine Quality composite score — single-number rollup
    // (drift + recovery + efficiency + decoupling). Top-of-
    // Performance positioning because it's the headline number;
    // the cards below break the rollup into specific surfaces
    // (HYROX score = pillar split, Race-Ready = race-weight
    // diagnostic, HR Baseline = athlete-specific Z3, etc.).
    private var engineScoreSection: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Engine Quality")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            EngineScoreView(races: races, maxHR: maxHR)
        }
    }

    // HYROX Score (0-1000) — the §17.3 credit-score-for-HYROX-
    // fitness headline. Combines best finish time + engine
    // rollup + pillar balance + race consistency into a single
    // tier (Bronze/Silver/Gold/Elite). Anchors the Performance
    // section as the "what am I as a HYROX athlete" identity
    // metric.
    private var hyroxScoreSection: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        let division = profiles.first?.resolvedDivision ?? .mensOpen
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HYROX Score")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            HyroxScoreView(races: races, division: division, maxHR: maxHR)
        }
    }

    // Personal HR baseline — athlete-specific race-pace HR band
    // (IQR + median) computed from their actual run splits across
    // recent races. Sits between Race-Ready (which talks about
    // weights) and the Overload trends so the Performance section
    // reads top-down: how am I built (pillars) → am I lifting
    // race-weight (race-ready) → what's my actual race HR target
    // (this) → how is volume + intensity trending (overload) →
    // which station hurts the engine most (engine impact). Hidden
    // when fewer than 8 run-split HR samples exist.
    private var hrBaselineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Race HR Target")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            PersonalHRBaselineView(races: races)
        }
    }

    // TRAINING — calendar heatmap + trends chart. The "what
    // does my training pattern look like" view.
    @ViewBuilder
    private var trainingSection: some View {
        let hasTrends = PerformanceTrendsView.hasEnoughData(in: races)

        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                title: "Training",
                icon: "chart.line.uptrend.xyaxis"
            )
            TrainingCalendarView(races: races)
            if hasTrends {
                trendsSection
            }
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // PERSONAL BESTS — single-card section for per-station PBs.
    // Earns its own header because PBs are an athlete's brag
    // sheet — the place they look first when a buddy asks
    // "what's your sled push time?"
    private var personalBestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                title: "Personal Bests",
                icon: "trophy.fill"
            )
            StationPersonalBestsView(races: races)
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // ACHIEVEMENTS — the badge wall. Hidden until any badge
    // has been earned so a fresh install doesn't see a row of
    // grey-locked tiles.
    @ViewBuilder
    private var achievementsGroupSection: some View {
        if BadgesView.hasAnyEarned(races: races, templates: templates) {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeader(
                    title: "Achievements",
                    icon: "rosette"
                )
                BadgesView(races: races, templates: templates)
            }
            .padding(.horizontal, Layout.screenMargin)
        }
    }

    // RECENT — the activity feed. Last 3 races as cards.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                title: "Recent Races",
                icon: "list.bullet.rectangle",
                trailing: races.count > 3 ? "Last 3 of \(races.count)" : nil
            )
            ForEach(recentRaces) { race in
                NavigationLink(value: race) {
                    RaceCardView(
                        race: race,
                        allRaces: races,
                        maxHR: profiles.first?.maxHeartRate ?? 190
                    )
                }
                .buttonStyle(.pressableCard)
            }
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // MARK: - Hero stats (drives ProfileHero tiles)

    // Pre-computed display strings so ProfileHero stays
    // formatting-agnostic. PB is the hero number; avg + streak
    // are supporting.
    private var heroPBDisplay: String {
        RaceStats.personalBest(races).map(RaceStats.format) ?? "—"
    }

    private var heroAvgDisplay: String {
        RaceStats.averageTotal(races).map(RaceStats.format) ?? "—"
    }

    private var heroStreakDays: Int {
        RaceStreaks.currentStreak(in: races)
    }

    // Most-recent finished races. Capped at 3 for a tight Strava-style
    // profile layout — if the user wants more, they use the History tab.
    private var recentRaces: [Race] {
        Array(races.prefix(3))
    }

    // HYROX Performance Score section — caps-label header + 3-tile
    // pillar grid. Sits between the aggregate stats grid and the
    // per-station Personal Bests so the layout reads top-down from
    // most-summary (counts/PB total) to most-detailed (per-station
    // bests). Now also surfaces a compact "Avg effort" pill under
    // the pillar grid when HR data exists across recent races.
    //
    // Distinct from `hyroxScoreSection` above which renders the
    // 0-1000 composite headline metric. This one is the 3-pillar
    // (Strength / Endurance / Engine) breakdown — both belong on
    // Profile but answer different questions.
    private var hyroxPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HYROX Performance")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            HyroxPerformanceScoreView(races: races)

            avgEffortLine
        }
    }

    // Compact "Avg effort N · HR-time across last X races" pill,
    // shown under the pillar grid when at least one finished race
    // has HR samples to score. Hidden silently when none do —
    // first-time users / athletes without an Apple Watch see only
    // the pillar grid.
    //
    // Computed from the same `RaceStats.averageEffortScore` helper
    // used everywhere else, so the number matches what the per-
    // race summary lines show.
    @ViewBuilder
    private var avgEffortLine: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        if let avg = RaceStats.averageEffortScore(across: races, maxHR: maxHR) {
            // Count of races that actually contributed a score —
            // shows "across 4 races" honestly even when the user
            // has 12 finished races but only 4 have HR data.
            let scoredCount = races
                .filter(\.isFinished)
                .compactMap { RaceStats.effortScore(for: $0, maxHR: maxHR) }
                .count

            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.heavy))
                Text("Avg effort \(Int(avg.rounded())) · HR-time across \(scoredCount) race\(scoredCount == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.accent.opacity(0.10))
            )
            .padding(.horizontal, 4)
        }
    }

    // Race-event banner — the future-facing anchor at the top of
    // Profile. Two visual states:
    //
    //   • Populated: coral-bordered card with the event name,
    //     "T-43 days" countdown, target time, optional location.
    //     Tap → edit sheet.
    //   • Empty: muted "Add upcoming race" placeholder. Tap →
    //     create sheet pre-filled with sensible defaults.
    //
    // The empty state intentionally renders even on a fresh
    // install — getting an athlete to pin their goal race ON DAY
    // ONE is the whole point. "What are you training for?" is
    // the first question this app should answer.
    @ViewBuilder
    private var raceEventBanner: some View {
        if let event = upcomingEvents.first {
            populatedRaceEventCard(event)
        } else {
            emptyRaceEventCard
        }
    }

    private func populatedRaceEventCard(_ event: RaceEvent) -> some View {
        Button {
            eventEditingMode = .edit(event)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.caption2.weight(.bold))
                    Text("NEXT RACE")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .foregroundStyle(Color.accent)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        if !event.location.isEmpty {
                            Text(event.location)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Spacer()

                    countdownTile(daysUntil: event.daysUntil)
                }

                // Bottom metadata row — division + target time.
                HStack(spacing: 12) {
                    metadataPill(
                        icon: "person.fill",
                        text: event.resolvedDivision.displayName
                    )
                    if let target = event.targetDuration {
                        metadataPill(
                            icon: "stopwatch.fill",
                            text: "Target \(RaceStats.format(target))"
                        )
                    }
                    Spacer()
                }
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.accent.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Right-aligned countdown tile in the populated banner.
    // "T-43" pre-race, "RACE DAY" on the day, "TODAY" same idea.
    // Past events shouldn't appear here (the @Query filters them
    // out), but we render "Past" defensively.
    private func countdownTile(daysUntil: Int) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if daysUntil > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("T-")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.accent)
                    Text("\(daysUntil)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accent)
                }
                Text(daysUntil == 1 ? "DAY" : "DAYS")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.accent)
            } else if daysUntil == 0 {
                Text("RACE")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accent)
                Text("DAY")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accent)
            } else {
                Text("PAST")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // Tight inline pill for division / target time. Same visual
    // weight as the badges + insight chips elsewhere.
    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.surface)
        )
    }

    // Empty-state placeholder when no upcoming event exists.
    // Dimmer than the populated card, dashed border to read as
    // "tap to fill in." The CTA is direct: "Add upcoming race"
    // rather than something abstract like "Set training goal."
    private var emptyRaceEventCard: some View {
        Button {
            eventEditingMode = .create
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add upcoming race")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Pin a HYROX event to anchor your training")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .strokeBorder(
                                Color.divider,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Yearly recap banner — broader-window analog of the monthly
    // banner. Visually distinct (calendar icon + "YEAR IN HYROX"
    // wordmark, larger year display) so the two banners stack
    // without feeling redundant. Only renders when there's at
    // least one race in the current year — a fresh January with
    // no races yet hides this and falls through to the monthly
    // banner alone.
    private func yearlyRecapBanner(_ recap: YearlyRecap) -> some View {
        NavigationLink(value: recap) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.caption2.weight(.bold))
                        Text("YEAR IN HYROX")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.accent)

                    Text(recap.displayName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("\(recap.raceCount) race\(recap.raceCount == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                        Text("·")
                            .foregroundStyle(Color.textTertiary)
                        Text("\(recap.monthsActive) of 12 months")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.accent.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Monthly recap banner — celebratory mini-card at the top of
    // the Profile stats stack. Two-row layout: caps-label "MONTH IN
    // HYROX" up top, big month name below it, race count + PB count
    // as a metadata row. Whole card is a NavigationLink to the full
    // MonthlyRecapView. Coral-tinted background gives it visual
    // weight versus the surrounding flat-surface cards.
    private func monthlyRecapBanner(_ recap: MonthlyRecap) -> some View {
        NavigationLink(value: recap) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "rosette")
                            .font(.caption2.weight(.bold))
                        Text("MONTH IN HYROX")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.accent)

                    Text(recap.displayName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("\(recap.raceCount) race\(recap.raceCount == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                        if recap.totalTimePBCount > 0 {
                            Text("·")
                                .foregroundStyle(Color.textTertiary)
                            Text("\(recap.totalTimePBCount) PB\(recap.totalTimePBCount == 1 ? "" : "s")")
                                .font(.caption.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(Color.success)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.accent.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.accent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Race-ready section — caps-label header is built into the
    // RaceReadyView itself (along with the "X of N" counter),
    // so this wrapper is just visibility-gated passthrough that
    // pulls the division from the live profile.
    private var raceReadySection: some View {
        RaceReadyView(
            races: races,
            division: profiles.first?.resolvedDivision ?? .mensOpen
        )
    }

    // (Old per-card `achievementsSection` wrapper removed; the
    // v2 redesign's grouped `achievementsGroupSection` above
    // owns the BadgesView placement under the new
    // ProfileSectionHeader treatment.)

    // Performance overload section — caps-label header + auto-
    // generated trend callouts. Same visibility-gated wrapper
    // pattern as Achievements; the parent already checks
    // hasMeaningfulTrends so this just adds the section header.
    private var overloadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progressive Overload")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            PerformanceOverloadView(races: races)
        }
    }

    // Engine Impact section — caps-label header + EngineImpactView
    // bars. Visibility gated by parent on `shouldShow(in: races)`
    // (3+ finished races, at least one multi-sample station). The
    // wrapper just adds the section header so the layout matches
    // the rest of Profile's section rhythm.
    private var engineImpactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Engine Impact")
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            EngineImpactView(races: races)
        }
    }

    // Performance trends section — caps-label header + chart, sandwiched
    // between Personal Bests and Recent Races. The chart itself is
    // gated on race count via PerformanceTrendsView.hasEnoughData; this
    // wrapper only adds the section header so the layout reads
    // consistently with the other Profile sections.
    //
    // Effort trend stacks below total-time trend when the athlete has
    // captured HR data on enough races. The two charts are
    // complementary — total time answers "am I getting faster," effort
    // answers "am I training harder." Skipping effort when HR is
    // missing keeps the section clean for athletes racing without a
    // watch.
    private var trendsSection: some View {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        let hasEffortTrend = EffortTrendView.hasEnoughData(in: races, maxHR: maxHR)
        let hasEffortDistribution = EffortDistributionView.hasEnoughData(in: races, maxHR: maxHR)
        let hasDriftTrend = HRDriftTrendView.hasEnoughData(in: races)
        let hasRecoveryTrend = RecoveryTrendView.hasEnoughData(in: races)
        let hasEngineTrend = EngineScoreTrendView.hasEnoughData(in: races, maxHR: maxHR)
        let hasRunDegradationTrend = RunDegradationTrendView.hasEnoughData(in: races)

        // Profile cleanup — keep the headline trend chart inline
        // (Engine Score Trend, the rollup of all other trends),
        // push the rest behind "View All Trends →" to
        // TrendsDetailView. Same depth-behind-nav approach as
        // Performance.
        //
        // Time Trend always renders in the detail view (the
        // PerformanceTrendsView shows a "not enough yet" empty
        // state on its own when needed), so the nav row appears
        // whenever there's at least one race; we never offer a
        // dead link.
        let hasMoreTrends = hasEffortTrend || hasEffortDistribution
            || hasDriftTrend || hasRecoveryTrend || hasRunDegradationTrend
            || !races.isEmpty  // Time Trend covers the always-on case

        return VStack(alignment: .leading, spacing: 12) {
            // Engine Score Trend — the headline rollup curve.
            // Composite of drift / recovery / efficiency /
            // decoupling. Stays above-the-fold because it's the
            // single answer to "where is my engine going."
            if hasEngineTrend {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Engine Score Trend")
                            .capsLabelStyle()
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    EngineScoreTrendView(races: races, maxHR: maxHR)
                }
            }

            // Detail navigation — pushes TrendsDetailView with
            // the secondary trend charts (Time, Effort, HR Drift,
            // Run Fade, Recovery, Intensity Mix).
            if hasMoreTrends {
                NavigationLink(value: ProfileDestination.trendsDetail) {
                    viewDetailRow(label: "View All Trends")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // (Old `recentRacesSection` was removed; the v2 redesign's
    // grouped `recentSection` above replaces it with the new
    // ProfileSectionHeader treatment + race-count trailing label.)

    // First-launch seeding. Runs every time ProfileView appears, but the
    // guard keeps it cheap — insert + save only happens once.
    private func bootstrapIfNeeded() {
        guard profiles.isEmpty else { return }
        let profile = UserProfile.makeDefault()
        modelContext.insert(profile)
        try? modelContext.save()
    }

    // Render the profile share card to a UIImage and stash in
    // @State for ShareLink. Idempotent — bails if the cached
    // image already exists or there's no profile yet (fresh
    // install where bootstrap hasn't completed).
    private func prepareProfileShareImage() {
        #if canImport(UIKit) && !os(watchOS)
        guard profileShareImage == nil,
              let profile = profiles.first
        else { return }

        let card = ProfileShareCardView(
            profile: profile,
            races: races,
            templates: templates
        )
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0  // 1080×1920 from a 360×640 canvas

        guard let cgImage = renderer.cgImage else { return }
        let uiImage = UIImage(cgImage: cgImage)

        profileShareImage = RaceShareImage(
            image: uiImage,
            filename: "HYROX-Profile-\(profile.handle.isEmpty ? "athlete" : profile.handle).png"
        )
        #endif
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

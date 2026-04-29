import SwiftUI
import SwiftData

// App root. A `TabView` gives us Race (for running a race), History (for
// reviewing past races), and Profile (identity + aggregate stats).
//
// The tint is pinned to our accent red so selected tabs match the rest of
// the brand without relying on system defaults.
//
// On first appear, seeds three starter WorkoutTemplate rows so a fresh-
// install user lands in the Custom Workout Builder with usable presets
// (Half HYROX / Strength Day / Conditioning) instead of an empty picker.
struct ContentView: View {

    // The app's SwiftData context, injected via the .modelContainer
    // modifier on HyroxappApp's WindowGroup. Used here to one-shot
    // seed default templates on first launch and bootstrap a default
    // UserProfile if none exists.
    @Environment(\.modelContext) private var modelContext

    // Profile + race count drive the onboarding gate. We need both
    // because:
    //   • profiles.isEmpty → brand-new install, definitely show wizard
    //   • profile.hasCompletedOnboarding == false → either a true new
    //     install OR an existing user from before the wizard shipped.
    //   • races.count > 0 → existing user; auto-mark them onboarded
    //     so they don't see the wizard on their next launch after
    //     this update lands.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    @Query(filter: #Predicate<Race> { $0.endedAt != nil })
    private var finishedRaces: [Race]

    @State private var isShowingOnboarding = false

    // Drives the What's New sheet — true when the launching version
    // differs from `UserProfile.lastSeenWhatsNewVersion`. Set in
    // `bootstrap()` after the profile loads; cleared on dismiss
    // when we also write the version back so the sheet doesn't
    // re-appear until the next bump.
    @State private var isShowingWhatsNew = false

    // Tracks the currently-selected tab. Quick Actions swap this
    // binding programmatically — tap "View History" on a long-
    // press → app launches → tab flips to .history without the
    // user touching anything.
    @State private var selectedTab: Tab = .race

    enum Tab: Hashable {
        case race, history, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RaceView()
                .tag(Tab.race)
                .tabItem {
                    Label("Race", systemImage: "flag.checkered")
                }

            HistoryView()
                .tag(Tab.history)
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }

            ProfileView()
                .tag(Tab.profile)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(Color.accent)
        // Drive color scheme from the user's setting. `.system`
        // resolves to nil → SwiftUI follows the iOS-wide mode; the
        // other two cases force light or dark. Was hardcoded
        // `.dark` pre-light-mode; now reactive to Settings →
        // Appearance picker.
        .preferredColorScheme(profiles.first?.resolvedThemePreference.colorScheme)
        // Solid background on the tab bar — the iOS default
        // translucency softens the dark theme more than we want
        // and lets content bleed through on scroll. .visible
        // forces the bar to render its own background so the
        // accent-coral icons sit on a stable surface.
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.background, for: .tabBar)
        .onAppear(perform: bootstrap)
        // Receive Quick Action taps from the AppDelegate. Routing
        // is centralized here so individual tabs don't have to
        // reach into UIApplication state — they just observe the
        // shared `quickActionTriggered` notification or the
        // pendingQuickAction trigger below.
        .onReceive(NotificationCenter.default.publisher(for: .quickActionTriggered)) { note in
            handleQuickAction(note.object as? QuickAction)
        }
        // Deep-link routing. Posted from HyroxappApp.onOpenURL
        // when the Live Activity's widgetURL lands. Currently
        // only the trakr://race path exists — flips the TabView
        // straight to the Race tab so tapping the lock-screen
        // activity always returns the athlete to their in-progress
        // race. New paths (history detail, profile share) plug
        // in as additional cases without touching the scene-
        // level handler.
        .onReceive(NotificationCenter.default.publisher(for: .trakrDeepLink)) { note in
            guard let url = note.object as? URL else { return }
            handleDeepLink(url)
        }
        // Re-schedule the streak reminder whenever the race count
        // changes. After a race finishes, today's training has
        // already protected the streak, so the pending reminder
        // gets cancelled. After a race is deleted (e.g. via
        // Settings → Clear all), the schedule re-evaluates from
        // the now-shorter history.
        .onChange(of: finishedRaces.count) { _, _ in
            guard let profile = profiles.first else { return }
            rescheduleStreakReminderIfNeeded(profile: profile)
        }
        // React to mid-session onboarding-flag flips. The Settings
        // "Reset onboarding" action sets the flag to false and
        // dismisses Settings — without this observer the wizard
        // would only appear on the next app cold-start, which is
        // a worse UX. Now: tap Reset → Settings closes → wizard
        // appears immediately.
        .onChange(of: profiles.first?.hasCompletedOnboarding) { _, completed in
            if completed == false {
                isShowingOnboarding = true
            }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            // Gate the sheet on the profile's existence — the
            // bootstrap call below guarantees one exists by the time
            // the sheet would render, but the optional unwrap keeps
            // SwiftUI happy with the @Bindable contract.
            if let profile = profiles.first {
                OnboardingView(profile: profile)
                    .interactiveDismissDisabled()
                    // Honor the same theme preference inside the
                    // sheet — sheets present in their own scene
                    // and don't inherit `.preferredColorScheme`
                    // from the host. nil = follow system.
                    .preferredColorScheme(profile.resolvedThemePreference.colorScheme)
            }
        }
        // What's New sheet — fires once per version bump for
        // existing users. Dismissing writes the current marketing
        // version back so it doesn't re-appear until the next
        // bump.
        .sheet(
            isPresented: $isShowingWhatsNew,
            onDismiss: markWhatsNewSeen
        ) {
            if let profile = profiles.first {
                WhatsNewView()
                    .preferredColorScheme(profile.resolvedThemePreference.colorScheme)
            } else {
                WhatsNewView()
            }
        }
    }

    // Records that the current marketing version's What's New has
    // been seen, so the sheet doesn't re-appear on the next launch.
    // Called from the sheet's `onDismiss`. No-op if the profile
    // doesn't exist (shouldn't happen — bootstrap ensures one).
    private func markWhatsNewSeen() {
        guard let profile = profiles.first else { return }
        profile.lastSeenWhatsNewVersion = WhatsNewView.currentMarketingVersion
        try? modelContext.save()
    }

    // First-launch setup: ensure templates exist, ensure a UserProfile
    // exists, decide whether to show the onboarding wizard. Idempotent
    // on every dimension — running it on every TabView reappear is
    // safe because each branch has its own "already done?" guard.
    private func bootstrap() {
        WorkoutTemplate.seedDefaultsIfNeeded(in: modelContext)

        // Ensure exactly one profile exists. This used to live in
        // ProfileView's onAppear but it has to run regardless of
        // which tab the user lands on — the wizard depends on it.
        if profiles.isEmpty {
            let profile = UserProfile.makeDefault()
            modelContext.insert(profile)
            try? modelContext.save()
        }

        guard let profile = profiles.first else { return }

        // Auto-onboard existing users (pre-wizard release) so they
        // don't get a wizard prompt out of nowhere. Anyone who's
        // finished a race has clearly set things up already; no
        // need to walk them through it again.
        if !profile.hasCompletedOnboarding && !finishedRaces.isEmpty {
            profile.hasCompletedOnboarding = true
            try? modelContext.save()
        }

        // Re-evaluate notification scheduling on every launch.
        // Streak protection is a daily concern — the calendar may
        // have rolled forward since the last schedule, the
        // streak might be longer/shorter, today's race may
        // already be in the bag. Running this on every appear
        // keeps the schedule fresh without needing a background
        // task.
        rescheduleStreakReminderIfNeeded(profile: profile)

        // Brand-new install (or user who somehow has neither races
        // nor a completed wizard) → show the wizard.
        if !profile.hasCompletedOnboarding {
            isShowingOnboarding = true
        } else {
            // Existing users see the What's New sheet once per
            // version bump. Skip the sheet for first-time users
            // (their onboarding wizard already covers the intro);
            // we mark the current version as seen for them so
            // they're never surprised by it later either.
            let current = WhatsNewView.currentMarketingVersion
            if profile.lastSeenWhatsNewVersion != current {
                isShowingWhatsNew = true
            }
        }

        // Brand-new users skip the sheet but we still record the
        // version so they don't get the post-onboarding pop later.
        if !profile.hasCompletedOnboarding {
            profile.lastSeenWhatsNewVersion = WhatsNewView.currentMarketingVersion
            try? modelContext.save()
        }
    }

    // Re-compute and re-schedule the streak-protection
    // notification. Only acts when the user has the feature on
    // (notificationsEnabled flag). Called from bootstrap() on
    // every TabView appear and (via .onChange) when the race
    // count changes — i.e. after a race finishes, the schedule
    // re-evaluates and cancels itself if today's training already
    // protected the streak.
    private func rescheduleStreakReminderIfNeeded(profile: UserProfile) {
        guard profile.notificationsEnabled else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let trainedToday = finishedRaces.contains { race in
            guard let end = race.endedAt else { return false }
            return cal.isDate(end, inSameDayAs: today)
        }

        Task { @MainActor in
            if trainedToday {
                // Already trained today — streak is safe, no need
                // for the reminder. Cancel any pending one.
                NotificationService.shared.cancelStreakReminder()
            } else {
                let streak = RaceStreaks.currentStreak(in: finishedRaces)
                let atRisk = RaceStreaks.isStreakAtRisk(in: finishedRaces)
                await NotificationService.shared.scheduleStreakReminder(
                    currentStreak: streak,
                    isAtRisk: atRisk
                )
            }
        }
    }

    // Route a Quick Action to the right tab. The custom-workout
    // case ALSO needs to trigger the builder sheet on RaceView's
    // child — that's handled inside RaceStartView via its own
    // `.onReceive` of the same notification, so we just swap to
    // the Race tab here and let RaceStartView mount and respond.
    private func handleQuickAction(_ action: QuickAction?) {
        guard let action else { return }
        switch action {
        case .startRace, .customWorkout:
            selectedTab = .race
        case .viewHistory:
            selectedTab = .history
        }
    }

    // Route a Trakr deep-link URL. URL host == path determines
    // destination. Currently only `trakr://race` exists (used by
    // the Live Activity widgetURL). The host == nil branch covers
    // both `trakr:race` and `trakr://race` because URLComponents
    // resolves the latter with `host = "race"`.
    private func handleDeepLink(_ url: URL) {
        let route = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch route {
        case "race":
            selectedTab = .race
        default:
            // Unknown deep-link route — degrade gracefully to
            // the Race tab. Better than no-op since the user
            // initiated some interaction with the app.
            selectedTab = .race
        }
    }
}

#Preview {
    ContentView()
}

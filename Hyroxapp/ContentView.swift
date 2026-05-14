import SwiftUI
import SwiftData
#if canImport(Auth)
// Required so we can access `user.id` directly from
// `AuthService.shared.user`. The User type lives in the `Auth`
// submodule of supabase-swift; Swift's implicit-member-access
// rule needs the defining module explicitly imported even
// though `import Supabase` brings the type into scope.
import Auth
#endif

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
    //
    // Default is `.feed` per CLAUDE.md §14 — the app opens to
    // social, Strava-style, to drive daily opens even on rest
    // days. Empty-state copy on FeedView covers the
    // brand-new-user case (no follows yet → "Feed is quiet").
    @State private var selectedTab: Tab = .feed

    // Cathedral-mode chrome control — true when a child view
    // (RaceStartView or RaceView's in-progress phase) wants the
    // bottom custom tab bar hidden so the in-race surface gets
    // its full screen budget. Updated reactively via the
    // `HideTabBarPreferenceKey` SwiftUI preference — children
    // emit `.hideTabBar(true)` on appear, `.hideTabBar(false)`
    // on disappear, and the OR-reduce in the preference key's
    // `reduce` function means "any subview that asks to hide
    // wins" without explicit coordination.
    @State private var hideTabBar: Bool = false

    // Scene-phase observer drives the foreground social
    // notification check. Each transition into `.active`
    // (cold launch, returning from background) fires a
    // single check against Supabase for new follows /
    // reactions / comments since the last cursor — see
    // `SocialNotificationService.checkAndFire`.
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: Hashable {
        case feed, history, race, profile, watch
    }

    var body: some View {
        // 5-tab structure per the v1 wireframe IA. Race sits at the
        // visual center (position 3) so it reads as the headline
        // action the rest of the app supports. Watch lives at the
        // trailing edge as the always-available pairing / streaming
        // surface — keeps Watch concerns out of Settings (where they
        // got buried) and gives the companion a real top-level home.
        //
        // Tab order: Feed | History | Race (FAB) | Profile | Watch
        //
        // **v1 design-system shift — custom center-FAB tab bar.**
        // Native TabView's tab bar is hidden via `.toolbar(.hidden,
        // for: .tabBar)` on each child; we render a custom
        // tab bar at the bottom via `.safeAreaInset` so the Race
        // tab can render as a prominent coral circular FAB
        // protruding above the bar (wireframe spec). Per-tab
        // navigation state is preserved because TabView still
        // owns the view tree — we just chrome it.
        //
        // Routing is unchanged: `selectedTab` is the source of
        // truth, Quick Actions and deep links still write to it,
        // and TabView reads it to swap the visible child.
        TabView(selection: $selectedTab) {
            FeedView()
                .tag(Tab.feed)
                .toolbar(.hidden, for: .tabBar)

            HistoryView()
                .tag(Tab.history)
                .toolbar(.hidden, for: .tabBar)

            RaceView()
                .tag(Tab.race)
                .toolbar(.hidden, for: .tabBar)

            ProfileView()
                .tag(Tab.profile)
                .toolbar(.hidden, for: .tabBar)

            WatchTabView()
                .tag(Tab.watch)
                .toolbar(.hidden, for: .tabBar)
        }
        .tint(Color.accent)
        // Drive color scheme from the user's setting. `.system`
        // resolves to nil → SwiftUI follows the iOS-wide mode; the
        // other two cases force light or dark. Was hardcoded
        // `.dark` pre-light-mode; now reactive to Settings →
        // Appearance picker.
        .preferredColorScheme(profiles.first?.resolvedThemePreference.colorScheme)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Cathedral mode — child views can ask to hide the
            // tab bar via the HideTabBarPreferenceKey. The
            // EmptyView fallback collapses the inset to zero so
            // the child surface uses the full screen height
            // (Start Race button, in-race Next Station button,
            // etc. all clear the bottom edge naturally).
            if hideTabBar {
                EmptyView()
            } else {
                customTabBar
            }
        }
        .onPreferenceChange(HideTabBarPreferenceKey.self) { newValue in
            hideTabBar = newValue
        }
        .onAppear(perform: bootstrap)
        // Foreground social notifications. Fires on every
        // active-phase transition — cold launch is covered
        // because scenePhase starts at .background and
        // transitions to .active during launch. Bails
        // internally on missing auth / missing permission so
        // the call site stays a one-liner.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await SocialNotificationService.checkAndFire() }
                // §30 — try to reconnect to the paired external BLE
                // HR device on every foreground transition. iOS
                // aggressively suspends CoreBluetooth in the
                // background; after a long background stretch the
                // peripheral connection often needs a kick. Bails
                // silently when no pairing record exists. The
                // service's attemptReconnectToPaired guards on its
                // own state, so this is safe to call repeatedly.
                ExternalHRService.shared.attemptReconnectToPaired()
            }
        }
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

    // MARK: - Custom tab bar
    //
    // 5-slot bar with a coral circular FAB in slot 3 (Race).
    // Sits in `.safeAreaInset` so it reserves space below the
    // TabView's child content — child views can scroll all the
    // way down without sliding under the bar.
    //
    // Each slot is a Button that writes to `selectedTab`. The
    // active slot reads as coral; inactive slots are
    // secondary-text. The Race FAB is always coral-filled
    // regardless of active state — it IS the brand moment.
    private var customTabBar: some View {
        // ZStack instead of HStack so the FAB can sit on top of the
        // bar's tinted background and visibly protrude above it
        // without the surrounding HStack reserving extra layout
        // height for the protrusion (a plain `.offset(y:)` inside an
        // HStack moves the view visually but the HStack's own
        // background still clips at the original frame edge — that
        // was the source of the "button not visible properly" bug:
        // the FAB's top arc was visually behind the hairline divider
        // and the bg tint, making it read as half-eaten).
        //
        // ZStack layers (bottom → top):
        //   1. Tab-bar bg + hairline (full width, anchored to bottom)
        //   2. The 4 standard tab items in an HStack, with a spacer
        //      slot in the center where the FAB lives
        //   3. The FAB itself, painted last so it sits cleanly above
        //      the hairline, the bg tint, and any neighbor labels.
        ZStack(alignment: .top) {
            // Layer 1+2: bar background + 4 tab items. A top
            // spacer reserves vertical space the FAB will
            // visually occupy when it protrudes — without it,
            // `.safeAreaInset(edge: .bottom)` only reserves the
            // bar's intrinsic height (~50pt) for scrolling
            // children, and the FAB's protruding top arc covers
            // the last row of any scrollable content. The 36pt
            // top spacer expands the inset so scrollable bodies
            // end well clear of the FAB.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 36)
                Rectangle()
                    .fill(Color.divider)
                    .frame(height: 0.5)
                HStack(spacing: 0) {
                    tabBarItem(.feed,    systemImage: "house",                 label: "Feed")
                    tabBarItem(.history, systemImage: "list.bullet.rectangle", label: "History")
                    // Center spacer slot — same width as a tab item
                    // so the surrounding HStack maths out cleanly,
                    // and the FAB rendered above this slot lands in
                    // the geometric center of the bar.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                    tabBarItem(.profile, systemImage: "person.crop.circle",    label: "Profile")
                    tabBarItem(.watch,   systemImage: "applewatch",            label: "Watch")
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .background(
                // Tinted bg covers ONLY the bar's intrinsic strip
                // (hairline + tab items) — the 36pt FAB-clearance
                // spacer above stays transparent so the FAB's
                // halo can fade naturally over scrolling content
                // beneath, not over a solid bg.
                VStack(spacing: 0) {
                    Color.clear.frame(height: 36)
                    Color.background
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            )

            // Layer 3: FAB, painted on top of the bar. Vertically
            // offset upward so most of the disc protrudes above the
            // bar baseline (classic Strava / Material FAB). The
            // offset value of −44 puts the FAB's vertical midpoint
            // ~6pt above the bar's top edge, so roughly two-thirds
            // of the disc reads as "floating" above the bar and the
            // remaining third tucks into the bar's tinted bg. With
            // a 60pt disc + 76pt halo, that's a clear, glanceable
            // protrusion that the previous −8 offset wasn't
            // achieving (it left the FAB looking half-eaten by the
            // bar's hairline divider).
            HStack {
                Spacer()
                raceFAB
                Spacer()
            }
            .offset(y: -44)
        }
        // The ZStack's intrinsic height is whatever the bar VStack
        // wants. The FAB's offset is purely visual; it does NOT
        // expand the safeAreaInset slot, which is what we want — the
        // child views below behave as if the bar is just the
        // 4-tab-item-tall strip. The FAB happens to render visually
        // above that strip, painted on top of the child content
        // beneath it (with a tap-through-safe Z-order; the FAB's
        // gradient is opaque coral and the icon glyph is white, so
        // there's no transparency issue).
    }

    private func tabBarItem(
        _ tab: Tab,
        systemImage: String,
        label: String
    ) -> some View {
        let isActive = (selectedTab == tab)
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: isActive ? .heavy : .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(isActive ? Color.accent : Color.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // Center Race FAB. Sits in slot 3, visually elevated above
    // the bar baseline so it reads as the primary action — the
    // "thing this app is for." Wireframe spec: coral filled
    // circle, soft accent halo, no label text below (the icon
    // carries the meaning).
    private var raceFAB: some View {
        Button {
            selectedTab = .race
        } label: {
            ZStack {
                // Outer halo ring — a slightly larger, lower-alpha
                // coral circle behind the main FAB. Reads as
                // stadium light and makes the button feel like it
                // belongs to the brand "race moment" rather than
                // a plain tab item. Pulled out as its own circle
                // (instead of just a shadow) so the protruding
                // edge stays crisp against the tab-bar bg.
                Circle()
                    .fill(Color.accent.opacity(0.18))
                    .frame(width: 76, height: 76)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    // Ring stroke at the gradient's outer edge —
                    // separates the coral from the halo on light
                    // mode so the disc reads as a discrete object
                    // and not a wash.
                    .overlay(
                        Circle()
                            .stroke(Color.accent.opacity(0.4), lineWidth: 1)
                            .frame(width: 60, height: 60)
                    )

                Image(systemName: "flag.checkered")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.onAccent)
                    // Active-tab badge — a subtle inner ring
                    // appears when the user is on the Race tab so
                    // the FAB matches the rest of the tab bar's
                    // selection language.
                    .scaleEffect(selectedTab == .race ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            }
            // Coral spotlight + drop shadow. Two stacked shadows:
            // the lifted-button shadow (black for elevation) and the
            // brand coral glow (warm for moment). Tuned per mode —
            // dialed back on warm light bg so it doesn't read as a
            // bleed.
            .shadow(
                color: Color.black.opacity(
                    (profiles.first?.resolvedThemePreference.colorScheme == .light)
                        ? 0.18 : 0.4
                ),
                radius: 10,
                x: 0,
                y: 4
            )
            .shadow(
                color: Color.accent.opacity(
                    (profiles.first?.resolvedThemePreference.colorScheme == .light)
                        ? 0.25 : 0.55
                ),
                radius: 18,
                x: 0,
                y: 0
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Race")
        .accessibilityAddTraits(selectedTab == .race ? .isSelected : [])
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

        // §20 Path A — hand the paired BLE HR device record from
        // UserProfile to the ExternalHRService cache. Doesn't
        // initiate a connection (that's race / free-run start's
        // job); just makes the service aware that a pairing
        // exists so its `attemptReconnectToPaired` later finds
        // the right peripheral UUID.
        let pairedUUID = profile.pairedHRDeviceUUID.flatMap { UUID(uuidString: $0) }
        ExternalHRService.shared.loadPaired(
            uuid: pairedUUID,
            name: profile.pairedHRDeviceName
        )

        // Stamp the Supabase user ID onto the local profile so any
        // future sync code knows which remote account this profile
        // belongs to. Lives here in bootstrap (called on every
        // ContentView appear) rather than buried in AuthService so
        // the local-state mutation happens on the SwiftData context
        // we already have. Idempotent — only writes when the value
        // would actually change.
        #if canImport(UIKit)
        if let remoteUser = AuthService.shared.user,
           profile.remoteUserID != remoteUser.id.uuidString {
            profile.remoteUserID = remoteUser.id.uuidString
            try? modelContext.save()
        }

        // Profile sync — last-write-wins reconciliation between
        // local UserProfile and the remote `profiles` row in
        // Supabase. First-ever launch: pushes local up. Returning
        // launch: pulls remote down if it's fresher, pushes local
        // up if it's not. Errors are swallowed inside the service
        // (sync is best-effort; the user can still use the app
        // offline). The Task hops off the bootstrap call's
        // synchronous path so launch isn't blocked on a network
        // round-trip.
        //
        // Race sync follows immediately after — same pattern,
        // many rows. pullAndReconcile fetches every remote race
        // for this user, merges by id with local races, pushes
        // any local-only races up. The race sync runs after
        // profile sync so the user identity is settled before
        // we start fetching their data.
        if let remoteUser = AuthService.shared.user {
            let userID = remoteUser.id.uuidString
            let context = modelContext
            Task { @MainActor in
                await ProfileSyncService.syncOnSignIn(
                    userID: userID,
                    localProfile: profile,
                    modelContext: context
                )
                await RaceSyncService.pullAndReconcile(
                    userID: userID,
                    modelContext: context
                )
                await FreeRunSyncService.pullAndReconcile(
                    userID: userID,
                    modelContext: context
                )
                // §16 — open the Realtime follow-sync subscription.
                // Idempotent — re-firing on a subsequent bootstrap
                // (after the auth gate swaps Sign-in → Content)
                // is a no-op if the user_id hasn't changed. The
                // service stops itself on auth-state change via
                // the signed-out path: AuthService.signOut clears
                // user; the auth gate then re-renders SignInView
                // and ContentView's bootstrap doesn't fire again.
                // Explicit stop on signout is wired alongside
                // signOut() in AuthService.
                await FollowSyncService.shared.start(forUserID: userID)
            }
        }
        #endif

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

    // Route a Trakrr deep-link URL. URL host == path determines
    // destination. Two routes today: `trakr://race` (race Live
    // Activity widgetURL) and `trakr://freerun` (§12C Free Run
    // Live Activity widgetURL). Both currently route into the
    // Race tab since that's the host for both the Train hub and
    // Free Run start path; future v2 could thread through an
    // additional pendingFreeRun-style state if we want to also
    // auto-resume the in-progress run on tap.
    //
    // The host == nil branch covers both `trakr:race` and
    // `trakr://race` because URLComponents resolves the latter
    // with `host = "race"`.
    private func handleDeepLink(_ url: URL) {
        let route = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch route {
        case "race", "freerun":
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

// MARK: - Cathedral chrome preference

// Child views (RaceStartView, RaceView in-progress phase, future
// FreeRunView in-progress, etc.) emit this preference to ask
// ContentView to hide the custom tab bar so the in-race surface
// gets the full screen budget.
//
// Why a preference key over a global observable: preferences
// flow up the view tree exactly when SwiftUI reconciles them,
// so the visibility tracks view lifecycle correctly (hide on
// appear, restore on disappear) without manual onAppear /
// onDisappear bookkeeping. Same pattern Apple uses internally
// for navigation titles and toolbar items.
//
// Reduce: OR-combine — if ANY subview wants the bar hidden,
// hide it. Means we don't have to coordinate across nested
// presenters; whoever cares speaks up.
struct HideTabBarPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Ask ContentView to hide the bottom custom tab bar while
    /// this view is on screen. Call with `true` on a focused
    /// surface (race start screen, in-race cathedral) and
    /// `false` everywhere else. Stacks fine — multiple emitters
    /// of `true` all map to "hidden" via the preference key's
    /// OR-reduce.
    func hideCustomTabBar(_ hide: Bool = true) -> some View {
        preference(key: HideTabBarPreferenceKey.self, value: hide)
    }
}

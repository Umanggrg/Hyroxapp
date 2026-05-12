import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Auth)
import Auth
#endif

// The Settings sheet. Home for app-wide preferences — today just the HYROX
// division, tomorrow a growing list (audio cues, run distance defaults,
// units, privacy toggles once Supabase ships). Kept deliberately simple:
// a `Form` with grouped sections, one setting per row, system-standard
// controls. No bespoke UI until a specific setting demands it.
//
// iOS-only — the sheet presentation + Form styling we rely on aren't
// appropriate for macOS builds, and Settings on macOS belongs in the
// application menu anyway.
#if canImport(UIKit)
struct SettingsView: View {

    // Every preference reads and writes through the single UserProfile row.
    // We could alternatively use @AppStorage-backed UserDefaults, but
    // UserProfile is what Supabase will eventually sync — keeping prefs
    // there means they travel with the user's account from day one.
    @Bindable var profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Finished + unfinished races — drives the count shown in the
    // Clear All confirmation and powers the JSON export. Includes
    // unfinished resumable rows so a "Clear all" really clears
    // everything, not just history.
    @Query(sort: [SortDescriptor(\Race.createdAt, order: .reverse)])
    private var allRaces: [Race]

    // Cached export bundle — built lazily when the user taps the
    // export row, then handed to ShareLink. Re-baked when the race
    // count changes so a fresh export always reflects current data.
    @State private var exportFile: RaceExportFile?

    // Confirmation alert state for the destructive "Clear all
    // races" action. Bool + count snapshot so the alert text
    // shows a stable number even if @Query updates mid-prompt.
    @State private var isShowingClearConfirm = false
    @State private var isShowingResetConfirm = false
    @State private var isShowingSignOutConfirm = false
    @State private var isShowingDeleteAccountConfirm = false

    // Drives the Edit Profile sheet pushed from the profile row
    // at the top of Settings. Keeps the editor near where the
    // athlete reads their identity — they don't have to back out
    // of Settings, navigate to Profile, then tap the pencil.
    @State private var isEditingProfile = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                appearanceSection
                hyroxSection
                inRaceDisplaysSection
                audioCuesSection
                notificationsSection
                privacySection
                dataSection
                accountSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        // Honor the user's selection inside this sheet too —
        // sheets present in their own scene and don't inherit
        // the host's `.preferredColorScheme`. nil = follow system.
        .preferredColorScheme(profile.resolvedThemePreference.colorScheme)
        .sheet(isPresented: $isEditingProfile) {
            EditProfileView(profile: profile)
        }
    }

    // MARK: - Sections

    // Top-of-Settings profile row — avatar + display name + handle
    // with a chevron, tap to open EditProfileView. Lives at the top
    // so the athlete's identity is the first thing they see when
    // they open Settings, mirroring the iOS Settings → Apple ID row.
    //
    // Compact: 44pt avatar, two lines of text, no padding overrides
    // so the row matches Form's standard chevron-list cell metrics.
    // Tapping anywhere on the row triggers the sheet — not just the
    // chevron — so the tap target stays huge.
    private var profileSection: some View {
        Section {
            Button {
                isEditingProfile = true
            } label: {
                HStack(spacing: 12) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName.isEmpty ? "Athlete" : profile.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                        Text(profile.handle.isEmpty ? "@athlete" : profile.handle)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.surface)
        }
    }

    // Avatar bubble — uses profile.avatarData if set, otherwise the
    // SF Symbol fallback (matches ProfileHero's treatment).
    // 44pt diameter is the iOS standard for compact-row avatars.
    @ViewBuilder
    private var profileAvatar: some View {
        if let data = profile.avatarData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.surfaceElevated)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 44, height: 44)
        }
    }

    // Light vs dark vs system mode picker. Same three-way model
    // iOS Settings → Display & Brightness uses, so the affordance
    // is familiar. `.system` follows whatever the OS is set to;
    // the explicit Light / Dark options force one regardless.
    //
    // Picker uses a segmented style with iconography matching
    // each option (iphone / sun / moon) so it reads at-a-glance
    // without needing to expand a dropdown — three options is
    // exactly the count where segmented beats a wheel.
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: Binding(
                get: { profile.resolvedThemePreference },
                set: { profile.resolvedThemePreference = $0 }
            )) {
                ForEach(ThemePreference.allCases) { pref in
                    Label(pref.displayName, systemImage: pref.systemImage)
                        .tag(pref)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.surface)

            footnote(
                "Choose Light, Dark, or follow your iOS setting. The race screens, share cards, and Live Activities all adapt. Changes apply instantly."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("Appearance")
        }
    }

    // The HYROX-specific settings live here. Division + max HR for
    // zone classification today; per-station overrides and other
    // race-level prefs would slot in here as the app grows.
    private var hyroxSection: some View {
        Section {
            // Picker binds through a custom Binding so that the Picker
            // still works with non-optional `Division` values, even
            // though `UserProfile.division` is stored as optional (see
            // UserProfile.swift for why). The getter coalesces nil to
            // `.mensOpen`; the setter writes the new value straight
            // back to the optional storage.
            Picker("Division", selection: Binding(
                get: { profile.resolvedDivision },
                set: { profile.resolvedDivision = $0 }
            )) {
                ForEach(Division.allCases) { division in
                    Text(division.displayName).tag(division)
                }
            }
            .listRowBackground(Color.surface)

            // Small explanatory footnote so athletes unfamiliar with the
            // Open/Pro split know what changes — we're not hiding the
            // rep-count effect behind a setting name.
            footnote(
                "Wall balls default to \(profile.resolvedDivision.wallBallCount) reps for \(profile.resolvedDivision.displayName)."
            )
            .listRowBackground(Color.surface)

            // Max HR stepper — drives the HR zones chart on race
            // detail. Range 140–220 covers the full plausible band
            // for HYROX athletes. Stepper feels right (not a slider)
            // because users typically know their target value to
            // within ±5 bpm and just want to tap it in.
            Stepper(value: $profile.maxHeartRate, in: 140...220) {
                HStack {
                    Text("Max heart rate")
                    Spacer()
                    Text("\(profile.maxHeartRate) bpm")
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .listRowBackground(Color.surface)

            footnote(
                "Used to compute HR zones on race detail. A common rule of thumb is 220 minus your age."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("HYROX")
        }
    }

    // Audio cues toggle — controls whether VoiceCueService fires
    // spoken station-transition announcements during a race.
    // Defaults on for new users; bound to UserProfile so the
    // preference syncs to cloud later (vs. AppStorage which is
    // device-local).
    private var audioCuesSection: some View {
        Section {
            Toggle("Voice cues", isOn: $profile.audioCuesEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Announces the next station out loud when you advance. Plays over your music — won't interrupt podcasts or playlists."
            )
            .listRowBackground(Color.surface)

            Toggle("Pre-race countdown", isOn: $profile.countdownEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Plays a 3-2-1-GO countdown before the race timer starts. Tap the countdown to skip."
            )
            .listRowBackground(Color.surface)

            Toggle("Track Roxzone time", isOn: $profile.roxzoneEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Splits the in-race advance into two taps — End Station then Start Next — so transition time gets logged separately from work time. The HYROX-specific metric athletes use for transition discipline."
            )
            .listRowBackground(Color.surface)

            Toggle("Manual run start", isOn: $profile.manualRunStartEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Run segments wait for a 'Start Run' tap before timing begins — gives you a beat to pre-position at the start line. The race total clock keeps ticking through."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("Race ritual")
        }
    }

    // In-race displays section. Toggles for the optional
    // information layers on the live race screen — coaching cues,
    // pace chip, predicted finish, Live Activity. All default ON
    // because each adds genuine value during a race; turn off the
    // ones that feel distracting for the athlete's particular
    // racing style. The chips themselves still render minimally
    // (HR + zone color, timer + target line) when toggled off —
    // these are display additions, not core functionality.
    private var inRaceDisplaysSection: some View {
        Section {
            Toggle("Coaching cues", isOn: $profile.coachingCuesEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "HR-based prompts on the live HR chip — HOLD, SLOW, PUSH on runs, WORK on stations. Off → only BPM and zone color."
            )
            .listRowBackground(Color.surface)

            Toggle("Coaching overlays", isOn: $profile.coachingOverlaysEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Full-width banner that takes the top of the screen for ~2 seconds when your HR enters a new state — HOLD / SLOW / REDLINE / RECOVER / PUSH. Each fires a distinct haptic. Off → no banner, no buzz."
            )
            .listRowBackground(Color.surface)

            Toggle("Pace chip", isOn: $profile.paceChipEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Shows whether you're ahead or behind your target finish time. Calculated from a naïve split of target across all 16 segments."
            )
            .listRowBackground(Color.surface)

            Toggle("Predicted finish", isOn: $profile.predictedFinishEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Projects your final time from current pace. Tinted green when on track to beat your target, amber when projecting to miss."
            )
            .listRowBackground(Color.surface)

            Toggle("Live Activity", isOn: $profile.liveActivityEnabled)
                .listRowBackground(Color.surface)

            footnote(
                "Shows the race timer + current station on your lock screen and Dynamic Island. Off → race runs in-app only. Takes effect on the next race."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("In-race displays")
        }
    }

    // Privacy section. Today: a single toggle for default-private
    // races (every fresh race starts with `isPrivate = true`). The
    // per-race summary toggle still works to flip individual races
    // public after the fact. Forward-compat for v2 social feed —
    // private races stay out of any future cross-athlete surface.
    private var privacySection: some View {
        Section {
            Toggle("Default new races private", isOn: $profile.defaultRacePrivate)
                .listRowBackground(Color.surface)

            footnote(
                "New races start hidden from any future social feed and leaderboards. You can still flip individual races public from the summary screen. Local History and Profile stats always include every race."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("Privacy")
        }
    }

    // Notifications section. Today: just streak protection (a
    // local notification at 6 PM if you've got a 2+ day streak
    // alive AND haven't trained yet today). Tomorrow: weekly
    // digest, race anniversaries, PR celebrations.
    //
    // The toggle is a custom Binding rather than a direct bind to
    // `profile.notificationsEnabled` so the on-flip side effects
    // (request permission, schedule reminder) and off-flip
    // cleanup (cancel pending) run in the right order. A direct
    // bind would update the persisted flag synchronously and
    // leave the permission/schedule calls dangling.
    private var notificationsSection: some View {
        Section {
            Toggle(
                "Streak protection reminder",
                isOn: Binding(
                    get: { profile.notificationsEnabled },
                    set: { newValue in
                        handleNotificationsToggle(newValue)
                    }
                )
            )
            .listRowBackground(Color.surface)

            footnote(
                "We'll ping you at 6 PM if you've got a 2+ day streak alive but haven't trained today — so you don't accidentally break it. iOS will ask permission the first time you turn this on."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("Notifications")
        }
    }

    // Async toggle handler — flips the flag, requests permission
    // on enable, then either schedules or cancels accordingly.
    // Permission denial silently flips the flag back so the UI
    // reflects reality (no point claiming notifications are on
    // if iOS won't deliver them).
    private func handleNotificationsToggle(_ newValue: Bool) {
        if newValue {
            Task { @MainActor in
                let granted = await NotificationService.shared.requestAuthorizationIfNeeded()
                guard granted else {
                    // User denied — keep the toggle off so the UI
                    // reflects "notifications won't fire."
                    profile.notificationsEnabled = false
                    return
                }
                profile.notificationsEnabled = true
                // Schedule based on the current streak. If below
                // threshold, scheduleStreakReminder no-ops. Pass
                // the at-risk flag so the notification copy
                // sharpens on streak-end days.
                let streak = RaceStreaks.currentStreak(in: allRaces)
                let atRisk = RaceStreaks.isStreakAtRisk(in: allRaces)
                await NotificationService.shared.scheduleStreakReminder(
                    currentStreak: streak,
                    isAtRisk: atRisk
                )
            }
        } else {
            profile.notificationsEnabled = false
            NotificationService.shared.cancelStreakReminder()
        }
    }

    // Data hygiene + portability section. Three actions:
    //   • Export races as JSON — backup / sanity-check your data
    //   • Reset onboarding — re-runs the wizard on next app launch
    //   • Clear all races — destructive, wipes every Race row
    //
    // Destructive actions get confirmation alerts; export is one
    // tap because there's nothing to undo.
    private var dataSection: some View {
        Section {
            // Export → ShareLink. We pre-bake the file on demand
            // (in `.onAppear` after the section first renders) so
            // ShareLink fires instantly with no spinner. If the
            // bake hasn't happened yet, show a placeholder row
            // that triggers it on tap as a fallback.
            if let file = exportFile {
                ShareLink(
                    item: file,
                    preview: SharePreview(
                        "HYROX races",
                        image: Image(systemName: "doc.fill")
                    )
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color.accent)
                        Text("Export races as JSON")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(allRaces.count)")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.surface)
            } else {
                Button {
                    prepareExportFile()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color.accent)
                        Text("Export races as JSON")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .listRowBackground(Color.surface)
            }

            // Reset onboarding — sets the flag to false. The user
            // sees the wizard the next time they open the app
            // (ContentView's bootstrap re-evaluates on appear).
            Button {
                isShowingResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(Color.accent)
                    Text("Reset onboarding")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
            }
            .listRowBackground(Color.surface)

            // Clear all races — gated behind a confirmation alert.
            // Renders red text so the destructiveness is visible
            // without tapping in.
            Button(role: .destructive) {
                isShowingClearConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear all races")
                    Spacer()
                    if allRaces.count > 0 {
                        Text("\(allRaces.count)")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .disabled(allRaces.isEmpty)
            .listRowBackground(Color.surface)

            footnote(
                "Export creates a JSON file you can save, share, or back up. Photos aren't included to keep file size small."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("Data")
        }
        .alert(
            "Reset onboarding?",
            isPresented: $isShowingResetConfirm
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                profile.hasCompletedOnboarding = false
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("The setup wizard will appear the next time you open the app. Your races and settings stay intact.")
        }
        .alert(
            "Clear all races?",
            isPresented: $isShowingClearConfirm
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(allRaces.count) race\(allRaces.count == 1 ? "" : "s")", role: .destructive) {
                clearAllRaces()
            }
        } message: {
            Text("This permanently deletes every race in your history. Your profile and settings stay intact. This cannot be undone — export first if you might want them back.")
        }
        .onAppear(perform: prepareExportFile)
        .onChange(of: allRaces.count) { _, _ in
            // Race count changed — invalidate the cached export
            // so the next ShareLink tap reflects current data.
            exportFile = nil
            prepareExportFile()
        }
    }

    // Build the export bundle and stash in @State. Idempotent —
    // bails if already cached. Encoding errors fall through
    // silently (the row stays in the spinner state); a real
    // production build would surface the error inline.
    private func prepareExportFile() {
        guard exportFile == nil else { return }
        let document = RaceExportDocument(races: allRaces)
        guard let data = try? document.encodeJSON() else { return }
        exportFile = RaceExportFile(
            data: data,
            filename: RaceExportFile.makeFilename()
        )
    }

    // Delete every persisted race. SwiftData's modelContext.delete
    // marks for deletion; the save() call commits. We don't reset
    // profile / templates / preferences — only the race history,
    // matching the alert's promise.
    private func clearAllRaces() {
        for race in allRaces {
            modelContext.delete(race)
        }
        try? modelContext.save()
        // Also clear the cached export — its data is now stale.
        exportFile = nil
    }

    // Account section — Sign Out + Delete Account request.
    // Lives between Data and About so the destructive actions
    // cluster at the bottom of the form, matching the iOS
    // Settings → Apple ID convention.
    //
    // Both rows are gated behind confirmation alerts. Sign Out
    // is reversible (user can sign back in); Delete Account is
    // an email-based request for v1 (server-side immediate-
    // delete RPC is queued — see CLAUDE.md notes). App Store
    // Guideline 5.1.1(v) requires apps with account creation
    // to support in-app deletion; an email-based request is
    // compliant as long as the option is visible AND we
    // process the request within 30 days.
    //
    // The whole section is hidden when there's no signed-in
    // user — Account actions would be meaningless on the
    // signed-out splash. AuthService is the source of truth.
    @ViewBuilder
    private var accountSection: some View {
        if isSignedIn {
            Section {
                Button {
                    isShowingSignOutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(Color.accent)
                        Text("Sign out")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.surface)

                Button(role: .destructive) {
                    isShowingDeleteAccountConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                        Text("Delete account")
                        Spacer()
                    }
                }
                .listRowBackground(Color.surface)

                footnote(
                    "Sign out keeps your data on this device. Delete account permanently removes your profile, races, photos, and follow graph from our servers."
                )
                .listRowBackground(Color.surface)
            } header: {
                Text("Account")
            }
            .alert(
                "Sign out?",
                isPresented: $isShowingSignOutConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Sign out", role: .destructive) {
                    performSignOut()
                }
            } message: {
                Text("You can sign back in any time with the same account. Your races stay on this device.")
            }
            .alert(
                "Delete your account?",
                isPresented: $isShowingDeleteAccountConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Email request", role: .destructive) {
                    requestAccountDeletion()
                }
            } message: {
                Text("We'll open a pre-filled email to support@trakrr.app. We process deletion requests within 30 days. This permanently removes your profile, races, photos, and follow graph from our servers.")
            }
        }
    }

    // True only when AuthService reports a signed-in user. The
    // setting sheet renders for unauthenticated users too
    // (offline mode), in which case the Account section is
    // simply absent — they have no account to manage.
    private var isSignedIn: Bool {
        #if canImport(Auth)
        return AuthService.shared.user != nil
        #else
        return false
        #endif
    }

    // Sign out via AuthService (clears Supabase session + local
    // auth state). Dismisses the sheet so the app's auth gate
    // can flip back to splash on the next render. Local
    // SwiftData rows stay intact — the user can sign back in
    // and the same races, profile, settings are still there.
    private func performSignOut() {
        #if canImport(Auth)
        AuthService.shared.signOut()
        #endif
        dismiss()
    }

    // Open a pre-filled support email. The mailto: URL carries
    // subject + body so the user only has to tap Send. iOS
    // routes to whichever mail client they've set up — we
    // don't presume Apple Mail.
    //
    // Why not MFMailComposeViewController? It's heavier (sheet
    // + delegate dance) and fails silently on simulator. A
    // mailto: URL is universal: Mail, Gmail, Outlook all
    // handle it. If the user has no mail client configured,
    // iOS surfaces its own "no mail app" alert — graceful
    // degradation.
    private func requestAccountDeletion() {
        let userID = currentUserIDForSupport
        let subject = "Trakrr account deletion request"
        let body = """
        Please delete my Trakrr account.

        User ID: \(userID)
        Handle: @\(profile.handle.isEmpty ? "(not set)" : profile.handle)

        I understand this permanently removes my profile, races, photos, and follow graph.
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        let mailURL = "mailto:support@trakrr.app?subject=\(encodedSubject)&body=\(encodedBody)"

        if let url = URL(string: mailURL) {
            UIApplication.shared.open(url)
        }
    }

    // Surface the local user's Supabase UUID in support
    // emails — speeds up the manual deletion sweep on our
    // side. Falls back to a dash so the email template still
    // looks well-formed even in the no-auth edge case.
    private var currentUserIDForSupport: String {
        #if canImport(Auth)
        return AuthService.shared.user?.id.uuidString ?? "—"
        #else
        return "—"
        #endif
    }

    // About section — brand wordmark + version + tagline.
    // Bottom-of-Settings polish: gives the page a real "end" so
    // the user doesn't feel like the form just stops mid-data.
    private var aboutSection: some View {
        Section {
            // Brand block — Trakrr wordmark in display weight,
            // tagline below. Reads as a quiet signature at the
            // bottom of the screen.
            VStack(spacing: 6) {
                Text("TRAKRR")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Color.accent)
                Text("Race · Track · Compete")
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.surface)

            HStack {
                Text("Version")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(appVersionString)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.surface)

            // Legal + support links. Each row opens its target
            // URL in the user's default browser (or Mail, for
            // the support row). External destinations live on
            // the marketing site (trakrr.app/privacy, /terms)
            // so legal updates don't need an app release.
            externalLinkRow(
                title: "Privacy Policy",
                systemImage: "lock.shield",
                url: "https://trakrr.app/privacy"
            )

            externalLinkRow(
                title: "Terms of Service",
                systemImage: "doc.text",
                url: "https://trakrr.app/terms"
            )

            externalLinkRow(
                title: "Support",
                systemImage: "envelope",
                url: "mailto:support@trakrr.app"
            )
        } header: {
            Text("About")
        }
    }

    // External link row helper — chevron-style nav row that
    // opens the given URL via `UIApplication.open`. iOS
    // surfaces the appropriate handler (Safari, Mail, etc.);
    // we don't presume which app the user prefers. The
    // arrow.up.right glyph matches Apple's Settings convention
    // for "leaves the app" links vs. the chevron-right for
    // in-app navigation.
    private func externalLinkRow(
        title: String,
        systemImage: String,
        url: String
    ) -> some View {
        Button {
            if let target = URL(string: url) {
                UIApplication.shared.open(target)
            }
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accent)
                Text(title)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.surface)
    }

    // MARK: - Helpers

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
    }

    // Reads from the synthesized Info.plist entries (CFBundleShortVersionString
    // + CFBundleVersion). `Bundle.main.infoDictionary` returns nil only in
    // exotic contexts; falling back to a dash keeps the row visually stable.
    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(marketing) (\(build))"
    }
}
#endif

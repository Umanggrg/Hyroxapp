import SwiftUI
import SwiftData

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

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                hyroxSection
                audioCuesSection
                notificationsSection
                dataSection
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
    }

    // MARK: - Sections

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
        } header: {
            Text("Race ritual")
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
                // threshold, scheduleStreakReminder no-ops.
                let streak = RaceStreaks.currentStreak(in: allRaces)
                await NotificationService.shared.scheduleStreakReminder(currentStreak: streak)
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

    // About section — brand wordmark + version + tagline.
    // Bottom-of-Settings polish: gives the page a real "end" so
    // the user doesn't feel like the form just stops mid-data.
    private var aboutSection: some View {
        Section {
            // Brand block — Hyroxapp wordmark in display weight,
            // tagline below. Reads as a quiet signature at the
            // bottom of the screen.
            VStack(spacing: 6) {
                Text("HYROXAPP")
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
        } header: {
            Text("About")
        }
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

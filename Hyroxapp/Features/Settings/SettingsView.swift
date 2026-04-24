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

    var body: some View {
        NavigationStack {
            Form {
                hyroxSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    // The HYROX-specific settings live here. Today: division. When we add
    // per-station overrides (e.g. custom wall ball count for training) or
    // audio cues, they slot in here.
    private var hyroxSection: some View {
        Section {
            // `Picker` inside a Form on iOS renders as a tappable row that
            // opens a dedicated pick screen — exactly what we want for a
            // list of 4 divisions. Bind directly to the model's field so
            // changes persist without a save button (SwiftData autosaves
            // on model dealloc and the ModelContext debounces writes).
            Picker("Division", selection: $profile.division) {
                ForEach(Division.allCases) { division in
                    Text(division.displayName).tag(division)
                }
            }
            .listRowBackground(Color.surface)

            // Small explanatory footnote so athletes unfamiliar with the
            // Open/Pro split know what changes — we're not hiding the
            // rep-count effect behind a setting name.
            footnote(
                "Wall balls default to \(profile.division.wallBallCount) reps for \(profile.division.displayName)."
            )
            .listRowBackground(Color.surface)
        } header: {
            Text("HYROX")
        }
    }

    // Skeleton section for version / about / feedback. Empty for now but
    // reserves the space so the Settings screen doesn't feel one-row thin.
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(appVersionString)
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

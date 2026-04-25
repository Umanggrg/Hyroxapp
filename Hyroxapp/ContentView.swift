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
    // seed default templates on first launch.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            RaceView()
                .tabItem {
                    Label("Race", systemImage: "flag.checkered")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(Color.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            // Idempotent — only inserts when no templates exist yet,
            // so re-firing on every TabView reappearance is harmless.
            WorkoutTemplate.seedDefaultsIfNeeded(in: modelContext)
        }
    }
}

#Preview {
    ContentView()
}

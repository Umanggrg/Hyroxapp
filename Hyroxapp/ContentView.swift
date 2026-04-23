import SwiftUI

// App root. A `TabView` gives us Race (for running a race), History (for
// reviewing past races), and Profile (identity + aggregate stats).
//
// The tint is pinned to our accent red so selected tabs match the rest of
// the brand without relying on system defaults.
struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
}

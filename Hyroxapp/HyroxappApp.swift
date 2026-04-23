import SwiftUI
import SwiftData

@main
struct HyroxappApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Registers a SwiftData container for `Race` and `UserProfile` —
        // creates the underlying store on first launch and injects a
        // `ModelContext` into the view hierarchy via the environment. Views
        // and view models reach it with `@Environment(\.modelContext)`.
        .modelContainer(for: [Race.self, UserProfile.self])
    }
}

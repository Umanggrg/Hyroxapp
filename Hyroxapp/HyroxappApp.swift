import SwiftUI
import SwiftData

@main
struct HyroxappApp: App {

    // Activate the iPhone↔Watch bridge as early as possible so any
    // messages queued by the watch (e.g. an orphaned "advance" sent
    // while the phone app wasn't running) are delivered on launch. The
    // service is a no-op on devices without a paired watch, so this is
    // safe to call unconditionally.
    //
    // Guarded by `canImport(WatchConnectivity)` because that framework
    // doesn't exist on macOS-native — the iOS target lists macOS in its
    // supported platforms, so without the guard this line would fail to
    // compile on a macOS build.
    init() {
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.activate()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Registers a SwiftData container for the app's persisted models —
        // creates the underlying store on first launch and injects a
        // `ModelContext` into the view hierarchy via the environment. Views
        // and view models reach it with `@Environment(\.modelContext)`.
        //
        // Adding a new @Model type? Include it here or queries for it
        // will crash with "entity not found."
        .modelContainer(for: [Race.self, UserProfile.self, WorkoutTemplate.self])
    }
}

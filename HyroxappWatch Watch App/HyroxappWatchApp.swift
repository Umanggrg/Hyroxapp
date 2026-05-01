import SwiftUI

// watchOS entry point for the Hyroxapp companion Watch app.
//
// Activates the `WatchRaceClient` on launch so the WCSession is ready
// to receive race-state pushes from the phone from the first frame,
// and injects the (same singleton) client into the SwiftUI environment
// so any view in the tree can read `@Environment(WatchRaceClient.self)`
// to observe the live snapshot.
//
// Pattern choice: we use a singleton + environment injection rather
// than `@State private var client = WatchRaceClient()` because the
// client must survive across WindowGroup recreation (which can happen
// on watchOS when the user crowns out and back) — a singleton keeps
// the single active WCSession delegate alive without SwiftUI tearing
// it down.
@main
struct HyroxappWatchApp: App {

    // Capture the singleton into a `@State` so SwiftUI's observation
    // tracking kicks in. `@Observable` classes observed via @State +
    // .environment trigger re-renders on any property change — which
    // is what we want when `snapshot` is reassigned by the session
    // delegate.
    @State private var client = WatchRaceClient.shared

    init() {
        // Activate before the first view renders so any context already
        // queued by the phone is ingested on launch.
        WatchRaceClient.shared.activate()

        // Request HealthKit authorization on first launch. The
        // permission prompt appears once and persists across launches;
        // calling twice is a no-op so this is safe to run on every
        // app start. We do it here (vs at race-start time) so a user
        // mid-warmup doesn't get a permission prompt when they tap
        // Start.
        //
        // Only HealthKit reads/writes are gated by this — the rest of
        // the Watch app (race mirror, advance button) works
        // independently of HealthKit auth.
        WatchWorkoutManager.shared.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            WatchRaceView()
                .environment(client)
        }
    }
}

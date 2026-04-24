import SwiftUI

// watchOS entry point for the Hyroxapp companion Watch app.
//
// Today this just mounts the static `WatchRaceView` placeholder — no state,
// no connectivity with the phone yet. Once `WatchCompanionService` ships
// (next session), this App also becomes responsible for spinning up the
// WCSession singleton so the watch is ready to receive race state from the
// phone from the moment it launches.
//
// We rename the auto-generated `HyroxappWatch_Watch_AppApp` to `HyroxappWatchApp`
// for readability. Xcode's template derived the ugly name from the target
// folder "HyroxappWatch Watch App"; the @main attribute cares about the
// entry point, not the exact struct name, so this is a safe rename.
@main
struct HyroxappWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRaceView()
        }
    }
}

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Home-screen Quick Actions plumbing. Long-press the Hyroxapp icon
// on the home screen → iOS shows up to four shortcut tiles → tap
// one and the app launches (or returns from background) routed to
// the right surface in one tap.
//
// Three shortcuts shipped today:
//   • Start Race — Race tab, ready to tap Start
//   • Custom Workout — Race tab with the builder sheet open
//   • View History — History tab
//
// Static plist-declared shortcuts would also work and would appear
// before first launch; we use DYNAMIC registration (set after app
// launch via UIApplication.shared.shortcutItems) so we don't have
// to touch Info.plist + INFOPLIST_KEY_* in the project file.
// Trade-off: shortcuts only appear after the user has launched the
// app once. Acceptable for v1 since on first install they're
// already in the app anyway.
//
// Cross-cutting wiring:
//   • AppDelegate (in HyroxappApp.swift) receives the shortcut tap
//     and posts a `.quickActionTriggered` notification with the
//     action type as the object.
//   • ContentView listens, sets `pendingQuickAction` on shared
//     state, and swaps the TabView selection accordingly.
//   • RaceView reads the same shared state to open the custom-
//     workout sheet when triggered.
//
// Guarded `#if canImport(UIKit)` because UIApplicationShortcutItem
// + the launch-time hook are UIKit-only.
#if canImport(UIKit)

// Stable string identifiers for each shortcut. Used by the
// AppDelegate to route the tap and by tests to assert routing
// behavior. Reverse-DNS-style namespacing matches Apple's
// recommended convention for Quick Actions.
enum QuickAction: String, CaseIterable, Sendable {
    case startRace      = "com.hyroxapp.shortcut.start-race"
    case customWorkout  = "com.hyroxapp.shortcut.custom-workout"
    case viewHistory    = "com.hyroxapp.shortcut.view-history"

    var localizedTitle: String {
        switch self {
        case .startRace:     return "Start Race"
        case .customWorkout: return "Custom Workout"
        case .viewHistory:   return "View History"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .startRace:     return "flag.checkered"
        case .customWorkout: return "slider.horizontal.3"
        case .viewHistory:   return "list.bullet.rectangle"
        }
    }

    @MainActor
    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: rawValue,
            localizedTitle: localizedTitle,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: sfSymbolName),
            userInfo: nil
        )
    }
}

extension Notification.Name {
    // Fired by the AppDelegate when a Quick Action lands. Object
    // is the QuickAction case for the matched shortcut, or nil if
    // the shortcut type didn't match any known action (defensive).
    static let quickActionTriggered = Notification.Name("HyroxappQuickActionTriggered")
}

// Convenience for wiring up the dynamic shortcuts at app launch.
// Idempotent — only sets the shortcuts when none are registered,
// or when the registered set differs from the current desired set.
@MainActor
enum QuickActionRegistrar {
    static func registerIfNeeded() {
        let desired = QuickAction.allCases.map(\.shortcutItem)
        let current = UIApplication.shared.shortcutItems ?? []

        // Compare by `type` (the rawValue) — that's the stable
        // identity. Title/icon changes are picked up on every
        // app version bump because we always overwrite when the
        // type set differs.
        let currentTypes = Set(current.map(\.type))
        let desiredTypes = Set(QuickAction.allCases.map(\.rawValue))
        guard current.isEmpty || currentTypes != desiredTypes else { return }

        UIApplication.shared.shortcutItems = desired
    }
}

#endif

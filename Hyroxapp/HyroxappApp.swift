import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct HyroxappApp: App {

    // SwiftUI doesn't expose UIApplicationDelegate methods directly,
    // so we attach an adapter for the two cross-cutting hooks we
    // care about today:
    //   1. Register Quick Actions on first launch (dynamic shortcuts
    //      for "Start Race" / "Custom Workout" / "View History").
    //   2. Receive Quick Action taps and forward them through
    //      NotificationCenter so SwiftUI views can route accordingly.
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(HyroxappAppDelegate.self) private var delegate
    #endif

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
    // Auth state lives at the App level so the gate flips between
    // SignInView (signed out) and ContentView (signed in) without
    // any view in the tree having to reach into the AuthService
    // singleton themselves. AuthService is `@Observable` so this
    // re-renders on `user` changes automatically.
    #if canImport(UIKit)
    @State private var authService = AuthService.shared
    #endif

    init() {
        #if canImport(WatchConnectivity)
        WatchCompanionService.shared.activate()
        #endif

        #if canImport(UIKit)
        // Restore any existing Supabase session on launch. Returning
        // users skip the sign-in screen because Supabase persists
        // session tokens to UserDefaults under the hood. If no
        // session is cached, AuthService.user stays nil and the
        // gate below renders SignInView.
        AuthService.shared.restoreSession()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            authGatedRoot
                // Deep-link receiver. The Live Activity's
                // `.widgetURL(URL(string: "trakr://race"))` lands
                // here when a user taps the lock-screen card or
                // Dynamic Island. We post a NotificationCenter
                // event the same way QuickActions do, and let
                // ContentView route by flipping the TabView's
                // selectedTab. Any future deep-link path (e.g.
                // trakr://history/<id>) plugs into the same
                // primitive without changing this scene closure.
                .onOpenURL { url in
                    guard url.scheme == "trakr" else { return }
                    NotificationCenter.default.post(
                        name: .trakrDeepLink,
                        object: url
                    )
                }
        }
        // Registers a SwiftData container for the app's persisted models —
        // creates the underlying store on first launch and injects a
        // `ModelContext` into the view hierarchy via the environment. Views
        // and view models reach it with `@Environment(\.modelContext)`.
        //
        // Adding a new @Model type? Include it here or queries for it
        // will crash with "entity not found."
        .modelContainer(for: [Race.self, UserProfile.self, WorkoutTemplate.self, RaceEvent.self, Challenge.self, FreeRun.self])
    }

    // Auth gate — renders SignInView when no Supabase session is
    // active, ContentView when one is. The `@ViewBuilder` lets us
    // return different concrete view types from the two branches
    // without an `AnyView` wrapper. SwiftUI handles the crossfade
    // animation automatically when `authService.user` flips.
    //
    // The macOS path skips the gate (returns ContentView directly)
    // because Sign in with Apple uses iOS-only frameworks
    // (AuthenticationServices is iOS+macOS but our SignInView
    // currently UIKit-gates). Future cleanup: extract a cross-
    // platform sign-in surface; for now the app is iPhone-first
    // and macOS doesn't need an auth gate.
    @ViewBuilder
    private var authGatedRoot: some View {
        #if canImport(UIKit)
        if authService.user != nil {
            ContentView()
        } else {
            SignInView()
        }
        #else
        ContentView()
        #endif
    }
}

// Deep-link Notification name. Posted by HyroxappApp.onOpenURL,
// observed by ContentView. Centralized here next to the scene
// that owns the URL handler.
extension Notification.Name {
    static let trakrDeepLink = Notification.Name("com.umanggurung.trakr.deepLink")
}

#if canImport(UIKit)
// Adapter for the small surface of UIApplicationDelegate we need.
// Keep it deliberately thin — feature logic lives in SwiftUI views
// and observable services; this class is just a router for system
// callbacks SwiftUI doesn't expose natively.
final class HyroxappAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register the home-screen Quick Actions. Idempotent — only
        // overwrites when the registered set differs from the
        // desired one, so app version bumps that change icons /
        // titles propagate while no-op launches do nothing.
        Task { @MainActor in
            QuickActionRegistrar.registerIfNeeded()
        }
        return true
    }

    // Called when the user taps a Quick Action while the app is
    // already running (foreground or background-suspended). For
    // cold launches the same shortcut arrives via launchOptions
    // — handled below.
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let action = QuickAction(rawValue: shortcutItem.type)
        NotificationCenter.default.post(
            name: .quickActionTriggered,
            object: action
        )
        completionHandler(action != nil)
    }

    // Cold-launch path: the shortcut sits in launchOptions when
    // the app is fully launched from a Quick Action tap. We need
    // to consume it here AND return false from the configure call
    // so iOS doesn't ALSO call performActionFor:. The official
    // pattern is: capture the item in configurationForConnecting,
    // then re-post it to NotificationCenter on a slight delay so
    // SwiftUI views have time to mount their listeners.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem {
            let action = QuickAction(rawValue: shortcut.type)
            // Defer one tick so SwiftUI views finish initial mount
            // (their `.onReceive` listeners are wired during view
            // body resolution; firing inside this synchronous
            // launch path would race them).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: .quickActionTriggered,
                    object: action
                )
            }
        }
        return UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
    }
}
#endif

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// Wraps ActivityKit so RaceViewModel can drive the lock-screen +
// Dynamic Island race timer without scattering ActivityKit
// imports + nil checks across the app. Same pattern as
// NotificationService and HealthKitService — one adapter, every
// feature site stays clean.
//
// Lifecycle:
//   • start(...) — request a new activity. iOS may refuse if
//     auth is denied or the budget is exhausted; failures are
//     swallowed silently (the in-app race UI is the source of
//     truth, the activity is purely additive).
//   • update(...) — push a new ContentState. Called on every
//     state-changing event (advance, pause, resume, roxzone
//     transitions). Cheap when there's no active activity.
//   • end() — terminate the activity, optionally with a final
//     content state and dismissal policy. Called on race
//     finish / abandon.
//
// Single-activity model: at most one race-timer activity exists
// at a time. start() ends any prior one before creating a new
// one to keep the contract clean.
//
// `@MainActor` because Activity APIs touch UI-adjacent state.
// Guarded `#if canImport(ActivityKit)` so non-iOS platforms
// compile.
#if canImport(ActivityKit)

@MainActor
final class LiveActivityService {

    static let shared = LiveActivityService()
    private init() {}

    // The currently-running activity, if any. Held weakly via
    // type erasure to `Activity<RaceActivityAttributes>` —
    // ActivityKit doesn't vend a non-generic handle, so we
    // store the typed one directly and rely on iOS to clean up
    // when the system kills it (e.g. user dismisses from the
    // lock screen).
    private var activeActivity: Activity<RaceActivityAttributes>?

    // MARK: - Lifecycle

    // Start a new race-timer activity. End any prior activity
    // first so there's only ever one race timer on the lock
    // screen. Throws nothing — failures are logged and ignored.
    func start(
        attributes: RaceActivityAttributes,
        contentState: RaceActivityAttributes.ContentState
    ) {
        // ActivityKit refuses requests when the user has
        // disabled live activities for the app at the system
        // level. Bail silently in that case — the in-app UI
        // still shows everything.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any leftover from a prior race. iOS sometimes
        // hangs onto activities across app launches if the
        // app crashed mid-race — clear them deliberately.
        endLeftoverActivities()

        do {
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(60 * 60 * 4)  // 4h staleness fallback
            )
            activeActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil  // local-only, no push notifications
            )
        } catch {
            // Most likely cause: budget exhausted (>1 active
            // activity in flight already). Non-fatal.
            activeActivity = nil
        }
    }

    // Update the active activity's ContentState. No-op if no
    // activity is running. Each update bumps iOS's per-app
    // budget counter; we only call this on real state changes
    // (advance, pause, resume, roxzone), not on tick.
    func update(_ contentState: RaceActivityAttributes.ContentState) {
        guard let activity = activeActivity else { return }

        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(60 * 60 * 4)
        )

        Task {
            await activity.update(content)
        }
    }

    // End the active activity. The optional final state lets
    // the lock-screen render a "FINISHED" state for a brief
    // moment before iOS dismisses it.
    func end(
        finalState: RaceActivityAttributes.ContentState? = nil
    ) {
        guard let activity = activeActivity else { return }
        activeActivity = nil

        let content: ActivityContent<RaceActivityAttributes.ContentState>?
        if let finalState {
            content = ActivityContent(
                state: finalState,
                staleDate: nil
            )
        } else {
            content = nil
        }

        Task {
            // .immediate dismissal kills the activity right
            // away; .default lets iOS show it for ~4h on the
            // lock screen as a finished-state ribbon. We use
            // .default so the athlete can see their finish time
            // on their lock screen post-race without unlocking.
            await activity.end(content, dismissalPolicy: .default)
        }
    }

    // Sweep up any pre-existing activities of our type. Called
    // from `start` to enforce the single-activity invariant
    // even across app launches / crashes.
    private func endLeftoverActivities() {
        for activity in Activity<RaceActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

#endif

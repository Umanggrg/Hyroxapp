import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// Local-notifications wrapper. Today the only thing it schedules
// is the streak-protection reminder ("Don't break your N-day
// streak!"), but the surface is generic enough to host other
// reminder types as they ship — weekly digests, race anniversaries,
// PR celebrations.
//
// Why local-only (no remote / push): nothing the app does requires
// server-originated alerts in v1. Streak math is fully derivable
// from the local SwiftData store, so scheduling locally avoids the
// entire APNs / certificate / backend layer.
//
// All notifications are user-opt-in. Permission is requested
// contextually when the user first enables a reminder in Settings,
// not on app launch — that gives the prompt visible cause-and-
// effect ("I just turned this on, here's what it'll do").
//
// Guarded `#if canImport(UserNotifications)` so the file compiles
// cleanly on platforms without the framework. macOS / iOS / Mac
// Catalyst all have it; watchOS does too but we don't trigger
// from the watch target — phone is authoritative for scheduling.
#if canImport(UserNotifications)

@MainActor
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    // Stable identifier for the streak-protection notification.
    // Re-using the same identifier means scheduling a fresh one
    // automatically replaces any pending older one — no manual
    // cancel-then-add dance required.
    private static let streakReminderID = "com.hyroxapp.notification.streak-reminder"

    // What hour (24h) to fire the reminder at. 6 PM is the
    // canonical "you've still got time tonight" cue — late enough
    // to not nag mid-day, early enough that the athlete still has
    // hours to actually do something before midnight breaks the
    // streak.
    private static let streakReminderHour = 18

    // MARK: - Authorization

    // Request alert + sound permission. Idempotent — iOS shows the
    // system prompt only on the very first call for an app; later
    // calls return whatever the user previously granted. Returns
    // true when the user has authorized notifications, false on
    // denial / restriction.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // Current authorization status — checked before scheduling so
    // we don't queue notifications that'll never fire (e.g. user
    // toggled the iOS-level permission off in Settings.app after
    // initially granting).
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Scheduling

    // Schedule the streak-protection reminder for 6 PM on the
    // calendar day represented by `streakDays > 0` and "no race
    // today." Caller is responsible for the predicate check;
    // this method just builds and queues the notification.
    //
    // Re-uses the same identifier on every call so the latest
    // scheduling wins — yesterday's pending request is replaced
    // by today's, with content that reflects the current streak
    // length.
    //
    // Skips silently when the trigger date is in the past (e.g.
    // it's already 7 PM), since iOS rejects backwards-dated
    // requests anyway.
    // Schedule the streak-protection reminder for 6 PM on the
    // calendar day. Pass `isAtRisk: true` when today is genuinely
    // a streak-break day (last training was yesterday, no race
    // logged yet today) — the copy sharpens accordingly. The
    // routine-reminder copy stays gentle for streaks that are just
    // active without imminent risk.
    func scheduleStreakReminder(currentStreak: Int, isAtRisk: Bool = false) async {
        guard currentStreak >= 2 else {
            // Below threshold — nothing to protect. Cancel any
            // stale request so a previously-scheduled reminder
            // doesn't fire after the streak's already broken.
            cancelStreakReminder()
            return
        }

        // Bail if user hasn't authorized — keeps us from silently
        // queueing requests that'll never deliver.
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = Self.streakReminderHour
        comps.minute = 0
        guard let triggerDate = cal.date(from: comps), triggerDate > Date() else {
            // It's already past 6 PM — don't try to schedule a
            // notification for the past. The streak is the user's
            // problem to defend tonight; we'll re-evaluate
            // tomorrow on app launch.
            cancelStreakReminder()
            return
        }

        let content = UNMutableNotificationContent()
        if isAtRisk {
            // At-risk path — the streak ends at midnight if no race
            // is logged tonight. Sharper title, more direct copy.
            // Caller (ContentView) determines this from
            // RaceStreaks.isStreakAtRisk.
            content.title = "Your \(currentStreak)-day streak ends tonight"
            content.body = "Last training was yesterday. A race today keeps it alive."
        } else {
            // Routine reminder — streak active but not in imminent
            // risk (e.g. the user opens the app mid-streak before
            // their typical training time). Gentler nudge.
            content.title = "Don't break your streak"
            content.body = "You've trained \(currentStreak) day\(currentStreak == 1 ? "" : "s") in a row. A race tonight keeps it alive."
        }
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: Self.streakReminderID,
            content: content,
            trigger: trigger
        )

        // Add silently fails on permission revocation between the
        // status check above and this call — try? swallows the
        // error, the next launch will re-evaluate cleanly.
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Cancel any pending streak reminder. Called when the user
    // disables notifications, finishes a race today (since today's
    // training already protected the streak), or has fallen below
    // the 2-day minimum.
    func cancelStreakReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.streakReminderID]
        )
    }

    // Cancel everything we ever scheduled. Used by Settings'
    // "Clear all races" cleanup path so a fresh-data state isn't
    // haunted by reminder content from before the wipe.
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

#endif

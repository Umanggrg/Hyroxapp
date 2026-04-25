import Foundation
import SwiftData

// A specific upcoming HYROX race the athlete is training for.
// HYROX Miami 2026, HYROX London Open Championships, etc. Pinning
// an event makes every training session feel deliberate — the
// Profile shows a countdown banner ("T-43 days · Target 1:25")
// instead of training in the abstract.
//
// v1 scope: one upcoming event at a time. The UI surfaces the
// most-recent-future event; older events can stay in the table
// as historical "I trained for this" rows but only the next one
// is featured. Multi-event lists, race-result attribution, and
// per-event training plans land in a later iteration.
//
// Persisted via SwiftData like Race / UserProfile / WorkoutTemplate.
// Adding a new @Model? Update HyroxappApp.swift's modelContainer
// declaration or queries will crash with "entity not found."
@Model
final class RaceEvent {

    // Stable identity for future cloud sync pairing.
    var id: UUID

    // User-given name. Defaults to "HYROX Race" if unset; the
    // edit form uses the picker placeholder to encourage athletes
    // to type the actual event name (HYROX Miami, etc.).
    var name: String

    // Race day. Stored at the day's start (midnight in the user's
    // calendar) so countdown math doesn't drift through the day.
    // Adjusted to local startOfDay on save in the edit sheet.
    var date: Date

    // Division the athlete plans to compete in. Stored as raw
    // string for SwiftData enum-attribute safety; resolved
    // through `resolvedDivision` for views.
    var divisionRawValue: String?

    // Optional finish-time goal. When set, surfaces in the
    // countdown banner as "Target 1:25". Leaving it nil means
    // "I don't have a specific target yet" — perfectly valid
    // for early-season planning.
    var targetDuration: TimeInterval?

    // Optional location string ("Miami, FL"). Plain text for v1
    // — no geocoding, no map view, no auto-complete. Just for
    // the athlete's reference + future feed display.
    var location: String

    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        division: Division? = nil,
        targetDuration: TimeInterval? = nil,
        location: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.divisionRawValue = division?.rawValue
        self.targetDuration = targetDuration
        self.location = location
        self.createdAt = createdAt
    }

    // Non-optional accessor for views — same pattern UserProfile
    // uses for its optional Division. Falls back to Men's Open
    // when nothing's set so pickers / banners always render
    // something.
    var resolvedDivision: Division {
        get {
            if let raw = divisionRawValue,
               let division = Division(rawValue: raw) {
                return division
            }
            return .mensOpen
        }
        set { divisionRawValue = newValue.rawValue }
    }

    // Days until race day, in the user's calendar. Negative for
    // past events (the race already happened). Drives the
    // countdown banner; the view layer chooses how to render
    // (e.g. "T-43" before, "Race day" on, "Past" after).
    var daysUntil: Int {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let then = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: now, to: then).day ?? 0
    }

    var isUpcoming: Bool { daysUntil >= 0 }
}

// Note: previous versions of this file shipped an
// `upcomingPredicate()` helper here. SwiftData's `#Predicate`
// macro can't reference local `let today = ...` captures during
// macro expansion either (it's stricter than runtime predicates),
// so the helper was unusable in `@Query` contexts. ProfileView
// now fetches every event sorted by date and filters to
// "upcoming" in a computed property using a plain Swift closure.

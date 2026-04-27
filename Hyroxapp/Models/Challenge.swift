import Foundation
import SwiftData

// A time-boxed personal goal the athlete commits to. Strava +
// Whoop + Apple Fitness all surface this as a core engagement
// loop: "do X by date Y." Naming it Challenge here aligns with
// Strava's terminology so HYROX athletes coming from that world
// recognize the pattern.
//
// v1 scope: one active challenge at a time, preset templates
// only (no full custom builder). The athlete picks from a small
// list — Race Count / Fastest Race / Streak Length — sets a
// target and a deadline, and the existing race history evaluates
// progress automatically. Hitting 100% sets `completedAt` so a
// completed challenge becomes a celebratory artifact in History
// rather than disappearing.
//
// Forward-compat: when v1 backend lands, every athlete's challenges
// sync to the cloud and the social feed can render "Sarah
// completed her March race-count challenge." The shape's already
// right — id, type, target, dates — so the backend mapping is a
// straight Codable pass-through.
//
// Persisted via SwiftData. Like every other @Model in this project,
// adding a new field needs to be additive (default value or
// optional) so existing rows decode cleanly. SwiftData migration
// is fragile beyond that.
@Model
final class Challenge {

    // Stable identity for future cloud sync pairing.
    var id: UUID

    // Type of challenge — drives the evaluator and the display
    // labels. Stored as a raw string for SwiftData compatibility;
    // resolve through `challengeType` for the typed value.
    var typeRaw: String

    // Target value. Interpretation depends on the challenge type:
    //   • raceCount      — number of races (5)
    //   • fastestRace    — total race time in seconds (5400 = 1:30)
    //   • streakLength   — consecutive-day count (7)
    //
    // Stored as Double rather than separate Int/TimeInterval fields
    // so the schema stays uniform across types. Each evaluator
    // knows how to interpret its own units.
    var targetValue: Double

    // Window the challenge runs over. Both inclusive — a race on
    // either boundary day counts. The athlete picks a window
    // length at creation time (7 days, 30 days, 90 days are the
    // template options).
    var startDate: Date
    var endDate: Date

    // When created — for sorting in the challenges list and for
    // age-of-challenge math.
    var createdAt: Date

    // Set the moment the evaluator first reports >= target. Lets
    // a challenge surface as "Completed" celebratory state rather
    // than disappearing the second it's met. Nil = still active /
    // unfinished. Set automatically by the evaluator's caller when
    // progress hits 100%.
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        type: ChallengeType,
        targetValue: Double,
        startDate: Date,
        endDate: Date,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.targetValue = targetValue
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    // Resolve the typed value, falling back to .raceCount on an
    // unknown raw string (defensive against forward-compat: an
    // older client decoding a future-version Challenge with an
    // unknown type shouldn't crash). Race count is the safest
    // default — every athlete has races, and the eval code
    // tolerates 0 races toward a target gracefully.
    var challengeType: ChallengeType {
        ChallengeType(rawValue: typeRaw) ?? .raceCount
    }

    // Convenience — true while the deadline hasn't passed AND
    // the challenge isn't yet completed.
    var isActive: Bool {
        completedAt == nil && Date() <= endDate
    }

    // Convenience — true when the deadline has passed without
    // completion. Lets the UI render "Expired" rather than
    // "Completed" or "Active" in the third bucket.
    var isExpired: Bool {
        completedAt == nil && Date() > endDate
    }
}

// MARK: - ChallengeType

// Three preset challenge shapes. Each carries display metadata
// (name, unit, default target, SF Symbol) so the UI doesn't need
// to switch on the type at every render call. Adding a new type
// is one switch arm here plus one evaluator branch.
enum ChallengeType: String, Codable, CaseIterable, Sendable {
    case raceCount       // "5 races in 30 days"
    case fastestRace     // "Sub-1:30 race in 30 days"
    case streakLength    // "7-day streak"

    var displayName: String {
        switch self {
        case .raceCount:    return "Race Count"
        case .fastestRace:  return "Fastest Race"
        case .streakLength: return "Streak Length"
        }
    }

    // Coaching framing — what the athlete is committing to.
    // Used as the headline on the challenge card.
    var headline: String {
        switch self {
        case .raceCount:    return "Complete N races"
        case .fastestRace:  return "Race under target time"
        case .streakLength: return "Train N days in a row"
        }
    }

    // SF Symbol per type. Different symbol than the goal/event
    // banner so a challenge is visually distinct from an upcoming
    // event countdown.
    var symbol: String {
        switch self {
        case .raceCount:    return "number.square.fill"
        case .fastestRace:  return "stopwatch.fill"
        case .streakLength: return "flame.fill"
        }
    }

    // Format helper for a target value into human copy. Each type
    // owns its own formatter so the UI just calls
    // `challenge.challengeType.formatTarget(challenge.targetValue)`.
    func formatTarget(_ value: Double) -> String {
        switch self {
        case .raceCount:
            return "\(Int(value)) race\(Int(value) == 1 ? "" : "s")"
        case .fastestRace:
            return RaceStats.format(value)
        case .streakLength:
            return "\(Int(value)) day\(Int(value) == 1 ? "" : "s")"
        }
    }
}

import Foundation
import SwiftUI

// Achievement badges — milestone tiles displayed on Profile.
// Mirrors Strava's badge wall pattern: a small set of named
// accomplishments the athlete can collect as they progress, each
// backed by a checkable criterion against their race history.
//
// Six badge types in the MVP set, chosen to span the athlete's
// journey from first race → competitive finish → consistency:
//
//   • firstRace — finishing your first HYROX. Onboarding milestone.
//   • subOneThirty — finishing under 1:30, the canonical HYROX
//     target finish. The "you're race-ready" badge.
//   • subOneFifteen — finishing under 1:15. Elite tier.
//   • tenRaces — completing ten finished races. Consistency over
//     time, regardless of pace.
//   • allStationsPB — setting personal bests on every split in a
//     single race. The "everything clicked" badge.
//   • customCrafter — saving three or more custom workout
//     templates. Rewards engagement with the Custom Workout
//     Builder beyond just running pre-seeded blocks.
//
// Adding a new badge type later is purely additive: append a case
// here, add a criterion in BadgeAwarder, and the existing UI
// renders it without further changes.
enum Badge: String, CaseIterable, Identifiable, Sendable {
    case firstRace
    case subOneThirty
    case subOneFifteen
    case tenRaces
    case allStationsPB
    case customCrafter

    var id: String { rawValue }

    // Display name shown on the badge tile.
    var displayName: String {
        switch self {
        case .firstRace:        return "First Race"
        case .subOneThirty:     return "Sub 1:30"
        case .subOneFifteen:    return "Sub 1:15"
        case .tenRaces:         return "Ten Races"
        case .allStationsPB:    return "Perfect Day"
        case .customCrafter:    return "Workout Builder"
        }
    }

    // Longer description shown when the athlete taps a badge to
    // see what it commemorates / what's required to earn it.
    var requirement: String {
        switch self {
        case .firstRace:
            return "Complete your first HYROX race."
        case .subOneThirty:
            return "Finish a HYROX in under 1 hour 30 minutes — the canonical race-day target."
        case .subOneFifteen:
            return "Finish a HYROX in under 1 hour 15 minutes — elite tier."
        case .tenRaces:
            return "Complete ten finished races."
        case .allStationsPB:
            return "Set new personal bests on every station in a single race."
        case .customCrafter:
            return "Save three or more custom workout templates."
        }
    }

    // SF Symbol used as the badge icon. Each pulls from Apple's
    // medal / trophy / fitness vocabulary so the visual language
    // is consistent.
    var symbol: String {
        switch self {
        case .firstRace:        return "flag.checkered"
        case .subOneThirty:     return "stopwatch.fill"
        case .subOneFifteen:    return "bolt.fill"
        case .tenRaces:         return "10.circle.fill"
        case .allStationsPB:    return "rosette"
        case .customCrafter:    return "wrench.and.screwdriver.fill"
        }
    }

    // Tint color used for the badge when earned. Maps onto the
    // existing theme tokens — no new color literals.
    var color: Color {
        switch self {
        case .firstRace:        return Color.accent
        case .subOneThirty:     return Color.success
        case .subOneFifteen:    return Color.warning
        case .tenRaces:         return Color(hex: 0x5B9BD5)   // calm blue, same as HRZone Z1
        case .allStationsPB:    return Color(hex: 0xFFD60A)   // gold yellow, same as HRZone Z3
        case .customCrafter:    return Color.textSecondary
        }
    }
}

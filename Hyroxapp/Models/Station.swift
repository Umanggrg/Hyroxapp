import Foundation

// A single segment in a HYROX race.
//
// An official HYROX race is 16 segments: 8 × 1km runs alternating with 8
// workout stations, starting with a run. Cases below are declared in race
// order, so `Station.allCases` yields the full sequence without any manual
// ordering list.
//
// NOTE: The station list in CLAUDE-2.md §4.1 omits Ski Erg (the first workout
// station in a real HYROX race). This file follows the official HYROX format
// — confirm with Umang before relying on this for ground truth.
enum Station: Int, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case run1
    case skiErg            // 1000 m
    case run2
    case sledPush          // 50 m
    case run3
    case sledPull          // 50 m
    case run4
    case burpeeBroadJumps  // 80 m
    case run5
    case rowing            // 1000 m
    case run6
    case farmersCarry      // 200 m
    case run7
    case sandbagLunges     // 100 m
    case run8
    case wallBalls         // 75 (women) / 100 (men) reps

    var id: Int { rawValue }

    // Whether this segment is a 1km run or a workout station.
    var kind: Kind {
        switch self {
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            return .run
        default:
            return .workout
        }
    }

    // Short display name for the race screen and split tables.
    var displayName: String {
        switch self {
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            return "1km Run"
        case .skiErg:            return "Ski Erg"
        case .sledPush:          return "Sled Push"
        case .sledPull:          return "Sled Pull"
        case .burpeeBroadJumps:  return "Burpee Broad Jumps"
        case .rowing:            return "Rowing"
        case .farmersCarry:      return "Farmers Carry"
        case .sandbagLunges:     return "Sandbag Lunges"
        case .wallBalls:         return "Wall Balls"
        }
    }

    // Target/required work, shown as a subtitle under the station name.
    var target: String {
        switch self {
        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            return "1000 m"
        case .skiErg:            return "1000 m"
        case .sledPush:          return "50 m"
        case .sledPull:          return "50 m"
        case .burpeeBroadJumps:  return "80 m"
        case .rowing:            return "1000 m"
        case .farmersCarry:      return "200 m"
        case .sandbagLunges:     return "100 m"
        case .wallBalls:         return "75 / 100 reps"
        }
    }

    // 1-indexed position within a full race, for UI like "Station 3 of 16".
    var raceIndex: Int { rawValue + 1 }

    enum Kind: Sendable {
        case run
        case workout
    }

    // The 16 segments in official HYROX order. Convenience alias — equivalent
    // to `Station.allCases` but reads more clearly at the call site.
    static let raceSequence: [Station] = Station.allCases
}

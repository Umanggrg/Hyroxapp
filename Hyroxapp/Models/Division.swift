import Foundation

// A HYROX competitive division. Determines, for now, the wall ball rep
// count — women's open = 75, everything else = 100 (per current HYROX
// rules as of 2026). Will likely expand later to influence sled / sandbag
// weight defaults, audio cues, and pace targets.
//
// Doubles variants (Men's, Women's, Mixed Doubles) are intentionally absent
// for now — they only become meaningful once Duo Mode (CLAUDE.md §4.5)
// ships in v2, which has its own rep-count model (150 shared, split between
// partners). Adding them before the Duo flow exists would be dead UI.
//
// Storage: backed by a `String` raw value so SwiftData can persist it
// directly on `UserProfile.division`. Adding a new case later is safe
// because SwiftData stores the raw string; unknown values on read would
// fall back to a default at the caller's discretion.
enum Division: String, Codable, CaseIterable, Identifiable, Sendable {
    case mensOpen    = "mens_open"
    case womensOpen  = "womens_open"
    case mensPro     = "mens_pro"
    case womensPro   = "womens_pro"

    var id: String { rawValue }

    // Human-readable label for pickers, summaries, and future profile
    // badges. Apostrophes are curly because the rest of the app uses
    // Apple-style typography.
    var displayName: String {
        switch self {
        case .mensOpen:   return "Men\u{2019}s Open"
        case .womensOpen: return "Women\u{2019}s Open"
        case .mensPro:    return "Men\u{2019}s Pro"
        case .womensPro:  return "Women\u{2019}s Pro"
        }
    }

    // Wall ball rep count prescribed by this division. Women's Open is 75;
    // every other division is 100. (Pro uses a heavier ball at 6kg vs 4kg
    // for Open Women, but the rep count is the same 100.)
    var wallBallCount: Int {
        switch self {
        case .womensOpen:
            return 75
        case .mensOpen, .mensPro, .womensPro:
            return 100
        }
    }

    // Race-day prescribed weight for the given station, in
    // kilograms. Returns nil for stations that don't have a
    // weight (1km Run, Ski Erg, Rowing, Burpee Broad Jumps —
    // bodyweight stations).
    //
    // Source: official HYROX rules current as of 2026. Doubled
    // values for Farmers Carry (e.g. 24 kg per hand → returns 24)
    // because the metric athletes care about IS the per-hand
    // weight, not the sum.
    //
    // Used by:
    //   • StationStatsSheet to pre-fill the weight stepper with
    //     the canonical race-day target.
    //   • RaceReadyView to color a station green when the athlete
    //     has logged at least one finished split at this exact
    //     weight.
    func raceWeight(for station: Station) -> Double? {
        switch station.kind {
        case .run:
            return nil
        case .workout:
            break
        }

        switch station {
        case .skiErg, .rowing, .burpeeBroadJumps:
            // No weight — bodyweight / fixed-resistance stations.
            return nil

        case .sledPush:
            switch self {
            case .mensOpen:   return 152
            case .mensPro:    return 202
            case .womensOpen: return 102
            case .womensPro:  return 152
            }

        case .sledPull:
            switch self {
            case .mensOpen:   return 103
            case .mensPro:    return 153
            case .womensOpen: return 78
            case .womensPro:  return 103
            }

        case .farmersCarry:
            // Per-hand weight (the kettlebell in each hand).
            switch self {
            case .mensOpen:   return 24
            case .mensPro:    return 32
            case .womensOpen: return 16
            case .womensPro:  return 24
            }

        case .sandbagLunges:
            switch self {
            case .mensOpen:   return 20
            case .mensPro:    return 30
            case .womensOpen: return 10
            case .womensPro:  return 20
            }

        case .wallBalls:
            // Med-ball weight. Open uses 9lb (4kg) for women / 6kg
            // for men; Pro uses 6kg / 9kg respectively.
            switch self {
            case .mensOpen:   return 6
            case .mensPro:    return 9
            case .womensOpen: return 4
            case .womensPro:  return 6
            }

        case .run1, .run2, .run3, .run4, .run5, .run6, .run7, .run8:
            // Unreachable — covered by the earlier kind == .run
            // branch — but the switch demands exhaustiveness on
            // the enum cases.
            return nil
        }
    }

    // Per-hand qualifier for stations whose race weight is "X kg
    // per hand" (Farmers Carry today; could grow). Used by the
    // StationStatsSheet so the displayed unit matches reality
    // ("24 kg per hand" not just "24 kg").
    static func isPerHandStation(_ station: Station) -> Bool {
        station == .farmersCarry
    }
}

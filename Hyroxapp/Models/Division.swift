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
    // for Open Women, but the rep count is the same 100 — we don't track
    // weight in this app yet.)
    var wallBallCount: Int {
        switch self {
        case .womensOpen:
            return 75
        case .mensOpen, .mensPro, .womensPro:
            return 100
        }
    }
}

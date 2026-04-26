import Foundation

// Solo or Duo race format.
//
// Duo (two athletes splitting work across each workout station) is an
// official HYROX category. Tier 1 of Duo ships via Apple's
// MultipeerConnectivity — two phones in the same room pair directly,
// no backend or accounts needed. Tier 2 (Supabase Realtime, supports
// remote partners) is gated on cloud auth landing first. See
// CLAUDE.md §4.5 for the full tiered spec.
enum RaceMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case solo
    case duo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solo: return "Solo"
        case .duo:  return "Duo"
        }
    }

    // Whether this mode is selectable in the current build. Tier 1
    // (Multipeer co-located) is shipping now, so .duo is `true`.
    var isAvailable: Bool {
        switch self {
        case .solo: return true
        case .duo:  return true
        }
    }
}

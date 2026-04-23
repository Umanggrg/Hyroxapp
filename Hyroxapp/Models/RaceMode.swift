import Foundation

// Solo or Duo race format.
//
// Duo (two athletes splitting work across each workout station) is an official
// HYROX category and is planned for v2 — implemented via Supabase Realtime so
// both partners' phones/watches stay synced. See CLAUDE-2.md §4.5.
//
// We define the enum now, in v0.1, so the start-screen "Solo / Duo" toggle has
// a real type to bind to. Only `.solo` is selectable today; `.duo` is rendered
// as "Coming soon" in the UI (gated via `isAvailable`).
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

    // Whether this mode is selectable in the current build.
    // Flip to `true` for `.duo` only when Supabase Realtime sync is wired up.
    var isAvailable: Bool {
        switch self {
        case .solo: return true
        case .duo:  return false
        }
    }
}

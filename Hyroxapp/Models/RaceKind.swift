import SwiftUI

// What kind of training session does this Race row represent?
//
// History was previously kind-blind: every row, whether a full
// 16-segment HYROX simulation, a one-station drill, or a free-
// form custom workout, surfaced as "HYROX Race" in the feed.
// That works in v0.1 (only one kind existed) but breaks down as
// the Train hub grows — athletes need to glance at the history
// list and distinguish "today's Race Mode attempt" from "last
// week's Quick Station drill" without tapping into each row.
//
// RaceKind is a thin label on the Race row. It doesn't change
// the schema shape — same Splits, same total duration, same HR
// stack — just the categorization. Most analytics treat all
// kinds the same (avg HR, PB tracking, leaderboards) but a few
// (most notably PB-eligibility for total time) probably want
// to gate on kind == .race in the future.
//
// Values:
//   • .race        — Full 16-segment HYROX simulation, the
//                    headline use case. PB-eligible. Unbadged
//                    on RaceCardView (it's the default).
//   • .simulation  — Practice rendition of the HYROX format,
//                    same 16-segment sequence and target HR
//                    bands but explicitly tagged as training.
//                    Differentiated mainly so race-day data
//                    doesn't get mixed with prep work for PB
//                    purposes. "SIM" badge.
//   • .quickStation — Single station drill (often paired with
//                    standalone benchmark workouts — fastest
//                    sled push, wall ball PR, etc.). "Q" badge.
//   • .training    — Multi-segment custom workout. Compromised
//                    sessions (run → station → run patterns),
//                    custom workout builder output. "T" badge.
//
// Migration-safe additive enum — pre-existing Race rows have
// no `kindRaw` field and decode as `.race` via the accessor's
// empty-string fallback. Same SwiftData additive pattern as
// `notes` / `name` / `hrSourcePrimary`.
enum RaceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case race
    case simulation
    case quickStation
    case training

    // Human-readable name for filter chips, deep links, etc.
    var displayName: String {
        switch self {
        case .race:         return "Race"
        case .simulation:   return "Simulation"
        case .quickStation: return "Quick Station"
        case .training:     return "Training"
        }
    }

    // Compact badge string for the History list row + RaceCardView
    // hero. Nil for `.race` so the default kind doesn't add visual
    // clutter — every other kind gets a short-and-loud uppercase
    // pill matching the SIM / Q / T grammar from the wireframes.
    var shortBadge: String? {
        switch self {
        case .race:         return nil
        case .simulation:   return "SIM"
        case .quickStation: return "Q"
        case .training:     return "T"
        }
    }

    // Accent color for the badge background — keeps each kind
    // visually distinguishable without an icon vocabulary fight.
    // Tints land inside the dark-theme palette already in use
    // throughout the app.
    var badgeColor: Color {
        switch self {
        case .race:         return .accent
        case .simulation:   return Color(hex: 0x5B9BD5)   // muted blue — "practice"
        case .quickStation: return .warning              // amber — "focused"
        case .training:     return .success              // green — "build"
        }
    }
}

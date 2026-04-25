import Foundation
import SwiftUI

// HYROX Performance Score — three-pillar rollup on Profile that
// summarizes an athlete's strengths and weaknesses across the
// HYROX station mix. Loosely modeled on Whoop's strain pillars
// or Strava's relative effort: a small set of headline metrics
// that capture "where am I strong, where do I need work?"
//
// Pillar groupings reflect the muscular / energy-system focus
// of each station:
//
//   • Strength — power-output stations (sleds, lunges, wall balls)
//   • Endurance — sustained-effort stations under load (burpees,
//     farmers carry)
//   • Engine — pure cardio capacity (the eight 1km runs, ski erg,
//     rowing)
//
// A station belongs to exactly one pillar in this MVP. Some
// stations could plausibly fit two (wall balls is strength AND
// endurance) but single-membership keeps the math clean and the
// pillar totals interpretable.
//
// Score model: per-pillar, sum the athlete's best-ever split for
// every station in that pillar — the "theoretical best HYROX if
// every station were optimized." Self-relative, no benchmarks,
// works from day one. Future v2+ could overlay community
// benchmarks once Supabase ships.
enum HyroxPillar: String, CaseIterable, Identifiable, Sendable {
    case strength
    case endurance
    case engine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength:  return "Strength"
        case .endurance: return "Endurance"
        case .engine:    return "Engine"
        }
    }

    // Tint used in the Performance Score tile and any future
    // pillar-specific UI (legend on a radar chart, e.g.). Maps onto
    // existing theme tokens — accent for strength (the most
    // attention-grabbing), warning for endurance (sustained pain),
    // success for engine (cardio "good condition" green).
    var color: Color {
        switch self {
        case .strength:  return Color.accent
        case .endurance: return Color.warning
        case .engine:    return Color.success
        }
    }

    // Stations that contribute to this pillar's best-time rollup.
    // For .engine, `.run1` is the canonical "1km Run" entry — the
    // RaceStats pillar helper multiplies its best by 8 to account
    // for all eight run slots in a full HYROX. Other run cases
    // (run2-run8) aren't listed because they share the same
    // displayName and aggregate by Station.kind == .run anyway.
    var stations: [Station] {
        switch self {
        case .strength:
            return [.sledPush, .sledPull, .sandbagLunges, .wallBalls]
        case .endurance:
            return [.burpeeBroadJumps, .farmersCarry]
        case .engine:
            return [.run1, .skiErg, .rowing]
        }
    }
}

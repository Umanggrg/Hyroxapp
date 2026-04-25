import Foundation
import SwiftUI

// HR zone classification used for time-in-zone analytics on race
// detail. Standard 5-zone model (Z1 recovery → Z5 max effort):
//
//   Z1: 50–60% of max HR — recovery / warm-up
//   Z2: 60–70% — aerobic base
//   Z3: 70–80% — tempo / steady-state
//   Z4: 80–90% — lactate threshold
//   Z5: 90–100% — VO2 max / anaerobic
//
// Anything below 50% is classified as Z1 too (resting / not really
// in a zone but counted there for visualization continuity).
//
// MVP classifies a whole split into one zone based on the split's
// avg HR. A more accurate version would use continuous HR samples
// and compute time-in-zone second-by-second, but we don't capture
// per-second samples — only per-segment aggregates from
// HKStatisticsQuery. Per-split classification is good enough to
// answer "did I spend most of this race in tempo or threshold?"
enum HRZone: Int, CaseIterable, Sendable {
    case z1 = 1
    case z2
    case z3
    case z4
    case z5

    // Lower bound of the zone as a fraction of max HR. Z1 starts at
    // 0 (anything below the 50% threshold falls into Z1 by convention
    // here, since recovery is the closest meaningful label).
    var lowerFraction: Double {
        switch self {
        case .z1: return 0.0
        case .z2: return 0.6
        case .z3: return 0.7
        case .z4: return 0.8
        case .z5: return 0.9
        }
    }

    // Upper bound (exclusive) of the zone as a fraction of max HR.
    // Z5 caps at infinity so a sample at 105% of max still counts as
    // Z5 rather than dropping off the chart.
    var upperFraction: Double {
        switch self {
        case .z1: return 0.6
        case .z2: return 0.7
        case .z3: return 0.8
        case .z4: return 0.9
        case .z5: return .infinity
        }
    }

    // Display label and color for the zones chart.
    var displayName: String {
        switch self {
        case .z1: return "Z1 Recovery"
        case .z2: return "Z2 Aerobic"
        case .z3: return "Z3 Tempo"
        case .z4: return "Z4 Threshold"
        case .z5: return "Z5 VO2 Max"
        }
    }

    // Canonical HR zone palette: cool → hot. Z1 muted blue,
    // Z5 hot red. Maps onto our existing theme colors where
    // possible (success/warning/accent) and falls back to system
    // colors for the rest.
    var color: Color {
        switch self {
        case .z1: return Color(hex: 0x5B9BD5)   // calm blue
        case .z2: return Color.success           // 0x32D74B (green)
        case .z3: return Color(hex: 0xFFD60A)   // yellow
        case .z4: return Color.warning           // 0xFF9F0A (orange)
        case .z5: return Color.accent            // 0xFF3B30 (red)
        }
    }

    // Classify a heart-rate sample (bpm) into a zone, given the
    // athlete's max HR. Defensive against zero or negative max HR
    // (can't divide) — falls back to Z1 in that case.
    static func zone(for bpm: Double, maxBPM: Int) -> HRZone {
        guard maxBPM > 0 else { return .z1 }
        let fraction = bpm / Double(maxBPM)
        for zone in HRZone.allCases.reversed() {
            if fraction >= zone.lowerFraction { return zone }
        }
        return .z1
    }

    // Aggregate split durations into time-in-zone totals.
    // Each split with avg HR present contributes its full duration
    // to whichever zone its avg HR falls in. Splits without HR
    // data are skipped (they'd otherwise need to be lumped into
    // some "unknown" bucket that adds noise to the chart).
    static func timeInZones(
        splits: [Split],
        maxBPM: Int
    ) -> [HRZone: TimeInterval] {
        var totals: [HRZone: TimeInterval] = [:]
        for split in splits {
            guard let avg = split.heartRateAvgBPM else { continue }
            let zone = zone(for: avg, maxBPM: maxBPM)
            totals[zone, default: 0] += split.duration
        }
        return totals
    }
}

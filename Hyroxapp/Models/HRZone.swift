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

    // Short HYROX-coded label — replaces the generic Z1...Z5 lingo
    // (which is borrowed from cycling/running training literature)
    // with vocabulary that maps to how athletes actually pace a
    // HYROX race. "Race" is the sustainable-tempo zone you want to
    // hold for 90 minutes; "Redline" is where you spend a tactical
    // 30-second push at sled push then back off.
    //
    // Used on the Live Activity HR chip and per-station tag where
    // brevity matters — fits the same space as "Z3" but reads as
    // coaching guidance rather than a zone number.
    var hyroxLabel: String {
        switch self {
        case .z1: return "Easy"
        case .z2: return "Steady"
        case .z3: return "Race"
        case .z4: return "Hard"
        case .z5: return "Redline"
        }
    }

    // Three-bucket grouping that maps onto how HYROX racers think
    // about pacing strategy: below race pace, at race pace, above
    // race pace. The 5-zone model under the hood preserves precision
    // for time-in-zone analytics; this band groups them for the
    // simpler "are you holding race effort right now?" question.
    //
    //   • .easy    — Z1 + Z2 (warmup / cooldown / easy days)
    //   • .race    — Z3      (sustainable HYROX race tempo)
    //   • .redline — Z4 + Z5 (max-effort tactical pushes only)
    //
    // Surfaces in the live HR chip on Watch / Live Activity as a
    // quick coaching cue ("⚠️ Above race pace" / "✅ Race pace").
    enum HyroxBand: Sendable {
        case easy
        case race
        case redline

        // Display label for the coarse band — same coaching-vocab
        // strategy as the per-zone hyroxLabel above.
        var displayName: String {
            switch self {
            case .easy:    return "Easy"
            case .race:    return "Race Pace"
            case .redline: return "Redline"
            }
        }
    }

    var hyroxBand: HyroxBand {
        switch self {
        case .z1, .z2: return .easy
        case .z3:      return .race
        case .z4, .z5: return .redline
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
        // Z5 = redline. Pre-v1 this mapped to `Color.accent` which
        // was iOS-system-red `#FF3B30`. The v1 coral shift moved the
        // brand off red, and the §31 Volt rebrand moved it off the
        // red family entirely (accent is now lime `#D4FF00`). Z5
        // stays on `Color.redline` (still `#FF3B30`) — the danger
        // semantic is independent of brand and "redline" should
        // always read as the iOS system-red. Keeping Z5 on the
        // brand color would now look wrong twice over: chartreuse
        // chip when you're maxed out doesn't communicate "back off."
        case .z5: return Color.redline           // 0xFF3B30 (red)
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

    // §27 — aggregate a dense `HRSample` series into
    // time-in-zone totals. Each sample contributes the time
    // until the NEXT sample (capped at `maxGap` seconds to
    // defend against long gaps where the Watch dropped or
    // briefly went off-wrist). The final sample weighs the
    // gap from itself to `end` if provided, also capped.
    //
    // Default `maxGap` is 30s — looser than the 10s cap inside
    // `HealthKitService.timeInZones` because the dense
    // WCSession-streamed series typically samples at ~1Hz and
    // genuine gaps almost always indicate transient connection
    // loss rather than per-sample timing noise. The 30s cap
    // limits the damage of a long unbroken silent window
    // (Watch died, off wrist for a stretch) while crediting
    // realistic continuity for the common 5-15s WCSession
    // hiccup pattern.
    //
    // Samples assumed pre-sorted ascending by sampledAt — the
    // FreeRunViewModel ingest guarantees this via the dedupe
    // guard. Out-of-order samples in the rare corruption
    // edge case would inflate the final bucket slightly; not
    // worth defending against at the cost of every other call.
    static func timeInZones(
        samples: [HRSample],
        maxBPM: Int,
        end: Date? = nil,
        maxGap: TimeInterval = 30
    ) -> [HRZone: TimeInterval] {
        guard !samples.isEmpty else { return [:] }
        var totals: [HRZone: TimeInterval] = [:]
        for index in samples.indices {
            let sample = samples[index]
            let next: Date
            if index + 1 < samples.count {
                next = samples[index + 1].sampledAt
            } else if let end {
                next = end
            } else {
                continue
            }
            let rawGap = next.timeIntervalSince(sample.sampledAt)
            let weight = max(0, min(rawGap, maxGap))
            guard weight > 0 else { continue }
            let bucket = zone(for: sample.bpm, maxBPM: maxBPM)
            totals[bucket, default: 0] += weight
        }
        return totals
    }
}

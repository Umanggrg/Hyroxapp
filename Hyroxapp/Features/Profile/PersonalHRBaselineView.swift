import SwiftUI

// Athlete-specific race-pace HR band, derived from their own
// historical run splits. Coaching question this answers: "given how
// *I* race, what's the HR I should hold during the runs?"
//
// This card replaces the textbook Z3 abstraction ("70-80% of max")
// with the athlete's actual observed band. The number on the wrist
// during a race becomes meaningful as a personal target, not a
// generic threshold. Other HYROX trackers don't surface this — they
// inherit fitness apps' generic zone language.
//
// The card shows:
//   • Hero band: the IQR (25th–75th percentile of run-pace HR) as
//     a "TARGET BAND" range readout. This is what the athlete should
//     hold during races.
//   • Median callout: the single best-fit HR for steady-state running
//     (50th percentile).
//   • Sample provenance line: "from N runs across M races" so the
//     athlete can see what's powering the number, and trust it more
//     once the sample grows.
//
// Hidden when fewer than 8 run-split HR samples have been captured
// across the athlete's history (RaceStats.personalHRBaseline returns
// nil under that threshold). One full HYROX race with HR data brings
// the sample count to 8, so this surfaces after the athlete's first
// fully-tracked race.
//
// Built as a pure read-only display — no editing, no manual override.
// The whole point is that the band is *observed*, not declared.
struct PersonalHRBaselineView: View {

    let races: [Race]

    var body: some View {
        if let baseline = RaceStats.personalHRBaseline(across: races) {
            card(baseline: baseline)
        } else {
            EmptyView()
        }
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        RaceStats.personalHRBaseline(across: races) != nil
    }

    // MARK: - Card

    private func card(baseline: RaceStats.PersonalHRBaseline) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hero — the IQR band rendered as "LOW – HIGH bpm".
            // Big, monospaced, dimmed accent so it reads like a
            // performance number not a vital sign.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(baseline.lowerQuartile.rounded()))")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                Text("–")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)

                Text("\(Int(baseline.upperQuartile.rounded()))")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                Text("bpm")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, 4)
            }

            // Median callout — the band's center, the "if I had to
            // pick one number, this is it" reading. Smaller and
            // dimmed because the band is the truer story; the
            // median is just a useful summary.
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accent)
                Text("Median \(Int(baseline.median.rounded())) bpm")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }

            // Provenance line — the athlete should be able to see
            // what's behind the number. Becomes more authoritative
            // as the sample grows.
            Text("from \(baseline.sampleCount) runs across \(baseline.racesCounted) race\(baseline.racesCounted == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 2)

            // Live-cue connection — explicit callout that this band
            // actively powers the in-race coaching pill (HOLD PACE /
            // SLOW DOWN / PUSH HARDER) on both iPhone and Watch.
            // Closes the loop visually so the athlete understands
            // why the per-race HR feels more relevant after enough
            // history is captured. Without this, the card reads as
            // "interesting fact"; with it, the card reads as
            // "this is the engine behind your cue."
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.success)
                Text("Powers the in-race coaching cue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}

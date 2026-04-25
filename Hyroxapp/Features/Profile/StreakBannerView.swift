import SwiftUI

// "Day streak" banner on Profile — Strava / Duolingo-style flame
// counter showing consecutive days the athlete has completed a race.
// Sits between the aggregate stats grid and the HYROX Performance
// section so it reads as a "you're still on it" cue right after the
// headline counters.
//
// Two readouts in one card:
//   • Current streak — big, hero number with flame icon. Warning
//     orange when active (current > 0), grey when broken (current
//     == 0 but a longest streak exists).
//   • Best streak — small subtitle "Best: N days" — only shown when
//     it's higher than the current streak (otherwise it'd just
//     duplicate what the hero says).
//
// Hidden by the parent until the athlete has trained on at least
// two consecutive days — `shouldShow` returns true when
// longestStreak >= 2. A solo "1 day streak" right after a first
// race feels like overstating things.
//
// Guarded `#if !os(watchOS)` because the underlying RaceStreaks
// helper is iOS-only.
#if !os(watchOS)
struct StreakBannerView: View {

    let races: [Race]

    private var current: Int {
        RaceStreaks.currentStreak(in: races)
    }

    private var longest: Int {
        RaceStreaks.longestStreak(in: races)
    }

    // Parent visibility helper — hide the banner until there's been
    // at least one multi-day streak. Without this, a brand-new user
    // would see "1 day streak" or "0 day streak" which feels like
    // noise rather than signal.
    static func shouldShow(in races: [Race]) -> Bool {
        RaceStreaks.longestStreak(in: races) >= 2
    }

    var body: some View {
        HStack(spacing: 16) {
            // Flame icon — burning warm orange when streak is alive,
            // dimmed to textTertiary grey when it's broken (current
            // == 0). Same visual language as Duolingo's broken
            // streak indicator.
            Image(systemName: "flame.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(current > 0 ? Color.warning : Color.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(current)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)

                    // English handles 0 / 1 / many uniformly here
                    // ("0 day streak" reads fine, "1 day streak"
                    // reads fine). Localizing to "1 day streak" vs
                    // "5 days streak" is a v2 problem.
                    Text("day streak")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                if longest > current {
                    Text("Best: \(longest) days")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                } else if current > 0 {
                    // When the current streak ties or exceeds best,
                    // call that out — extra motivation. "All-time
                    // best!" reads as a victory cue.
                    Text("All-time best!")
                        .font(.caption.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(Color.success)
                }
            }

            Spacer()
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}
#endif

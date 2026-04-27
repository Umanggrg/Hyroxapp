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

    // Drives the flame's gentle flicker when the streak is active.
    // 1.2s ease-in-out scale loop between 0.95 and 1.08 — reads as
    // "burning" without feeling like a notification. Off when streak
    // is broken (current == 0) so a dim grey flame stays still.
    @State private var flamePulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // streak indicator. Active streak's flame gently pulses
            // (1.2s ease-in-out loop, 0.95 → 1.08 scale) so it reads
            // as "burning" instead of a static decal. Broken streak
            // stays still — pulsing a dead flame would mock the loss.
            Image(systemName: "flame.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(current > 0 ? Color.warning : Color.textTertiary)
                .scaleEffect(current > 0 && flamePulse ? 1.08 : 0.95)
                .animation(
                    reduceMotion || current == 0
                        ? .none
                        : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: flamePulse
                )
                .onAppear {
                    if current > 0 && !reduceMotion {
                        flamePulse = true
                    }
                }

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

// Streak-at-risk CTA — sits ABOVE StreakBannerView on the days
// when the athlete's streak is in danger of breaking. Only renders
// when:
//   • There's an active multi-day streak (currentStreak >= 2,
//     so a "1-day streak at risk" never fires — that's noise).
//   • The most recent training day was YESTERDAY (today = already
//     protected; older = already broken).
//
// Coral / warning treatment to read as urgent without feeling
// punitive. Strava + Duolingo both nail this — the language is
// "your streak ends tonight if..." not "you've failed." The CTA
// nudges toward the Race tab; it doesn't lecture.
//
// Hidden the moment the athlete completes a race today — the
// streak flips to "protected today" status and the banner
// vanishes naturally.
struct StreakAtRiskBanner: View {

    let races: [Race]

    private var streak: Int {
        RaceStreaks.currentStreak(in: races)
    }

    static func shouldShow(in races: [Race]) -> Bool {
        // At-risk fires only on standing streaks (>= 2 days).
        // For a 1-day streak we don't nag — it's an early-stage
        // habit, not yet a streak to protect.
        guard RaceStreaks.currentStreak(in: races) >= 2 else { return false }
        return RaceStreaks.isStreakAtRisk(in: races)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.warning.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.warning)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Streak at risk")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text("Race today to keep your \(streak)-day streak alive.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.warning.opacity(0.35), lineWidth: 1)
        )
    }
}
#endif

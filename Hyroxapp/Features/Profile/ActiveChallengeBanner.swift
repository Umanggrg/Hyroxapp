import SwiftUI
import SwiftData

// Profile-level card showing the athlete's currently-active
// challenge with a progress bar, the headline goal copy, and
// days-remaining countdown. Two states:
//
//   • Active — coral progress bar + "3 / 5 races · 8 days left"
//   • Complete — green checkmark hero + "Challenge complete" copy
//
// Sits in the Next Up section on Profile alongside the readiness
// banner and race-event countdown. Three forward-looking signals
// stacked together: how you feel today, what you're training for,
// what goal you committed to.
//
// Tap-through navigates to ActiveChallengeDetailSheet (later)
// where the athlete can edit, abandon, or replace the challenge.
// For v1 just the banner — the detail sheet is a polish-pass
// follow-up.
//
// Auto-completion side effect: when this view computes progress
// and finds it >= 1.0 with completedAt still nil, it stamps
// completedAt via the modelContext. That means simply rendering
// the Profile triggers completion detection — no separate worker
// needed. Cheap, idempotent, runs on every appearance.
//
// Guarded `#if !os(watchOS)` because Challenge / Race are iOS-only.
#if !os(watchOS)
struct ActiveChallengeBanner: View {

    let challenge: Challenge
    let races: [Race]

    @Environment(\.modelContext) private var modelContext

    private var progress: ChallengeProgress.Progress {
        ChallengeProgress.evaluate(challenge, races: races)
    }

    private var daysRemaining: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: challenge.endDate)
        return cal.dateComponents([.day], from: today, to: end).day ?? 0
    }

    var body: some View {
        if challenge.completedAt != nil || progress.isComplete {
            completedContent
        } else {
            activeContent
        }
    }

    // MARK: - Active content

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: challenge.challengeType.symbol)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.challengeType.headline)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text(currentLabel)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)

                        Text("·")
                            .foregroundStyle(Color.textTertiary)

                        Text(daysRemainingLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(daysRemaining <= 3 ? Color.warning : Color.textTertiary)
                    }
                }

                Spacer()
            }

            // Progress bar — coral fill against surfaceElevated
            // track, clamped at 1.0 even when the athlete blew
            // past the target (the headline number above shows
            // the raw count, the bar reads as "you're done").
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surfaceElevated)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.accent, Color.accent.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * CGFloat(min(1.0, progress.fraction)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
            // Smooth animation when progress changes mid-session
            // (athlete finishes a race, comes back to Profile,
            // bar grows). Reduce-motion-respecting via system
            // animation defaults.
            .animation(.smooth(duration: 0.5), value: progress.fraction)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .onAppear {
            // Auto-stamp completion when first detected. Idempotent
            // — if already set, the assignment no-ops. Saving the
            // context is safe-by-default; SwiftData batches.
            if progress.isComplete && challenge.completedAt == nil {
                challenge.completedAt = Date()
                try? modelContext.save()
            }
        }
    }

    // Numeric label per challenge type. Each type has a different
    // shape: count for raceCount ("3 / 5 races"), time delta for
    // fastestRace ("Best 1:34:12 / target 1:30:00"), days for
    // streakLength ("4 / 7 days").
    private var currentLabel: String {
        switch challenge.challengeType {
        case .raceCount, .streakLength:
            return "\(Int(progress.currentValue)) / \(Int(progress.targetValue))"
        case .fastestRace:
            // Show the athlete's best time inside the window when
            // it's a finite value, otherwise show the target.
            if progress.currentValue.isFinite {
                return "Best \(RaceStats.format(progress.currentValue))"
            } else {
                return "Target \(RaceStats.format(progress.targetValue))"
            }
        }
    }

    private var daysRemainingLabel: String {
        if daysRemaining < 0 {
            return "Expired"
        } else if daysRemaining == 0 {
            return "Today's the day"
        } else if daysRemaining == 1 {
            return "1 day left"
        } else {
            return "\(daysRemaining) days left"
        }
    }

    // MARK: - Completed content

    // Celebratory state when challenge is met. Green checkmark
    // hero, "Complete" headline, target line as confirmation of
    // what was achieved. Stays visible until the athlete picks a
    // new challenge — the UI doesn't auto-archive completed
    // challenges; that's a deliberate choice to give the win some
    // visible duration.
    private var completedContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.success.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.success)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Challenge complete")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text(challenge.challengeType.formatTarget(challenge.targetValue))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.success.opacity(0.30), lineWidth: 1)
        )
    }
}
#endif

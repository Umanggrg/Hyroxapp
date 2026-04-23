import SwiftUI

// Launch-time prompt shown when an unfinished `Race` was found in storage —
// the athlete likely force-killed the app or the device crashed mid-race.
//
// Resume: engine state is rebuilt from the persisted race; timings continue
//         from the original start (not paused during the blackout).
// Discard: the Race row is deleted; no history of the attempt remains.
//
// Takes callbacks rather than the VM directly so the flow is explicit and
// this view can be previewed or reused.
struct ResumePromptView: View {
    let race: Race
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Unfinished Race")
                .capsLabelStyle()
                .foregroundStyle(Color.warning)

            VStack(spacing: 6) {
                Text(resumeHeroTime)
                    .font(.heroStat)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("on \(currentStationName) · \(race.startedAt.formatted(.relative(presentation: .named)))")
                    .font(.metadata)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text("Pick up from where you left off, or discard this race and start fresh. Timings continue from the original start — not paused.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onResume) {
                    Text("Resume Race")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.raceButtonHeight)
                        .background(Color.accent)
                        .foregroundStyle(Color.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                }

                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.standardButtonHeight + 8)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // Time the race had accumulated when it was last persisted. Derived from
    // the last completed split's end (or the start if no splits yet).
    private var resumeHeroTime: String {
        let lastInstant = race.splits.last?.endedAt ?? race.currentSegmentStartedAt ?? race.startedAt
        let seconds = lastInstant.timeIntervalSince(race.startedAt)
        return RaceStats.format(seconds)
    }

    // Which station the athlete was in the middle of when the app died.
    private var currentStationName: String {
        let nextIndex = race.splits.count
        let sequence = race.sequence
        guard nextIndex < sequence.count else { return sequence.last?.displayName ?? "Finish" }
        return sequence[nextIndex].displayName
    }
}

import SwiftUI
import SwiftData

// Wireframe §03.5 "Save only" confirmation. Presented as a sheet
// when the athlete taps "Save only" on the race summary screen —
// confirms the private save in a quiet, intentional moment.
//
// Layout (top → bottom, center-aligned):
//   • Green ✓ in a circle (success badge)
//   • "Saved privately." headline
//   • "Only you can see this race. Find it under History anytime."
//   • Race summary card (caps "YOUR RACE" + time + PB delta)
//   • Bottom row: Share later (outline) + Done (coral)
//
// Side effects: flips `race.isPrivate = true` so the race stays
// out of any future cross-athlete surface (feed, leaderboards).
// The race row is already in SwiftData; we just mutate it.
struct RaceSaveOnlyConfirmView: View {

    @Bindable var race: Race

    // Called when the athlete taps Share later — opens the
    // existing share-card / system share flow.
    let onShareLater: () -> Void

    // Called when the athlete taps Done — dismisses + returns to
    // the parent's resting state.
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 16)

            successBadge
                .padding(.top, 24)

            Text("Saved privately.")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 6)

            Text("Only you can see this race. Find it under History anytime.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .frame(maxWidth: 280)

            raceSummaryCard
                .padding(.top, 24)
                .padding(.horizontal, Layout.screenMargin)

            Spacer(minLength: 0)

            actionRow
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background.ignoresSafeArea())
        .onAppear {
            // Commit the private flag the moment this sheet
            // appears — the wireframe spec frames this as a
            // confirmation, not a decision point. The user has
            // already chosen "Save only" by tapping the CTA on
            // the summary screen.
            race.isPrivate = true
            Haptics.success()
        }
    }

    // MARK: - Success badge

    // Green ✓ circle. 56pt round with a 2pt border + the SF
    // checkmark glyph centered. Matches the wireframe exactly.
    private var successBadge: some View {
        ZStack {
            Circle()
                .fill(Color.success.opacity(0.18))
                .frame(width: 56, height: 56)
            Circle()
                .stroke(Color.success, lineWidth: 2)
                .frame(width: 56, height: 56)
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color.success)
        }
    }

    // MARK: - Race summary card

    // Compact recap card — caps label + finish time + optional
    // PB delta. Same shape as the post-composer's preview but
    // explicitly labeled "YOUR RACE" so the private framing reads.
    private var raceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR RACE").capsLabelStyle()

            Text(RaceStats.format(race.totalDuration ?? 0))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 2)

            // Optional PB delta line; the parent injects this via
            // a closure-based init in a future enhancement.
            // For v1, kept silent — the summary screen already
            // showed the PB delta moments ago.
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    // MARK: - Action row

    // Bottom CTAs: Share later (outline neutral) + Done (coral).
    // Wireframe ordering: Share later left, Done right.
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: onShareLater) {
                Text("Share later")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.divider, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.pressableCard)

            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .fill(Color.accent)
                    )
            }
            .buttonStyle(.pressableCard)
        }
    }
}

// Preview omitted intentionally — the #Preview macro chokes on
// the combination of in-memory ModelContainer + @Bindable on a
// SwiftData @Model class with "Failed to produce diagnostic for
// expression." Sidestepping the canvas preview lets the file
// compile; the view is reachable via its normal call site
// (RaceSummaryView's Save-only sheet) during simulator runs.

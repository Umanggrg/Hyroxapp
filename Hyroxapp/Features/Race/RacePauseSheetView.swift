import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Wireframe §03.4 — Pause sheet. Presented as a `.sheet` from
// RaceView when the athlete taps the bottom Pause button mid-race.
// The race timer is already frozen (cathedralPauseButton calls
// `viewModel.pauseRace()` before opening this) so the sheet is a
// pure decision surface — Resume / Restart / End / Discard.
//
// Wireframe layout (top → bottom):
//   • Grabber bar (system-provided via presentationDragIndicator)
//   • "PAUSED AT" caps + race timer + station progress
//   • Resume race    — coral filled, primary
//   • Restart current segment — neutral outline
//   • End race here  — coral outline, save partial
//   • Discard race   — text-only, destructive
//
// The four actions are passed in as closures so the sheet stays
// view-only — the parent (RaceView) handles confirm dialogs, view
// model calls, sheet dismissal.
struct RacePauseSheetView: View {

    // Display strings derived from the parent's race state.
    let elapsedLabel: String        // "18:32"
    let stationLabel: String        // "Run 5/8" or "Sled Push · 4/8"

    // Action closures. The parent decides what happens — typically:
    //   • onResume:  resumeRace() + dismiss
    //   • onRestart: rebaseCurrentSegment(at: Date()) + resumeRace() + dismiss
    //   • onEnd:     show end-early confirm; on confirm endEarlyAndSave()
    //   • onDiscard: show discard confirm; on confirm abandon()
    let onResume: () -> Void
    let onRestart: () -> Void
    let onEnd: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // Pause-at hero. Wireframe caps + xl number layout.
            VStack(spacing: 4) {
                Text("PAUSED AT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(Color.textSecondary)

                Text("\(elapsedLabel) · \(stationLabel)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            VStack(spacing: 10) {
                // Resume — primary coral.
                actionButton(
                    title: "Resume race",
                    style: .primary,
                    action: onResume
                )

                // Restart current segment — neutral outline.
                actionButton(
                    title: "Restart current segment",
                    style: .neutralOutline,
                    action: onRestart
                )

                // End race here — coral outline, save partial.
                actionButton(
                    title: "End race here",
                    style: .accentOutline,
                    action: onEnd
                )

                // Discard race — text only, destructive.
                actionButton(
                    title: "Discard race",
                    style: .textOnly,
                    action: onDiscard
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.screenMargin)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Color.background.ignoresSafeArea())
    }

    // MARK: - Action button factory

    private enum ButtonStyleKind {
        case primary           // filled coral
        case neutralOutline    // divider-bordered, neutral text
        case accentOutline     // coral-bordered, coral text
        case textOnly          // no border, dim text
    }

    private func actionButton(
        title: String,
        style: ButtonStyleKind,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(textColor(for: style))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(backgroundForStyle(style))
        }
        .buttonStyle(.pressableCard)
    }

    private func textColor(for style: ButtonStyleKind) -> Color {
        switch style {
        case .primary:        return Color.onAccent
        case .neutralOutline: return Color.textPrimary
        case .accentOutline:  return Color.accent
        case .textOnly:       return Color.textTertiary
        }
    }

    @ViewBuilder
    private func backgroundForStyle(_ style: ButtonStyleKind) -> some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.accent)
        case .neutralOutline:
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.divider, lineWidth: 1.5)
        case .accentOutline:
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.accent, lineWidth: 1.5)
        case .textOnly:
            // Invisible bg — the button is hit-testable via the
            // text frame, no visual surface needed.
            Color.clear
        }
    }
}

#if DEBUG
#Preview {
    RacePauseSheetView(
        elapsedLabel: "18:32",
        stationLabel: "Run 5/8",
        onResume: {},
        onRestart: {},
        onEnd: {},
        onDiscard: {}
    )
    .preferredColorScheme(.dark)
}
#endif

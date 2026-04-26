import SwiftUI

// A primary-action button that fires only after the user holds it for a
// configurable duration (default 1.5s). During the hold, a progress shade
// fills the button from left to right; on early release, the fill animates
// back to empty.
//
// Why: on the final station of a HYROX race — wall balls, sweaty, winded —
// a stray tap on a giant accent-red "Finish" button will lock in the wrong
// time with no undo. Requiring a deliberate hold is the pattern Strava and
// other sports apps use to prevent this class of mis-tap. Intermediate
// stations keep instant-tap because there's no risk of a catastrophic early
// advance (the next segment is just as valid a place to be).
//
// Implementation notes:
//   - `DragGesture(minimumDistance: 0)` detects "finger down on me" better
//     than `.onLongPressGesture` because it gives us a continuous stream
//     of location updates and fires `onEnded` for both release and cancel.
//   - Progress is derived from elapsed time, not accumulated per-tick, so
//     the fill never drifts (same principle as the race timer).
//   - Reduce Motion: instead of animating the fill, we render it in 3
//     discrete states (empty → half → full) that update as time crosses
//     thresholds. The effect is still "hold to confirm" without motion.
//   - Success haptic fires exactly once on confirm; no haptic on cancel
//     (the visual snap-back is feedback enough).
struct HoldToConfirmButton: View {

    let title: String
    let holdDuration: TimeInterval
    let onConfirm: () -> Void

    // Reduce Motion is a system accessibility setting; we check it at body
    // evaluation so the button does the right thing without the caller
    // knowing. @Environment keeps this in SwiftUI's dependency graph, so
    // toggling the setting live updates the rendering.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Tracks whether the user's finger is currently down. `nil` means idle
    // (finger up); a Date means "holding since this moment."
    @State private var pressStartedAt: Date?

    // Prevents re-entrancy if the confirm callback is slow — once we've
    // fired it for a given hold, we latch until the finger lifts.
    @State private var didConfirm = false

    init(
        title: String,
        holdDuration: TimeInterval = 1.5,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.holdDuration = holdDuration
        self.onConfirm = onConfirm
    }

    var body: some View {
        // A TimelineView(.animation) ticks once per frame while visible,
        // giving us a cheap way to recompute progress every frame without
        // managing our own Timer. When the user isn't holding, the body
        // still runs, but `progress(at:)` returns 0 so the fill is empty.
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let p = progress(at: context.date)

                ZStack(alignment: .leading) {
                    // Base (idle) pill — the whole button's silhouette.
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.accent)

                    // Darker fill overlay that grows left→right as the
                    // user holds. At p == 1.0 the whole button is
                    // overlaid; this visually distinguishes "almost
                    // confirmed" from "just started holding."
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: proxy.size.width * CGFloat(p))
                        .animation(
                            // When idle (finger up → p == 0) snap smoothly
                            // back to empty. While holding, trust the
                            // per-frame `p` value from TimelineView — no
                            // animation needed since it's already smooth.
                            pressStartedAt == nil ? Motion.standardSpring : nil,
                            value: p
                        )

                    HStack {
                        Spacer()
                        Text(title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            // Brand-contract white-on-coral; this
                            // button always sits on a coral fill so
                            // the label color is fixed regardless of
                            // the user's app theme.
                            .foregroundStyle(Color.onAccent)
                            // Progress is visible even in Reduce Motion
                            // mode — three quantized steps provide the
                            // same "am I there yet?" feedback without
                            // smooth animation.
                            .overlay(alignment: .trailing) {
                                if reduceMotion, p > 0 {
                                    Text(reduceMotionLabel(for: p))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.onAccent)
                                        .padding(.leading, 8)
                                }
                            }
                        Spacer()
                    }
                }
                // `minimumDistance: 0` means "fire onChanged as soon as
                // the finger is down, regardless of motion." Critical for
                // a press-and-hold gesture — the default DragGesture
                // requires motion before it fires.
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressStartedAt == nil {
                                pressStartedAt = Date()
                                didConfirm = false
                            }
                        }
                        .onEnded { _ in
                            // Release before completion cancels the hold;
                            // the TimelineView-driven progress will snap
                            // back to zero on next frame.
                            pressStartedAt = nil
                        }
                )
                // When progress hits 1.0, fire confirm exactly once.
                // Checking inside TimelineView's closure gives us
                // frame-accurate completion without a separate Timer.
                .onChange(of: p) { _, newValue in
                    if newValue >= 1.0, !didConfirm, pressStartedAt != nil {
                        didConfirm = true
                        Haptics.success()
                        onConfirm()
                        // Clear the hold state so if the button is still
                        // on screen (e.g. parent doesn't dismiss it
                        // immediately) it returns to idle cleanly.
                        pressStartedAt = nil
                    }
                }
            }
        }
        .frame(height: Layout.raceButtonHeight)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }

    // Fraction of the hold completed at the given moment, clamped 0...1.
    // Returns 0 when the user isn't holding.
    private func progress(at now: Date) -> Double {
        guard let start = pressStartedAt else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1.0, max(0.0, elapsed / holdDuration))
    }

    // Reduce Motion label — quantized into three states so the user sees
    // progress via text rather than animation.
    private func reduceMotionLabel(for p: Double) -> String {
        switch p {
        case 0..<0.33:  return ""
        case 0.33..<0.66: return "•"
        case 0.66..<1.0:  return "••"
        default:          return "•••"
        }
    }
}

#Preview("Hold to Finish") {
    ZStack {
        Color.background.ignoresSafeArea()
        VStack {
            Spacer()
            HoldToConfirmButton(title: "Hold to Finish") {
                print("Confirmed")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

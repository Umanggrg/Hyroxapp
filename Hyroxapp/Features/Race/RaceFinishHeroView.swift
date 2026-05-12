import SwiftUI

// Wireframe §03.4 — 3-second finish hero. Sits between the moment a
// race ends (final advance or `endEarlyAndSave`) and the
// `RaceSummaryView` taking over. Pure celebration moment — branded,
// loud, then gracefully steps aside.
//
// Layout (top → bottom, all center-aligned):
//   • "FINISHED" caps coral
//   • 78pt race time, near-black background
//   • Optional "−42s personal best" green line (only when PB)
//   • Handwritten "that was the one." quote — heroic typography
//   • "Tap to see the summary" hint (fades in after 1.5s)
//
// Background is a radial coral glow centered on the screen — the
// wireframe spec is `radial-gradient(ellipse at center,
// rgba(255,69,48,.18) 0%, transparent 60%)`. Subtle on dark, dialed
// down on warm light backgrounds via `adaptiveGlowOpacity`.
//
// Auto-dismisses after 3 seconds via the parent's onDismiss
// callback. Tap-to-skip is also wired so impatient athletes don't
// wait the full duration.
struct RaceFinishHeroView: View {

    let totalDuration: TimeInterval
    let pbDelta: TimeInterval?  // negative = new PB (faster than prior best)
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Drives the staggered entrance: caps + time + PB land
    // immediately, the handwritten quote scales in ~200ms later,
    // and the "Tap to see summary" hint fades in ~1.5s in.
    @State private var hasAppeared = false
    @State private var hintVisible = false

    var body: some View {
        ZStack {
            // Radial coral glow background. RadialGradient renders
            // a soft spotlight centered on the screen — the
            // wireframe's signature "victory light." Opacity scales
            // per mode so the warm light-mode bg doesn't read as a
            // coral wash.
            RadialGradient(
                colors: [
                    Color.accent.opacity(
                        adaptiveGlowOpacity(base: 0.18, scheme: colorScheme)
                    ),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // FINISHED caps — coral.
                Text("FINISHED")
                    .font(.caption.weight(.heavy))
                    .tracking(2.4)
                    .foregroundStyle(Color.accent)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.85)
                    .padding(.bottom, 10)

                // Hero time — 78pt rounded heavy.
                Text(RaceStats.format(totalDuration))
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 16)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.88)

                // PB delta — only renders on a new PB. Green text,
                // signed delta in MM:SS format.
                if let delta = pbDelta, delta < 0 {
                    Text("\(RaceStats.format(abs(delta))) personal best")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.onPace)
                        .padding(.top, 8)
                        .opacity(hasAppeared ? 1 : 0)
                }

                // Handwritten quote — the cathedral's emotional
                // close. Italic + slightly larger so it reads as
                // someone's handwriting on the moment, not a system
                // label. Lands ~200ms after the hero time so the
                // sequence feels staged: state → number → quote.
                Text(quoteForFinish)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.92)

                Spacer()

                // Hint copy — fades in after 1.5s so it doesn't
                // compete with the hero moment, but the athlete
                // who looks down at the phone after a couple
                // seconds sees the route forward.
                Text("Tap to see the summary")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .opacity(hintVisible ? 1 : 0)
                    .padding(.bottom, 56)
            }
        }
        .contentShape(Rectangle())  // make the whole area tappable
        .onTapGesture {
            Haptics.impact(.light)
            onTap()
        }
        .onAppear {
            // Stagger the entrance. Both animations respect
            // Reduce Motion — under that flag, hasAppeared flips
            // synchronously without any spring/scale so the
            // content shows immediately at rest.
            if reduceMotion {
                hasAppeared = true
                hintVisible = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    hasAppeared = true
                }
                // Hint copy materializes 1.5s in — the wireframe
                // wants the athlete to feel the celebration first,
                // navigation second.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeIn(duration: 0.4)) {
                        hintVisible = true
                    }
                }
            }
            // Success haptic on appear — the wrist confirms the
            // moment in case the athlete is looking away when the
            // hero lands.
            Haptics.success()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Tap to see the summary")
    }

    // Closing quote. Defaults to the wireframe's "that was the one."
    // line. On a PB we lean into the moment with a different phrase
    // so back-to-back races don't read identically.
    private var quoteForFinish: String {
        if let delta = pbDelta, delta < 0 {
            return "that was the one."
        }
        return "well raced."
    }

    private var accessibilitySummary: String {
        var parts: [String] = ["Finished. Total time \(RaceStats.format(totalDuration))."]
        if let delta = pbDelta, delta < 0 {
            parts.append("New personal best by \(RaceStats.format(abs(delta))).")
        }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
#Preview("New PB") {
    RaceFinishHeroView(
        totalDuration: 4722,           // 1:18:42
        pbDelta: -42,                   // 42s PB
        onTap: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Standard finish") {
    RaceFinishHeroView(
        totalDuration: 5400,           // 1:30:00
        pbDelta: nil,
        onTap: {}
    )
    .preferredColorScheme(.dark)
}
#endif

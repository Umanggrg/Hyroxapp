import SwiftUI

// Full-screen alert overlay for the watchOS race screen, per
// CLAUDE.md §15 Race Awareness System. When the coaching cue
// transitions mid-race (HOLD → SLOW, PUSH → HOLD, etc.), the
// entire watch face briefly takes over with the state word + a
// state-distinct haptic, then auto-dismisses back to the
// underlying Race View.
//
// Why a full-screen takeover instead of relying on the existing
// chip + haptic: a 14pt cue pill on the wrist is easy to miss
// mid-sprint, especially with sweat on the screen and HR at 170+.
// The full-screen word + color is *unmissable* — same UX
// language as Apple's "STAND" / Garmin's "RECOVERY" alerts. The
// overlay shows for 2-3 seconds and gets out of the way; if the
// athlete is in the middle of a station and didn't see it, the
// cue color on the chip remains as the persistent state.
//
// §15 design principle: "The app does NOT spam alerts. It speaks
// ONLY when the athlete needs to make a decision." So this
// overlay only fires on TRANSITIONS — entering a new cue state —
// not continuously while in that state.
struct WatchAlertOverlay: View {

    let cue: RaceStats.CoachingCue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Full-screen tinted backdrop. Cue color at low
            // opacity so the state word reads against a vignette
            // rather than a flat color (less harsh under bright
            // gym lights).
            tint.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                // SF Symbol that reinforces the state's intent
                // visually. A well-chosen glyph reads faster than
                // text — the icon lands in the eye first, then
                // the word confirms.
                Image(systemName: glyphName)
                    .font(WatchMetrics.font(size: 38, weight: .heavy))
                    .foregroundStyle(Color.onAccent)

                // The state word — huge, all caps, monospaced-
                // weight rounded font. This is what the athlete
                // glances at and reads in <0.5s. Scaled per
                // hardware so it fills the smaller watches and
                // dominates the bigger ones equally well.
                Text(stateWord)
                    .font(WatchMetrics.font(size: 32, weight: .black, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Color.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // Sub-cue — one line of "why" so a confused
                // athlete can interpret the alert. Skipped in
                // favor of vertical breathing room when the
                // hint is empty (workout/none cues never reach
                // this overlay).
                Text(subhint)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.onAccent.opacity(0.85))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }
        }
        // Soft entrance — the takeover lands rather than blasts.
        // Reduce-motion users get a hard cut.
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }

    // Tier color contract — matches the cue chip on the Race page
    // and the iPhone's live HR chip. HOLD green, SLOW coral,
    // PUSH calm blue. Workout/none never reach the overlay
    // (filtered upstream in the trigger).
    private var tint: Color {
        switch cue {
        case .hold:    return Color.success
        case .slow:    return Color.accent
        case .push:    return Color(hex: 0x5B9BD5)
        case .workout, .none: return Color.surface
        }
    }

    // SF Symbols that reinforce the cue's intent. Same glyph
    // vocabulary as the iPhone's chip cues.
    private var glyphName: String {
        switch cue {
        case .hold:    return "hand.raised.fill"  // "stay here"
        case .slow:    return "exclamationmark.triangle.fill"
        case .push:    return "bolt.fill"
        case .workout: return "dumbbell.fill"
        case .none:    return ""
        }
    }

    private var stateWord: String {
        switch cue {
        case .hold:    return "HOLD"
        case .slow:    return "SLOW"
        case .push:    return "PUSH"
        case .workout: return "WORK"
        case .none:    return ""
        }
    }

    private var subhint: String {
        switch cue {
        case .hold:    return "On pace · stay steady"
        case .slow:    return "HR rising · pull back"
        case .push:    return "More gas · go harder"
        case .workout: return ""
        case .none:    return ""
        }
    }
}

// Whether a given cue should trigger the full-screen overlay
// when entered. Workout and none don't — workout because mid-
// sled-push the wrist is loaded and any takeover reads as a
// glitch (see §15: silence = you're fine on workout stations);
// none because there's no HR sample yet, so any "alert" would
// be premature.
extension RaceStats.CoachingCue {
    var shouldShowAlertOverlay: Bool {
        switch self {
        case .hold, .slow, .push: return true
        case .workout, .none:     return false
        }
    }
}

// MARK: - Segment Transition Moment

// Brief celebratory overlay shown after every segment advance,
// per CLAUDE.md §15. Reads:
//
//   ┌─────────────────────────┐
//   │     ✓ RUN 3 COMPLETE    │  ← what just finished
//   │       4:42              │  ← time of the just-completed split
//   │                         │
//   │     NEXT: SLED PUSH     │  ← what's coming up
//   └─────────────────────────┘
//
// Different from the alert overlay: this fires on station
// CHANGE (not cue change), uses a coral-on-dark treatment
// (celebratory, not coaching), and shows ~3s — long enough for
// a sweaty glance to read what's coming next, short enough to
// step out of the way before the new segment timer needs the
// glance budget.
//
// Renders ON TOP of the new-station UI so the athlete already
// sees the next station's setup behind the overlay (peeking
// out as the overlay fades). That continuity matters — when
// the overlay clears the athlete is already half-oriented to
// the new segment.
struct WatchSegmentTransitionOverlay: View {

    let completedStationLabel: String
    let completedDuration: TimeInterval
    let nextStationLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Slightly transparent dark backdrop so the next
            // segment's UI peeks through during the overlay's
            // exit fade — the athlete's eye starts orienting
            // before the overlay fully clears.
            Color.background.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                // Checkmark + "X COMPLETE" header. Coral so the
                // moment reads as a brand-tinted celebration
                // rather than a system notification.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(WatchMetrics.font(size: 18, weight: .heavy))
                    Text("\(completedStationLabel) COMPLETE")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Color.accent)

                // The completed time — the satisfying number.
                // Big, monospaced, with a soft coral underglow
                // matching the §15 brand language.
                Text(RaceStats.format(completedDuration))
                    .font(WatchMetrics.font(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .shadow(color: Color.accent.opacity(0.30), radius: 10, y: 0)

                Spacer(minLength: 4)

                // What's coming. "NEXT:" caps strap + station
                // name. The athlete looks at this for ~1s and
                // mentally preps before the overlay clears.
                VStack(spacing: 2) {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(Color.textSecondary)
                    Text(nextStationLabel.uppercased())
                        .font(WatchMetrics.font(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }
}

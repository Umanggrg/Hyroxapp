import SwiftUI
import SwiftData

// First-launch onboarding wizard. A 4-step paged flow that
// captures the four settings everything else in the app reads
// from but that we'd otherwise silently default:
//
//   1. Welcome — introduces the app, sets expectations
//   2. Display name + handle — your identity (foreshadows social)
//   3. Division + max HR — drives wall ball reps + HR zone math
//   4. Audio cues — opt-in or out before you ever start a race
//
// Bound to a single `@Bindable` UserProfile so each step writes
// directly to the persisted row — no transient form state to
// reconcile, no risk of "I tapped Done but nothing saved."
//
// Dismissed by setting `profile.hasCompletedOnboarding = true`
// on the final step, which the parent sheet observes to close.
//
// Guarded `#if !os(watchOS)` because UserProfile is iOS-only.
#if !os(watchOS)
struct OnboardingView: View {

    @Bindable var profile: UserProfile

    @Environment(\.dismiss) private var dismiss

    // Active color scheme — drives shadow + glow scaling so the
    // wizard reads cleanly on both warm off-white (light) and
    // near-black (dark) backgrounds. Coral shadow opacity stays
    // brand-true in dark, dials back ~50% in light to keep the
    // hero icon from looking like it's glowing through fog.
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: Step = .welcome

    // Tracks the direction of the most recent step change so the
    // transition can be asymmetric — new content slides in from
    // the trailing edge when advancing, leading edge when going
    // back. Without this, every step change would slide the same
    // direction and a "Back" tap would feel wrong.
    @State private var slideDirection: SlideDirection = .forward

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Asymmetric slide direction used by the step content's
    // .transition modifier. forward = new content from the right
    // (typical "next page" feel); backward = new content from the
    // left (typical "previous page" feel).
    enum SlideDirection {
        case forward
        case backward

        var insertEdge: Edge {
            switch self {
            case .forward:  return .trailing
            case .backward: return .leading
            }
        }

        var removeEdge: Edge {
            switch self {
            case .forward:  return .leading
            case .backward: return .trailing
            }
        }
    }

    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case identity
        case division
        case audio

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:  return "Welcome to HYROX"
            case .identity: return "Your athlete profile"
            case .division: return "Division & heart rate"
            case .audio:    return "During the race"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return "The training app for HYROX athletes. Track every race, every station, every PB — built like a pro."
            case .identity:
                return "How should we name you on race cards and your profile?"
            case .division:
                return "Drives wall ball reps and your heart rate zone tiers. You can change either later in Settings."
            case .audio:
                return "Voice cues call out the next station so you never have to glance at your phone mid-sprint."
            }
        }

        var systemImage: String {
            switch self {
            case .welcome:  return "flag.checkered.2.crossed"
            case .identity: return "person.crop.circle.fill"
            case .division: return "heart.fill"
            case .audio:    return "speaker.wave.2.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 24)
                    .padding(.horizontal, Layout.screenMargin)

                ScrollView {
                    // Whole content panel (hero + step body) is
                    // keyed by step and gets an asymmetric slide
                    // transition. Treating hero + body as one unit
                    // means the icon, title, subtitle, and inputs
                    // travel together — reads as a single panel
                    // sliding rather than separate elements
                    // crossfading at different times.
                    //
                    // .id(step) is what triggers SwiftUI to treat
                    // the new step's view as a distinct insertion
                    // (firing the transition) vs. a state update
                    // on the existing view (which wouldn't animate).
                    VStack(alignment: .leading, spacing: 28) {
                        heroBlock
                        Group {
                            switch step {
                            case .welcome:  welcomeStep
                            case .identity: identityStep
                            case .division: divisionStep
                            case .audio:    audioStep
                            }
                        }
                    }
                    .padding(Layout.screenMargin)
                    .id(step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: slideDirection.insertEdge)
                                    .combined(with: .opacity),
                                removal: .move(edge: slideDirection.removeEdge)
                                    .combined(with: .opacity)
                            )
                    )
                }

                Spacer(minLength: 0)

                actionRow
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Hero block (icon + title + subtitle)

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hero icon in a coral-tinted circle with a soft glow
            // shadow. More premium first-launch feel than the bare
            // 48pt SF Symbol — frames the icon as a content
            // moment, not just a decoration.
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 96, height: 96)

                Circle()
                    .stroke(Color.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 96, height: 96)

                Image(systemName: step.systemImage)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            // Halo shadow scales with mode — full strength on dark
            // (looks like a stadium spotlight), softened on light
            // (so the icon doesn't sit in a coral fog against the
            // warm bg).
            .shadow(
                color: Color.accent.opacity(colorScheme == .dark ? 0.35 : 0.18),
                radius: 24,
                x: 0,
                y: 0
            )
            .padding(.bottom, 4)

            Text(step.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text(step.subtitle)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step bodies

    // Welcome step has no input — pure narration. Three bullet
    // callouts of what the app actually does so the user knows
    // what they're signing up for before answering questions.
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureBullet(
                icon: "stopwatch.fill",
                title: "Race Mode",
                detail: "One-tap timer for the full 16-segment HYROX format."
            )
            featureBullet(
                icon: "chart.line.uptrend.xyaxis",
                title: "Personal bests",
                detail: "Per-station PBs, trend charts, performance overload."
            )
            featureBullet(
                icon: "flame.fill",
                title: "Streaks & badges",
                detail: "Earn badges as you race. Build daily training streaks."
            )
        }
    }

    private func featureBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(
                label: "DISPLAY NAME",
                placeholder: "Athlete name",
                text: $profile.displayName
            )

            field(
                label: "HANDLE",
                placeholder: "@athlete",
                text: $profile.handle
            )
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)

            TextField(placeholder, text: text)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.surface)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var divisionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DIVISION")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)

                // Division chips — tap to select. Picker would also
                // work but the chip row reads better at this scale
                // and matches the iOS Health onboarding pattern.
                ForEach(Division.allCases, id: \.self) { division in
                    divisionRow(division)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("MAX HEART RATE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)

                Stepper(
                    "Max HR: \(profile.maxHeartRate) bpm",
                    value: $profile.maxHeartRate,
                    in: 140...220
                )
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.surface)
                )

                Text("A reasonable starting point is 220 minus your age. Use the rule of thumb if you don't know yours.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func divisionRow(_ division: Division) -> some View {
        let isSelected = profile.resolvedDivision == division
        return Button {
            profile.resolvedDivision = division
        } label: {
            HStack {
                Text(division.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accent : Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(isSelected ? Color.accent : Color.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var audioStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $profile.audioCuesEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice cues")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Announces \"Next: Sled Push\" on every transition")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .tint(Color.accent)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )

            Toggle(isOn: $profile.countdownEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-race countdown")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("3-2-1-GO before the timer starts. Tap to skip.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .tint(Color.accent)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )

            Text("Mixes with podcasts and music — your audio just ducks briefly during the announcement.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Progress bar (top of every step)

    // Four-segment pill bar showing current progress. Filled
    // segments are coral; remaining are surfaceElevated. The
    // CURRENT step's segment carries a soft glow so the eye
    // tracks "this is where you are." Smooth spring transition
    // between steps via the .animation modifier on the parent
    // step value.
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases) { stepCase in
                let isFilled = stepCase.rawValue <= step.rawValue
                let isCurrent = stepCase == step

                RoundedRectangle(cornerRadius: 2)
                    .fill(isFilled ? Color.accent : Color.surfaceElevated)
                    .frame(height: 4)
                    .shadow(
                        color: isCurrent ? Color.accent.opacity(0.6) : Color.clear,
                        radius: isCurrent ? 6 : 0,
                        x: 0,
                        y: 0
                    )
            }
        }
        .animation(Motion.snappySpring, value: step)
    }

    // MARK: - Action row (Back / Next or Get Started)

    private var actionRow: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .fill(Color.surfaceElevated)
                        )
                }
                // Pressable-card style so the Back button compresses
                // slightly on tap (0.98 scale, 0.3s spring). Same
                // tactile feedback the rest of the app uses on
                // tappable card surfaces; consistency reads as
                // craft, not novelty.
                .buttonStyle(.pressableCard)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .leading).combined(with: .opacity)
                )
            }

            Button {
                goNext()
            } label: {
                Text(step == .audio ? "Get started" : "Next")
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .fill(Color.accent)
                    )
            }
            .buttonStyle(.pressableCard)
        }
        // Animate the Back button's appearance+disappearance — on
        // step .welcome it doesn't render; on every other step it
        // does. The button slides in from the leading edge as the
        // user advances and slides out as they return to welcome.
        // Tied to the same step-change spring so back/next +
        // button-row + content panel all move as a coordinated
        // group.
        .animation(stepAnimation, value: step)
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        // Set direction BEFORE the step change so the asymmetric
        // transition reads the correct insert/remove edges. If we
        // animated the step first, the transition would still see
        // the previous (forward) direction and the slide would go
        // the wrong way.
        slideDirection = .backward
        withAnimation(stepAnimation) {
            step = prev
        }
    }

    private func goNext() {
        if let next = Step(rawValue: step.rawValue + 1) {
            slideDirection = .forward
            withAnimation(stepAnimation) {
                step = next
            }
        } else {
            // Final step — flip the completion flag and dismiss.
            // The parent sheet observes the binding and closes.
            profile.hasCompletedOnboarding = true
            dismiss()
        }
    }

    // Spring matching CLAUDE.md §5's canonical motion shape
    // (response 0.4, dampingFraction 0.8). Lands with weight,
    // doesn't bounce. Reduce-Motion users get a quick fade
    // courtesy of the .opacity transition fallback applied at
    // the content site.
    private var stepAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.45, dampingFraction: 0.85)
    }
}
#endif

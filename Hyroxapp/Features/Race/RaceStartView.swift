import SwiftUI
import SwiftData

// Pre-race screen: HYROX header, Solo/Duo toggle (Duo greyed out with
// "Coming soon" per CLAUDE.md §4.5 until Supabase Realtime sync lands in
// v2), the big Start Race button (runs the full 16-segment official
// race), and a secondary "Custom Workout" entry point that opens the
// builder sheet.
//
// Takes the owning `RaceViewModel` as a parameter rather than creating its
// own — the VM lives for the entire race flow (pre → in-progress → summary),
// and is owned by `RaceView`.
struct RaceStartView: View {
    let viewModel: RaceViewModel

    // Read the user's countdown setting so the start button knows
    // whether to fire the 3-2-1 ritual or kick off the engine
    // immediately. Falls back to true (countdown on) when no
    // profile row exists yet — bootstrap should always have run
    // by the time the start screen renders, but this keeps things
    // safe in odd states.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Pinned upcoming race event — drives the optional "T-N days
    // to HYROX Miami" callout above the primary CTA. Sorted by
    // soonest first; we surface only the first.
    @Query(sort: [SortDescriptor(\RaceEvent.date, order: .forward)])
    private var allEvents: [RaceEvent]

    private var nextEvent: RaceEvent? {
        let today = Calendar.current.startOfDay(for: Date())
        return allEvents.first { $0.date >= today }
    }

    private var countdownEnabled: Bool {
        profiles.first?.countdownEnabled ?? true
    }

    // Drives the Custom Workout Builder sheet. Stays false until the
    // user explicitly taps the secondary button below the primary
    // Start Race CTA.
    @State private var isBuilderPresented = false

    // Drives the target-time picker sheet.
    @State private var isTargetPickerPresented = false

    // Athlete's finish-time goal for the next race they start.
    // Defaults to 1:30:00 — the canonical HYROX target finish — so the
    // common case (elite/competitive athlete) is zero-config. Setting
    // to nil clears the goal (race runs without a target).
    // Persists for this screen's lifetime; resets on app restart.
    @State private var targetDuration: TimeInterval? = 90 * 60

    // Subtle pulse-glow animation on the primary CTA. Drives the
    // ambient breathing on the Start Race button — pulls the eye
    // without flashing. Tied to a Bool that toggles on appear.
    @State private var ctaGlowing = false

    var body: some View {
        ZStack {
            HeroBackdrop(.standard)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                heroBlock

                Spacer(minLength: 24)

                if let event = nextEvent {
                    eventCountdownChip(for: event)
                        .padding(.bottom, 16)
                }

                modeToggle
                    .padding(.bottom, 12)

                targetRow
                    .padding(.bottom, 20)

                primaryCTA
                    .padding(.bottom, 12)

                customWorkoutSecondary
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            // Kick off the ambient CTA pulse on a small delay so the
            // initial render doesn't show the animation start.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ctaGlowing = true
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $isBuilderPresented) {
            CustomWorkoutBuilderView { sequence in
                Haptics.impact(.medium)
                viewModel.startRaceWithCountdown(
                    sequence: sequence,
                    targetDuration: targetDuration,
                    countdownEnabled: countdownEnabled
                )
            }
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            TargetDurationPickerSheet(
                duration: $targetDuration,
                isPresented: $isTargetPickerPresented
            )
            .preferredColorScheme(.dark)
        }
        // Quick Action listener — when the user long-presses the
        // app icon and picks "Custom Workout", ContentView swaps
        // to the Race tab and this view picks up the same notice
        // to auto-open the builder. ContentView's notice listener
        // handles tab routing; this one only cares about the
        // builder-open intent.
        .onReceive(NotificationCenter.default.publisher(for: .quickActionTriggered)) { note in
            guard let action = note.object as? QuickAction,
                  action == .customWorkout
            else { return }
            isBuilderPresented = true
        }
        #endif
    }

    // MARK: - v2 hero composition

    // Top-of-screen hero: caps wordmark + giant HYROX display + tag.
    // The display font is the redesign's primary visual identity —
    // bigger, blacker, more presence than the v1 56pt. Tracking
    // bumped to 6 so the letters breathe at this size.
    private var heroBlock: some View {
        VStack(spacing: 6) {
            Text("READY TO RACE")
                .font(.caption2.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(Color.accent)

            Text("HYROX")
                .font(.system(size: 76, weight: .black, design: .rounded))
                .tracking(6)
                .foregroundStyle(Color.textPrimary)
                .shadow(color: Color.accent.opacity(0.3), radius: 24, x: 0, y: 0)

            Text("Tap start when you're at the line")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)
        }
    }

    // Event countdown chip — only renders when the athlete has
    // pinned an upcoming race event. Reads "T-43 DAYS · HYROX MIAMI"
    // and ties this training session emotionally to the goal.
    // Coral-bordered pill so it reads as "this matters."
    private func eventCountdownChip(for event: RaceEvent) -> some View {
        let days = event.daysUntil
        let dayText: String
        if days > 1 {
            dayText = "T-\(days) DAYS"
        } else if days == 1 {
            dayText = "T-1 DAY"
        } else if days == 0 {
            dayText = "RACE DAY"
        } else {
            dayText = "PAST"
        }

        return HStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.caption.weight(.bold))
            Text(dayText)
                .font(.caption.weight(.heavy))
                .tracking(0.6)
                .monospacedDigit()
            Text("·")
                .foregroundStyle(Color.accent.opacity(0.5))
            Text(event.name.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(0.6)
                .lineLimit(1)
        }
        .foregroundStyle(Color.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.accent.opacity(0.10))
                .overlay(
                    Capsule()
                        .stroke(Color.accent.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // Primary CTA — Start Race. Bigger, with an ambient coral
    // glow that gently pulses to draw the eye. The glow uses
    // .shadow + opacity animation rather than a stroke so it
    // reads as "lit up from within."
    private var primaryCTA: some View {
        Button {
            Haptics.impact(.heavy)
            viewModel.startRaceWithCountdown(
                targetDuration: targetDuration,
                countdownEnabled: countdownEnabled
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 22, weight: .heavy))
                Text("Start Race")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.raceButtonHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accent,
                                    Color.accent.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    // Inner highlight for a touch of dimensional
                    // shine — reads as polish at the seam where
                    // the gradient meets the corner radius.
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        .blendMode(.overlay)
                }
            )
            .shadow(
                color: Color.accent.opacity(ctaGlowing ? 0.55 : 0.25),
                radius: ctaGlowing ? 28 : 14,
                x: 0,
                y: 0
            )
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .animation(
            Motion.ambient.repeatForever(autoreverses: true),
            value: ctaGlowing
        )
        .padding(.horizontal, Layout.screenMargin - 4)
    }

    // Secondary CTA — Custom Workout. Outlined, muted, clearly
    // not competing with the primary. Visually anchors as an
    // alternative path rather than a feature.
    private var customWorkoutSecondary: some View {
        Button {
            isBuilderPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.callout.weight(.semibold))
                Text("Custom Workout")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.standardButtonHeight + 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surface.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Layout.screenMargin - 4)
    }

    // Tappable row showing the current target. When set, reads
    // "TARGET · 1:30:00"; when cleared, reads "TARGET · Not set".
    // The whole row is one tap target to stay forgiving on sweaty
    // fingers pre-race.
    private var targetRow: some View {
        Button {
            isTargetPickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(targetDuration == nil ? Color.textTertiary : Color.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("TARGET TIME")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.textSecondary)
                    Text(targetDuration.map(RaceStats.format) ?? "No goal set")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(targetDuration == nil ? Color.textTertiary : Color.textPrimary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Layout.cardPadding)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surface.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Layout.screenMargin - 4)
    }

    private var modeToggle: some View {
        HStack(spacing: 10) {
            modeChip(.solo)
            modeChip(.duo)
        }
        .padding(.horizontal, Layout.screenMargin - 4)
    }

    // TargetDurationPickerSheet was extracted to its own file
    // (Features/Race/TargetDurationPickerSheet.swift) so
    // RaceEventEditSheet can reuse it. Behavior unchanged.

    private func modeChip(_ mode: RaceMode) -> some View {
        // Solo is the only selectable mode in v0.1; Duo is laid out now so
        // the pattern exists in v2 when Supabase Realtime wires it up.
        let isSelected = (mode == .solo)
        let available = mode.isAvailable

        return VStack(spacing: 6) {
            Image(systemName: mode == .solo ? "person.fill" : "person.2.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(
                    isSelected ? Color.accent
                        : (available ? Color.textSecondary : Color.textTertiary)
                )

            Text(mode.displayName)
                .font(.system(size: 15, weight: .heavy, design: .rounded))

            if !available {
                Text("COMING SOON")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accent.opacity(0.10) : Color.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.accent.opacity(0.55) : Color.divider,
                    lineWidth: 1
                )
        )
        .foregroundStyle(available ? Color.textPrimary : Color.textTertiary)
        .opacity(available ? 1.0 : 0.5)
    }
}

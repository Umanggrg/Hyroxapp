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

    // Duo state owned by the parent RaceView. Bindings rather than
    // local @State because the coordinator + controller need to
    // outlive RaceStartView's lifetime — a duo race continues after
    // the user taps Start and RaceStartView is no longer rendered.
    @Binding var selectedMode: RaceMode
    @Binding var duoCoordinator: DuoCoordinator?
    @Binding var duoController: DuoRaceController?
    @Binding var isPairingPresented: Bool

    // Read the user's countdown setting so the start button knows
    // whether to fire the 3-2-1 ritual or kick off the engine
    // immediately. Falls back to true (countdown on) when no
    // profile row exists yet — bootstrap should always have run
    // by the time the start screen renders, but this keeps things
    // safe in odd states.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Active mode — drives glow opacity scaling on the start CTA.
    // The pulsing coral spotlight that anchors the dark version
    // would read as a coral haze on warm off-white if applied at
    // full strength.
    @Environment(\.colorScheme) private var colorScheme

    // Pinned upcoming race event — drives the optional "T-N days
    // to HYROX Miami" callout above the primary CTA. Sorted by
    // soonest first; we surface only the first.
    @Query(sort: [SortDescriptor(\RaceEvent.date, order: .forward)])
    private var allEvents: [RaceEvent]

    // Historical finished races — input to the §17.5 pre-race
    // predictor chip rendered above the primary CTA. The chip
    // hides itself silently when fewer than 1 finished race
    // exists, so the @Query is cheap on a fresh-install render
    // (returns []) and the chip just doesn't appear.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    )
    private var finishedRaces: [Race]

    // Athlete's configured max HR — drives the engine-score
    // input to the predictor. Falls back to the standard 190
    // when no profile is bootstrapped yet (defensive — the
    // bootstrap should always have run by the time the start
    // screen renders).
    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // Resolved division for the current athlete — needed by the
    // predictor (different divisions have different reference
    // times in the underlying model, though phase 1 doesn't use
    // division-specific anchors yet).
    private var resolvedDivision: Division {
        profiles.first?.resolvedDivision ?? .mensOpen
    }

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

    // (selectedMode, duoCoordinator, duoController, and
    // isPairingPresented are now @Binding properties owned by
    // the parent RaceView — see top of struct.)

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
                    .padding(.bottom, 12)

                // §17.5 — pre-race finish predictor chip. Sits
                // directly above the primary CTA so the athlete
                // sees their predicted time as they're about to
                // start. Hidden silently for first-race users
                // (no baseline to predict from); appears once
                // the athlete has 1+ prior finished race.
                if RacePredictorChip.hasEnoughData(
                    in: finishedRaces,
                    division: resolvedDivision,
                    maxHR: maxHeartRate
                ) {
                    RacePredictorChip(
                        races: finishedRaces,
                        division: resolvedDivision,
                        maxHR: maxHeartRate
                    )
                    .padding(.horizontal, Layout.screenMargin - 4)
                    .padding(.bottom, 16)
                }

                primaryCTA
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 4)

            // Floating "•••" menu overlay — top-right corner of
            // the screen, on top of the hero backdrop. Houses
            // secondary entrypoints (Custom Workout) that were
            // previously stacked below the primary CTA cluttering
            // the bottom of the screen. Floats rather than living
            // in a NavigationStack toolbar because RaceStartView
            // sits inside an unwrapped Race tab — adding a nav
            // bar would break the immersive HeroBackdrop bleed.
            //
            // <5% of session starts are Custom Workout; one tap
            // through the menu is the right ergonomics for that
            // frequency.
            VStack {
                HStack {
                    Spacer()
                    moreOptionsMenu
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
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
        }
        .sheet(isPresented: $isPairingPresented) {
            #if canImport(MultipeerConnectivity)
            if let coordinator = duoCoordinator {
                DuoPairingView(coordinator: coordinator) {
                    // Partner paired and the local user confirmed.
                    // Promote selectedMode so the chip reads as Duo,
                    // and spin up the in-race controller so it's
                    // ready to broadcast (host) or receive (guest)
                    // the moment the host taps Start.
                    selectedMode = .duo
                    let role = coordinator.role ?? .host
                    duoController = DuoRaceController(
                        role: role,
                        coordinator: coordinator,
                        // Only the host's controller mutates a
                        // local engine; the guest renders read-only
                        // from received snapshots.
                        viewModel: role == .host ? viewModel : nil
                    )
                }
            }
            #endif
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

    // Top-of-screen hero: caps wordmark + HYROX display.
    //
    // De-cluttered from the v1 hero — the "Tap start when you're at
    // the line" subtitle was decorative filler that pushed the
    // primary CTA further down without adding real information. The
    // HYROX wordmark itself is the brand anchor; the caps strap
    // ("READY TO RACE") provides the contextual call-to-action
    // already. Wordmark also dropped from 76pt → 60pt: at 76 the
    // hero ate ~30% of the vertical space on a 6.1" iPhone, leaving
    // the Start CTA and target row clustered at the bottom. 60pt
    // still reads as a hero, frees ~80pt of vertical breathing
    // room for the controls below.
    private var heroBlock: some View {
        VStack(spacing: 6) {
            Text("READY TO RACE")
                .font(.caption2.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(Color.accent)

            Text("HYROX")
                .font(.system(size: 60, weight: .black, design: .rounded))
                .tracking(5)
                .foregroundStyle(Color.textPrimary)
                .shadow(color: Color.accent.opacity(0.3), radius: 20, x: 0, y: 0)
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

    // True when the local user has paired as a guest. In this
    // state, the primary CTA can't start a race — only the host
    // does. We render a non-interactive "Waiting for host" panel
    // instead.
    private var isGuestWaiting: Bool {
        #if canImport(MultipeerConnectivity)
        return selectedMode == .duo
            && duoCoordinator?.role == .guest
        #else
        return false
        #endif
    }

    // Primary CTA — Start Race. Bigger, with an ambient coral
    // glow that gently pulses to draw the eye. The glow uses
    // .shadow + opacity animation rather than a stroke so it
    // reads as "lit up from within."
    @ViewBuilder
    private var primaryCTA: some View {
        if isGuestWaiting {
            guestWaitingPanel
        } else {
            hostStartButton
        }
    }

    // Read-only panel shown to the guest while paired. Replaces
    // the Start Race button — the guest can't start the race,
    // only the host can. When the host starts, the controller's
    // first inbound stateUpdate triggers a fullScreenCover
    // routing the guest into DuoGuestRaceView.
    private var guestWaitingPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.accent)
                Text("Waiting for host…")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.raceButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accent.opacity(0.35), lineWidth: 1)
            )

            Text("\(pairedPartnerName ?? "Your partner") will tap Start on their phone.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Layout.screenMargin - 4)
    }

    // The original primary CTA — solo and host both use this.
    // Tapping in duo mode (host) starts a normal race; the engine
    // state change fires the broadcast hook on the parent RaceView.
    private var hostStartButton: some View {
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
                Text(selectedMode == .duo ? "Start Duo Race" : "Start Race")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
            }
            // Brand-contract white-on-coral; see Color.onAccent.
            .foregroundStyle(Color.onAccent)
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
                // Pulsing coral spotlight scales with mode — full
                // OLED-tuned values on dark, halved on light so the
                // CTA reads as polished, not haloed.
                color: Color.accent.opacity(
                    colorScheme == .dark
                        ? (ctaGlowing ? 0.55 : 0.25)
                        : (ctaGlowing ? 0.30 : 0.14)
                ),
                radius: ctaGlowing ? 28 : 14,
                x: 0,
                y: 0
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.12),
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .animation(
            Motion.ambient.repeatForever(autoreverses: true),
            value: ctaGlowing
        )
        .padding(.horizontal, Layout.screenMargin - 4)
    }

    // Floating "•••" menu — top-right corner overlay, surfaces
    // secondary entrypoints (Custom Workout) one tap away without
    // letting them eat permanent vertical real estate at the
    // bottom of the screen. Visual treatment matches the nav-bar
    // ellipsis convention iOS users already know, but lives in a
    // floating circle since this view has no NavigationStack
    // ancestor.
    private var moreOptionsMenu: some View {
        Menu {
            Button {
                isBuilderPresented = true
            } label: {
                Label("Custom Workout", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.surface.opacity(0.85))
                        .overlay(
                            Circle()
                                .stroke(Color.divider.opacity(0.6), lineWidth: 1)
                        )
                )
        }
        .accessibilityLabel("More race options")
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
        let isSelected = (mode == selectedMode)

        return Button {
            handleModeTap(mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode == .solo ? "person.fill" : "person.2.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)

                Text(mode.displayName)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))

                // For Duo: show the partner's name once pairing is
                // complete so the chip doubles as a "you're paired
                // with X" indicator. Pre-pair / Solo, this slot
                // stays empty.
                if mode == .duo, let partner = pairedPartnerName {
                    Text("with \(partner)")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(Color.success)
                        .lineLimit(1)
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
            .foregroundStyle(Color.textPrimary)
            // Subtle scale lift on the selected chip so the
            // active mode reads visually elevated even before
            // the user looks at the border + bg tint cues. 1.04
            // is small enough to feel like depth, not a callout.
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.pressableCard)
    }

    // Tap handler for the Solo / Duo chips.
    //
    // Solo tap: revert to solo, tear down any active duo coordinator.
    // Duo tap (no coordinator yet): create a coordinator, present the
    //   pairing sheet. Mode flip waits for the sheet's onReady — we
    //   don't want to commit selectedMode = .duo just because they
    //   tapped the chip; only after a partner is paired.
    // Duo tap (already paired): re-present the sheet so the user can
    //   see the connected status / cancel.
    private func handleModeTap(_ mode: RaceMode) {
        switch mode {
        case .solo:
            if selectedMode == .duo {
                duoCoordinator?.cancel()
                duoCoordinator = nil
                // Tear down the controller too so it doesn't
                // try to broadcast / receive after we've left
                // duo mode. The fullScreenCover bound to its
                // existence will dismiss naturally.
                duoController = nil
            }
            selectedMode = .solo

        case .duo:
            #if canImport(MultipeerConnectivity)
            if duoCoordinator == nil {
                let profile = profiles.first
                let displayName = profile?.displayName.trimmingCharacters(in: .whitespaces) ?? "Athlete"
                let division = profile?.resolvedDivision ?? .mensOpen
                let maxHR = profile?.maxHeartRate ?? 190
                duoCoordinator = DuoCoordinator(
                    localDisplayName: displayName.isEmpty ? "Athlete" : displayName,
                    localDivision: division,
                    localMaxHeartRate: maxHR
                )
            }
            isPairingPresented = true
            #endif
        }
    }

    // Convenience for the chip subtitle. Returns the partner's
    // display name once the coordinator is in .ready state.
    private var pairedPartnerName: String? {
        #if canImport(MultipeerConnectivity)
        guard let coordinator = duoCoordinator,
              case .ready(let name, _) = coordinator.state
        else { return nil }
        return name
        #else
        return nil
        #endif
    }
}

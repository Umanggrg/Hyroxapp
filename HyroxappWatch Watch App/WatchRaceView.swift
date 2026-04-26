import SwiftUI

// Live race screen for the watchOS companion app.
//
// Reads `WatchRaceClient.shared.snapshot` via `@Environment` and renders
// one of three states:
//   - `.waiting`   — no snapshot received yet (launched before the phone
//                    pushed anything, or paired phone not reachable).
//   - `.inProgress` — live race: computes its own timer from
//                     `snapshot.startedAt` every frame via TimelineView,
//                     shows current station + target + advance button.
//   - `.finished`   — frozen final time (from `endedAt - startedAt`),
//                     labeled "Finished".
// A separate `notStarted` phase rolls into `.waiting` visually — an
// idle phone with no active race looks the same to the athlete as a
// watch that hasn't heard from the phone yet.
//
// The watch does NOT own race state. Every field rendered here comes
// from the snapshot pushed by the phone. The only thing the watch
// computes locally is elapsed time (to avoid per-frame pushes eating
// the battery and network).
//
// Design language carries the same brand identity as the iOS app:
// the 16-bar fingerprint motif, coral chip + glow on the station/
// timer hero, white-on-coral button (`Color.onAccent` for the
// brand contract). Tuned for 41–49mm Watch faces — no filler,
// every Spacer earns its place. watchOS is dark-only so we don't
// need light-mode plumbing here; `Color.background` falls back
// to the dark hex on watchOS automatically.
struct WatchRaceView: View {

    @Environment(WatchRaceClient.self) private var client

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            // Switch on phase. The `case` bindings pull the snapshot into
            // each branch so we can pass concrete values to the subviews
            // without having to unwrap optional fields everywhere.
            if let snapshot = client.snapshot {
                switch snapshot.phase {
                case .inProgress:
                    inProgressView(snapshot: snapshot)
                case .paused:
                    pausedView(snapshot: snapshot)
                case .inRoxzone:
                    roxzoneView(snapshot: snapshot)
                case .finished:
                    finishedView(snapshot: snapshot)
                case .notStarted:
                    waitingView
                }
            } else {
                waitingView
            }
        }
    }

    // MARK: - In-progress

    // Live race layout. TimelineView re-evaluates every animation frame;
    // we pass `context.date` into the timer formatter so the digits tick
    // without any manual `Timer` bookkeeping.
    private func inProgressView(snapshot: RaceStateSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            VStack(spacing: 6) {
                // Brand fingerprint progress bar — anchors the screen
                // with the recurring 16-bar motif and doubles as a
                // glance-able "where am I in the race" cue without
                // needing to read text.
                WatchFingerprintProgress(
                    completedCount: snapshot.completedStationsCount,
                    currentIndex: snapshot.currentStationIndex,
                    totalCount: snapshot.totalStations
                )
                .frame(height: 18)
                .padding(.horizontal, 4)

                stationHeader(snapshot: snapshot)

                Spacer(minLength: 2)

                timerDisplay(snapshot: snapshot, now: context.date)

                Spacer(minLength: 2)

                // Final-station guard: on station 16 (or the last
                // station of any custom sequence), a stray tap on
                // an instant button locks in the wrong final time
                // with no undo. The phone has the same guard on
                // its hold-to-finish CTA. The watch carries it
                // here so a sweaty wrist swing can't accidentally
                // close out a race.
                if isFinalStation(snapshot: snapshot) {
                    holdToFinishButton
                } else {
                    advanceButton
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    // True when the upcoming advance would close the race —
    // the athlete is currently on the last segment, so the next
    // tap on the button finishes (rather than progresses to a
    // new segment). Mirrors the same check on the iPhone's
    // RaceView.
    private func isFinalStation(snapshot: RaceStateSnapshot) -> Bool {
        snapshot.completedStationsCount + 1 == snapshot.totalStations
    }

    // MARK: - Paused

    // Race is frozen — phone is in .paused state. The watch
    // shows the elapsed time at the moment of pause, dimmed,
    // with a "PAUSED" chip and a hint that resume is on the
    // phone (the Watch doesn't have a resume affordance yet —
    // the phone owns the pause/resume gesture so the owner of
    // the action sees the result).
    //
    // No TimelineView here — the timer is frozen, so we just
    // render once. That also saves a tiny bit of battery while
    // the user is dealing with the interruption.
    private func pausedView(snapshot: RaceStateSnapshot) -> some View {
        let frozen: TimeInterval = {
            guard let start = snapshot.startedAt,
                  let pause = snapshot.pausedAt
            else { return 0 }
            return pause.timeIntervalSince(start)
        }()

        return VStack(spacing: 6) {
            // Same fingerprint at the top — completed bars stay
            // lit, current bar still glows. Visual continuity
            // with the running state so the user knows they're
            // in the same race, just paused.
            WatchFingerprintProgress(
                completedCount: snapshot.completedStationsCount,
                currentIndex: snapshot.currentStationIndex,
                totalCount: snapshot.totalStations
            )
            .frame(height: 18)
            .padding(.horizontal, 4)
            .opacity(0.55)

            // Pause chip — textSecondary tint signals "passive
            // state, nothing's happening." No coral — coral
            // means action and there's nothing actionable
            // here from the wrist.
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("PAUSED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.surfaceElevated)
            )

            Spacer(minLength: 2)

            Text(RaceStats.format(frozen))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                // Dimmer than the running state's textPrimary —
                // textSecondary signals "frozen / inactive."
                .foregroundStyle(Color.textSecondary)

            if let station = snapshot.currentStation {
                Text("on \(station.displayName)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Text("Resume on iPhone")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    // MARK: - In Roxzone

    // Athlete just ended a segment; transition timer is running
    // until they tap to start the next station. Mirrors the
    // iOS roxzone overlay's visual language: amber-tinted
    // timer with a soft glow, "IN ROXZONE" caps chip, the
    // upcoming station's name as the up-next hint, and a
    // start-next button.
    //
    // Same `.advance` action as the regular Next Station
    // button — on the phone side, the engine's
    // `startNextSegment` handler interprets that correctly
    // when the engine state is .inRoxzone.
    private func roxzoneView(snapshot: RaceStateSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let transitionElapsed = snapshot.currentSegmentStartedAt
                .map { context.date.timeIntervalSince($0) } ?? 0

            VStack(spacing: 6) {
                WatchFingerprintProgress(
                    completedCount: snapshot.completedStationsCount,
                    currentIndex: snapshot.currentStationIndex,
                    totalCount: snapshot.totalStations
                )
                .frame(height: 18)
                .padding(.horizontal, 4)

                // Amber chip — same `Color.warning` token used
                // for transition-time treatments throughout the
                // app. Reads as "you're in a meaningful but
                // off-station state."
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .heavy))
                    Text("IN ROXZONE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.0)
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.warning.opacity(0.16))
                )

                Spacer(minLength: 2)

                // Transition time hero — amber instead of the
                // textPrimary used during a station, signaling
                // "this is non-work time, keep moving."
                Text(RaceStats.format(transitionElapsed))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.warning)
                    .shadow(color: Color.warning.opacity(0.35), radius: 10, y: 0)

                if let station = snapshot.currentStation {
                    Text("Up next · \(station.displayName)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 2)

                // Start-next button — same coral CTA, different
                // label and icon. Sends `.advance`; phone routes
                // it to `startNextSegment` based on engine state.
                Button {
                    Haptics.impact(.medium)
                    WatchRaceClient.shared.send(.advance)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Start \(snapshot.currentStation?.displayName ?? "Next")")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.accent.opacity(0.4), radius: 10, y: 0)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private func stationHeader(snapshot: RaceStateSnapshot) -> some View {
        VStack(spacing: 3) {
            // Station counter — coral pill so it reads as "you are
            // here" rather than passive metadata. Same caps-tracked
            // typography as the iOS app's section headers, scaled
            // for the watch viewport.
            Text("STATION \(snapshot.completedStationsCount + 1) OF \(snapshot.totalStations)")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.accent.opacity(0.15))
                )

            Text(snapshot.currentStation?.displayName ?? "—")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Station target uses the user's division (from the snapshot)
            // so wall balls renders 75 reps / 100 reps correctly on the
            // watch too — no need for the watch to know about UserProfile.
            if let station = snapshot.currentStation {
                Text(station.target(for: snapshot.division))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func timerDisplay(snapshot: RaceStateSnapshot, now: Date) -> some View {
        // Compute elapsed locally from startedAt so the watch ticks in
        // sync with the phone without per-second pushes. `startedAt` is
        // always present in inProgress snapshots — but we guard with ??
        // for safety.
        let total = snapshot.startedAt.map { now.timeIntervalSince($0) } ?? 0
        let segment = snapshot.currentSegmentStartedAt.map { now.timeIntervalSince($0) } ?? 0

        return VStack(spacing: 2) {
            Text(RaceStats.format(total))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                // Subtle coral underglow — same brand language as
                // the iOS hero finish moment, dialed for the
                // smaller viewport.
                .shadow(color: Color.accent.opacity(0.35), radius: 10, y: 0)

            HStack(spacing: 8) {
                Text(RaceStats.format(segment))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                // HR chip — small heart + bpm digits. Visible only
                // when the host is publishing HR samples; absent
                // when HealthKit isn't authorized or no Watch
                // hardware is feeding samples. We render the chip
                // on the same line as the segment timer so the
                // hero block stays compact.
                if let hr = snapshot.currentHeartRateBPM {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9, weight: .heavy))
                        Text("\(Int(hr.rounded()))")
                            .font(.system(size: 11, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
    }

    // MARK: - Finished

    private func finishedView(snapshot: RaceStateSnapshot) -> some View {
        let total: TimeInterval = {
            guard let start = snapshot.startedAt, let end = snapshot.endedAt else {
                return 0
            }
            return end.timeIntervalSince(start)
        }()

        return VStack(spacing: 8) {
            // Filled fingerprint — every bar lit, signal that the
            // race is complete without needing to read text.
            WatchFingerprintProgress(
                completedCount: snapshot.totalStations,
                currentIndex: snapshot.totalStations - 1,
                totalCount: snapshot.totalStations
            )
            .frame(height: 18)
            .padding(.horizontal, 4)

            // Success chip — green tint signals "done" emotionally
            // before the eye reads the time.
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 10, weight: .heavy))
                Text("FINISHED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.success)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.success.opacity(0.16))
            )

            Text(RaceStats.format(total))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .shadow(color: Color.success.opacity(0.35), radius: 10, y: 0)

            Text("\(snapshot.completedStationsCount) of \(snapshot.totalStations) stations")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Waiting / idle

    // Shown when no snapshot has arrived yet, OR the phone reports
    // `.notStarted` (no race active). Visually identical for both —
    // from the athlete's perspective, nothing's happening yet.
    private var waitingView: some View {
        VStack(spacing: 10) {
            // Dim fingerprint at the top — empty bars, signals the
            // race shape is ready but nothing is filled yet. Same
            // motif the user sees during a race, but at idle weight.
            WatchFingerprintProgress(
                completedCount: 0,
                currentIndex: -1,
                totalCount: 16
            )
            .frame(height: 14)
            .opacity(0.35)
            .padding(.horizontal, 6)

            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }

            VStack(spacing: 2) {
                Text("Ready")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text("Start a race on iPhone")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Advance button

    // On tap: fire a light haptic for immediate tactile confirmation
    // ("your tap was seen"), then send the advance action to the paired
    // iPhone. The iPhone's `RaceViewModel.advance()` handles the state
    // transition; the resulting state change propagates back to the
    // Watch via the application-context push, updating this view's
    // `snapshot` within 1-2 seconds.
    //
    // No hold-to-finish on Watch yet — the phone still requires it on
    // the final station, so the Watch's tap on station 16 is a safety
    // risk if mistapped. Worth addressing in a polish pass; for MVP we
    // rely on the user being deliberate with their wrist.
    private var advanceButton: some View {
        Button {
            Haptics.impact(.medium)
            WatchRaceClient.shared.send(.advance)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text("Next Station")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            // Brand contract: white-on-coral for primary CTAs.
            // Color.onAccent stays fixed across modes (and on
            // watchOS the whole app is dark-only anyway, but the
            // token keeps the call site consistent with iOS).
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                LinearGradient(
                    colors: [Color.accent, Color.accent.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.accent.opacity(0.4), radius: 10, y: 0)
        }
        .buttonStyle(.plain)
    }

    // Watch-tuned variant of the iPhone's `HoldToConfirmButton`.
    // Same gesture pattern + 1.5s hold + per-frame TimelineView
    // progress, but scaled to the 38pt button height we use on
    // the wrist. Delivered inline rather than as a shared
    // component because:
    //   • iOS HoldToConfirmButton is iOS-target-only (UIKit-touched)
    //   • watch dimensions differ enough that a parameterized
    //     version would still need watch-specific call sites
    //   • the only consumer here is this single button — extracting
    //     it pays off only if a second use case appears.
    //
    // Sends the same `.advance` action as the regular button on
    // confirm — the phone closes the race when it receives an
    // advance on the final segment.
    private var holdToFinishButton: some View {
        WatchHoldToFinishButton {
            WatchRaceClient.shared.send(.advance)
        }
    }
}

// MARK: - Hold-to-finish (watch-tuned)

// Press-and-hold confirmation button for the Watch's final-station
// case. Mirrors the iOS `HoldToConfirmButton` semantics:
//   • finger down → fill grows left-to-right over `holdDuration` (1.5s)
//   • release before completion → fill snaps back to empty, no fire
//   • completion → success haptic + onConfirm callback exactly once
//
// Differences from iOS:
//   • 38pt height instead of 80pt (Watch viewport)
//   • 14pt label instead of 24pt
//   • No reduce-motion text quantization here — Watch users
//     experience this less and the button is smaller; if needed,
//     it can be added by mirroring the iOS quantizedLabel logic.
struct WatchHoldToFinishButton: View {

    let onConfirm: () -> Void

    private let holdDuration: TimeInterval = 1.5

    @State private var pressStartedAt: Date?
    @State private var didConfirm = false

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let p = progress(at: context.date)

                ZStack(alignment: .leading) {
                    // Base — same coral gradient as the regular
                    // advance button so the visual identity carries
                    // through. The gesture is the new behavior, not
                    // the appearance.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.accent, Color.accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Progress fill — darkens the button left-to-right
                    // as the hold progresses. At p == 1 the whole
                    // surface is overlaid; visual cue that "you're
                    // there" before the haptic + onConfirm fires.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: proxy.size.width * CGFloat(p))
                        .animation(
                            // Snap-back when finger lifts before
                            // completion. While holding, the
                            // TimelineView's per-frame progress is
                            // already smooth — no extra animation.
                            pressStartedAt == nil ? .easeOut(duration: 0.2) : nil,
                            value: p
                        )

                    HStack(spacing: 4) {
                        Spacer()
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Hold to Finish")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(Color.onAccent)
                }
                .contentShape(Rectangle())
                .gesture(
                    // `minimumDistance: 0` is the trick that turns
                    // DragGesture into a press-detect — fires
                    // onChanged the instant the finger touches.
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressStartedAt == nil {
                                pressStartedAt = Date()
                                didConfirm = false
                            }
                        }
                        .onEnded { _ in
                            pressStartedAt = nil
                        }
                )
                .onChange(of: p) { _, newValue in
                    // Latch on confirm so we don't double-fire if
                    // the parent doesn't dismiss us instantly.
                    if newValue >= 1.0, !didConfirm, pressStartedAt != nil {
                        didConfirm = true
                        Haptics.success()
                        onConfirm()
                        pressStartedAt = nil
                    }
                }
            }
        }
        .frame(height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.accent.opacity(0.4), radius: 10, y: 0)
    }

    private func progress(at now: Date) -> Double {
        guard let start = pressStartedAt else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1.0, max(0.0, elapsed / holdDuration))
    }
}

// MARK: - Fingerprint progress bar

// 16-bar progress strip that doubles as the brand fingerprint motif.
// Each bar's HEIGHT is fixed by the same hand-tuned rhythm used on
// the app icon and HeroBackdrop watermark — so the silhouette of
// the strip reads as the brand even at a glance, no matter which
// bars are lit. Each bar's COLOR encodes race progress:
//
//   • completed (index < completedCount)         → solid coral
//   • current   (index == currentIndex)          → coral with glow
//   • upcoming  (index > currentIndex)           → dim surfaceElevated
//
// Pure decoration on the iOS app; here it's load-bearing — at one
// glance the athlete sees both "what race is this" (the shape)
// AND "where am I" (the fill).
struct WatchFingerprintProgress: View {

    let completedCount: Int
    let currentIndex: Int
    let totalCount: Int

    // Heights normalized 0.0–1.0, same rhythm as the brand
    // fingerprint. Even indices are runs (R1 R2…), odd are
    // workouts. We slice to `totalCount` so non-16 races (half-rox,
    // custom workouts) still render cleanly.
    private static let heights: [CGFloat] = [
        0.55, 0.85, 0.50, 0.95, 0.55, 0.92, 0.60, 0.78,
        0.65, 0.88, 0.65, 0.72, 0.70, 0.82, 0.72, 1.00
    ]

    private func height(at index: Int) -> CGFloat {
        // Wrap (defensive) — for races > 16 segments, repeat the
        // rhythm rather than show flat bars at the tail.
        Self.heights[index % Self.heights.count]
    }

    private func color(at index: Int) -> Color {
        if index < completedCount {
            return Color.accent
        } else if index == currentIndex {
            return Color.accent
        } else {
            return Color.surfaceElevated
        }
    }

    var body: some View {
        GeometryReader { geo in
            let n = max(totalCount, 1)
            let gap: CGFloat = 2
            let totalGap = gap * CGFloat(n - 1)
            let barWidth = (geo.size.width - totalGap) / CGFloat(n)
            let barRadius = max(barWidth * 0.4, 1)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<n, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barRadius)
                        .fill(color(at: i))
                        .frame(
                            width: barWidth,
                            height: max(geo.size.height * height(at: i), 3)
                        )
                        // Current bar gets a soft glow so the
                        // active station stands out without a
                        // larger size or a different hue.
                        .shadow(
                            color: i == currentIndex
                                ? Color.accent.opacity(0.7)
                                : Color.clear,
                            radius: i == currentIndex ? 4 : 0,
                            y: 0
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

#Preview {
    WatchRaceView()
        .environment(WatchRaceClient.shared)
}

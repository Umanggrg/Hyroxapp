import SwiftUI
import SwiftData

#if canImport(UIKit)

// Live screen for an in-progress Free Run.
//
// Reads cumulative distance + HR from FreeRunViewModel (which is
// fed by FreeRunWorkoutManager's HKLiveWorkoutBuilder). Renders:
//   • Hero elapsed timer (recomputed from `phase`'s anchor — never
//     accumulated tick-by-tick).
//   • Distance HUD in the user's chosen unit (mile or km).
//   • Live pace (current — last 30s avg) + average pace (whole run).
//   • HR chip — fades in once a sample lands.
//   • Splits ribbon — chips for each completed split with split's
//     duration + pace.
//   • Pause/Resume + End controls.
//
// On end, persists the run, kicks off the post-finish HK rehydrate
// (~8s after to give buffered samples time to flush), and pushes
// FreeRunSummaryView. End is two-step (alert) so a sweaty mis-tap
// doesn't kill the run.
struct FreeRunView: View {

    let locationType: FreeRunLocationType
    let splitUnit: FreeRunSplitUnit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = FreeRunViewModel()
    @State private var isShowingEndConfirm = false

    // §11 Free Run cathedral — pull max-HR from the active
    // profile for zone classification. Falls back to 190 when
    // bootstrap hasn't completed (matches RaceView's defensive
    // default). The HR card uses this to compute zone color
    // tinting + the 5-bar Z1-Z5 visualization.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // §11 — coaching cue banner state. Same overlay machinery
    // RaceView uses for the cathedral race screen, ported here
    // with a Free-Run-specific HR evaluator
    // (RaceStats.coachingCueForFreeRun) that drops the
    // station-context gate.
    //
    // Lifecycle:
    //   • onChange of currentHeartRateBPM → evaluateCoachingBanner
    //   • Fires when cue changes AND ≥ 10s since last fire
    //   • 2.5s auto-dismiss; tap dismisses early
    //   • Respects the same `coachingOverlaysEnabled` profile
    //     setting that gates the race screen banner
    @State private var activeCoachingCue: RaceStats.CoachingCue?
    @State private var coachingBannerDismissTask: Task<Void, Never>?
    @State private var lastBannerFiredCue: RaceStats.CoachingCue?
    @State private var lastBannerFiredAt: Date?
    @State private var lastHRSampleForCue: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // After end, pushes the summary view as a navigation
    // destination. Set to the just-finished run; cleared on
    // back-nav so the view can dismiss cleanly.
    @State private var finishedRun: FreeRun?

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                content(now: context.date)
            }

            // §11 — coaching cue overlay. Same banner SwiftUI
            // component RaceView uses; positioned at the top of
            // the screen with a top-edge transition. Suppressed
            // by `coachingOverlaysEnabled` setting in
            // evaluateCoachingBanner; this overlay always renders
            // when activeCoachingCue is non-nil.
            coachingBannerOverlay
        }
        .onChange(of: viewModel.currentHeartRateBPM) { _, newBpm in
            evaluateCoachingBanner(newHR: newBpm)
        }
        .navigationTitle("Free Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.modelContext = modelContext
            if !viewModel.hasActiveSession {
                viewModel.start(
                    locationType: locationType,
                    splitUnit: splitUnit
                )
            }

            #if canImport(WatchConnectivity)
            // Wire the Watch → iPhone action callback (wrist
            // pause/resume/end → view model).
            //
            // §52 audit note: WatchCompanionService.shared.onAction
            // is a single global slot also used by RaceView. The
            // app's nav structure prevents both views from being
            // simultaneously appeared (tab bar surfaces one or
            // the other), and the onDisappear teardown below
            // clears the handler so the next view's onAppear
            // re-registers cleanly. If a future redesign allows
            // overlapping presentation, this slot would need to
            // become a per-feature handler stack — but for the
            // current tab-bar UX it's correct as-is.
            WatchCompanionService.shared.onAction = { action in
                switch action {
                case .pauseFreeRun: viewModel.pause()
                case .resumeFreeRun: viewModel.resume()
                case .endFreeRun:
                    let run = viewModel.activeRun
                    viewModel.end()
                    finishedRun = run
                    viewModel.finishSession()
                default: break
                }
            }

            // Wire the Watch → iPhone HR streaming callback. The
            // Watch's HKLiveWorkoutBuilder publishes HR samples
            // via WCSession at ~1Hz during the run; FreeRunView
            // forwards them straight into `currentHeartRateBPM`
            // on the view model so the live HR chip ticks at the
            // wrist's native cadence rather than waiting for the
            // 5s polling fallback. Same dual-source pattern Race
            // Mode uses — Watch streaming is primary, HK polling
            // (in FreeRunWorkoutManager) is the fallback when
            // the wrist isn't streaming.
            WatchCompanionService.shared.onHeartRate = { update in
                // Stale-sample filter — same threshold as race
                // ingest. Late-delivered queued samples that
                // outlive their relevance get dropped.
                let age = Date().timeIntervalSince(update.sampledAt)
                guard age < 90 else { return }
                guard update.bpm >= 30, update.bpm <= 230 else { return }
                // §27 — forward the original sample timestamp,
                // not Date(). The buffer's chronology must
                // reflect when the Watch captured the sample,
                // not when WCSession happened to hand it to us
                // (queued deliveries can lag by seconds).
                viewModel.ingestHeartRateBPM(update.bpm, at: update.sampledAt)
            }
            #endif
        }
        .onDisappear {
            #if canImport(WatchConnectivity)
            // Clear handlers so torn-down closures don't
            // reference stale state. RaceView re-registers its
            // own handlers on its onAppear.
            WatchCompanionService.shared.onAction = nil
            WatchCompanionService.shared.onHeartRate = nil
            #endif
        }
        .alert(
            "End run?",
            isPresented: $isShowingEndConfirm
        ) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                let run = viewModel.activeRun
                viewModel.end()
                // Snapshot the finished run BEFORE finishSession
                // tears down the view model — finishedRun drives
                // the navigation push to the summary.
                finishedRun = run
                viewModel.finishSession()
            }
        } message: {
            Text("Saves to your history. You can edit details after.")
        }
        .navigationDestination(item: $finishedRun) { run in
            FreeRunSummaryView(run: run, onClose: {
                dismiss()
            })
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 20) {
            heroTime(now: now)

            distanceAndPaceRow(now: now)

            hrChip

            splitsRibbon

            Spacer(minLength: 8)

            controlBar
        }
        .padding(.horizontal, Layout.screenMargin)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // Hero — big elapsed-time number.
    private func heroTime(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        return VStack(spacing: 4) {
            Text("ELAPSED")
                .font(.caption.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
            Text(RaceStats.format(elapsed))
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // Distance + pace tiles, side-by-side.
    private func distanceAndPaceRow(now: Date) -> some View {
        HStack(spacing: 12) {
            distanceTile
            paceTile(now: now)
        }
    }

    private var distanceTile: some View {
        let metres = viewModel.engine?.distanceMetres ?? 0
        let units = metres / splitUnit.metresPerUnit
        return VStack(spacing: 4) {
            Text("DISTANCE")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.2f", units))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(splitUnit.shortLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func paceTile(now: Date) -> some View {
        let elapsed = computeElapsed(now: now)
        let metres = viewModel.engine?.distanceMetres ?? 0
        let pace: TimeInterval? = {
            guard metres > 0, elapsed > 0 else { return nil }
            return elapsed / (metres / splitUnit.metresPerUnit)
        }()

        return VStack(spacing: 4) {
            Text("AVG PACE")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(pace.map { formatPace($0) } ?? "—")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("/\(splitUnit.shortLabel)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // §11 / §25 — Free Run HR + cadence card. Cathedral race-
    // screen treatment ported over so the visual language matches
    // across surfaces. Renders:
    //   • Heart icon (tinted by current zone)
    //   • Big BPM number (zone-tinted, monospaced for digit
    //     stability as it ticks)
    //   • Source attribution glyph (applewatch / airpodspro /
    //     fused) — same as the race screen's statCellHR
    //   • Full-width HR zones bar — five rounded rectangles
    //     (Z1-Z5), with caps Hyrox zone names (Easy / Steady /
    //     Race / Hard / Redline) under each cell. The cell
    //     matching the athlete's CURRENT zone fills with that
    //     zone's color, the rest stay dimmed. Identical pattern
    //     to RaceView.hrZonesBar so the HYROX race screen and
    //     Free Run cathedral read in the exact same language.
    //   • Cadence sub-row when AirPods Pro 1+ are publishing
    //     spm via HeadphoneMotionService — auto-hides on
    //     iPhone-only / Watch-only / non-motion AirPods
    //
    // Whole card self-hides until the first HR sample lands;
    // the placeholder "—" pattern from the cramped race-screen
    // stat-strip isn't needed here because the Free Run layout
    // has the room to omit the card cleanly.
    @ViewBuilder
    private var hrChip: some View {
        if let bpm = viewModel.currentHeartRateBPM {
            let zone = HRZone.zone(for: bpm, maxBPM: maxHeartRate)
            let source = SensorSourceRegistry.shared.lastHRSource

            VStack(spacing: 12) {
                hrRow(bpm: bpm, zone: zone, source: source)

                hrZonesBar(currentZone: zone)

                if let spm = HeadphoneMotionService.shared.currentCadenceSPM {
                    cadenceRow(spm: spm)
                }
            }
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // First row of the HR card — heart + BPM on the left,
    // source glyph trailing. Zone visualization moves into the
    // dedicated full-width bar below.
    private func hrRow(
        bpm: Double,
        zone: HRZone,
        source: SensorSourceRegistry.HRSource
    ) -> some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(zone.color)
                Text("\(Int(bpm.rounded()))")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(zone.color)
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)

            // Numeric Z-tag — small, retained alongside the
            // bar's labels because the Z-number reads at a
            // glance ("I'm in Z3") faster than scanning for the
            // lit cell.
            Text("Z\(zone.rawValue)")
                .font(.caption.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(zone.color)

            // Source attribution glyph — same set used by the
            // race screen's statCellHR. Hidden before the
            // first sample's source is classified.
            if source != .unknown {
                Image(systemName: source.symbolName)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    // Full-width HR zones bar — five rounded rectangles (Z1-Z5)
    // stretched across the card width, with caps Hyrox zone
    // names (Easy / Steady / Race / Hard / Redline) under each
    // cell. The cell matching the athlete's CURRENT zone fills
    // with that zone's color; the rest dim to 20% of the same
    // color so the dial reads as a continuous gradient at low
    // intensity.
    //
    // Mirrors RaceView.hrZonesBar 1:1 — the HYROX race screen
    // and Free Run cathedral now share the exact same zone
    // visualization (Phase 25). Spring animation on zone
    // changes, gated by Reduce Motion.
    private func hrZonesBar(currentZone: HRZone) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(HRZone.allCases, id: \.self) { zone in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(zone == currentZone
                              ? zone.color
                              : zone.color.opacity(0.20))
                        .frame(height: 10)
                        .animation(
                            reduceMotion ? .none : .smooth(duration: 0.4),
                            value: currentZone
                        )
                }
            }
            HStack(spacing: 0) {
                ForEach(HRZone.allCases, id: \.self) { zone in
                    Text(zone.hyroxLabel)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(zone == currentZone
                                         ? zone.color
                                         : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true) // already announced via the BPM text
    }

    // Cadence sub-row — small caps "CAD" label + spm number
    // + AirPods glyph indicating where the metric came from.
    // §19.4 Phase 10H semantics: nil-cadence means AirPods
    // Pro 1+ aren't in the route OR motion-capable AirPods
    // aren't publishing fresh steps; the caller handles the
    // visibility gate.
    private func cadenceRow(spm: Int) -> some View {
        HStack(spacing: 6) {
            Text("CAD")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text("\(spm)")
                .font(.callout.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
            Text("spm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Image(systemName: "airpodspro")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cadence \(spm) steps per minute from AirPods")
    }

    // Splits ribbon — small chip per completed split. Empty until
    // the first km/mile boundary fires.
    @ViewBuilder
    private var splitsRibbon: some View {
        let splits = viewModel.engine?.splits ?? []
        if !splits.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(splits) { split in
                        splitChip(for: split)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func splitChip(for split: FreeRunSplit) -> some View {
        VStack(spacing: 2) {
            Text("\(split.index + 1)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accent)
            Text(RaceStats.format(split.duration))
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .frame(width: 56, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            pauseResumeButton
            endButton
        }
    }

    private var pauseResumeButton: some View {
        let isPaused = viewModel.engine?.isPaused ?? false
        return Button {
            Haptics.impact(.medium)
            if isPaused {
                viewModel.resume()
            } else {
                viewModel.pause()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text(isPaused ? "Resume" : "Pause")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            // 60pt-tall pressable → sheet tier (22pt) per the
            // v1 two-tier radius hierarchy.
            .background(
                RoundedRectangle(cornerRadius: Layout.sheetCornerRadius)
                    .fill(Color.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private var endButton: some View {
        Button {
            Haptics.warning()
            isShowingEndConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text("End")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            // Same — 60pt full-bleed pressable in the sheet
            // tier.
            .background(
                RoundedRectangle(cornerRadius: Layout.sheetCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color.accent.opacity(0.35), radius: 14, y: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func computeElapsed(now: Date) -> TimeInterval {
        guard let engine = viewModel.engine else { return 0 }
        switch engine.phase {
        case .notStarted: return 0
        case .inProgress(let startedAt): return now.timeIntervalSince(startedAt)
        case .paused(let startedAt, let pausedAt):
            return pausedAt.timeIntervalSince(startedAt)
        case .finished(let startedAt, let endedAt):
            return endedAt.timeIntervalSince(startedAt)
        }
    }

    // Pace renders as M:SS — typical conversational form for
    // running pace ("8:30 mile, 5:15 km").
    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Coaching cue banner (§11)

    // Top-edge overlay rendering the active CoachingCue (if any).
    // Same SwiftUI component RaceView uses — keeps the visual
    // language identical across the race + Free Run surfaces.
    // Tap to dismiss early.
    @ViewBuilder
    private var coachingBannerOverlay: some View {
        if let cue = activeCoachingCue {
            VStack {
                CoachingBanner(
                    cue: cue,
                    currentHR: viewModel.currentHeartRateBPM
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .onTapGesture {
                    coachingBannerDismissTask?.cancel()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        activeCoachingCue = nil
                    }
                }
                Spacer()
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(10)
        }
    }

    // Fires on every fresh HR sample. Mirrors RaceView's
    // evaluator with three Free-Run-specific differences:
    //   • No station context — uses coachingCueForFreeRun (which
    //     drops the station gate but preserves the five-state
    //     palette).
    //   • No segment progression — the "PUSH on the final
    //     segment" branch doesn't apply; PUSH only fires when
    //     HR is below Z3 per the textbook fallback.
    //   • No personal HR baseline yet — Free Run uses the
    //     textbook Z3-anchored classification. Future v2:
    //     thread the same personalHRBaseline race uses.
    //
    // Same `coachingOverlaysEnabled` setting gates the banner
    // — turning that off in Settings clears any in-flight
    // banner and suppresses future fires until re-enabled.
    private func evaluateCoachingBanner(newHR: Double?) {
        guard profiles.first?.coachingOverlaysEnabled ?? true else {
            if activeCoachingCue != nil {
                coachingBannerDismissTask?.cancel()
                activeCoachingCue = nil
            }
            return
        }

        // Gate on an active running session — no coaching during
        // pre-run / post-run / paused states. `hasActiveSession`
        // is the FreeRunViewModel flag that turns true on start,
        // false on end / abandon.
        guard viewModel.hasActiveSession else { return }

        let cue = RaceStats.coachingCueForFreeRun(
            currentHR: newHR,
            maxHR: maxHeartRate,
            priorHR: lastHRSampleForCue
        )

        defer { lastHRSampleForCue = newHR }

        guard cue.firesBanner else { return }
        if cue == lastBannerFiredCue { return }
        if let lastFiredAt = lastBannerFiredAt,
           Date().timeIntervalSince(lastFiredAt) < 10 {
            return
        }

        coachingBannerDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            activeCoachingCue = cue
        }
        lastBannerFiredCue = cue
        lastBannerFiredAt = Date()

        Haptics.coachingCue(cue)

        coachingBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                activeCoachingCue = nil
            }
        }
    }
}

#endif

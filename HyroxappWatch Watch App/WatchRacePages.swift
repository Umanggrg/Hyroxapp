import SwiftUI

// Three-page Watch race UI per CLAUDE.md §15. Each page is its own
// view so the file stays scoped and a future page (e.g. partner HR
// during Duo) can be added without bloating WatchRaceView's body.
//
// Pages, in vertical-paging order via Digital Crown:
//   • Splits  (scroll up from default)   — completed segments at a glance
//   • Race    (default)                  — segment + big timer + pace + HR
//   • HR      (scroll down from default) — engine-room detail
//
// Race is the default because it answers the most common glance
// question ("how am I doing right now?"). Splits is the
// retrospective view; HR is the deep-dive when the athlete wants to
// check engine state without competing with the timer for visual
// real estate.
//
// All three pages read the same `RaceStateSnapshot` published by
// the iPhone via WCSession. The watch owns no race state — it
// renders from the snapshot and sends `WatchAction.advance` /
// `.pause` upstream when the athlete taps a control. See
// WatchRaceView for the orchestrator + control buttons.

// MARK: - Race page (default)

// Primary live-race surface. Matches the §15 sketch:
//
//   ┌─────────────────────────┐
//   │  RUN 3          3/8 ▶   │  ← segment header
//   │                         │
//   │      4:42               │  ← segment elapsed (HUGE)
//   │                         │
//   │   -0:08                 │  ← pace ghost delta
//   │                         │
//   │  ♥ 168   ▐▐▐▐░░  Z3    │  ← HR + zone bar
//   │                         │
//   │   [   Advance / Finish  ]
//   └─────────────────────────┘
//
// Segment time is the visual anchor — that's the number the athlete
// is racing against in the moment. Total race time is demoted from
// the v1 hero (was 38pt) to a small chip on the splits page,
// because mid-segment the athlete cares more about "this segment"
// than "the whole race."
struct WatchRaceMainPage: View {

    let snapshot: RaceStateSnapshot
    let now: Date

    /// Closure fired when the athlete taps the advance button.
    /// Owned by the parent (WatchRaceView) so paging this page out
    /// to a sheet for testing doesn't drag the action machinery
    /// along with it.
    let onAdvance: () -> Void

    /// True when the next advance closes the race. Drives the
    /// hold-to-finish guard. Computed by the parent.
    let isFinalStation: Bool

    /// The hold-to-finish view rendered in place of the advance
    /// button on the final segment. The parent owns the actual
    /// gesture machinery — we just slot the rendered view in.
    let holdToFinishButton: AnyView

    var body: some View {
        VStack(spacing: 6) {
            header

            Spacer(minLength: 4)

            segmentTime

            paceDelta

            // §13.8 Tier 2 — wrist IMU rep counter. Self-hides
            // except on rep-counting stations (Phase 1 = wall
            // balls) where WatchRepCountingService is active. Sits
            // between the pace delta and the heart rate bar so
            // the athlete's natural glance order is timer → reps
            // → HR.
            repCounterChip

            Spacer(minLength: 4)

            heartRateBar

            Spacer(minLength: 4)

            if isFinalStation {
                holdToFinishButton
            } else {
                advanceButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // §13.8 Tier 2 — live rep counter chip. Wraps the rep counting
    // service's @Observable currentRepCount in a small wrist-tuned
    // surface. Hidden when isCounting is false (off-station or
    // hardware doesn't support rep counting) or the count is still
    // zero (no reps detected yet). The chip glows coral with a
    // dumbbell glyph to read as "this is the active rep counter"
    // without taking the visual weight of the timer hero.
    @ViewBuilder
    private var repCounterChip: some View {
        let service = WatchRepCountingService.shared
        if service.isCounting && service.currentRepCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 10, weight: .heavy))
                Text("\(service.currentRepCount)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("REPS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .opacity(0.7)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.accent.opacity(0.14))
            )
        }
    }

    // Top header — segment name + run/station progress count.
    // §15 specifies "RUN 3" + "3/8" for run stations and the
    // station name + station-number progression for workouts. We
    // pre-compute both indices so the header reads naturally
    // either way without surgery on Station's rawValue layout.
    private var header: some View {
        let station = snapshot.currentStation
        let displayName = station?.displayName.uppercased() ?? "—"
        let progress = headerProgress(for: snapshot)

        return HStack {
            Text(displayName)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(Color.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            // Progress chip — "3/8" with a small chevron implying
            // "you're in the middle of the run sequence" rather
            // than a flat fraction.
            HStack(spacing: 2) {
                Text(progress)
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
            }
            .foregroundStyle(Color.textSecondary)
        }
    }

    // Computes the "M/N" progress string for the header. For run
    // stations, count among runs (1-8). For workout stations,
    // count among workouts (1-8). Falls back to overall station
    // count if the station kind is unknown — defensive only;
    // every stock HYROX station has a known kind.
    private func headerProgress(for snapshot: RaceStateSnapshot) -> String {
        guard let station = snapshot.currentStation else {
            return "\(snapshot.completedStationsCount + 1)/\(snapshot.totalStations)"
        }

        // Iterate the canonical sequence up to and including the
        // current station, count how many of the same kind landed
        // before us. Cheap — ~16 checks max.
        let sequence = Station.raceSequence
        let currentIndex = sequence.firstIndex(of: station) ?? 0
        let kindCount = sequence.prefix(currentIndex + 1).filter { $0.kind == station.kind }.count
        let totalOfKind = sequence.filter { $0.kind == station.kind }.count
        return "\(kindCount)/\(totalOfKind)"
    }

    // Big segment-elapsed display. This is the §15 hero — what the
    // athlete glances at while sweating. 44pt rounded heavy with a
    // monospace digit set so the digits don't dance as they tick.
    private var segmentTime: some View {
        let elapsed = snapshot.currentSegmentStartedAt.map { now.timeIntervalSince($0) } ?? 0
        // 44pt is the §15 hero size on the 41mm baseline; WatchMetrics
        // scales it down to ~39pt on a 40mm Series 4 (so it doesn't
        // overflow) and up to ~52pt on a 49mm Ultra (so it doesn't
        // look anaemic on the bigger viewport).
        return Text(RaceStats.format(elapsed))
            .font(WatchMetrics.font(size: 44, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .shadow(color: Color.accent.opacity(0.30), radius: 12, y: 0)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // Pace Ghost delta — §15. Computes the naïve even-split
    // expected total at the current point in the race, compares
    // to the actual elapsed total, and renders the delta with
    // green-ahead / amber on-pace / red-behind tinting.
    //
    // Naïve method: target_per_segment = targetDuration /
    // totalSegments. Expected total at this point = target_per_
    // segment × completedSegments + currentSegmentElapsed (the
    // cleanest version that doesn't require segment-weighted
    // baselines). Delta = expected - actual; positive = ahead.
    //
    // Hidden when no targetDuration was set, when the race
    // hasn't started yet, or when targetDuration is non-positive
    // (defensive against bad inputs).
    @ViewBuilder
    private var paceDelta: some View {
        if let target = snapshot.targetDuration,
           target > 0,
           snapshot.totalStations > 0,
           let startedAt = snapshot.startedAt {
            // Wrap the label/tint resolution in an immediately-
            // invoked closure so the @ViewBuilder body sees a
            // single expression series. An if-else chain that
            // assigns to local lets isn't allowed in @ViewBuilder
            // context — the builder treats it as a Void
            // statement and errors with "Type '()' cannot
            // conform to 'View'."
            let resolved: (label: String, tint: Color) = {
                let elapsed = now.timeIntervalSince(startedAt)
                let perSegment = target / Double(snapshot.totalStations)

                // Expected position at this exact moment:
                // completed segments fully elapsed + the active
                // segment partly elapsed. We approximate the
                // active fraction as elapsed-since-segment-start
                // / per-segment-budget, clamped 0...1.
                let segmentElapsed = snapshot.currentSegmentStartedAt
                    .map { now.timeIntervalSince($0) }
                    ?? 0
                let activeFraction = max(0, min(1, segmentElapsed / perSegment))
                let expected = Double(snapshot.completedStationsCount) * perSegment
                    + activeFraction * perSegment

                let delta = expected - elapsed
                let absSeconds = Int(abs(delta).rounded())

                // ±5s window reads as "on pace" — tighter than
                // that would feel jittery. Outside the window,
                // render as ahead/behind with sign.
                if absSeconds <= 5 {
                    return ("on pace", Color.textSecondary)
                } else if delta > 0 {
                    return ("+\(formatDelta(absSeconds)) ahead", Color.success)
                } else {
                    return ("-\(formatDelta(absSeconds)) behind", Color.accent)
                }
            }()

            Text(resolved.label)
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(resolved.tint)
                .contentTransition(.numericText())
        } else {
            // No target → reserve no space (clean omission). The
            // big segment timer above and the HR row below close
            // up around the missing line.
            EmptyView()
        }
    }

    // Format a positive integer second count as "M:SS" or just
    // "Ss" depending on size. Keeps the delta line compact on
    // the wrist.
    private func formatDelta(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(secs)s"
    }

    // Live HR + zone bar. Heart icon + bpm digits + 5-segment zone
    // bar with the current zone highlighted. Coaching-cue color
    // tints the entire row so a glance reads both the BPM and
    // whether it's a hold/slow/push moment.
    //
    // HR source priority:
    //   1. WatchWorkoutManager.currentHeartRateBPM (LOCAL — zero
    //      latency, the Watch sees its own HR sample as soon as
    //      the builder publishes it)
    //   2. snapshot.currentHeartRateBPM (REMOTE — the value the
    //      iPhone bounced back via the application-context push,
    //      ~1-3s slower)
    //
    // We check local first so the wrist UI doesn't wait for a
    // round-trip to display HR data the Watch already has. The
    // snapshot fallback covers the case where the Watch isn't
    // running its own workout session (e.g. iPhone-only race
    // with the Watch app foregrounded but no local HK auth).
    @ViewBuilder
    private var heartRateBar: some View {
        if let hr = WatchWorkoutManager.shared.currentHeartRateBPM
            ?? snapshot.currentHeartRateBPM {
            let zone = HRZone.zone(for: hr, maxBPM: snapshot.maxHeartRate)
            let cue = snapshot.coachingCue(forCurrentHR: hr)
            let cueColor = colorForCue(cue, fallback: zone.color)
            // Guardrail status — drives ceiling chip + tinting.
            // §17.1 — when HR is within the approach band, the
            // ceiling chip glows amber; when above the ceiling,
            // it goes coral. Below the approach threshold, no
            // tint change (silent).
            let ceiling = snapshot.segmentHRCeiling
            let approachThreshold = snapshot.segmentHRApproachThreshold
            let guardrailState: GuardrailState = {
                guard let ceiling, let approachThreshold, hr > 0 else { return .silent }
                if hr >= ceiling { return .aboveCeiling }
                if hr >= approachThreshold { return .approaching }
                return .silent
            }()

            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(cueColor)
                Text("\(Int(hr.rounded()))")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(cueColor)
                    .contentTransition(.numericText())

                // Guardrail ceiling chip — small "/172" suffix
                // showing the personalized ceiling for this
                // station. Renders only when the snapshot
                // carries a ceiling (history-based or textbook
                // fallback). Tints follow the guardrail state:
                // silent (textTertiary) below approach, amber
                // approaching, coral above ceiling.
                if let ceiling {
                    Text("/\(Int(ceiling.rounded()))")
                        .font(.system(size: 10, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(guardrailTint(for: guardrailState))
                }

                Spacer(minLength: 2)

                zoneBar(currentZone: zone)

                Text("Z\(zone.rawValue)")
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(cueColor)
            }
        } else {
            // No HR sample yet — render a dim placeholder so the
            // row's height stays consistent and the layout
            // doesn't jump when the first sample arrives.
            HStack(spacing: 6) {
                Image(systemName: "heart")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                Text("—")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 2)
                zoneBar(currentZone: .z1)
                    .opacity(0.25)
                Text("—")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // 5-segment zone bar — visual representation of "where in the
    // 5-zone band is your current HR." Each segment lights up to
    // its zone color when the current HR is at or above that
    // zone's lower bound; segments above the current zone stay
    // dim. Reads quickly at a glance — colored cells from left
    // approximate the climb up through the zones.
    private func zoneBar(currentZone: HRZone) -> some View {
        // `id: \.self` because HRZone is Hashable (Int raw enum)
        // but not Identifiable. Ditto on the HR page below — the
        // bar is the same component, drawn larger.
        HStack(spacing: 2) {
            ForEach(HRZone.allCases, id: \.self) { zone in
                Capsule()
                    .fill(zone.rawValue <= currentZone.rawValue
                        ? zone.color
                        : Color.divider.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // Coaching-cue color contract — same as the iPhone race
    // screen's HR chip and the wrist's existing chip.
    private func colorForCue(_ cue: RaceStats.CoachingCue, fallback: Color) -> Color {
        switch cue {
        case .hold:    return Color.success
        case .slow:    return Color.slow
        case .redline: return Color.redline
        case .recover: return Color.recover
        case .push:    return Color(hex: 0x5B9BD5)
        case .workout, .none: return fallback
        }
    }

    // Guardrail tint contract per §17.1:
    //   • silent (HR below approach) → textTertiary, low-key
    //   • approaching (within band)  → warning amber, "heads up"
    //   • aboveCeiling (past ceiling) → accent coral, "stop pushing"
    private func guardrailTint(for state: GuardrailState) -> Color {
        switch state {
        case .silent:        return Color.textTertiary
        case .approaching:   return Color.warning
        case .aboveCeiling:  return Color.accent
        }
    }

    // Single tappable advance button. White-on-coral, 38pt height
    // — slim because it's competing with the rest of the §15
    // layout for vertical space, but still finger-target sized.
    private var advanceButton: some View {
        Button(action: onAdvance) {
            HStack(spacing: 4) {
                Text("Next")
                    .font(WatchMetrics.font(size: 14, weight: .heavy, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(WatchMetrics.font(size: 12, weight: .heavy))
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            // Button height tracks the hero scale so the tap target
            // stays proportional on every watch — taller on Ultra,
            // a touch shorter on 40mm so the rest of the layout
            // (timer + pace + HR row) still fits comfortably.
            .frame(height: WatchMetrics.dim(36))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accent)
            )
        }
        .buttonStyle(.plain)
    }
}

// Guardrail state for the §17.1 ceiling system. Computed from
// snapshot.segmentHRCeiling + segmentHRApproachThreshold +
// current HR. Drives the ceiling chip's tint and the
// anticipatory haptic in WatchRaceView's onChange handler.
enum GuardrailState: Equatable {
    case silent           // below approach band
    case approaching      // in [approach, ceiling) band
    case aboveCeiling     // at or above ceiling
}

// MARK: - Splits page (scroll up)

// Compact list of completed segments. §15 sketch shows: segment
// label + time + delta vs target + zone. We render exactly that;
// each row is 16pt tall so a 41mm watch can show all 16 segments
// without clipping.
//
// Currently completed segment is implicit — it's the first row
// that reads "ACTIVE" rather than a finished time. Doesn't need a
// scroll affordance because watchOS auto-scrolls to fit.
struct WatchRaceSplitsPage: View {

    let snapshot: RaceStateSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SPLITS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.accent)
                Spacer()
                Text(RaceStats.format(totalElapsed))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 2)

            ScrollView {
                LazyVStack(spacing: 4) {
                    // Completed segments — rendered from the
                    // serialized splits the host carries on the
                    // snapshot. Most-recent first so the athlete
                    // sees their just-finished segment without
                    // scrolling.
                    ForEach(Array(snapshot.splits.enumerated().reversed()), id: \.offset) { index, split in
                        completedRow(index: index, split: split)
                    }

                    // The active segment — what they're working
                    // through right now. Shown only while the
                    // race is in progress.
                    if snapshot.phase == .inProgress {
                        activeRow
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var totalElapsed: TimeInterval {
        snapshot.startedAt.map { now.timeIntervalSince($0) } ?? 0
    }

    private func completedRow(index: Int, split: SerializedSplit) -> some View {
        let station = Station(rawValue: split.stationRaw)
        let stationLabel = stationAbbreviation(for: station)
        let duration = split.endedAt.timeIntervalSince(split.startedAt)
        let zone = split.heartRateAvgBPM.map { avg in
            HRZone.zone(for: avg, maxBPM: snapshot.maxHeartRate)
        }

        return HStack(spacing: 6) {
            Text(stationLabel)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 42, alignment: .leading)

            Text(RaceStats.format(duration))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)

            // §15 splits sketch — vs-target delta column. Same
            // sign convention as the Race page's pace ghost
            // (positive ⇒ ahead of target ⇒ green, negative ⇒
            // behind ⇒ coral). Hidden when no target is set so
            // the row stays clean for free-form training. ±2s
            // window reads as "on target" to suppress jitter
            // from naïve per-segment splits (workouts and runs
            // share one budget here; the benchmarked-split
            // model in §13.1 Tier 2 would tighten this).
            deltaLabel(for: duration)

            Spacer()

            if let zone {
                Text("Z\(zone.rawValue)")
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(zone.color)
            }
        }
        .padding(.vertical, 2)
    }

    // Render the per-segment delta vs target ("+0:08" green,
    // "-0:12" coral, "±" muted). Returns EmptyView when no
    // target was set on the race.
    @ViewBuilder
    private func deltaLabel(for duration: TimeInterval) -> some View {
        if let target = snapshot.targetDuration,
           target > 0,
           snapshot.totalStations > 0 {
            let perSegment = target / Double(snapshot.totalStations)
            // delta = perSegment - actualDuration
            // Positive ⇒ finished under target ⇒ ahead.
            let delta = perSegment - duration
            let absSeconds = Int(abs(delta).rounded())

            if absSeconds <= 2 {
                Text("±")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
            } else if delta > 0 {
                Text("+\(formatDeltaShort(absSeconds))")
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.success)
            } else {
                Text("-\(formatDeltaShort(absSeconds))")
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
            }
        }
    }

    // Compact M:SS / Ss formatter for the splits-row delta —
    // tighter than the race page's helper so the row stays
    // single-line on a 40mm wrist.
    private func formatDeltaShort(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(secs)s"
    }

    private var activeRow: some View {
        HStack(spacing: 6) {
            Text(stationAbbreviation(for: snapshot.currentStation))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.accent)
                .frame(width: 42, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 9, weight: .heavy))
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
            }
            .foregroundStyle(Color.accent)

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accent.opacity(0.10))
        )
    }

    // Compact station label for the splits row. Same convention
    // as the Live Activity widget — short tokens that fit a 42pt
    // column. Kept inline (not on Station itself) because the
    // abbreviation strategy is presentation-specific; the full
    // displayName lives on Station for screens that have room.
    private func stationAbbreviation(for station: Station?) -> String {
        guard let station else { return "—" }
        switch station {
        case .run1: return "R1"
        case .run2: return "R2"
        case .run3: return "R3"
        case .run4: return "R4"
        case .run5: return "R5"
        case .run6: return "R6"
        case .run7: return "R7"
        case .run8: return "R8"
        case .skiErg:           return "SKI"
        case .sledPush:         return "PUSH"
        case .sledPull:         return "PULL"
        case .burpeeBroadJumps: return "BURP"
        case .rowing:           return "ROW"
        case .farmersCarry:     return "CARRY"
        case .sandbagLunges:    return "BAG"
        case .wallBalls:        return "WALL"
        }
    }
}

// MARK: - HR page (scroll down)

// Engine-room detail. §15 sketch shows current HR, zone bar, avg,
// peak, ceiling, and recovery. We render Avg + Peak + Ceiling
// tiles when those values are available. Recovery (HR drop
// between stations) intentionally omitted — `SerializedSplit`
// doesn't carry entry/end/recovery boundary samples (those live
// only on the iPhone-side `Split` model). Extending the wire
// schema to ship boundaries through the snapshot would unlock a
// fourth tile; for now the page shows what it can compute from
// what's on the wire.
struct WatchRaceHRPage: View {

    let snapshot: RaceStateSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HEART RATE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.accent)
                Spacer()
            }

            currentHRBlock

            Spacer(minLength: 4)

            statsGrid
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var currentHRBlock: some View {
        // Same source-priority logic as the main page's HR bar:
        // local Watch builder first, snapshot fallback. See the
        // comment on `WatchRaceMainPage.heartRateBar` for the
        // full rationale.
        if let hr = WatchWorkoutManager.shared.currentHeartRateBPM
            ?? snapshot.currentHeartRateBPM {
            let zone = HRZone.zone(for: hr, maxBPM: snapshot.maxHeartRate)
            let cue = snapshot.coachingCue(forCurrentHR: hr)
            let tint = colorForCue(cue, fallback: zone.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(WatchMetrics.font(size: 16, weight: .heavy))
                    Text("\(Int(hr.rounded()))")
                        .font(WatchMetrics.font(size: 36, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("bpm")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, 4)
                }
                .foregroundStyle(tint)

                // Zone bar — same component as the Race page,
                // bigger here since this is the dedicated HR view.
                HStack(spacing: 3) {
                    ForEach(HRZone.allCases, id: \.self) { z in
                        Capsule()
                            .fill(z.rawValue <= zone.rawValue
                                ? z.color
                                : Color.divider.opacity(0.4))
                            .frame(height: 8)
                    }
                }
                .padding(.top, 2)

                Text("\(zone.hyroxLabel) · Z\(zone.rawValue)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
                    .padding(.top, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("—")
                    .font(WatchMetrics.font(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textTertiary)
                Text("waiting for sample")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // Avg / Peak / Ceiling / Recovery row. Avg + peak come from
    // the host-derived per-split stats already accumulated on
    // the snapshot's splits array. Ceiling comes from §17.1
    // guardrails (`snapshot.segmentHRCeiling`). Recovery is the
    // average HR drop across all splits where both endHR and
    // the 30s-recovery sample are present — higher drop reads
    // as better cardiovascular conditioning. All four tiles
    // gracefully self-hide when their underlying data is nil
    // so a race with no HR auth (or pre-first-split) still
    // shows whatever's available without "—" holes.
    @ViewBuilder
    private var statsGrid: some View {
        let avgs = snapshot.splits.compactMap(\.heartRateAvgBPM)
        let peaks = snapshot.splits.compactMap(\.heartRateMaxBPM)
        let avgHR: Int? = avgs.isEmpty ? nil : Int((avgs.reduce(0, +) / Double(avgs.count)).rounded())
        let peakHR: Int? = peaks.max().map { Int($0.rounded()) }

        // Ceiling lives on the snapshot when guardrails resolved
        // a value for the current station. When nil, the tile
        // omits itself so the row stays visually balanced
        // rather than leaving a "—" hole.
        let ceiling = snapshot.segmentHRCeiling.map { Int($0.rounded()) }
        let ceilingTint = ceilingTileTint()

        // Recovery — avg BPM drop in the 30s after each
        // completed station, taken across all splits with both
        // boundary samples present. Self-hides until at least
        // one split has both samples (typically after the
        // second station, since recovery samples land 30s past
        // a segment end).
        let recoveryDrop = averageRecoveryDrop()

        // 2-row 2-col grid when ceiling AND recovery both
        // present (4 tiles), falls back to a single-row layout
        // otherwise. Keeps each tile tappably-sized on the
        // 40mm baseline rather than shrinking to fit four
        // tiles in one row.
        let hasCeiling = ceiling != nil
        let hasRecovery = recoveryDrop != nil

        if hasCeiling && hasRecovery {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    avgTile(avgHR)
                    peakTile(peakHR)
                }
                HStack(spacing: 6) {
                    statTile(
                        label: "CEIL",
                        value: ceiling.map { "\($0)" } ?? "—",
                        unit: "bpm",
                        valueColor: ceilingTint
                    )
                    statTile(
                        label: "RECOV",
                        value: recoveryDrop.map { "▼\($0)" } ?? "—",
                        unit: "bpm",
                        valueColor: Color.success
                    )
                }
            }
        } else {
            HStack(spacing: 6) {
                avgTile(avgHR)
                peakTile(peakHR)
                if let ceiling {
                    statTile(
                        label: "CEIL",
                        value: "\(ceiling)",
                        unit: "bpm",
                        valueColor: ceilingTint
                    )
                }
                if let drop = recoveryDrop {
                    statTile(
                        label: "RECOV",
                        value: "▼\(drop)",
                        unit: "bpm",
                        valueColor: Color.success
                    )
                }
            }
        }
    }

    // Render an AVG tile from an optional HR value. Extracted
    // so the 2x2 grid and the fallback 1-row layout share the
    // same render code.
    private func avgTile(_ value: Int?) -> some View {
        statTile(
            label: "AVG",
            value: value.map { "\($0)" } ?? "—",
            unit: "bpm",
            valueColor: Color.textPrimary
        )
    }

    private func peakTile(_ value: Int?) -> some View {
        statTile(
            label: "PEAK",
            value: value.map { "\($0)" } ?? "—",
            unit: "bpm",
            valueColor: Color.textPrimary
        )
    }

    // Average HR drop in the 30s after each completed station.
    // Same definition StationDetailView uses on the iPhone-side
    // boundary HR row — endHR minus the 30s-recovery sample.
    // Higher drop = better recovery / engine conditioning.
    //
    // Returns nil until at least one split has BOTH samples.
    // The very first split usually doesn't have a 30s sample
    // yet (it lands ~30s after the segment ended) so this
    // value typically resolves after segment 2 completes.
    private func averageRecoveryDrop() -> Int? {
        let drops: [Double] = snapshot.splits.compactMap { split in
            guard let endHR = split.heartRateEndBPM,
                  let r30 = split.heartRateRecovery30sBPM else { return nil }
            return endHR - r30
        }
        guard !drops.isEmpty else { return nil }
        let avg = drops.reduce(0, +) / Double(drops.count)
        return Int(avg.rounded())
    }

    // Resolve the ceiling tile's value color based on current HR
    // vs the guardrail bands. Mirrors the Race page's chip tint
    // (silent / approaching / above) so the same visual language
    // reads across both surfaces. Defaults to textPrimary when
    // current HR isn't available or no ceiling is set.
    private func ceilingTileTint() -> Color {
        guard
            let ceiling = snapshot.segmentHRCeiling,
            let approach = snapshot.segmentHRApproachThreshold,
            let hr = WatchWorkoutManager.shared.currentHeartRateBPM
                ?? snapshot.currentHeartRateBPM,
            hr > 0
        else { return Color.textPrimary }

        if hr >= ceiling   { return Color.accent }
        if hr >= approach  { return Color.warning }
        return Color.textPrimary
    }

    private func statTile(
        label: String,
        value: String,
        unit: String,
        valueColor: Color = Color.textPrimary
    ) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surface)
        )
    }

    private func colorForCue(_ cue: RaceStats.CoachingCue, fallback: Color) -> Color {
        switch cue {
        case .hold:    return Color.success
        case .slow:    return Color.slow
        case .redline: return Color.redline
        case .recover: return Color.recover
        case .push:    return Color(hex: 0x5B9BD5)
        case .workout, .none: return fallback
        }
    }
}

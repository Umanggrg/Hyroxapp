import ActivityKit
import SwiftUI
import WidgetKit

// The race-timer Live Activity. Renders three surfaces from the
// same `RaceActivityAttributes.ContentState`:
//
//   1. Lock screen + iOS notification — the `body` of
//      ActivityConfiguration. Full hero treatment with the
//      race timer, current station, optional roxzone overlay.
//
//   2. Dynamic Island expanded — when the user long-presses
//      the island. Same data, broken into leading/trailing/
//      bottom regions per Apple's layout grammar.
//
//   3. Dynamic Island compact + minimal — ambient state when
//      the user isn't actively looking at the island.
//
// All three timers (race, segment, roxzone) use SwiftUI's
// `Text(_:style:)` timer so the system process renders the
// ticking number for free without us pushing per-second
// updates that'd burn ActivityKit's per-app budget.
//
// Lives in the Widget Extension target; depends on the shared
// RaceActivityAttributes type.
struct RaceLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceActivityAttributes.self) { context in
            // Lock-screen / notification UI. Tapping anywhere on
            // the card deep-links back into the active race —
            // the URL scheme is registered in the main app's
            // Info.plist + handled by HyroxappApp.onOpenURL,
            // which flips the TabView to .race.
            LockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "trakr://race"))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — appears when the island is long-pressed.
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(state: context.state, attributes: context.attributes)
                }
            } compactLeading: {
                // Compact — left side of the island when the
                // activity is active. The race timer ticks here.
                compactTimer(state: context.state)
                    .foregroundStyle(islandTimerColor(for: context.state.phase))

            } compactTrailing: {
                // Compact — right side. Two-mode display:
                //   • When HR is publishing — render a small
                //     heart glyph + BPM in a zone-colored
                //     capsule. The compact island is a 1.5s
                //     glance surface; HR is the most dynamic
                //     effort signal we have, so it deserves
                //     priority over the station name (which
                //     the user just advanced to and remembers).
                //   • When no HR sample yet — fall back to the
                //     station abbreviation pill (RUN / PUSH /
                //     PULL / WALL) so the compact island isn't
                //     empty. The abbreviation also reads more
                //     on-brand than a bare number.
                //
                // The expanded view always shows BOTH (station
                // + HR via the lock-screen chip), so this
                // compact toggle never hides information — it
                // just picks the more useful of the two for a
                // glance.
                compactTrailingContent(state: context.state)

            } minimal: {
                // Minimal — single-element view shown when
                // multiple activities compete for the island.
                Image(systemName: phaseIcon(for: context.state.phase))
                    .foregroundStyle(islandTimerColor(for: context.state.phase))
            }
        }
    }

    // MARK: - Compact island timer

    @ViewBuilder
    private func compactTimer(state: RaceActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .running:
            Text(state.timerStart, style: .timer)
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
        case .paused:
            // Frozen timer — render the snapshot, not a live
            // ticker, since the race is paused.
            Text(formatDuration(state.frozenElapsed ?? 0))
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
        case .inRoxzone:
            // Show the roxzone countup in compact mode — that's
            // the most-relevant timer right now.
            if let roxStart = state.roxzoneStart {
                Text(roxStart, style: .timer)
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
            } else {
                Text("·")
            }
        case .finished:
            Text(formatDuration(state.frozenElapsed ?? 0))
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
        }
    }

    // MARK: - Compact trailing content

    // Two-mode compact-trailing renderer. See compactTrailing
    // block above for the full rationale.
    @ViewBuilder
    private func compactTrailingContent(
        state: RaceActivityAttributes.ContentState
    ) -> some View {
        if let hr = state.currentHR {
            // HR mode — heart icon + BPM in zone-colored pill.
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .heavy))
                Text("\(hr)")
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(compactHRTint(zone: state.currentHRZone).opacity(0.40))
            )
        } else {
            // Station abbreviation fallback — same shape as
            // before. Phase color drops out on this branch so
            // running / paused / finished all read consistently
            // when HR is absent (which is the common case
            // before the first sample lands).
            Text(stationAbbreviation(for: state.currentStationName))
                .font(.caption2.weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(islandTimerColor(for: state.phase).opacity(0.30))
                )
        }
    }

    // Tint for the compact trailing HR pill. Mirrors the
    // lock-screen hrZoneColor() palette (kept duplicated for
    // the same reason — widget target doesn't include
    // HRZone.swift). Falls back to phase color when zone is
    // unknown so the pill never goes flat-gray.
    private func compactHRTint(zone: Int?) -> Color {
        switch zone {
        case 1: return Color(red: 0.36, green: 0.61, blue: 0.84)
        case 2: return Color.success
        case 3: return Color(red: 1.0, green: 0.84, blue: 0.04)
        case 4: return Color.warning
        case 5: return Color.accent
        default: return Color.accent
        }
    }

    // MARK: - Expanded island regions

    @ViewBuilder
    private func expandedLeading(
        state: RaceActivityAttributes.ContentState
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("STATION")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            Text("\(state.currentStationIndex) of \(state.totalStations)")
                .font(.callout.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(state.currentStationName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func expandedTrailing(
        state: RaceActivityAttributes.ContentState
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(phaseLabel(for: state.phase))
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(islandTimerColor(for: state.phase))

            switch state.phase {
            case .running:
                Text(state.timerStart, style: .timer)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            case .paused, .finished:
                Text(formatDuration(state.frozenElapsed ?? 0))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            case .inRoxzone:
                if let roxStart = state.roxzoneStart {
                    Text(roxStart, style: .timer)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(islandTimerColor(for: .inRoxzone))
                } else {
                    Text("·")
                }
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(
        state: RaceActivityAttributes.ContentState,
        attributes: RaceActivityAttributes
    ) -> some View {
        HStack {
            Text(attributes.raceName.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            // Progress bar — proportional segment count, gives
            // an at-a-glance sense of how much race is left.
            ProgressView(
                value: Double(state.currentStationIndex),
                total: Double(state.totalStations)
            )
            .progressViewStyle(.linear)
            .tint(Color.accent)
            .frame(width: 100)
        }
    }

    // MARK: - Helpers

    private func phaseLabel(for phase: RaceActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .running:    return "ELAPSED"
        case .paused:     return "PAUSED"
        case .inRoxzone:  return "ROXZONE"
        case .finished:   return "FINISHED"
        }
    }

    private func phaseIcon(for phase: RaceActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .running:    return "flag.checkered"
        case .paused:     return "pause.fill"
        case .inRoxzone:  return "arrow.right.circle"
        case .finished:   return "flag.checkered.2.crossed"
        }
    }

    private func islandTimerColor(
        for phase: RaceActivityAttributes.ContentState.Phase
    ) -> Color {
        switch phase {
        case .running:    return Color.accent
        case .paused:     return Color.warning
        case .inRoxzone:  return Color.warning
        case .finished:   return Color.success
        }
    }

    // Format MM:SS / H:MM:SS for paused / finished snapshots.
    // (Live phases use Text(_:style:) instead.)
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // Map a full station display name to a 3-5 char on-brand
    // abbreviation for the Dynamic Island compact view. The
    // 8 unique HYROX disciplines each get a recognizable token
    // — anything else (custom workouts, future stations) falls
    // back to the first 4 characters uppercased so the widget
    // still renders SOMETHING readable.
    //
    // Defined here on the Widget side rather than as a property
    // on the engine's Station enum because abbreviation rules
    // are a presentation concern of the Live Activity, not a
    // domain concern of the race itself. Keeps RaceActivityAttributes
    // free of display logic and lets the abbreviations evolve
    // without touching the iOS app target.
    private func stationAbbreviation(for stationName: String) -> String {
        let lower = stationName.lowercased()
        if lower.contains("run")             { return "RUN" }
        if lower.contains("sled push")       { return "PUSH" }
        if lower.contains("sled pull")       { return "PULL" }
        if lower.contains("burpee")          { return "BURP" }
        if lower.contains("row")             { return "ROW" }
        if lower.contains("farmer")          { return "CARRY" }
        if lower.contains("lunge") || lower.contains("sandbag") { return "BAG" }
        if lower.contains("wall")            { return "WALL" }
        return String(stationName.prefix(4)).uppercased()
    }
}

// MARK: - Lock-screen / notification view

// Renders below the lock screen and inside the notification
// banner. Larger and more layout-flexible than the Dynamic
// Island regions. Hero race timer + station info + optional
// roxzone overlay.
private struct LockScreenView: View {
    let attributes: RaceActivityAttributes
    let state: RaceActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.caption.weight(.heavy))
                Text(attributes.raceName.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.0)
                Spacer()
                if let hr = state.currentHR {
                    hrChip(hr, zone: state.currentHRZone)
                }
                phaseChip
            }
            .foregroundStyle(.white.opacity(0.7))

            // Hero timer block
            HStack(alignment: .firstTextBaseline) {
                heroTimer
                Spacer()
                stationBlock
            }

            // Pace ghost line — same naïve-even-split math the
            // Watch race page uses. Tells the user at a lock-
            // screen glance whether they're ahead, on pace, or
            // behind their target. Hidden when no target was
            // set (paused / finished phases also skip render).
            paceGhost

            // Progress bar across the bottom — segment count
            // visualization. Cosmetic but helps the lock-screen
            // glance read as "X of Y stations done."
            ProgressView(
                value: Double(state.currentStationIndex),
                total: Double(state.totalStations)
            )
            .progressViewStyle(.linear)
            .tint(Color.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // Pace ghost — green / textSecondary / coral label based on
    // how far ahead or behind the target finish pace the
    // athlete is right now. Hidden during paused / finished /
    // roxzone phases AND when no target was set. Uses the same
    // naïve-even-split model as the Watch race page so the
    // glance reading is identical across surfaces.
    //
    // Calculation:
    //   • perSegment = targetDuration / totalStations
    //   • expected = completedSegments × perSegment +
    //                activeFraction × perSegment
    //   • delta = expected - elapsed   (positive ⇒ ahead)
    //
    // Active fraction approximates how much of the current
    // segment is "done" by elapsed-since-segment-start over
    // per-segment budget, clamped 0...1. Same caveat as the
    // Watch implementation — workouts and runs share one
    // budget; a finer benchmark-split model lives in §13.1
    // Tier 2.
    @ViewBuilder
    private var paceGhost: some View {
        if state.phase == .running,
           let target = state.targetDuration,
           target > 0,
           state.totalStations > 0 {
            // Wrap the label/tint/delta decision in an IIFE so
            // the @ViewBuilder body sees a single value, not a
            // mutating let-then-if-else chain (which Swift
            // treats as a Void statement and rejects with
            // "Type '()' cannot conform to 'View'"). Same
            // pattern WatchRaceMainPage.paceDelta uses for the
            // same constraint.
            let resolved: (label: String, tint: Color, delta: TimeInterval) = {
                let elapsed = Date().timeIntervalSince(state.timerStart)
                let completed = max(0, state.currentStationIndex - 1)
                let perSegment = target / Double(state.totalStations)
                let segmentElapsed = Date().timeIntervalSince(state.segmentStart)
                let activeFraction = max(0, min(1, segmentElapsed / perSegment))
                let expected = Double(completed) * perSegment + activeFraction * perSegment
                let delta = expected - elapsed
                let absSeconds = Int(abs(delta).rounded())

                if absSeconds <= 5 {
                    return ("on pace", Color.white.opacity(0.65), delta)
                } else if delta > 0 {
                    return ("+\(formatDelta(absSeconds)) ahead", Color.success, delta)
                } else {
                    return ("-\(formatDelta(absSeconds)) behind", Color.accent, delta)
                }
            }()

            HStack(spacing: 4) {
                Image(systemName: resolved.delta > 5
                    ? "chevron.up"
                    : (resolved.delta < -5 ? "chevron.down" : "minus"))
                    .font(.system(size: 9, weight: .heavy))
                Text(resolved.label)
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(resolved.tint)
        }
    }

    // Format a positive integer second count as "M:SS" or "Ss"
    // depending on size. Mirrors the Watch race page's
    // helper so the pace ghost reads identically on both
    // surfaces.
    private func formatDelta(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(secs)s"
    }

    private var phaseChip: some View {
        Text(phaseLabel)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(phaseColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(phaseColor.opacity(0.15))
            )
    }

    // Live heart-rate chip — a small heart glyph + BPM value, plus
    // a Z1...Z5 zone indicator when the iOS side has classified the
    // current HR. Only renders when state.currentHR is non-nil
    // (HealthKit authorized AND a sensor is publishing). The zone
    // tints the heart icon + draws a Z-label suffix so the athlete
    // can pace by zone color at a glance — much faster to read
    // mid-sprint than a raw BPM number.
    //
    // Intentionally restrained — same visual weight as the phase
    // chip beside it, so the header reads "race · HR · phase" left
    // to right without any single chip dominating.
    @ViewBuilder
    private func hrChip(_ bpm: Int, zone: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(hrZoneColor(zone))
            Text("\(bpm)")
                .font(.system(size: 9, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            if let zone, let label = hrZoneHyroxLabel(zone) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(hrZoneColor(zone))
                    .padding(.leading, 1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }

    // Map the pre-computed HR zone (1...5) to a color. Mirrors the
    // canonical palette used by the in-app HRZonesView so the same
    // zone reads the same color across surfaces. Falls back to
    // muted accent for unknown / nil zone values.
    private func hrZoneColor(_ zone: Int?) -> Color {
        switch zone {
        case 1: return Color(red: 0.36, green: 0.61, blue: 0.84)  // 0x5B9BD5 — calm blue
        case 2: return Color.success                              // green
        case 3: return Color(red: 1.0, green: 0.84, blue: 0.04)   // 0xFFD60A — yellow
        case 4: return Color.warning                              // orange
        case 5: return Color.accent                               // red
        default: return Color.accent                              // fallback
        }
    }

    // Map the pre-computed HR zone (1...5) to its HYROX-coded label.
    // Mirrors HRZone.hyroxLabel on the iOS side; duplicated here
    // because the widget target doesn't include HRZone.swift in its
    // member list. Five short labels chosen to fit the same lock-
    // screen / Dynamic Island space as the previous "Z<n>" tag while
    // reading as coaching guidance instead of training-plan jargon.
    private func hrZoneHyroxLabel(_ zone: Int?) -> String? {
        switch zone {
        case 1: return "Easy"
        case 2: return "Steady"
        case 3: return "Race"
        case 4: return "Hard"
        case 5: return "Redline"
        default: return nil
        }
    }

    @ViewBuilder
    private var heroTimer: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch state.phase {
            case .running:
                Text(state.timerStart, style: .timer)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            case .paused, .finished:
                Text(formatDuration(state.frozenElapsed ?? 0))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            case .inRoxzone:
                if let roxStart = state.roxzoneStart {
                    Text(roxStart, style: .timer)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.warning)
                }
            }
            Text(timerLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var stationBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("STATION")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            Text("\(state.currentStationIndex) / \(state.totalStations)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(state.currentStationName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .running:    return "RACING"
        case .paused:     return "PAUSED"
        case .inRoxzone:  return "ROXZONE"
        case .finished:   return "FINISHED"
        }
    }

    private var timerLabel: String {
        switch state.phase {
        case .running, .paused, .finished:  return "RACE TIME"
        case .inRoxzone:                    return "TRANSITION"
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .running:    return Color.accent
        case .paused:     return Color.warning
        case .inRoxzone:  return Color.warning
        case .finished:   return Color.success
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

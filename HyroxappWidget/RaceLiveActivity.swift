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
                // Compact — right side. The current station's
                // abbreviated name (RUN / PUSH / PULL / WALL etc.)
                // in a phase-colored capsule. Reads more on-brand
                // than a bare number — HYROX athletes know these
                // station names by reputation and the abbreviation
                // signals "this is your current discipline" at a
                // glance. The capsule tint doubles as a state
                // signal — coral while running, amber when
                // paused/in-roxzone, green when finished.
                Text(stationAbbreviation(for: context.state.currentStationName))
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(
                                islandTimerColor(for: context.state.phase)
                                    .opacity(0.30)
                            )
                    )

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
                    hrChip(hr)
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

    // Live heart-rate chip — a small heart glyph + BPM value.
    // Only renders when state.currentHR is non-nil (HealthKit
    // authorized AND a sensor is publishing). Intentionally
    // restrained — same visual weight as the phase chip beside
    // it, so the header reads "race · HR · phase" left to right
    // without any single chip dominating.
    @ViewBuilder
    private func hrChip(_ bpm: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.accent)
            Text("\(bpm)")
                .font(.system(size: 9, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
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

import ActivityKit
import SwiftUI
import WidgetKit

// §12C — Free Run Live Activity widget. Parallel to
// RaceLiveActivity with Free-Run-shaped surfaces:
//
//   1. Lock screen + iOS notification — hero timer, distance,
//      pace, optional HR chip, location-type strap header.
//   2. Dynamic Island expanded — leading = DISTANCE block,
//      trailing = phase + timer, bottom = location + pace.
//   3. Dynamic Island compact + minimal — timer left, HR or
//      distance right (compact); phase icon (minimal).
//
// Tap deep-link via `trakr://freerun` — the iOS app's
// onOpenURL handler routes back into the Free Run tab. Same
// scheme + Notification routing pattern RaceLiveActivity uses.
struct FreeRunLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FreeRunActivityAttributes.self) { context in
            // Lock-screen / notification UI.
            FreeRunLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "trakr://freerun"))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(
                        state: context.state,
                        attributes: context.attributes
                    )
                }
            } compactLeading: {
                // Compact left — race timer. Same Text(_:style:)
                // pattern RaceLiveActivity uses; the system
                // process ticks the digits without burning
                // ActivityKit's update budget.
                compactTimer(state: context.state)
                    .foregroundStyle(phaseTimerColor(for: context.state.phase))

            } compactTrailing: {
                // Compact right — HR pill when publishing,
                // distance text otherwise. Same fallback logic
                // RaceLiveActivity's compact trailing uses, just
                // with distance as the no-HR substitute.
                compactTrailingContent(state: context.state)

            } minimal: {
                Image(systemName: phaseIcon(for: context.state.phase))
                    .foregroundStyle(phaseTimerColor(for: context.state.phase))
            }
        }
    }

    // MARK: - Compact timer

    @ViewBuilder
    private func compactTimer(state: FreeRunActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .running:
            Text(state.timerStart, style: .timer)
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
        case .paused, .finished:
            Text(formatDuration(state.frozenElapsed ?? 0))
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
        }
    }

    // MARK: - Compact trailing

    @ViewBuilder
    private func compactTrailingContent(
        state: FreeRunActivityAttributes.ContentState
    ) -> some View {
        if let hr = state.currentHR {
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
            // Distance fallback — show the running distance in
            // the user's preferred unit. Tight format (no
            // decimals for >10 units, one decimal otherwise)
            // to fit the compact trailing's narrow slot.
            Text(compactDistanceLabel(state: state))
                .font(.caption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(phaseTimerColor(for: state.phase).opacity(0.30))
                )
        }
    }

    private func compactDistanceLabel(
        state: FreeRunActivityAttributes.ContentState
    ) -> String {
        let units = state.distanceMeters / max(state.splitUnitMetres, 1)
        if units >= 10 {
            return "\(Int(units))\(state.splitUnitLabel)"
        }
        return String(format: "%.1f%@", units, state.splitUnitLabel)
    }

    // MARK: - Expanded regions

    @ViewBuilder
    private func expandedLeading(
        state: FreeRunActivityAttributes.ContentState
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DISTANCE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatDistance(state: state))
                    .font(.callout.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(state.splitUnitLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let pace = state.avgPaceSecondsPerUnit {
                Text("\(formatPace(pace))/\(state.splitUnitLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func expandedTrailing(
        state: FreeRunActivityAttributes.ContentState
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(phaseLabel(for: state.phase))
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(phaseTimerColor(for: state.phase))

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
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(
        state: FreeRunActivityAttributes.ContentState,
        attributes: FreeRunActivityAttributes
    ) -> some View {
        HStack {
            Text(attributes.locationLabel.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            if let hr = state.currentHR {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(hrZoneColor(state.currentHRZone))
                    Text("\(hr) bpm")
                        .font(.system(size: 10, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    // MARK: - Helpers

    private func phaseLabel(for phase: FreeRunActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .running:  return "ELAPSED"
        case .paused:   return "PAUSED"
        case .finished: return "FINISHED"
        }
    }

    private func phaseIcon(for phase: FreeRunActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .running:  return "figure.run"
        case .paused:   return "pause.fill"
        case .finished: return "checkmark.circle"
        }
    }

    private func phaseTimerColor(
        for phase: FreeRunActivityAttributes.ContentState.Phase
    ) -> Color {
        switch phase {
        case .running:  return Color.accent
        case .paused:   return Color.warning
        case .finished: return Color.success
        }
    }

    // HR zone palette — same canonical mapping the race
    // activity uses. Duplicated locally for the same reason
    // (widget target doesn't include HRZone.swift).
    private func hrZoneColor(_ zone: Int?) -> Color {
        switch zone {
        case 1: return Color(red: 0.36, green: 0.61, blue: 0.84)  // 0x5B9BD5 — calm blue
        case 2: return Color.success                              // green
        case 3: return Color(red: 1.0, green: 0.84, blue: 0.04)   // 0xFFD60A — yellow
        case 4: return Color.warning                              // orange
        case 5: return Color(red: 1.0, green: 0.23, blue: 0.19)   // §31 — Z5 redline stays iOS systemRed (#FF3B30), NOT brand Volt lime
        default: return Color(red: 1.0, green: 0.23, blue: 0.19)  // §31 — fallback to redline, not brand
        }
    }

    private func compactHRTint(zone: Int?) -> Color {
        hrZoneColor(zone)
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

    private func formatDistance(state: FreeRunActivityAttributes.ContentState) -> String {
        let units = state.distanceMeters / max(state.splitUnitMetres, 1)
        return String(format: "%.2f", units)
    }

    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Lock-screen view

private struct FreeRunLockScreenView: View {
    let attributes: FreeRunActivityAttributes
    let state: FreeRunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.caption.weight(.heavy))
                Text(attributes.locationLabel.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.0)
                Spacer()
                if let hr = state.currentHR {
                    hrChip(bpm: hr, zone: state.currentHRZone)
                }
                phaseChip
            }
            .foregroundStyle(.white.opacity(0.7))

            // Hero block — big elapsed timer on the left,
            // distance + pace on the right. Mirrors race
            // activity's hero treatment with Free-Run-shaped
            // trailing stack.
            HStack(alignment: .firstTextBaseline) {
                heroTimer
                Spacer()
                distanceBlock
            }
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

    @ViewBuilder
    private func hrChip(bpm: Int, zone: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(hrZoneColor(zone))
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
            }
            Text("ELAPSED")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var distanceBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("DISTANCE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatDistance())
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(state.splitUnitLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let pace = state.avgPaceSecondsPerUnit {
                Text("\(formatPace(pace))/\(state.splitUnitLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .running:  return "RUNNING"
        case .paused:   return "PAUSED"
        case .finished: return "FINISHED"
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .running:  return Color.accent
        case .paused:   return Color.warning
        case .finished: return Color.success
        }
    }

    private func hrZoneColor(_ zone: Int?) -> Color {
        switch zone {
        case 1: return Color(red: 0.36, green: 0.61, blue: 0.84)  // 0x5B9BD5 — calm blue
        case 2: return Color.success                              // green
        case 3: return Color(red: 1.0, green: 0.84, blue: 0.04)   // 0xFFD60A — yellow
        case 4: return Color.warning                              // orange
        case 5: return Color(red: 1.0, green: 0.23, blue: 0.19)   // §31 — Z5 redline stays iOS systemRed (#FF3B30), NOT brand Volt lime
        default: return Color(red: 1.0, green: 0.23, blue: 0.19)  // §31 — fallback to redline, not brand
        }
    }

    private func formatDistance() -> String {
        let units = state.distanceMeters / max(state.splitUnitMetres, 1)
        return String(format: "%.2f", units)
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

    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

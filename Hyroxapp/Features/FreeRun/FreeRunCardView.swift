import SwiftUI

#if canImport(UIKit)

// History feed card for a Free Run. Mirrors RaceCardView's anatomy
// (header strap → hero → supporting stats → footer) but with the
// hero showing total DISTANCE rather than finish time, since
// distance is the metric a free run is judged by.
//
// Same press-feedback button style + scroll-appear transition the
// History list applies to RaceCardView, so the two card types feel
// homogeneous in the same scroll.
struct FreeRunCardView: View {

    let run: FreeRun

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            heroDistance

            supportingStats

            if !run.notes.isEmpty {
                Text(run.notes)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }

            footer
        }
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.divider, lineWidth: 0.5)
        )
    }

    // Header strap — Free Run badge + relative time + privacy icon.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "figure.run")
                    .font(.caption.weight(.heavy))
                Text("FREE RUN")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.accent.opacity(0.14))
            )

            Text("·")
                .foregroundStyle(Color.textTertiary)

            Text(relativeTimeString)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            Spacer()

            // Indoor / outdoor pill — small label letting the user
            // distinguish at-a-glance which surface this run was
            // logged on.
            HStack(spacing: 3) {
                Image(systemName: run.locationType.iconName)
                    .font(.caption2.weight(.bold))
                Text(run.locationType.displayName)
                    .font(.caption2.weight(.heavy))
                    .tracking(0.4)
            }
            .foregroundStyle(Color.textTertiary)

            if run.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // Hero — total distance in chosen unit. Largest type weight on
    // the card.
    private var heroDistance: some View {
        let units = run.distanceMetres / run.splitUnit.metresPerUnit
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(format: "%.2f", units))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(run.splitUnit.shortLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // Three-up grid: total time, average pace, average HR.
    private var supportingStats: some View {
        HStack(spacing: 8) {
            statTile(label: "TIME", value: timeString)
            statTile(label: "PACE", value: paceString)
            statTile(label: "AVG HR", value: hrString)
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceElevated)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Derived

    private var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: run.startedAt, relativeTo: Date())
    }

    private var timeString: String {
        guard let total = run.totalDuration else { return "—" }
        return RaceStats.format(total)
    }

    private var paceString: String {
        guard let total = run.totalDuration,
              run.distanceMetres > 0,
              total > 0 else { return "—" }
        let units = run.distanceMetres / run.splitUnit.metresPerUnit
        let secondsPerUnit = total / units
        let mins = Int(secondsPerUnit) / 60
        let secs = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var hrString: String {
        guard let avg = run.heartRateAvgBPM else { return "—" }
        return "\(Int(avg.rounded()))"
    }
}

#endif

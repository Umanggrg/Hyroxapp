import SwiftUI

// Post-race screen: total time hero, all 16 splits, a free-form notes
// field for "how did this feel?", and a Done button that returns the VM
// to its resting state (the race itself is already persisted and will
// appear in History).
//
// Notes are bound directly to the active `Race` via `@Bindable` so edits
// persist without a Save button — SwiftData autosaves on model dealloc
// and debounces context writes. The same binding is re-used on
// `RaceDetailView` so athletes can reflect and edit after the fact too.
struct RaceSummaryView: View {
    let viewModel: RaceViewModel

    var body: some View {
        // `VStack + ScrollView` layout: scrollable content up top, Done
        // button pinned at the bottom so it's always reachable regardless
        // of how tall the notes grow.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer().frame(height: 12)

                    Text("Race Complete")
                        .capsLabelStyle()
                        .foregroundStyle(Color.success)

                    Text(RaceStats.format(viewModel.finalTime))
                        .font(.raceTimer)
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)

                    Text("Total time")
                        .font(.metadata)
                        .foregroundStyle(Color.textSecondary)

                    // Target outcome — only shown if the athlete set a
                    // goal. "Goal met" + green delta when beaten,
                    // warning delta when missed. Centralized in
                    // TargetOutcomeView so RaceDetailView uses the
                    // same format when reviewing past races.
                    if let race = viewModel.activeRace, let target = race.targetDuration {
                        TargetOutcomeView(
                            targetDuration: target,
                            actualDuration: viewModel.finalTime
                        )
                        .padding(.top, 4)
                    }

                    splitsCard
                        .padding(.top, 16)

                    // Notes live right under splits so the athlete's
                    // thought ("how did that feel?") is adjacent to the
                    // data they're reflecting on. Only rendered when
                    // there's an active race — defensive, shouldn't
                    // happen in practice since summary only shows when
                    // a race has finished.
                    if let race = viewModel.activeRace {
                        NotesSection(race: race)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 2)
            }

            Button(action: viewModel.finishSession) {
                Text("Done")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(Color.surfaceElevated)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            .padding(.vertical, 16)
        }
    }

    private var splitsCard: some View {
        VStack(spacing: 0) {
            // id: \.offset (not \.element.id) so custom workouts with
            // repeated stations (e.g. 3× Sled Push) render distinct rows.
            // Station.rawValue isn't unique across an array that allows
            // duplicates; position always is.
            ForEach(Array(viewModel.splits.enumerated()), id: \.offset) { index, split in
                splitRow(for: split)
                if index < viewModel.splits.count - 1 {
                    Divider().background(Color.divider)
                }
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func splitRow(for split: Split) -> some View {
        HStack {
            Text(split.station.displayName)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RaceStats.format(split.duration))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                // HR subtitle appears only when HealthKit had samples
                // in the segment window. Three shapes:
                //   both avg + max  →  "168 / 184 bpm"
                //   only avg        →  "168 bpm"
                //   neither         →  row has just the time, no subtitle
                if let hrText = Self.heartRateSubtitle(for: split) {
                    Text(hrText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.accentDim)
                }
            }
        }
        .padding(.vertical, 10)
    }

    // Shared formatting between summary and detail views. Centralizing
    // the choice of "show avg / max / both" in one place keeps the two
    // surfaces consistent if the format changes (e.g. adding "(184 peak)"
    // phrasing later).
    static func heartRateSubtitle(for split: Split) -> String? {
        switch (split.heartRateAvgBPM, split.heartRateMaxBPM) {
        case (let avg?, let max?):
            return "\(Int(avg.rounded())) / \(Int(max.rounded())) bpm"
        case (let avg?, nil):
            return "\(Int(avg.rounded())) bpm"
        case (nil, let max?):
            // Edge case: max present but avg missing shouldn't happen
            // from a healthy `HKStatisticsQuery`, but handle it just in
            // case — labeled explicitly so it doesn't look like avg.
            return "\(Int(max.rounded())) bpm peak"
        case (nil, nil):
            return nil
        }
    }
}

// MARK: - Target outcome

// Post-race readout comparing actual finish time against the goal the
// athlete set at start. "Goal met · 1:15 ahead" (success green) or
// "Over target · 5:23 slower" (warning). Lives alongside the summary
// hero time and is reused on RaceDetailView for the same display on
// historical races.
//
// Exposed as a top-level struct (not private) so RaceDetailView can
// import it without duplicating format logic.
struct TargetOutcomeView: View {
    let targetDuration: TimeInterval
    let actualDuration: TimeInterval

    var body: some View {
        let delta = actualDuration - targetDuration
        let isMet = delta <= 0
        let absDelta = Swift.abs(delta)

        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMet ? "Goal met" : "Over target")
                    .font(.caption.weight(.semibold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                // Qualifier reads "1:15 ahead" when met, "5:23 slower"
                // when missed — describes *how* the actual differed
                // from the goal in plain language.
                Text("Target \(RaceStats.format(targetDuration)) · \(RaceStats.format(absDelta)) \(isMet ? "ahead" : "slower")")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isMet ? Color.success : Color.warning)
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}

// MARK: - Notes section

// Extracted into its own view so `@Bindable var race` has a stable
// declaration site — `@Bindable` can't be declared inline inside an
// if-let branch of the parent view's body.
//
// Reused as-is on `RaceDetailView` (shared component in intent;
// lives here alongside its primary caller until it earns promotion
// to Shared/Components/).
struct NotesSection: View {
    @Bindable var race: Race

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            // `axis: .vertical` with `lineLimit(3...8)` gives a TextField
            // that grows as the user types up to 8 visible lines before
            // internally scrolling. Matches Apple's standard notes field
            // look (Reminders, Notes app inline notes).
            TextField(
                "How did this feel?",
                text: $race.notes,
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }
}

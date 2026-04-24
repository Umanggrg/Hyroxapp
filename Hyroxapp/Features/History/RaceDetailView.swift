import SwiftUI
import SwiftData

// Full detail screen for a single race: hero total time, all 16 splits,
// heart rate + fatigue charts when enough data exists, and the athlete's
// free-form notes (editable in place). Pushed from `HistoryView` via
// NavigationStack.
//
// `@Bindable` on the Race lets the `NotesSection`'s TextField write
// directly back to the SwiftData-backed model — no save button needed,
// context autosave handles persistence. Reuses the same NotesSection
// used on RaceSummaryView so the edit UX is identical in both places.
//
// Also `@Query`s every finished race so per-split rows can answer
// "was this a PB at the time?" / "how much faster/slower was this
// than my prior best for this station?" — feedback the athlete cares
// about every time they look at a recent race.
struct RaceDetailView: View {
    @Bindable var race: Race

    // All finished races in the store — used to compute per-station
    // PB status and delta-from-prior-best for every split in THIS
    // race. Filtered by endedAt so in-progress rows (resumable state)
    // don't skew the comparisons. Read-only; we never mutate this list.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .forward)]
    ) private var allFinishedRaces: [Race]

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    // Target outcome readout — shown only when this race
                    // was started with a finish-time goal. Uses the
                    // shared TargetOutcomeView so the format matches
                    // what RaceSummaryView shows immediately post-race.
                    if let target = race.targetDuration,
                       let actual = race.totalDuration {
                        TargetOutcomeView(
                            targetDuration: target,
                            actualDuration: actual
                        )
                    }
                    splitsCard
                    // Only render the HR chart when at least one split
                    // has captured HR data — old pre-HealthKit races,
                    // or races done without a Watch, have nothing to
                    // chart and the empty-bar version would look broken.
                    if HeartRateChartView.hasAnyHeartRateData(in: race.splits) {
                        heartRateSection
                    }
                    // Run fatigue needs 2+ runs to render a meaningful
                    // trend. On a complete race this is always true
                    // (8 runs); on a partially-completed abandoned race
                    // we gate for safety.
                    if RunFatigueChartView.hasFatigueData(in: race.splits) {
                        runFatigueSection
                    }
                    NotesSection(race: race)
                }
                .padding(Layout.screenMargin)
            }
        }
        .navigationTitle(race.startedAt.formatted(date: .abbreviated, time: .shortened))
        .hyroxDarkNavigationBar(inline: true)
    }

    private var heroCard: some View {
        VStack(spacing: 6) {
            Text(RaceStats.totalTime(race))
                .font(.raceTimer)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text("Total Time")
                .capsLabelStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Heart rate section shown below splits when HR data exists for
    // this race. Caps-label header matches the Splits section so the
    // two sit visually as peers.
    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate").capsLabelStyle()
                .padding(.horizontal, 4)

            HeartRateChartView(splits: race.splits)
        }
    }

    // Run fatigue line chart — shows the 8 (or however many) 1km-run
    // split durations over the course of the race so the athlete can
    // see at a glance whether later runs slowed down relative to
    // earlier ones.
    private var runFatigueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run Fatigue").capsLabelStyle()
                .padding(.horizontal, 4)

            RunFatigueChartView(splits: race.splits)
        }
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Splits").capsLabelStyle()
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // id: \.offset supports custom workouts with repeated
                // stations — see comment in RaceSummaryView.
                ForEach(Array(race.splits.enumerated()), id: \.offset) { index, split in
                    splitRow(index: index + 1, split: split)
                    if index < race.splits.count - 1 {
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
    }

    private func splitRow(index: Int, split: Split) -> some View {
        // Compute per-split PB status once for this row. `wasPBSplit`
        // returns true on the very first completion of a station
        // (nothing to beat = implicit PB); `deltaFromPriorBest` returns
        // nil for that case so we don't render a nonsensical "±0:00".
        let isPB = RaceStats.wasPBSplit(split, in: race, among: allFinishedRaces)
        let delta = RaceStats.deltaFromPriorBest(for: split, in: race, among: allFinishedRaces)

        return HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24, alignment: .leading)

            Text(split.station.displayName)
                .font(.body)
                .foregroundStyle(Color.textPrimary)

            // PB badge — shown only when this split actually broke the
            // prior best (including "first time ever"). Small, inline,
            // so it doesn't push the time column around.
            if isPB {
                pbBadge
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(RaceStats.format(split.duration))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                // HR subtitle format is centralized on RaceSummaryView
                // so both surfaces stay in sync. Returns nil when no
                // HR data is available; UI omits the line in that case.
                if let hrText = RaceSummaryView.heartRateSubtitle(for: split) {
                    Text(hrText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.accentDim)
                }
                // Delta vs prior best. Non-PB splits get a warning-
                // colored "+X:XX slower" readout; PB splits get a
                // success-colored "-X:XX faster" readout (quantifying
                // by how much they broke the record). First-time
                // stations show nothing — no prior data to delta from.
                if let delta, let deltaText = Self.deltaLabel(for: delta) {
                    Text(deltaText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(delta < 0 ? Color.success : Color.warning)
                }
            }
        }
        .padding(.vertical, 10)
    }

    // Tight inline badge matching the style of the New-PB trophy on
    // RaceCardView. Inline not standalone so it flows in the row.
    private var pbBadge: some View {
        Text("PB")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.success.opacity(0.18))
            )
            .foregroundStyle(Color.success)
    }

    // Format a signed TimeInterval delta as "-0:04" (faster) or
    // "+0:12" (slower). Returns nil when the delta is below a floor
    // of ~0.5s so the UI doesn't clutter with meaningless ±0:00 badges
    // on floating-point rounding noise.
    private static func deltaLabel(for delta: TimeInterval) -> String? {
        let abs = Swift.abs(delta)
        guard abs >= 0.5 else { return nil }
        let sign = delta < 0 ? "-" : "+"
        return "\(sign)\(RaceStats.format(abs))"
    }
}

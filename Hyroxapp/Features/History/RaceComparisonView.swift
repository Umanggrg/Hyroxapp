import SwiftUI
import SwiftData

// Side-by-side comparison of two races — Strava's "Compare" feature
// for HYROX. Athletes pick a "Race A" and a "Race B" from their
// finished history and see, at a glance:
//
//   • total time delta (which was faster, by how much)
//   • per-station deltas for stations both races share — green
//     when faster, warning orange when slower
//   • headline aggregates: avg HR, total calories
//
// Custom workouts complicate the per-station comparison: race A
// might have done 3× Sled Push, race B only 1. We handle that
// pragmatically — for each canonical station type, compare the
// FIRST occurrence of that station in each race. This works
// perfectly for full HYROX races (one of each station) and reads
// sensibly for mixed sequences ("how did your first sled push
// compare to your first sled push last time?").
//
// Hidden if fewer than 2 finished races exist — handled by the
// parent (HistoryView) so the entry button isn't even shown.
//
// Guarded `#if !os(watchOS)` because Race-dependent helpers are
// iOS-only.
#if !os(watchOS)
struct RaceComparisonView: View {

    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var allFinishedRaces: [Race]

    // Local UserProfile drives the effort-score row's max HR
    // value. Same singleton-via-Query pattern used elsewhere on
    // iOS — bootstrap guarantees exactly one row.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Selected race IDs — drives the picker pills + the diff view.
    // Persistent IDs work as @State because they're Hashable and
    // SwiftData round-trips them losslessly.
    @State private var raceAID: PersistentIdentifier?
    @State private var raceBID: PersistentIdentifier?

    // Sheet state for the picker UI (one per side).
    @State private var pickingSide: Side?

    enum Side: Identifiable {
        case a
        case b
        var id: Int { self == .a ? 0 : 1 }
    }

    // Resolved races from the IDs. Defaults to the most recent two
    // finished races on first appearance — saves the athlete from
    // having to pick anything to see something useful.
    private var raceA: Race? {
        guard let id = raceAID else { return nil }
        return allFinishedRaces.first { $0.persistentModelID == id }
    }

    private var raceB: Race? {
        guard let id = raceBID else { return nil }
        return allFinishedRaces.first { $0.persistentModelID == id }
    }

    var body: some View {
        ZStack {
            HeroBackdrop(.calm)

            ScrollView {
                VStack(spacing: 22) {
                    pickerRow.applyScrollAppearTransition()

                    if let a = raceA, let b = raceB {
                        comparisonHero(a: a, b: b).applyScrollAppearTransition()
                        aggregatesCard(a: a, b: b).applyScrollAppearTransition()
                        splitsCompareCard(a: a, b: b).applyScrollAppearTransition()
                    } else {
                        emptyState.applyScrollAppearTransition()
                    }
                }
                .padding(Layout.screenMargin)
            }
        }
        .navigationTitle("Compare")
        .hyroxDarkNavigationBar(inline: true)
        .onAppear(perform: seedDefaultsIfNeeded)
        .sheet(item: $pickingSide) { side in
            RaceComparisonPickerSheet(
                races: allFinishedRaces,
                excluding: side == .a ? raceBID : raceAID,
                onSelect: { id in
                    if side == .a { raceAID = id } else { raceBID = id }
                    pickingSide = nil
                }
            )
        }
    }

    // Default the two pickers to the two most recent finished races
    // so the user lands on a populated comparison without setup.
    // Idempotent — bails if either side is already set (e.g. user
    // navigates away and comes back).
    private func seedDefaultsIfNeeded() {
        if raceAID == nil, allFinishedRaces.indices.contains(0) {
            raceAID = allFinishedRaces[0].persistentModelID
        }
        if raceBID == nil, allFinishedRaces.indices.contains(1) {
            raceBID = allFinishedRaces[1].persistentModelID
        }
    }

    // MARK: - Picker row (two race pills side by side)

    private var pickerRow: some View {
        HStack(spacing: 12) {
            picker(label: "RACE A", race: raceA, side: .a)
            picker(label: "RACE B", race: raceB, side: .b)
        }
    }

    private func picker(label: String, race: Race?, side: Side) -> some View {
        Button {
            pickingSide = side
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)

                if let race {
                    Text(race.name.isEmpty
                         ? race.startedAt.formatted(date: .abbreviated, time: .omitted)
                         : race.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(RaceStats.totalTime(race))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Tap to choose")
                        .font(.body)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comparison hero (v2 redesign)

    // Hero comparison treatment — answers the headline question
    // "did I get faster?" prominently with a single big delta
    // number. Layout:
    //   • Caps wordmark of the faster race
    //   • 64pt heavy delta number ("0:32" or "1:14") in the
    //     winner's accent (success green or warning orange)
    //   • Both races' totals as smaller stacked columns underneath
    //
    // Tie case (delta == 0) — nobody's faster, render the time
    // in textPrimary with a "tied" caption.
    private func comparisonHero(a: Race, b: Race) -> some View {
        let aTotal = a.totalDuration ?? 0
        let bTotal = b.totalDuration ?? 0
        let delta = aTotal - bTotal
        let aFaster = aTotal < bTotal
        let isTie = (delta == 0)
        let winnerColor: Color = isTie ? Color.textPrimary
            : (aFaster ? Color.success : Color.warning)
        let winnerLabel: String = isTie ? "TIED"
            : (aFaster ? "RACE A IS FASTER" : "RACE B IS FASTER")

        return VStack(spacing: 8) {
            Text(winnerLabel)
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(winnerColor)

            Text(isTie ? "0:00" : RaceStats.format(abs(delta)))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(winnerColor)
                .shadow(color: winnerColor.opacity(0.3), radius: 16, x: 0, y: 0)

            if !isTie {
                Text(aFaster ? "FASTER THAN B" : "FASTER THAN A")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 32) {
                totalTimeColumn(label: "A", time: aTotal, isFaster: aFaster && !isTie)
                Rectangle()
                    .fill(Color.divider)
                    .frame(width: 1, height: 36)
                totalTimeColumn(label: "B", time: bTotal, isFaster: !aFaster && !isTie)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, Layout.cardPadding)
        // Token-aligned to `Layout.cardCornerRadius` so future
        // radius tuning sweeps this surface too.
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .stroke(winnerColor.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func totalTimeColumn(label: String, time: TimeInterval, isFaster: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(isFaster ? Color.success : Color.textTertiary)
            Text(RaceStats.format(time))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isFaster ? Color.success : Color.textPrimary)
        }
    }

    // (Old centered `deltaPill` removed; the v2 redesign's
    // `comparisonHero` shows the delta as the headline 64pt
    // number above the per-race stack, replacing the small
    // pill treatment.)

    // MARK: - Aggregates row (avg HR, calories)

    private func aggregatesCard(a: Race, b: Race) -> some View {
        VStack(spacing: 0) {
            aggregateRow(
                label: "Avg HR",
                aValue: avgHRString(a),
                bValue: avgHRString(b)
            )
            Divider().background(Color.divider)
            aggregateRow(
                label: "Calories",
                aValue: caloriesString(a),
                bValue: caloriesString(b)
            )
            // Effort row — surfaces the HR-time integration alongside
            // the raw HR and calorie aggregates. When neither race
            // has HR data, both sides render '—' and the row is
            // still useful as a visual anchor (presence of the
            // metric, absence of data).
            Divider().background(Color.divider)
            aggregateRow(
                label: "Effort",
                aValue: effortString(a),
                bValue: effortString(b)
            )
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Effort score formatted for the comparison row. Reads the
    // local user's max HR from their UserProfile so the score
    // matches what the per-race summary line shows. Returns "—"
    // when the race has no HR data to integrate.
    private func effortString(_ race: Race) -> String {
        let maxHR = profiles.first?.maxHeartRate ?? 190
        guard let score = RaceStats.effortScore(for: race, maxHR: maxHR) else {
            return "—"
        }
        return "\(Int(score.rounded()))"
    }

    private func aggregateRow(label: String, aValue: String, bValue: String) -> some View {
        HStack {
            Text(aValue)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(label)
                .capsLabelStyle()

            Text(bValue)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private func avgHRString(_ race: Race) -> String {
        let hrs = race.splits.compactMap(\.heartRateAvgBPM)
        guard !hrs.isEmpty else { return "—" }
        let avg = hrs.reduce(0, +) / Double(hrs.count)
        return "\(Int(avg.rounded())) bpm"
    }

    private func caloriesString(_ race: Race) -> String {
        guard let kcal = RaceStats.totalActiveCalories(race) else { return "—" }
        return "\(Int(kcal.rounded())) kcal"
    }

    // MARK: - Splits comparison card

    // Per-station table: A's time, station name centered, B's time.
    // Faster side is green-highlighted on each row; the slower side
    // gets a textSecondary tone. Stations not present in both races
    // are skipped with a quiet "—" placeholder.
    private func splitsCompareCard(a: Race, b: Race) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Splits").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let stations = Station.canonicalPickerOptions
                ForEach(Array(stations.enumerated()), id: \.offset) { index, station in
                    splitRow(
                        station: station,
                        aSplit: firstSplit(matching: station, in: a),
                        bSplit: firstSplit(matching: station, in: b)
                    )
                    if index < stations.count - 1 {
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

    // Pull the first split for the given canonical station type.
    // For run cases that's the first 1km run in the race; for
    // workout stations it's that one station's split.
    private func firstSplit(matching station: Station, in race: Race) -> Split? {
        race.splits.first { split in
            station.kind == .run
                ? split.station.kind == .run
                : split.station == station
        }
    }

    private func splitRow(station: Station, aSplit: Split?, bSplit: Split?) -> some View {
        let aDur = aSplit?.duration
        let bDur = bSplit?.duration

        let aFaster: Bool? = {
            guard let a = aDur, let b = bDur else { return nil }
            if a == b { return nil }
            return a < b
        }()

        return HStack(spacing: 8) {
            cell(value: aDur, isFaster: aFaster == true, alignment: .leading)
            Text(station.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            cell(value: bDur, isFaster: aFaster == false, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private func cell(value: TimeInterval?, isFaster: Bool, alignment: HorizontalAlignment) -> some View {
        let frameAlignment: Alignment = (alignment == .leading) ? .leading : .trailing
        let textAlignment: TextAlignment = (alignment == .leading) ? .leading : .trailing

        return Group {
            if let value {
                Text(RaceStats.format(value))
                    .font(.body.weight(isFaster ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isFaster ? Color.success : Color.textPrimary)
                    .multilineTextAlignment(textAlignment)
            } else {
                Text("—")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 60)
            Text("Pick two races to compare")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Tap a slot above to choose a race.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// Sheet for picking a single race from the finished list. Excludes
// the race already selected on the OTHER side so the two slots
// can't reference the same race.
private struct RaceComparisonPickerSheet: View {
    let races: [Race]
    let excluding: PersistentIdentifier?
    let onSelect: (PersistentIdentifier) -> Void

    @Environment(\.dismiss) private var dismiss

    private var visibleRaces: [Race] {
        races.filter { $0.persistentModelID != excluding }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleRaces) { race in
                    Button {
                        onSelect(race.persistentModelID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(race.name.isEmpty
                                     ? race.startedAt.formatted(date: .abbreviated, time: .shortened)
                                     : race.name)
                                    .foregroundStyle(Color.textPrimary)
                                    .font(.body.weight(.semibold))
                                if !race.name.isEmpty {
                                    Text(race.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            Spacer()
                            Text(RaceStats.totalTime(race))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accent)
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.background)
            .navigationTitle("Pick a race")
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
                #endif
            }
        }
    }
}
#endif

import SwiftUI

// §55 — Station-level personal-record callout.
//
// Sits on RaceSummaryView (and reused on RaceDetailView)
// right after the race-wide rollups. Lists every station
// whose duration on THIS race beat the athlete's prior
// best for that station type. Each row shows the station
// name, the new best duration, and the signed delta vs the
// prior best.
//
// The race-level "New Personal Best" ribbon on the finish
// hero already handles the WHOLE-RACE PB case (rare — once
// every 10-20 races). Station-level PRs are more common —
// you'll often beat at least one prior best per race. This
// section is the place where those quieter wins surface so
// the athlete sees them without scrolling into the History
// detail. Big psychological lift on a race where the
// overall time was off pace but a station-level breakthrough
// happened.
//
// Self-hides when no station-level PRs were set, so it never
// renders an empty "no PRs" placeholder.
//
// Reuses existing helpers (RaceStats.wasPBSplit,
// RaceStats.deltaFromPriorBest, RaceStats.bestDuration) so
// the math matches what the Station Detail view's PB pill
// computes — no risk of drift between the two surfaces.
struct StationPRCalloutSection: View {

    let race: Race
    let allFinishedRaces: [Race]

    // MARK: - Body

    var body: some View {
        let prs = personalRecords
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                header(count: prs.count)
                ForEach(prs, id: \.station) { entry in
                    row(entry: entry)
                }
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color(hex: 0xFFD60A).opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color(hex: 0xFFD60A).opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Header

    private func header(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rosette")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color(hex: 0xFFD60A))
            Text("\(count) NEW STATION PR\(count == 1 ? "" : "S")")
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color(hex: 0xFFD60A))
        }
    }

    // MARK: - Row

    private func row(entry: PREntry) -> some View {
        HStack(spacing: 10) {
            // Station glyph in a small tinted disc — same
            // visual register as the existing station-name
            // rows on the splits table.
            ZStack {
                Circle()
                    .fill(Color(hex: 0xFFD60A).opacity(0.20))
                    .frame(width: 28, height: 28)
                Image(systemName: entry.station.glyph)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color(hex: 0xFFD60A))
            }

            // Station name on top, new best time + delta below.
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.station.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 6) {
                    Text(RaceStats.format(entry.newBest))
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                    if let delta = entry.signedDelta {
                        // Negative delta = faster than prior best
                        // — that's why it's a PR. Render with the
                        // "↓" arrow + the absolute magnitude in
                        // the success tint.
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.caption2.weight(.heavy))
                            Text(RaceStats.format(abs(delta)))
                                .font(.caption2.weight(.heavy))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.success)
                    } else {
                        // First-ever attempt at this station —
                        // implicit PR (no prior to beat). Label
                        // it accordingly so the athlete knows
                        // the bar is freshly set, not just
                        // beaten by an arbitrary amount.
                        Text("FIRST ATTEMPT")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.4)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Derivation

    /// Per-station PR entries for this race. Order matches the
    /// HYROX race sequence (skiErg → sledPush → sledPull → ...
    /// → wallBalls) so PRs read in the order the athlete hit
    /// them, not alphabetically.
    private var personalRecords: [PREntry] {
        // Runs all collapse to a single "1km Run" PR
        // semantically (per StationDetailView's `run`
        // collapse). Including each of run1...run8 here
        // would surface up to 8 PR entries for the same
        // achievement — too noisy. Skip individual runs in
        // the per-split scan and append a single "1km Run"
        // PR at the end IF any run beat the prior best.
        let workoutPRs: [PREntry] = race.splits.compactMap { split in
            guard split.station.kind != .run else { return nil }
            guard RaceStats.wasPBSplit(split, in: race, among: allFinishedRaces) else {
                return nil
            }
            let delta = RaceStats.deltaFromPriorBest(
                for: split,
                in: race,
                among: allFinishedRaces
            )
            return PREntry(
                station: split.station,
                newBest: split.duration,
                signedDelta: delta
            )
        }
        if let runEntry = runPREntry() {
            return workoutPRs + [runEntry]
        }
        return workoutPRs
    }

    /// Single "1km Run" PR entry derived from the fastest
    /// run-split in THIS race vs the all-time best run split
    /// in earlier races. Collapses runs 1-8 into one entry so
    /// the section doesn't render the same achievement eight
    /// times.
    private func runPREntry() -> PREntry? {
        let thisRaceRuns = race.splits.filter { $0.station.kind == .run }
        guard let fastestThisRace = thisRaceRuns
            .min(by: { $0.duration < $1.duration }) else {
            return nil
        }
        // Prior best across ALL earlier races' runs.
        let priorRuns = allFinishedRaces
            .filter { $0.createdAt < race.createdAt && $0.isFinished }
            .flatMap(\.splits)
            .filter { $0.station.kind == .run }
            .map(\.duration)
        let priorBest = priorRuns.min()

        // Was this race's fastest run faster than the prior
        // all-time best? If no prior data, treat as PR
        // (first-attempt semantics).
        if let priorBest, fastestThisRace.duration >= priorBest {
            return nil
        }
        let delta: TimeInterval? = priorBest.map { fastestThisRace.duration - $0 }
        return PREntry(
            station: fastestThisRace.station,
            newBest: fastestThisRace.duration,
            signedDelta: delta
        )
    }

    // MARK: - PR entry type

    private struct PREntry: Equatable {
        let station: Station
        let newBest: TimeInterval
        /// Signed seconds vs prior best. Negative = faster
        /// (the typical case — that's why this is a PR).
        /// Nil = first-ever attempt, no prior to compare against.
        let signedDelta: TimeInterval?
    }
}

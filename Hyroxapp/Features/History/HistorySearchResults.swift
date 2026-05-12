import SwiftUI

// Wireframe §04.1 search-results layout. Replaces the standard
// List mode when the athlete has typed something into the search
// bar — shows compact result rows + (when the query matches a
// station name) a station summary card at the bottom with the
// athlete's best / avg / last for that station.
//
// Search semantics:
//   • Race name match — substring, case-insensitive
//   • Station name match — substring, case-insensitive
//     (e.g. "sled pull" matches every race that has a sled-pull
//     split, with the split's time shown as the row's delta)
//
// When a query matches a station name, we treat the matching
// races' SPLIT for that station as the "result" — the row's
// time-label shows the split's duration, with a coral PB / +Xs
// callout vs the athlete's best for that station.
struct HistorySearchResults: View {

    let query: String
    let races: [Race]
    let onRaceTap: (Race) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            resultsCountHeader

            resultRows

            // Station summary card — only rendered when the
            // query maps to a known Station name. Internal @ViewBuilder
            // gates this conditionally so callers don't need to
            // unwrap (you can't `if let` on a non-Optional `some View`).
            stationSummaryCard

            if matchingResults.isEmpty {
                emptyResultsState
            }
        }
    }

    // MARK: - Header

    private var resultsCountHeader: some View {
        let count = matchingResults.count
        return Text("\(count) RESULT\(count == 1 ? "" : "S")")
            .capsLabelStyle()
    }

    // MARK: - Result rows

    @ViewBuilder
    private var resultRows: some View {
        VStack(spacing: 6) {
            ForEach(matchingResults) { match in
                rowButton(for: match)
            }
        }
    }

    private func rowButton(for match: SearchMatch) -> some View {
        Button {
            Haptics.impact(.light)
            onRaceTap(match.race)
        } label: {
            HStack(spacing: 12) {
                dateBadge(for: match)

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.titleLabel)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(match.subtitleLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                if let delta = match.deltaLabel {
                    Text(delta)
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(match.deltaIsRegression ? Color.accent : Color.onPace)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
        .buttonStyle(.pressableCard)
    }

    // 36×36 date badge (slightly smaller than List-mode rows
    // since search-results need more room for the longer station
    // context). Coral when this match is a full HYROX race.
    private func dateBadge(for match: SearchMatch) -> some View {
        let isFullRace = match.race.sequenceRaw == Station.raceSequence.map(\.rawValue)
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        let label = fmt.string(from: match.race.createdAt)

        return Text(label)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(isFullRace ? Color.onAccent : Color.textSecondary)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFullRace ? Color.accent : Color.surfaceElevated)
            )
    }

    // MARK: - Station summary card

    // When the query matches a station name, a summary card shows
    // best / avg / last for that station — wireframe's "YOUR SLED
    // PULL" card.
    @ViewBuilder
    private var stationSummaryCard: some View {
        if let station = matchingStation {
            let splits = races
                .filter { $0.isFinished }
                .flatMap(\.splits)
                .filter { $0.station == station }

            if !splits.isEmpty {
                let durations = splits.map(\.duration)
                let best = durations.min() ?? 0
                let avg = durations.reduce(0, +) / Double(durations.count)
                let last = splits.max { $0.startedAt < $1.startedAt }?.duration ?? 0
                let lastIsRegression = last > avg

                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR \(station.displayName.uppercased())")
                        .capsLabelStyle()

                    HStack(spacing: 14) {
                        stat(label: "BEST", time: best, tint: Color.onPace)
                        stat(label: "AVG", time: avg, tint: Color.textPrimary)
                        stat(label: "LAST", time: last,
                             tint: lastIsRegression ? Color.accent : Color.onPace)
                        Spacer()
                    }
                }
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.surfaceElevated)
                )
            }
        }
    }

    private func stat(label: String, time: TimeInterval, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
            Text(RaceStats.format(time))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    // MARK: - Empty results

    private var emptyResultsState: some View {
        VStack(spacing: 6) {
            Text("No matches for \"\(query)\"")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
            Text("Try a station name or part of a race title.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Match generation

    // The single Station the query maps to, if any. Used to gate
    // the YOUR-STATION summary card AND to compute per-row
    // station-split labels.
    private var matchingStation: Station? {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        return Station.allCases.first { station in
            station.displayName.lowercased().contains(needle)
        }
    }

    // The full set of result rows. Race-name matches always
    // include the race; station matches additionally include
    // races that contain the matching station as a split.
    private var matchingResults: [SearchMatch] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }

        let finished = races.filter { $0.isFinished }

        if let station = matchingStation {
            // Station-flavored matches — pull every race that
            // has a split for the matching station, label the
            // row with the station split context.
            let priorBest = finished
                .flatMap(\.splits)
                .filter { $0.station == station }
                .map(\.duration)
                .min() ?? 0

            return finished.compactMap { race -> SearchMatch? in
                guard let split = race.splits.first(where: { $0.station == station })
                else { return nil }

                let raceTitle = race.name.trimmingCharacters(in: .whitespaces)
                let titleLabel: String
                if raceTitle.isEmpty {
                    titleLabel = "In · HYROX race"
                } else {
                    titleLabel = "In · \(raceTitle)"
                }

                let position = (race.sequenceRaw.firstIndex(of: station.rawValue) ?? 0) + 1
                let subtitleLabel = "Station \(position) · \(RaceStats.format(split.duration))"

                let deltaLabel: String?
                let deltaIsRegression: Bool
                if split.duration == priorBest, priorBest > 0 {
                    deltaLabel = "PB"
                    deltaIsRegression = false
                } else if abs(split.duration - priorBest) < 1 {
                    deltaLabel = "avg"
                    deltaIsRegression = false
                } else if split.duration > priorBest {
                    deltaLabel = "+\(RaceStats.format(split.duration - priorBest))"
                    deltaIsRegression = true
                } else {
                    deltaLabel = "−\(RaceStats.format(priorBest - split.duration))"
                    deltaIsRegression = false
                }

                return SearchMatch(
                    id: "\(race.id.uuidString)-\(station.rawValue)",
                    race: race,
                    titleLabel: titleLabel,
                    subtitleLabel: subtitleLabel,
                    deltaLabel: deltaLabel,
                    deltaIsRegression: deltaIsRegression
                )
            }
        }

        // Plain race-name match.
        return finished.compactMap { race -> SearchMatch? in
            let title = race.name.trimmingCharacters(in: .whitespaces)
            guard title.lowercased().contains(needle) else { return nil }

            let totalLabel = RaceStats.format(race.totalDuration ?? 0)
            let stationCount = race.splits.filter { $0.station.kind == .workout }.count

            return SearchMatch(
                id: "\(race.id.uuidString)-name",
                race: race,
                titleLabel: title,
                subtitleLabel: "\(stationCount) stations · \(totalLabel)",
                deltaLabel: nil,
                deltaIsRegression: false
            )
        }
    }
}

// Lightweight VM for each search result. Decouples the row view
// from the underlying Race so the same row type can render both
// name-matches AND station-matches with different subtitle
// + delta semantics.
private struct SearchMatch: Identifiable {
    let id: String
    let race: Race
    let titleLabel: String
    let subtitleLabel: String
    let deltaLabel: String?
    let deltaIsRegression: Bool
}

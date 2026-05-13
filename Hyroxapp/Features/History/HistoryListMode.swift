import SwiftUI

// Wireframe §04.1 list mode — the default History view. Groups
// rows by week (THIS WEEK / LAST WEEK / N WEEKS AGO) with caps
// section headers, renders the wireframe-compact
// HistoryListRowView for each row.
//
// Takes pre-filtered `[HistoryItem]` so the parent can chain
// existing filters (activity-kind, preset chips, tags, search)
// before handing rows down. This view is purely presentation.
struct HistoryListMode: View {

    let items: [HistoryItem]
    let allRaces: [Race]
    let onRaceTap: (Race) -> Void
    let onRunTap: (FreeRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groupedByWeek, id: \.headerKey) { group in
                weekSection(group)
            }
        }
    }

    // One section per week-bucket. Caps header + the rows in that
    // week. Sections render in date-descending order (newest week
    // first).
    private func weekSection(_ group: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.headerKey)
                .capsLabelStyle()
                .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(group.items) { item in
                    rowButton(for: item)
                }
            }
        }
    }

    // Each row is a tappable button that routes via the parent's
    // callback (the parent owns the NavigationStack destination
    // bindings, so it does the actual push). PressableCard style
    // matches the rest of the app's tappable surfaces.
    @ViewBuilder
    private func rowButton(for item: HistoryItem) -> some View {
        let descriptor = descriptor(for: item)
        Button {
            Haptics.impact(.light)
            switch item {
            case .race(let race): onRaceTap(race)
            case .run(let run):   onRunTap(run)
            }
        } label: {
            HistoryListRowView(descriptor: descriptor)
        }
        .buttonStyle(.pressableCard)
    }

    // Build the row descriptor from the source model. Each model
    // type has its own subtitle + PB-delta semantics.
    private func descriptor(for item: HistoryItem) -> HistoryRowDescriptor {
        switch item {
        case .race(let race):
            return raceDescriptor(race)
        case .run(let run):
            return runDescriptor(run)
        }
    }

    private func raceDescriptor(_ race: Race) -> HistoryRowDescriptor {
        let isFullRace = race.sequenceRaw == Station.raceSequence.map(\.rawValue)
        let stationCount = race.splits.filter { $0.station.kind == .workout }.count

        // Partial = race ended early. Splits captured fewer than
        // the prescribed sequence — happens via endEarlyAndSave
        // (wireframe §03.4) or in legacy data from before the
        // discard/end distinction shipped.
        let isPartial = race.splits.count < race.sequenceRaw.count

        let subtitle: String
        if isFullRace && !isPartial {
            subtitle = "FULL · \(stationCount) STATIONS"
        } else if isFullRace && isPartial {
            // A "full HYROX" race that ended early. Tag the
            // subtitle with the actual count rather than the
            // misleading "8 STATIONS" — athletes need to know
            // they bailed mid-race when scanning History later.
            subtitle = "FULL · \(stationCount)/8 STATIONS"
        } else {
            subtitle = "CUSTOM · \(stationCount) \(stationCount == 1 ? "STATION" : "STATIONS")"
        }

        let title: String = {
            let trimmed = race.name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "HYROX race" : trimmed
        }()

        let timeLabel = RaceStats.format(race.totalDuration ?? 0)

        // PB delta — negative TimeInterval means this race was
        // faster than the prior best. Excluded for partial races
        // because they're not a fair comparison to a full race.
        let pbDelta: String? = {
            guard !isPartial else { return nil }
            let priorBest: TimeInterval? = allRaces
                .filter { $0.isFinished && $0.id != race.id }
                .compactMap(\.totalDuration)
                .min()
            guard let total = race.totalDuration,
                  let prior = priorBest,
                  total < prior else { return nil }
            let delta = prior - total
            return "−\(RaceStats.format(delta))"
        }()

        return HistoryRowDescriptor(
            id: "race-\(race.id.uuidString)",
            date: race.createdAt,
            title: title,
            subtitleCaps: subtitle,
            timeLabel: timeLabel,
            pbDeltaLabel: pbDelta,
            isFullRace: isFullRace && !isPartial,
            isPartial: isPartial,
            isImportedFromHealth: race.importedFromHealth,
            // §14 — non-default RaceKind surfaces as a coloured
            // pill ("SIM" / "Q" / "T") on the list row. The
            // shortBadge accessor returns nil for `.race` which
            // suppresses the pill (default kind doesn't need a
            // marker; the subtitle line already conveys "full
            // 16-station HYROX" via "FULL · 16 STATIONS").
            kindBadgeLabel: race.kind.shortBadge,
            kindBadgeTint: race.kind.shortBadge != nil ? race.kind.badgeColor : nil
        )
    }

    private func runDescriptor(_ run: FreeRun) -> HistoryRowDescriptor {
        let title: String = {
            let trimmed = run.name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Free run" : trimmed
        }()

        // FreeRun uses British spelling `distanceMetres` (matches
        // HealthKit's HKMetricLengthFormatter conventions).
        let distanceKm = run.distanceMetres / 1000.0
        let subtitle = String(format: "%.1f KM", distanceKm)

        // FreeRun's totalDuration is TimeInterval? (nil while
        // in-flight). History only ever passes finished runs, but
        // we coalesce defensively.
        let timeLabel = RaceStats.format(run.totalDuration ?? 0)

        return HistoryRowDescriptor(
            id: "run-\(run.id.uuidString)",
            date: run.createdAt,
            title: title,
            subtitleCaps: subtitle,
            timeLabel: timeLabel,
            pbDeltaLabel: nil,  // free runs don't surface PB delta here
            isFullRace: false,
            isPartial: false,           // free runs aren't "partial"
            isImportedFromHealth: false, // free runs aren't currently imported
            // FreeRun rows have their own subtitle vocabulary
            // (distance "5.2 KM"); a kind badge would be
            // redundant. Set both nil so the row's kind-tag
            // branch silently no-ops.
            kindBadgeLabel: nil,
            kindBadgeTint: nil
        )
    }

    // MARK: - Weekly grouping

    // Group items by calendar week. THIS WEEK = current week,
    // LAST WEEK = one week ago, N WEEKS AGO for older. Same
    // language as Strava's history view.
    private var groupedByWeek: [WeekGroup] {
        let cal = Calendar.current
        let now = Date()
        let nowWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        var bucketByHeader: [String: [HistoryItem]] = [:]
        var orderForHeader: [String: Int] = [:]

        for item in items {
            let itemWeekStart = cal.dateInterval(of: .weekOfYear, for: item.createdAt)?.start
                ?? item.createdAt
            let weeksAgo = cal.dateComponents([.weekOfYear], from: itemWeekStart, to: nowWeekStart).weekOfYear ?? 0

            let header: String
            switch weeksAgo {
            case ...(-1): header = "FUTURE"  // shouldn't happen for finished races but defensive
            case 0:       header = "THIS WEEK"
            case 1:       header = "LAST WEEK"
            case 2...4:   header = "\(weeksAgo) WEEKS AGO"
            default:
                // For older items, fall back to month-year label
                // ("OCTOBER 2026") rather than 6+ WEEKS AGO which
                // becomes unhelpful.
                let fmt = DateFormatter()
                fmt.dateFormat = "MMMM yyyy"
                header = fmt.string(from: itemWeekStart).uppercased()
            }

            bucketByHeader[header, default: []].append(item)
            orderForHeader[header] = weeksAgo
        }

        // Sort each bucket by date descending (newest in the
        // group first), then sort the groups themselves by
        // weeks-ago ascending (newest group first).
        let sortedGroups = bucketByHeader
            .map { (header: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { (a, b) in
                (orderForHeader[a.header] ?? 0) < (orderForHeader[b.header] ?? 0)
            }
            .map { WeekGroup(headerKey: $0.header, items: $0.items) }

        return sortedGroups
    }

    // Local model for grouped section rendering.
    private struct WeekGroup {
        let headerKey: String
        let items: [HistoryItem]
    }
}

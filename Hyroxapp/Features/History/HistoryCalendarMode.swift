import SwiftUI

// Wireframe §04.1 calendar mode — month-grid heatmap with
// race-day indicators. Coral cells = full HYROX race; green
// cells = custom workout or free run. Tap any day to surface
// its detail card beneath the grid.
//
// Takes the full race + free-run arrays so it can scan for
// days that had activity. Navigation arrows (← / →) move
// between months; the body re-renders against the new month
// without touching parent state.
struct HistoryCalendarMode: View {

    let races: [Race]
    let freeRuns: [FreeRun]
    let onRaceTap: (Race) -> Void
    let onRunTap: (FreeRun) -> Void

    @State private var anchorDate = Date()
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            monthHeader

            weekdayHeader

            dayGrid

            legend

            // Detail card for the currently-selected day (or
            // most recent day with activity if none selected).
            if let detailDay = effectiveSelectedDay {
                selectedDayCard(detailDay)
            }
        }
    }

    // MARK: - Month header

    // "November" + arrow buttons. Tapping ← / → walks the anchor
    // month back / forward by one. Future months allowed (the
    // wireframe doesn't restrict — athletes can plan ahead).
    private var monthHeader: some View {
        HStack {
            Text(monthYearLabel)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Weekday header

    // M T W T F S S caps row above the grid. Uses the system's
    // first-weekday convention via the calendar (USA → Sunday-first,
    // most of Europe → Monday-first).
    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // 7 single-letter caps labels in calendar order.
    private var weekdaySymbols: [String] {
        let firstWeekday = calendar.firstWeekday
        let base = ["S", "M", "T", "W", "T", "F", "S"]
        // Rotate the array so the user's first-weekday is first.
        let offset = firstWeekday - 1
        return Array(base[offset...] + base[..<offset])
    }

    // MARK: - Day grid

    // 6-row × 7-col grid of day cells covering the visible month
    // (with leading + trailing padding cells for partial weeks).
    private var dayGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 4
        ) {
            ForEach(daysInGrid, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: GridDay) -> some View {
        switch day {
        case .padding:
            // Leading/trailing month-padding cells render as the
            // neutral surface elevated so the grid keeps its
            // 7×6 shape without highlighting empty days as
            // tappable.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceElevated.opacity(0.5))
                .aspectRatio(1, contentMode: .fit)

        case .day(let date):
            dayActivityCell(date)
        }
    }

    private func dayActivityCell(_ date: Date) -> some View {
        let activity = activityKind(on: date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        return Button {
            Haptics.impact(.light)
            selectedDay = date
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated)
                    .aspectRatio(1, contentMode: .fit)

                if let kind = activity {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(kind.cellTint)
                        .padding(2)
                }

                Text(dayOfMonthLabel(date))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(activity == nil ? Color.textTertiary : Color.onAccent)
                    .monospacedDigit()
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isSelected ? Color.accent : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendChip(label: "Full race", color: Color.accent)
            legendChip(label: "Custom / run", color: Color.success)
            Spacer()
        }
    }

    private func legendChip(label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Selected-day card

    // Detail card for the tapped day (or fallback to most-recent
    // activity day when nothing's been tapped yet). Caps date +
    // activity title + finish time + optional PB delta. Tapping
    // the card opens the corresponding race/run detail.
    @ViewBuilder
    private func selectedDayCard(_ date: Date) -> some View {
        if let race = race(on: date) {
            Button {
                Haptics.impact(.light)
                onRaceTap(race)
            } label: {
                dayDetailCard(date: date, race: race)
            }
            .buttonStyle(.pressableCard)
        } else if let run = run(on: date) {
            Button {
                Haptics.impact(.light)
                onRunTap(run)
            } label: {
                dayDetailRunCard(date: date, run: run)
            }
            .buttonStyle(.pressableCard)
        } else {
            emptyDayCard(date)
        }
    }

    private func dayDetailCard(date: Date, race: Race) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(longDateLabel(date))
                .capsLabelStyle()
            Text(raceTitle(race))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 2)
            Text(RaceStats.format(race.totalDuration ?? 0))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    private func dayDetailRunCard(date: Date, run: FreeRun) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(longDateLabel(date))
                .capsLabelStyle()
            Text(runTitle(run))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 2)
            HStack(spacing: 12) {
                Text(String(format: "%.1f KM", run.distanceMetres / 1000.0))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                Text(RaceStats.format(run.totalDuration ?? 0))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    private func emptyDayCard(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(longDateLabel(date))
                .capsLabelStyle()
            Text("No activity that day.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    // MARK: - Helpers

    private func raceTitle(_ race: Race) -> String {
        let trimmed = race.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "HYROX race" : trimmed
    }

    private func runTitle(_ run: FreeRun) -> String {
        let trimmed = run.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Free run" : trimmed
    }

    private func dayOfMonthLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: date)
    }

    private func longDateLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · EEEE"
        return fmt.string(from: date).uppercased()
    }

    // Used by the selected-day fallback when the user hasn't
    // tapped a day yet — surfaces the most recent active day.
    private var effectiveSelectedDay: Date? {
        if let selectedDay { return selectedDay }
        // Pick the latest activity day within the current
        // displayed month, falling back to nothing.
        let monthInterval = calendar.dateInterval(of: .month, for: anchorDate)
        guard let monthInterval else { return nil }
        let allDates = (races.compactMap(\.endedAt) + freeRuns.compactMap(\.endedAt))
        let inMonth = allDates.filter { monthInterval.contains($0) }
        return inMonth.max()
    }

    // Look up the first race that ended on the given day. nil if none.
    private func race(on day: Date) -> Race? {
        races.first { race in
            guard let end = race.endedAt else { return false }
            return calendar.isDate(end, inSameDayAs: day)
        }
    }

    // Look up the first free run that ended on the given day. nil if none.
    private func run(on day: Date) -> FreeRun? {
        freeRuns.first { run in
            guard let end = run.endedAt else { return false }
            return calendar.isDate(end, inSameDayAs: day)
        }
    }

    // Classify a day's activity for the heatmap fill. Race wins
    // over run when both exist on the same day (rare but possible).
    private func activityKind(on day: Date) -> DayActivityKind? {
        if let race = race(on: day) {
            let isFullRace = race.sequenceRaw == Station.raceSequence.map(\.rawValue)
            return isFullRace ? .fullRace : .customWorkout
        }
        if run(on: day) != nil {
            return .freeRun
        }
        return nil
    }

    private var monthYearLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: anchorDate)
    }

    private func shiftMonth(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: anchorDate) else { return }
        anchorDate = next
        selectedDay = nil  // clear selection when navigating away
    }

    // Build the full 6×7 grid of day cells for the visible month,
    // padding leading + trailing partial weeks with non-tappable
    // placeholder cells.
    private var daysInGrid: [GridDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchorDate) else { return [] }
        let firstDay = monthInterval.start

        // How many weekday slots before the 1st? Calendar's
        // firstWeekday + the weekday of the first-of-month
        // determine the leading-padding count.
        let firstDayWeekday = calendar.component(.weekday, from: firstDay)
        let leadingPadding = ((firstDayWeekday - calendar.firstWeekday) + 7) % 7

        let daysInMonth = calendar.range(of: .day, in: .month, for: anchorDate)?.count ?? 30

        var grid: [GridDay] = []
        for _ in 0..<leadingPadding {
            grid.append(.padding)
        }
        for dayOffset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) {
                grid.append(.day(date))
            }
        }
        // Trailing padding to fill out the last partial week.
        while grid.count % 7 != 0 {
            grid.append(.padding)
        }
        return grid
    }

    enum GridDay: Hashable {
        case padding
        case day(Date)
    }

    enum DayActivityKind {
        case fullRace
        case customWorkout
        case freeRun

        var cellTint: Color {
            switch self {
            case .fullRace:        return Color.accent          // coral
            case .customWorkout:   return Color.success         // green
            case .freeRun:         return Color.success         // green
            }
        }
    }
}

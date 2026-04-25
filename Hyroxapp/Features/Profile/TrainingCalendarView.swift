import SwiftUI

// 12-week training heatmap on Profile — GitHub-contributions-style
// grid where each square is a calendar day, colored by training
// intensity that day. The athlete's last 84 days of training fit on
// a single phone-screen-wide row of columns, giving a dense but
// scannable view of "have I been consistent?"
//
// Visual encoding:
//   • 12 columns × 7 rows. Each column is a week (Mon–Sun), each
//     row is a day-of-week. Bottom-right square is today.
//   • Squares are color-graded by race count: 0 races → dim
//     surface-elevated, 1 race → coral 30%, 2 → coral 60%, 3+ →
//     coral full. Same scale GitHub uses for commit count.
//   • Future days (e.g. Friday and Saturday of the current week
//     when it's only Wednesday) render as completely transparent
//     placeholders so the grid keeps its rectangular shape without
//     pretending there's "no training" on a day that hasn't happened.
//
// Pairs naturally with the streak banner above — streaks tell the
// "how long" story, the heatmap tells the "how often / when" story.
//
// Guarded `#if !os(watchOS)` because Race is iOS-only.
#if !os(watchOS)
struct TrainingCalendarView: View {

    let races: [Race]

    // Anchor the grid to the calendar week containing `referenceDate`,
    // walk back 11 weeks (84 days total). Defaulted to `Date()` so
    // tests can drive the grid deterministically.
    let referenceDate: Date

    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2  // Monday-first — matches HYROX-Europe norm
        return c
    }()

    // Number of weeks shown horizontally. 12 fits comfortably on a
    // ~360pt iPhone width with 7-row vertical packing.
    private static let weeksShown = 12
    private static let daysPerWeek = 7

    init(races: [Race], referenceDate: Date = Date()) {
        self.races = races
        self.referenceDate = referenceDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 12 Weeks")
                    .capsLabelStyle()
                Spacer()
                Text("\(trainingDayCount) training days")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 4)

            grid

            legend
                .padding(.top, 4)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // 12 columns × 7 rows of small rounded squares. Geometry-reader
    // sizes them flexibly to fill the card width — squares grow /
    // shrink with the available width so the grid always looks
    // proportional regardless of screen size or padding.
    private var grid: some View {
        GeometryReader { geo in
            let totalGap: CGFloat = CGFloat(Self.weeksShown - 1) * 4
            let cellSize = (geo.size.width - totalGap) / CGFloat(Self.weeksShown)

            HStack(spacing: 4) {
                ForEach(weeks, id: \.self) { weekStart in
                    VStack(spacing: 4) {
                        ForEach(0..<Self.daysPerWeek, id: \.self) { dayOffset in
                            cellView(
                                weekStart: weekStart,
                                dayOffset: dayOffset,
                                size: cellSize
                            )
                        }
                    }
                }
            }
        }
        // Total grid height = 7 rows × cellSize + 6 gaps × 4pt.
        // Approximate at a fixed height that matches the typical
        // card-width math on iPhone (~10pt cells × 7 + gaps).
        .frame(height: 7 * 12 + 6 * 4)
    }

    // Resolve a single day cell — returns either a colored square
    // for past/today, or a transparent placeholder for future days.
    @ViewBuilder
    private func cellView(weekStart: Date, dayOffset: Int, size: CGFloat) -> some View {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        let dayStart = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: referenceDate)

        if dayStart > today {
            // Future day — invisible spacer keeps grid rectangular
            // without falsely implying "no training" on a day that
            // hasn't happened yet.
            Rectangle()
                .fill(Color.clear)
                .frame(width: size, height: size)
        } else {
            let count = raceCountByDay[dayStart] ?? 0
            RoundedRectangle(cornerRadius: 2)
                .fill(intensityColor(forRaceCount: count))
                .frame(width: size, height: size)
        }
    }

    // Color ramp: 0 races → dim, 1 → 30%, 2 → 60%, 3+ → full coral.
    // Same step pattern as GitHub's contribution graph (5 levels)
    // but tuned to coral. Empty days still get a faint visible
    // square so the grid reads as an actual grid, not a void.
    private func intensityColor(forRaceCount count: Int) -> Color {
        switch count {
        case 0:  return Color.surfaceElevated
        case 1:  return Color.accent.opacity(0.30)
        case 2:  return Color.accent.opacity(0.60)
        default: return Color.accent
        }
    }

    // Bottom legend — "Less ▢▢▢▢ More" — same affordance GitHub
    // uses to teach the color scale. Rendered tight so it doesn't
    // dominate.
    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)

            ForEach(0..<4) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(intensityColor(forRaceCount: level))
                    .frame(width: 10, height: 10)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)

            Spacer()
        }
    }

    // MARK: - Date math

    // The 12 week-start dates we render across the columns,
    // oldest first. Each is the calendar's firstWeekday for that week.
    private var weeks: [Date] {
        let todayWeekStart = startOfWeek(for: referenceDate)
        return (0..<Self.weeksShown).reversed().compactMap { weeksAgo in
            calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: todayWeekStart)
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        let comps = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: date
        )
        return calendar.date(from: comps) ?? date
    }

    // Pre-aggregate finished races into a (startOfDay -> count) dict
    // once per render pass so the per-cell lookup is O(1). Without
    // this each of 84 cells would walk the entire races array.
    private var raceCountByDay: [Date: Int] {
        var map: [Date: Int] = [:]
        for race in races where race.endedAt != nil {
            guard let end = race.endedAt else { continue }
            let day = calendar.startOfDay(for: end)
            map[day, default: 0] += 1
        }
        return map
    }

    // Visible range of training days — the count above the grid.
    // Limited to days within the rendered 12-week window so the
    // number matches what the athlete sees on screen.
    private var trainingDayCount: Int {
        let earliest = weeks.first ?? referenceDate
        let today = calendar.startOfDay(for: referenceDate)
        return raceCountByDay.keys.filter { day in
            day >= earliest && day <= today
        }.count
    }
}
#endif

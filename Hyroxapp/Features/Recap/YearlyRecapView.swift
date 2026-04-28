import SwiftUI
import SwiftData

// In-app full-screen "year in review" — pushed from the recap
// banner on Profile. Same content shape as the share card but
// laid out richer because the in-app screen has more vertical
// real estate and supports interactive drill-down (tap any race
// in the list to push its detail).
//
// Toolbar share button bakes the YearlyRecapShareCardView once on
// appear, same caching pattern used everywhere else.
//
// Guarded `#if !os(watchOS)`.
#if !os(watchOS)
struct YearlyRecapView: View {

    let recap: YearlyRecap

    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var allFinishedRaces: [Race]

    @State private var shareImage: RaceShareImage?

    // Races whose endedAt falls inside this recap's calendar year.
    // Computed from the live store so renames / photo adds reflect
    // here without a navigation pop.
    private var racesInYear: [Race] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year], from: recap.yearStart)
        return allFinishedRaces.filter { race in
            guard let end = race.endedAt else { return false }
            return cal.dateComponents([.year], from: end).year == comps.year
        }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard.applyScrollAppearTransition()
                    statsGrid.applyScrollAppearTransition()
                    sparklineCard.applyScrollAppearTransition()

                    if let mover = recap.biggestMover {
                        biggestMoverCard(mover).applyScrollAppearTransition()
                    }

                    highlightsCard.applyScrollAppearTransition()
                    racesSection.applyScrollAppearTransition()
                }
                .padding(Layout.screenMargin)
            }
        }
        .navigationTitle(recap.displayName)
        .hyroxDarkNavigationBar(inline: true)
        .toolbar {
            #if !os(macOS)
            ToolbarItem(placement: .topBarTrailing) {
                if let item = shareImage {
                    ShareLink(
                        item: item,
                        preview: SharePreview(
                            "\(recap.displayName) · HYROX",
                            image: Image(uiImage: item.image)
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share yearly recap")
                }
            }
            #endif
        }
        .onAppear(perform: prepareShareImage)
    }

    // MARK: - Hero (year + best month subtitle)

    private var heroCard: some View {
        VStack(spacing: 8) {
            Text(recap.displayName)
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("YEAR IN HYROX")
                .font(.caption.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(Color.accent)

            Text("\(recap.raceCount) race\(recap.raceCount == 1 ? "" : "s") across \(recap.monthsActive) of 12 months")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - 2×2 stat grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            statTile(value: "\(recap.raceCount)", label: "RACES")
            statTile(value: hoursTrainedString, label: "TRAINED")
            statTile(
                value: "\(recap.totalTimePBCount)",
                label: "PBs SET",
                accent: recap.totalTimePBCount > 0
            )
            statTile(value: "\(recap.streakPeak)", label: "STREAK PEAK")
        }
    }

    private func statTile(value: String, label: String, accent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? Color.accent : Color.textPrimary)

            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Monthly sparkline

    private var sparklineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Races by month").capsLabelStyle()
                Spacer()
                if let best = recap.bestMonth {
                    Text("Best: \(best.displayName) (\(best.raceCount))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .monospacedDigit()
                }
            }

            GeometryReader { geo in
                let maxCount = recap.racesByMonth.values.max() ?? 1
                let totalGap: CGFloat = 11 * 4
                let barWidth = (geo.size.width - totalGap) / 12

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(1...12, id: \.self) { month in
                        let count = recap.racesByMonth[month] ?? 0
                        let height: CGFloat = count == 0
                            ? 4
                            : geo.size.height * CGFloat(count) / CGFloat(maxCount)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(count == 0 ? Color.surfaceElevated : Color.accent)
                            .frame(width: barWidth, height: max(height, 4))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .frame(height: 80)

            // Month-initial labels.
            HStack(spacing: 4) {
                ForEach(1...12, id: \.self) { month in
                    Text(monthInitial(month))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func monthInitial(_ month: Int) -> String {
        let symbols = DateFormatter().shortMonthSymbols ?? []
        guard symbols.indices.contains(month - 1) else { return "" }
        return String(symbols[month - 1].prefix(1))
    }

    // MARK: - Biggest mover

    private func biggestMoverCard(_ mover: YearlyRecap.BiggestMover) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.success)

            VStack(alignment: .leading, spacing: 2) {
                Text("BIGGEST MOVER OF THE YEAR")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.success)

                Text(mover.station.displayName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Text("\(Int(mover.percentChange.rounded()))% faster recently")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.success.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .stroke(Color.success.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Highlights row

    private var highlightsCard: some View {
        VStack(spacing: 0) {
            highlightRow(
                label: "Fastest race",
                value: recap.fastestTotal.map(RaceStats.format) ?? "—"
            )
            Divider().background(Color.divider)
            highlightRow(
                label: "Fastest 1km run",
                value: recap.fastestRun.map(RaceStats.format) ?? "—"
            )
            Divider().background(Color.divider)
            highlightRow(
                label: "Active calories",
                value: recap.totalCalories
                    .map { "\(Int($0.rounded())) kcal" } ?? "—"
            )
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func highlightRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Races list

    private var racesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Races this year").capsLabelStyle()
                Spacer()
            }

            ForEach(racesInYear) { race in
                NavigationLink(value: race) {
                    RaceCardView(race: race, allRaces: allFinishedRaces)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Share

    private func prepareShareImage() {
        guard shareImage == nil else { return }

        let card = YearlyRecapShareCardView(recap: recap)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0

        guard let cgImage = renderer.cgImage else { return }
        let uiImage = UIImage(cgImage: cgImage)

        let f = DateFormatter()
        f.dateFormat = "yyyy"
        let filename = "HYROX-\(f.string(from: recap.yearStart))-recap.png"

        shareImage = RaceShareImage(image: uiImage, filename: filename)
    }

    private var hoursTrainedString: String {
        let total = Int(recap.totalDuration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
#endif

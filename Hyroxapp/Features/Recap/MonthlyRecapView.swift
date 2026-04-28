import SwiftUI
import SwiftData

// In-app reflection screen for a single month of HYROX training —
// the deeper read on the data the share card summarizes. Pushed
// from the recap banner on Profile, scrollable, with the same
// stats as the share card plus the actual list of races so the
// athlete can drill into any specific session.
//
// Story-aspect share button in the toolbar — taps render the
// MonthlyRecapShareCardView and hand the image to ShareLink.
//
// Guarded `#if !os(watchOS)`.
#if !os(watchOS)
struct MonthlyRecapView: View {

    let recap: MonthlyRecap

    // Re-query finished races so the inline race list stays live
    // (rename a race / add a photo and it reflects here without a
    // navigation pop). Filter to this month at view-derivation time.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var allFinishedRaces: [Race]

    // Cached share image — same `.onAppear` bake pattern used by
    // RaceSummaryView / RaceDetailView so the Share button fires
    // instantly without spinning up the renderer on tap.
    @State private var shareImage: RaceShareImage?

    // Races in this recap's calendar month, newest first. Computed
    // here rather than passed in so the list reacts to live store
    // changes (notes edits, photo adds, etc.).
    private var racesInMonth: [Race] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: recap.monthStart)
        return allFinishedRaces.filter { race in
            guard let end = race.endedAt else { return false }
            let raceComps = cal.dateComponents([.year, .month], from: end)
            return raceComps.year == comps.year && raceComps.month == comps.month
        }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard.applyScrollAppearTransition()
                    statsGrid.applyScrollAppearTransition()

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
                    .accessibilityLabel("Share monthly recap")
                }
            }
            #endif
        }
        .onAppear(perform: prepareShareImage)
    }

    // MARK: - Hero (month name + year)

    private var heroCard: some View {
        VStack(spacing: 6) {
            Text(recap.monthName.uppercased())
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text(recap.yearLabel)
                .font(.caption.weight(.bold))
                .tracking(2.0)
                .foregroundStyle(Color.accent)

            Text("\(recap.raceCount) race\(recap.raceCount == 1 ? "" : "s")")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

    // MARK: - Biggest mover

    private func biggestMoverCard(_ mover: MonthlyRecap.BiggestMover) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.success)

            VStack(alignment: .leading, spacing: 2) {
                Text("BIGGEST MOVER")
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

    // MARK: - Highlights row (fastest race / fastest run / calories)

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

    // MARK: - Races section (clickable list)

    private var racesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Races this month").capsLabelStyle()
                Spacer()
            }

            ForEach(racesInMonth) { race in
                NavigationLink(value: race) {
                    RaceCardView(race: race, allRaces: allFinishedRaces)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Share

    // Bake the share card into a UIImage on appear. Renderer is
    // @MainActor so calling from .onAppear keeps everything on the
    // right thread.
    private func prepareShareImage() {
        guard shareImage == nil else { return }

        let card = MonthlyRecapShareCardView(recap: recap)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0

        guard let cgImage = renderer.cgImage else { return }
        let uiImage = UIImage(cgImage: cgImage)

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let filename = "HYROX-\(f.string(from: recap.monthStart))-recap.png"

        shareImage = RaceShareImage(image: uiImage, filename: filename)
    }

    // MARK: - Computed

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

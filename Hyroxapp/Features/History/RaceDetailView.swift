import SwiftUI

// Full detail screen for a single race: hero total time, then all 16 splits
// in order. Pushed from `HistoryView` via NavigationStack.
struct RaceDetailView: View {
    let race: Race

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    splitsCard
                }
                .padding(Layout.screenMargin)
            }
        }
        .navigationTitle(race.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Splits").capsLabelStyle()
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(race.splits.enumerated()), id: \.element.id) { index, split in
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
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24, alignment: .leading)

            Text(split.station.displayName)
                .font(.body)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text(RaceStats.format(split.duration))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.vertical, 10)
    }
}

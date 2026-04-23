import SwiftUI

// Post-race screen: total time hero, all 16 splits in a scrollable card,
// and a Done button that returns the VM to its resting state (the race
// itself is already persisted and will appear in History).
struct RaceSummaryView: View {
    let viewModel: RaceViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Race Complete")
                .capsLabelStyle()
                .foregroundStyle(Color.success)

            Text(RaceStats.format(viewModel.finalTime))
                .font(.raceTimer)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("Total time")
                .font(.metadata)
                .foregroundStyle(Color.textSecondary)

            splitsCard
                .padding(.top, 16)

            Spacer()

            Button(action: viewModel.finishSession) {
                Text("Done")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(Color.surfaceElevated)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            .padding(.bottom, 16)
        }
    }

    private var splitsCard: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.splits.enumerated()), id: \.element.id) { index, split in
                    splitRow(for: split)
                    if index < viewModel.splits.count - 1 {
                        Divider().background(Color.divider)
                    }
                }
            }
            .padding(Layout.cardPadding)
        }
        .frame(maxHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func splitRow(for split: Split) -> some View {
        HStack {
            Text(split.station.displayName)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(RaceStats.format(split.duration))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 10)
    }
}
